// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FullMath} from "./FullMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";

/// @title 计算 tick 范围内兑换（swap）的结果
/// @notice 包含在单个 tick 价格区间（即单个 tick）内计算兑换结果的方法。
library SwapMath {
    /// @notice 兑换手续费以百分之一基点（hundredths of a bip）为单位表示，因此最大值为 100%
    /// @dev 兑换手续费是一次兑换的总手续费，包括 LP 手续费和协议手续费
    uint256 internal constant MAX_SWAP_FEE = 1e6;

    /// @notice 计算下一个兑换步骤的目标平方根价格
    /// @param zeroForOne 兑换方向，true 表示 currency0 换 currency1，false 表示 currency1 换 currency0
    /// @param sqrtPriceNextX96 下一个已初始化 tick 对应的 Q64.96 平方根价格
    /// @param sqrtPriceLimitX96 Q64.96 平方根价格限制。若为 zero for one，兑换后价格不能低于该值；
    /// 若为 one for zero，兑换后价格不能高于该值
    /// @return sqrtPriceTargetX96 下一个兑换步骤的目标价格
    function getSqrtPriceTarget(bool zeroForOne, uint160 sqrtPriceNextX96, uint160 sqrtPriceLimitX96)
        internal
        pure
        returns (uint160 sqrtPriceTargetX96)
    {
        assembly ("memory-safe") {
            // 用于在 sqrtPriceNextX96 与 sqrtPriceLimitX96 之间切换的标志位
            // 当 zeroForOne == true 时，nextOrLimit 化简为 sqrtPriceNextX96 >= sqrtPriceLimitX96
            // sqrtPriceTargetX96 = max(sqrtPriceNextX96, sqrtPriceLimitX96)
            // 当 zeroForOne == false 时，nextOrLimit 化简为 sqrtPriceNextX96 < sqrtPriceLimitX96
            // sqrtPriceTargetX96 = min(sqrtPriceNextX96, sqrtPriceLimitX96)
            sqrtPriceNextX96 := and(sqrtPriceNextX96, 0xffffffffffffffffffffffffffffffffffffffff)
            sqrtPriceLimitX96 := and(sqrtPriceLimitX96, 0xffffffffffffffffffffffffffffffffffffffff)
            let nextOrLimit := xor(lt(sqrtPriceNextX96, sqrtPriceLimitX96), and(zeroForOne, 0x1))
            let symDiff := xor(sqrtPriceNextX96, sqrtPriceLimitX96)
            sqrtPriceTargetX96 := xor(sqrtPriceLimitX96, mul(symDiff, nextOrLimit))
        }
    }

    /// @notice 根据兑换参数，计算换入一定数量或换出一定数量的兑换结果
    /// @dev 若兑换的 amountSpecified 为负数，手续费与输入数量之和永远不会超过剩余数量的绝对值。
    /// @param sqrtPriceCurrentX96 池子当前的平方根价格
    /// @param sqrtPriceTargetX96 不能超过的价格，兑换方向由此推断
    /// @param liquidity 可用的流动性
    /// @param amountRemaining 剩余待换入/换出的输入或输出数量
    /// @param feePips 从输入数量中收取的手续费，以百分之一基点为单位表示
    /// @return sqrtPriceNextX96 换入/换出该数量后的价格，不会超过目标价格
    /// @return amountIn 需换入的数量（currency0 或 currency1，取决于兑换方向）
    /// @return amountOut 将收到的数量（currency0 或 currency1，取决于兑换方向）
    /// @return feeAmount 将作为手续费收取的输入数量
    /// @dev 对于本函数，feePips 不得大于 MAX_SWAP_FEE。我们在设置手续费之前会通过 LPFeeLibrary.isValid 确保这一点。
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        unchecked {
            uint256 _feePips = feePips; // 只向上转型一次并缓存
            bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
            bool exactIn = amountRemaining < 0;

            if (exactIn) {
                uint256 amountRemainingLessFee =
                    FullMath.mulDiv(uint256(-amountRemaining), MAX_SWAP_FEE - _feePips, MAX_SWAP_FEE);
                amountIn = zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, true);
                if (amountRemainingLessFee >= amountIn) {
                    // `amountIn` 受目标价格封顶
                    sqrtPriceNextX96 = sqrtPriceTargetX96;
                    feeAmount = _feePips == MAX_SWAP_FEE
                        ? amountIn // 此处 amountIn 恒为 0，因为 amountRemainingLessFee == 0 且 amountRemainingLessFee >= amountIn
                        : FullMath.mulDivRoundingUp(amountIn, _feePips, MAX_SWAP_FEE - _feePips);
                } else {
                    // 耗尽剩余数量
                    amountIn = amountRemainingLessFee;
                    sqrtPriceNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                        sqrtPriceCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
                    );
                    // 未到达目标价格，因此将最大输入量的剩余部分作为手续费收取
                    feeAmount = uint256(-amountRemaining) - amountIn;
                }
                amountOut = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false)
                    : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
            } else {
                amountOut = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
                    : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);
                if (uint256(amountRemaining) >= amountOut) {
                    // `amountOut` 受目标价格封顶
                    sqrtPriceNextX96 = sqrtPriceTargetX96;
                } else {
                    // 限制输出数量，使其不超过剩余的输出数量
                    amountOut = uint256(amountRemaining);
                    sqrtPriceNextX96 =
                        SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPriceCurrentX96, liquidity, amountOut, zeroForOne);
                }
                amountIn = zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
                // 对于精确输出（exact out），`feePips` 不可能为 `MAX_SWAP_FEE`
                feeAmount = FullMath.mulDivRoundingUp(amountIn, _feePips, MAX_SWAP_FEE - _feePips);
            }
        }
    }
}
