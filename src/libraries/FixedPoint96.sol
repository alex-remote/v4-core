// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title FixedPoint96
/// @notice 用于处理二进制定点数的库，参见 https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev 在 SqrtPriceMath.sol 中使用
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
