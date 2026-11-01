// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title BitMath
/// @dev 该库提供计算无符号整数位属性的功能
/// @author Solady (https://github.com/Vectorized/solady/blob/8200a70e8dc2a77ecb074fc2e99a2a0d36547522/src/utils/LibBit.sol)
library BitMath {
    /// @notice 返回该数的最高有效位的索引，
    ///     其中最低有效位的索引为 0，最高有效位的索引为 255
    /// @param x 要计算其最高有效位的值，必须大于 0
    /// @return r 最高有效位的索引
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);

        assembly ("memory-safe") {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            // forgefmt: disable-next-item
            r := or(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0x0706060506020500060203020504000106050205030304010505030400000000))
        }
    }

    /// @notice 返回该数的最低有效位的索引，
    ///     其中最低有效位的索引为 0，最高有效位的索引为 255
    /// @param x 要计算其最低有效位的值，必须大于 0
    /// @return r 最低有效位的索引
    function leastSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);

        assembly ("memory-safe") {
            // 分离出最低有效位。
            x := and(x, sub(0, x))
            // 对于结果的高 3 位，使用一种类似 De Bruijn 的查找方法。
            // 致谢 adhusson：https://blog.adhusson.com/cheap-find-first-set-evm/
            // forgefmt: disable-next-item
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            // 对于结果的低 5 位，使用 De Bruijn 查找方法。
            // forgefmt: disable-next-item
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }
}
