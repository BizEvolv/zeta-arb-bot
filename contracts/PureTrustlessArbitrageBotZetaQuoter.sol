// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * PureTrustlessArbitrageBotZetaQuoter
 * - Ownerless, user-funded arbitrage executor for ZetaChain (or any EVM)
 * - Integrates Uniswap V3 QuoterV2 for accurate quotes
 * - Dynamically selects best V3 fee tier among 500/3000/10000
 * - Supports V2 routers (UniswapV2/Sushi-like) and V3 router
 *
 * Notes
 * - No flash loans: the caller provides liquidity via token approvals to THIS contract.
 * - Profits are returned to msg.sender.
 * - This is a reference implementation. Always audit before mainnet use.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function WETH() external pure returns (address);
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }
    function quoteExactInputSingle(QuoteExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

contract PureTrustlessArbitrageBotZetaQuoter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error UnsupportedToken();
    error InvalidDEX();
    error NoOpportunity();
    error InsufficientOutput();
    error InvalidAmount();

    struct DEXInfo {
        address router;
        uint8 dexType; // 0=V2, 1=V3
        string name;
    }

    struct Opportunity {
        bool exists;
        uint8 dexIn;
        uint8 dexOut;
        uint24 feeIn;   // only if V3
        uint24 feeOut;  // only if V3
        uint256 expProfit;
        uint256 amountIn;
    }

    // Immutable router/quoter addresses
    address public immutable UNI_V2_ROUTER;
    address public immutable UNI_V3_ROUTER;
    address public immutable QUOTER_V2;
    address public immutable WRAPPED_NATIVE;

    // DEX registry (0: V2, 1: V3). You can add more if needed.
    DEXInfo[2] public dex;

    // Supported tokens simple allowlist
    mapping(address => bool) public supported;

    // Limits
    uint256 public constant MAX_TRADE = 100 ether;
    uint256 public constant MIN_PROFIT = 1e15; // 0.001 native token (adjust per network)

    // Stats
    uint256 public totalTrades;
    uint256 public totalVolume;

    event ArbitrageExecuted(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 profit, uint8 dexIn, uint8 dexOut, uint24 feeIn, uint24 feeOut);

    constructor(
        address _uniV2Router,
        address _uniV3Router,
        address _quoterV2,
        address _wrappedNative,
        address[] memory _supportedTokens
    ) {
        require(_uniV2Router != address(0) && _uniV3Router != address(0) && _quoterV2 != address(0), "bad routers");
        UNI_V2_ROUTER = _uniV2Router;
        UNI_V3_ROUTER = _uniV3Router;
        QUOTER_V2 = _quoterV2;
        WRAPPED_NATIVE = _wrappedNative;

        dex[0] = DEXInfo({router: _uniV2Router, dexType: 0, name: "V2"});
        dex[1] = DEXInfo({router: _uniV3Router, dexType: 1, name: "V3"});

        for (uint i = 0; i < _supportedTokens.length; i++) {
            supported[_supportedTokens[i]] = true;
        }
    }

    // ----------- View helpers -----------

    function isSupported(address t) public view returns (bool) { return supported[t]; }

    function _quoteV2(address router, address a, address b, uint256 amountIn) internal view returns (uint256) {
        address[] memory p = new address[](2);
        p[0] = a; p[1] = b;
        try IUniswapV2Router02(router).getAmountsOut(amountIn, p) returns (uint[] memory amounts) {
            return amounts.length > 1 ? amounts[1] : 0;
        } catch { return 0; }
    }

    function _bestV3Quote(address a, address b, uint256 amountIn) internal returns (uint256 outAmt, uint24 bestFee) {
        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];
        uint256 best = 0;
        uint24 picked = 0;

        for (uint i=0;i<fees.length;i++) {
            try IQuoterV2(QUOTER_V2).quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: a,
                    tokenOut: b,
                    amountIn: amountIn,
                    fee: fees[i],
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountOut,, ,) {
                if (amountOut > best) { best = amountOut; picked = fees[i]; }
            } catch {}
        }
        return (best, picked);
    }

    function _quoteDEX(uint8 dexId, address a, address b, uint256 amountIn) internal returns (uint256 out, uint24 fee) {
        if (dexId == 0) {
            out = _quoteV2(dex[dexId].router, a, b, amountIn);
            fee = 0;
        } else if (dexId == 1) {
            (out, fee) = _bestV3Quote(a, b, amountIn);
        } else {
            revert InvalidDEX();
        }
    }

    function previewBest(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (Opportunity memory best) {
        require(amountIn > 0 && amountIn <= MAX_TRADE, "bad amount");
        if (!supported[tokenIn] || !supported[tokenOut] || tokenIn == tokenOut) revert UnsupportedToken();

        uint256 bestProfit = 0;
        Opportunity memory cand;

        for (uint8 inDex = 0; inDex < dex.length; inDex++) {
            (uint256 mid, uint24 feeIn) = _quoteDEX(inDex, tokenIn, tokenOut, amountIn);
            if (mid == 0) continue;
            for (uint8 outDex = 0; outDex < dex.length; outDex++) {
                if (inDex == outDex) continue;
                (uint256 back, uint24 feeOut) = _quoteDEX(outDex, tokenOut, tokenIn, mid);
                if (back <= amountIn) continue;
                uint256 profit = back - amountIn;
                if (profit > bestProfit) {
                    bestProfit = profit;
                    cand = Opportunity({
                        exists: true,
                        dexIn: inDex,
                        dexOut: outDex,
                        feeIn: feeIn,
                        feeOut: feeOut,
                        expProfit: profit,
                        amountIn: amountIn
                    });
                }
            }
        }
        return cand;
    }

    // ----------- Execution -----------

    function _execV2(address router, address a, address b, uint256 amountIn, uint256 minOut, address to) internal returns (uint256) {
        IERC20(a).safeApprove(router, 0);
        IERC20(a).safeApprove(router, amountIn);
        address[] memory p = new address[](2);
        p[0] = a; p[1] = b;
        uint[] memory amounts = IUniswapV2Router02(router).swapExactTokensForTokens(
            amountIn, minOut, p, to, block.timestamp + 300
        );
        return amounts[1];
    }

    function _execV3(address router, address a, address b, uint24 fee, uint256 amountIn, uint256 minOut, address to) internal returns (uint256) {
        IERC20(a).safeApprove(router, 0);
        IERC20(a).safeApprove(router, amountIn);
        IUniswapV3Router.ExactInputSingleParams memory p = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: a,
            tokenOut: b,
            fee: fee,
            recipient: to,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });
        return IUniswapV3Router(router).exactInputSingle(p);
    }

    /**
     * @notice Execute arbitrage using previously previewed params.
     * Caller must have approved `tokenIn` amount to this contract.
     * Remaining profit (in tokenIn) is transferred back to the caller.
     */
    function autoArbitrage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint8 dexIn,
        uint8 dexOut,
        uint24 feeIn,
        uint24 feeOut,
        uint256 minReturn // slippage guard on final amount
    ) external nonReentrant {
        if (amountIn == 0 || amountIn > MAX_TRADE) revert InvalidAmount();
        if (!supported[tokenIn] || !supported[tokenOut] || tokenIn == tokenOut) revert UnsupportedToken();
        if (dexIn >= dex.length || dexOut >= dex.length || dexIn == dexOut) revert InvalidDEX();

        // Pull funds from user
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 startBal = IERC20(tokenIn).balanceOf(address(this));

        // First swap tokenIn -> tokenOut
        uint256 interOut;
        if (dexIn == 0) {
            interOut = _execV2(dex[0].router, tokenIn, tokenOut, amountIn, 0, address(this));
        } else {
            uint24 tier = (feeIn == 500 || feeIn == 3000 || feeIn == 10000) ? feeIn : 3000;
            interOut = _execV3(dex[1].router, tokenIn, tokenOut, tier, amountIn, 0, address(this));
        }
        require(interOut > 0, "first swap failed");

        // Second swap tokenOut -> tokenIn
        uint256 finalOut;
        if (dexOut == 0) {
            finalOut = _execV2(dex[0].router, tokenOut, tokenIn, interOut, minReturn, address(this));
        } else {
            uint24 tier2 = (feeOut == 500 || feeOut == 3000 || feeOut == 10000) ? feeOut : 3000;
            finalOut = _execV3(dex[1].router, tokenOut, tokenIn, tier2, interOut, minReturn, address(this));
        }

        uint256 endBal = IERC20(tokenIn).balanceOf(address(this));
        uint256 gained = endBal > startBal ? endBal - startBal : 0;
        if (gained < MIN_PROFIT) revert InsufficientOutput();

        // Return everything (principal + profit) to user
        IERC20(tokenIn).safeTransfer(msg.sender, endBal);

        totalTrades += 1;
        totalVolume += amountIn;

        emit ArbitrageExecuted(msg.sender, tokenIn, tokenOut, amountIn, gained, dexIn, dexOut, feeIn, feeOut);
    }
}
