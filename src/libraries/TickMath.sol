// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BitMath} from "./BitMath.sol";
import {CustomRevert} from "./CustomRevert.sol";

/// @title 用于根据 tick 计算平方根价格及其逆运算的数学库
/// @notice 计算以 1.0001 为步长的 tick 对应的平方根价格，即 sqrt(1.0001^tick)，结果为 Q64.96 定点数。支持
/// 介于 2**-128 与 2**128 之间的价格
library TickMath {
    using CustomRevert for bytes4;

    /// @notice 当传给 #getSqrtPriceAtTick 的 tick 不在 MIN_TICK 与 MAX_TICK 之间时抛出
    error InvalidTick(int24 tick);
    /// @notice 当传给 #getTickAtSqrtPrice 的价格不对应于 MIN_TICK 与 MAX_TICK 之间的价格时抛出
    error InvalidSqrtPrice(uint160 sqrtPriceX96);

    /// @dev 可传给 #getSqrtPriceAtTick 的最小 tick，由以 1.0001 为底 2**-128 的对数计算得出
    /// @dev 如果 MIN_TICK 与 MAX_TICK 不再以 0 为中心对称，则 getSqrtPriceAtTick 中的 absTick 逻辑将不能使用
    int24 internal constant MIN_TICK = -887272;
    /// @dev 可传给 #getSqrtPriceAtTick 的最大 tick，由以 1.0001 为底 2**128 的对数计算得出
    /// @dev 如果 MIN_TICK 与 MAX_TICK 不再以 0 为中心对称，则 getSqrtPriceAtTick 中的 absTick 逻辑将不能使用
    int24 internal constant MAX_TICK = 887272;

    /// @dev 从 int16 类型取值范围中选取的大于 0 的最小 tick 间距值，即区间 [1, 32767] 中的最小值
    int24 internal constant MIN_TICK_SPACING = 1;
    /// @dev 从 int16 类型取值范围中选取的最大 tick 间距值，即区间 [1, 32767] 中的最大值
    int24 internal constant MAX_TICK_SPACING = type(int16).max;

    /// @dev #getSqrtPriceAtTick 可返回的最小值，等同于 getSqrtPriceAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    /// @dev #getSqrtPriceAtTick 可返回的最大值，等同于 getSqrtPriceAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;
    /// @dev 用于优化边界检查的阈值，等于 `MAX_SQRT_PRICE - MIN_SQRT_PRICE - 1`
    uint160 internal constant MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE =
        1461446703485210103287273052203988822378723970342 - 4295128739 - 1;

    /// @notice 给定 tickSpacing，计算可用的最大 tick
    function maxUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (MAX_TICK / tickSpacing) * tickSpacing;
        }
    }

    /// @notice 给定 tickSpacing，计算可用的最小 tick
    function minUsableTick(int24 tickSpacing) internal pure returns (int24) {
        unchecked {
            return (MIN_TICK / tickSpacing) * tickSpacing;
        }
    }

    /// @notice 计算 sqrt(1.0001^tick) * 2^96
    /// @dev 若 |tick| > 最大 tick 则抛出异常
    /// @param tick 上述公式的输入 tick
    /// @return sqrtPriceX96 一个 Q64.96 定点数，表示两种资产价格（currency1/currency0）的平方根
    /// （在给定 tick 处）
    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        unchecked {
            uint256 absTick;
            assembly ("memory-safe") {
                tick := signextend(2, tick)
                // 若 tick >= 0 则 mask = 0，否则 mask = -1（所有位均为 1）
                let mask := sar(255, tick)
                // 若 tick >= 0，|tick| = tick = 0 ^ tick
                // 若 tick < 0，|tick| = ~~|tick| = ~(-|tick| - 1) = ~(tick - 1) = (-1) ^ (tick - 1)
                // 无论哪种情况，|tick| = mask ^ (tick + mask)
                absTick := xor(mask, add(mask, tick))
            }

            if (absTick > uint256(int256(MAX_TICK))) InvalidTick.selector.revertWith(tick);

            // 将 tick 按位分解，对于每个被置位的第 i 位，计算 1/sqrt(1.0001^(2^i)) 的乘积
            // （使用 Q128.128 表示）。此计算所用的常量均已四舍五入到最接近的整数

            // 等价于：
            //     price = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
            //     或 price = int(2**128 / sqrt(1.0001)) if (absTick & 0x1) else 1 << 128
            uint256 price;
            assembly ("memory-safe") {
                price := xor(shl(128, 1), mul(xor(shl(128, 1), 0xfffcb933bd6fad37aa2d162d1a594001), and(absTick, 0x1)))
            }
            if (absTick & 0x2 != 0) price = (price * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) price = (price * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) price = (price * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) price = (price * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) price = (price * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) price = (price * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) price = (price * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) price = (price * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) price = (price * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) price = (price * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) price = (price * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) price = (price * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) price = (price * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) price = (price * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) price = (price * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) price = (price * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) price = (price * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) price = (price * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) price = (price * 0x48a170391f7dc42444e8fa2) >> 128;

            assembly ("memory-safe") {
                // if (tick > 0) price = type(uint256).max / price;
                if sgt(tick, 0) { price := div(not(0), price) }

                // 除以 1<<32 并向上取整，从而将 Q128.128 转换为 Q128.96。
                // 随后进行向下类型转换，因为输入 tick 的约束保证了结果总能放入 160 位
                // 除法中向上取整，以保证对输出价格调用 getTickAtSqrtPrice 的结果始终一致
                // `sub(shl(32, 1), 1)` 即 `type(uint32).max`
                // `price + type(uint32).max` 不会溢出，因为 `price` 可放入 192 位
                sqrtPriceX96 := shr(32, add(price, sub(shl(32, 1), 1)))
            }
        }
    }

    /// @notice 计算满足 getSqrtPriceAtTick(tick) <= sqrtPriceX96 的最大 tick 值
    /// @dev 当 sqrtPriceX96 < MIN_SQRT_PRICE 时抛出异常，因为 MIN_SQRT_PRICE 是 getSqrtPriceAtTick
    /// 可能返回的最小值。
    /// @param sqrtPriceX96 用于计算 tick 的平方根价格，格式为 Q64.96
    /// @return tick 满足 getSqrtPriceAtTick(tick) 小于或等于输入 sqrtPriceX96 的最大 tick
    function getTickAtSqrtPrice(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        unchecked {
            // 等价于：if (sqrtPriceX96 < MIN_SQRT_PRICE || sqrtPriceX96 >= MAX_SQRT_PRICE) revert InvalidSqrtPrice();
            // 第二个不等式必须用 >=，因为价格永远无法达到最大 tick 处的价格
            // 若 sqrtPriceX96 < MIN_SQRT_PRICE，`sub` 会下溢，`gt` 结果为 true
            // 若 sqrtPriceX96 >= MAX_SQRT_PRICE，则 sqrtPriceX96 - MIN_SQRT_PRICE > MAX_SQRT_PRICE - MIN_SQRT_PRICE - 1
            if ((sqrtPriceX96 - MIN_SQRT_PRICE) > MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE) {
                InvalidSqrtPrice.selector.revertWith(sqrtPriceX96);
            }

            uint256 price = uint256(sqrtPriceX96) << 32;

            uint256 r = price;
            uint256 msb = BitMath.mostSignificantBit(r);

            if (msb >= 128) r = price >> (msb - 127);
            else r = price << (127 - msb);

            int256 log_2 = (int256(msb) - 128) << 64;

            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(63, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(62, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(61, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(60, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(59, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(58, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(57, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(56, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(55, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(54, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(53, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(52, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(51, f))
                r := shr(f, r)
            }
            assembly ("memory-safe") {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(50, f))
            }

            int256 log_sqrt10001 = log_2 * 255738958999603826347141; // Q22.128 格式的数

            // 该魔数表示近似计算 log_sqrt10001(x) 时误差最大值的上取整
            int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);

            // 该魔数表示近似计算 log_sqrt10001(x) 时误差的最小值，前提是
            // sqrtPrice 位于区间 (2^-64, 2^64) 内。由于 MIN_SQRT_PRICE 大于 2^-64，这是安全的。如果 MIN_SQRT_PRICE
            // 发生变化，此值可能也需要相应修改
            int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

            tick = tickLow == tickHi ? tickLow : getSqrtPriceAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
        }
    }
}
