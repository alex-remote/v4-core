// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title 流动性数学库
library LiquidityMath {
    /// @notice 将有符号的流动性 delta 加到流动性上，若溢出或下溢则回滚（revert）
    /// @param x 变更前的流动性
    /// @param y 流动性需要变化的 delta
    /// @return z 流动性 delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        assembly ("memory-safe") {
            z := add(and(x, 0xffffffffffffffffffffffffffffffff), signextend(15, y))
            if shr(128, z) {
                // 以 SafeCastOverflow() 错误回滚（revert）
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
        }
    }
}
