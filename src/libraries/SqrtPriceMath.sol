// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "./SafeCast.sol";

import {FullMath} from "./FullMath.sol";
import {UnsafeMath} from "./UnsafeMath.sol";
import {FixedPoint96} from "./FixedPoint96.sol";

/// @title 基于 Q64.96 平方根价格与流动性的函数
/// @notice 包含以 Q64.96 格式的价格平方根与流动性来计算 delta 的数学运算
library SqrtPriceMath {
    using SafeCast for uint256;

    error InvalidPriceOrLiquidity();
    error InvalidPrice();
    error NotEnoughLiquidity();
    error PriceOverflow();

    /// @notice 给定 currency0 的 delta，计算下一个平方根价格
    /// @dev 总是向上取整，因为在精确输出（exact output）情形下（价格上升），我们需要让价格至少移动
    /// 足够远以获得期望的输出数量；而在精确输入（exact input）情形下（价格下降），我们需要让
    /// 价格移动得少一些，以免发送过多的输出。
    /// 对此最精确的公式是 liquidity * sqrtPX96 / (liquidity +- amount * sqrtPX96)，
    /// 若因溢出而无法计算，则改为计算 liquidity / (liquidity / sqrtPX96 +- amount)。
    /// @param sqrtPX96 起始价格，即计入 currency0 delta 之前的价格
    /// @param liquidity 可用流动性的数量
    /// @param amount 要向虚拟储备中添加或从中移除的 currency0 数量
    /// @param add 是添加还是移除该数量的 currency0
    /// @return 添加或移除 amount 之后的价格，取决于 add
    function getNextSqrtPriceFromAmount0RoundingUp(uint160 sqrtPX96, uint128 liquidity, uint256 amount, bool add)
        internal
        pure
        returns (uint160)
    {
        // 对 amount == 0 进行短路处理，否则无法保证结果等于输入价格
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            unchecked {
                uint256 product = amount * sqrtPX96;
                if (product / amount == sqrtPX96) {
                    uint256 denominator = numerator1 + product;
                    if (denominator >= numerator1) {
                        // 结果总能放入 160 位
                        return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
                    }
                }
            }
            // 分母会进行溢出检查
            return uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96) + amount));
        } else {
            unchecked {
                uint256 product = amount * sqrtPX96;
                // 如果乘积溢出，则可知分母必然下溢
                // 此外，我们还必须检查分母不会下溢
                // 等价于：if (product / amount != sqrtPX96 || numerator1 <= product) revert PriceOverflow();
                assembly ("memory-safe") {
                    if iszero(
                        and(
                            eq(div(product, amount), and(sqrtPX96, 0xffffffffffffffffffffffffffffffffffffffff)),
                            gt(numerator1, product)
                        )
                    ) {
                        mstore(0, 0xf5c787f1) // PriceOverflow() 的选择器
                        revert(0x1c, 0x04)
                    }
                }
                uint256 denominator = numerator1 - product;
                return FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator).toUint160();
            }
        }
    }

    /// @notice 给定 currency1 的 delta，计算下一个平方根价格
    /// @dev 总是向下取整，因为在精确输出情形下（价格下降），我们需要让价格至少移动
    /// 足够远以获得期望的输出数量；而在精确输入情形下（价格上升），我们需要让
    /// 价格移动得少一些，以免发送过多的输出。
    /// 我们计算的公式与无损版本相差不到 1 wei：sqrtPX96 +- amount / liquidity
    /// @param sqrtPX96 起始价格，即计入 currency1 delta 之前的价格
    /// @param liquidity 可用流动性的数量
    /// @param amount 要向虚拟储备中添加或从中移除的 currency1 数量
    /// @param add 是添加还是移除该数量的 currency1
    /// @return 添加或移除 `amount` 之后的价格
    function getNextSqrtPriceFromAmount1RoundingDown(uint160 sqrtPX96, uint128 liquidity, uint256 amount, bool add)
        internal
        pure
        returns (uint160)
    {
        // 如果是加（减），向下取整要求将商向下（向上）取整
        // 两种情况下，对大多数输入都避免调用 mulDiv
        if (add) {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? (amount << FixedPoint96.RESOLUTION) / liquidity
                    : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
            );

            return (uint256(sqrtPX96) + quotient).toUint160();
        } else {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)
                    : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
            );

            // 等价于：if (sqrtPX96 <= quotient) revert NotEnoughLiquidity();
            assembly ("memory-safe") {
                if iszero(gt(and(sqrtPX96, 0xffffffffffffffffffffffffffffffffffffffff), quotient)) {
                    mstore(0, 0x4323a555) // NotEnoughLiquidity() 的选择器
                    revert(0x1c, 0x04)
                }
            }
            // 结果总能放入 160 位
            unchecked {
                return uint160(sqrtPX96 - quotient);
            }
        }
    }

    /// @notice 给定 currency0 或 currency1 的输入数量，计算下一个平方根价格
    /// @dev 如果价格或流动性为 0，或者下一个价格超出范围，则抛出异常
    /// @param sqrtPX96 起始价格，即计入输入数量之前的价格
    /// @param liquidity 可用流动性的数量
    /// @param amountIn 兑换（swap）输入的 currency0 或 currency1 的数量
    /// @param zeroForOne 输入数量是 currency0 还是 currency1
    /// @return uint160 将输入数量计入 currency0 或 currency1 之后的价格
    function getNextSqrtPriceFromInput(uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        internal
        pure
        returns (uint160)
    {
        // 等价于：if (sqrtPX96 == 0 || liquidity == 0) revert InvalidPriceOrLiquidity();
        assembly ("memory-safe") {
            if or(
                iszero(and(sqrtPX96, 0xffffffffffffffffffffffffffffffffffffffff)),
                iszero(and(liquidity, 0xffffffffffffffffffffffffffffffff))
            ) {
                mstore(0, 0x4f2461b8) // InvalidPriceOrLiquidity() 的选择器
                revert(0x1c, 0x04)
            }
        }

        // 取整以确保不会越过目标价格
        return zeroForOne
            ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
            : getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /// @notice 给定 currency0 或 currency1 的输出数量，计算下一个平方根价格
    /// @dev 如果价格或流动性为 0，或者下一个价格超出范围，则抛出异常
    /// @param sqrtPX96 计入输出数量之前的起始价格
    /// @param liquidity 可用流动性的数量
    /// @param amountOut 兑换（swap）输出的 currency0 或 currency1 的数量
    /// @param zeroForOne 输出数量是 currency1 还是 currency0
    /// @return uint160 移除 currency0 或 currency1 的输出数量之后的价格
    function getNextSqrtPriceFromOutput(uint160 sqrtPX96, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        internal
        pure
        returns (uint160)
    {
        // 等价于：if (sqrtPX96 == 0 || liquidity == 0) revert InvalidPriceOrLiquidity();
        assembly ("memory-safe") {
            if or(
                iszero(and(sqrtPX96, 0xffffffffffffffffffffffffffffffffffffffff)),
                iszero(and(liquidity, 0xffffffffffffffffffffffffffffffff))
            ) {
                mstore(0, 0x4f2461b8) // InvalidPriceOrLiquidity() 的选择器
                revert(0x1c, 0x04)
            }
        }

        // 取整以确保会越过目标价格
        return zeroForOne
            ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
            : getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    }

    /// @notice 获取两个价格之间的 amount0 delta
    /// @dev 计算 liquidity / sqrt(lower) - liquidity / sqrt(upper)，
    /// 即 liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtPriceAX96 一个平方根价格
    /// @param sqrtPriceBX96 另一个平方根价格
    /// @param liquidity 可用流动性的数量
    /// @param roundUp 数量是向上取整还是向下取整
    /// @return uint256 在两个给定价格之间覆盖规模为 liquidity 的头寸所需的 currency0 数量
    function getAmount0Delta(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

            // 等价于：if (sqrtPriceAX96 == 0) revert InvalidPrice();
            assembly ("memory-safe") {
                if iszero(and(sqrtPriceAX96, 0xffffffffffffffffffffffffffffffffffffffff)) {
                    mstore(0, 0x00bfc921) // InvalidPrice() 的选择器
                    revert(0x1c, 0x04)
                }
            }

            uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
            uint256 numerator2 = sqrtPriceBX96 - sqrtPriceAX96;

            return roundUp
                ? UnsafeMath.divRoundingUp(FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtPriceBX96), sqrtPriceAX96)
                : FullMath.mulDiv(numerator1, numerator2, sqrtPriceBX96) / sqrtPriceAX96;
        }
    }

    /// @notice 等价于：`a >= b ? a - b : b - a`
    function absDiff(uint160 a, uint160 b) internal pure returns (uint256 res) {
        assembly ("memory-safe") {
            let diff :=
                sub(and(a, 0xffffffffffffffffffffffffffffffffffffffff), and(b, 0xffffffffffffffffffffffffffffffffffffffff))
            // 若 a >= b 则 mask = 0，否则 mask = -1（全为 1）
            let mask := sar(255, diff)
            // 若 a >= b，res = a - b = 0 ^ (a - b)
            // 若 a < b，res = b - a = ~~(b - a) = ~(-(b - a) - 1) = ~(a - b - 1) = (-1) ^ (a - b - 1)
            // 无论哪种情况，res = mask ^ (a - b + mask)
            res := xor(mask, add(mask, diff))
        }
    }

    /// @notice 获取两个价格之间的 amount1 delta
    /// @dev 计算 liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtPriceAX96 一个平方根价格
    /// @param sqrtPriceBX96 另一个平方根价格
    /// @param liquidity 可用流动性的数量
    /// @param roundUp 数量是向上取整还是向下取整
    /// @return amount1 在两个给定价格之间覆盖规模为 liquidity 的头寸所需的 currency1 数量
    function getAmount1Delta(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount1)
    {
        uint256 numerator = absDiff(sqrtPriceAX96, sqrtPriceBX96);
        uint256 denominator = FixedPoint96.Q96;
        uint256 _liquidity = uint256(liquidity);

        /**
         * 等价于：
         *   amount1 = roundUp
         *       ? FullMath.mulDivRoundingUp(liquidity, sqrtPriceBX96 - sqrtPriceAX96, FixedPoint96.Q96)
         *       : FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, FixedPoint96.Q96);
         * 不会溢出，因为 `type(uint128).max * type(uint160).max >> 96 < (1 << 192)`。
         */
        amount1 = FullMath.mulDiv(_liquidity, numerator, denominator);
        assembly ("memory-safe") {
            amount1 := add(amount1, and(gt(mulmod(_liquidity, numerator, denominator), 0), roundUp))
        }
    }

    /// @notice 获取带符号 currency0 delta 的辅助函数
    /// @param sqrtPriceAX96 一个平方根价格
    /// @param sqrtPriceBX96 另一个平方根价格
    /// @param liquidity 用于计算 amount0 delta 的流动性变化量
    /// @return int256 在两个价格之间与传入的 liquidityDelta 相对应的 currency0 数量
    function getAmount0Delta(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, int128 liquidity)
        internal
        pure
        returns (int256)
    {
        unchecked {
            return liquidity < 0
                ? getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(-liquidity), false).toInt256()
                : -getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(liquidity), true).toInt256();
        }
    }

    /// @notice 获取带符号 currency1 delta 的辅助函数
    /// @param sqrtPriceAX96 一个平方根价格
    /// @param sqrtPriceBX96 另一个平方根价格
    /// @param liquidity 用于计算 amount1 delta 的流动性变化量
    /// @return int256 在两个价格之间与传入的 liquidityDelta 相对应的 currency1 数量
    function getAmount1Delta(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, int128 liquidity)
        internal
        pure
        returns (int256)
    {
        unchecked {
            return liquidity < 0
                ? getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(-liquidity), false).toInt256()
                : -getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(liquidity), true).toInt256();
        }
    }
}
