// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title 不检查输入或输出的数学函数
/// @notice 包含执行常见数学运算的方法，但不做任何溢出或下溢检查
library UnsafeMath {
    /// @notice 返回 ceil(x / y)
    /// @dev 除以 0 将返回 0，应在外部进行检查
    /// @param x 被除数
    /// @param y 除数
    /// @return z 商，即 ceil(x / y)
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    /// @notice 计算 floor(a×b÷denominator)
    /// @dev 除以 0 将返回 0，应在外部进行检查
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result 256 位的结果，即 floor(a×b÷denominator)
    function simpleMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            result := div(mul(a, b), denominator)
        }
    }
}
