// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CustomRevert} from "./CustomRevert.sol";

/// @title 安全类型转换方法
/// @notice 包含在不同类型之间进行安全转换的方法
library SafeCast {
    using CustomRevert for bytes4;

    error SafeCastOverflow();

    /// @notice 将 uint256 转换为 uint160，溢出时回滚（revert）
    /// @param x 要向下转换的 uint256
    /// @return y 向下转换后的整数，类型为 uint160
    function toUint160(uint256 x) internal pure returns (uint160 y) {
        y = uint160(x);
        if (y != x) SafeCastOverflow.selector.revertWith();
    }

    /// @notice 将 uint256 转换为 uint128，溢出时回滚（revert）
    /// @param x 要向下转换的 uint256
    /// @return y 向下转换后的整数，类型为 uint128
    function toUint128(uint256 x) internal pure returns (uint128 y) {
        y = uint128(x);
        if (x != y) SafeCastOverflow.selector.revertWith();
    }

    /// @notice 将 int128 转换为 uint128，溢出或下溢时回滚（revert）
    /// @param x 要转换的 int128
    /// @return y 转换后的整数，类型为 uint128
    function toUint128(int128 x) internal pure returns (uint128 y) {
        if (x < 0) SafeCastOverflow.selector.revertWith();
        y = uint128(x);
    }

    /// @notice 将 int256 转换为 int128，溢出或下溢时回滚（revert）
    /// @param x 要向下转换的 int256
    /// @return y 向下转换后的整数，类型为 int128
    function toInt128(int256 x) internal pure returns (int128 y) {
        y = int128(x);
        if (y != x) SafeCastOverflow.selector.revertWith();
    }

    /// @notice 将 uint256 转换为 int256，溢出时回滚（revert）
    /// @param x 要转换的 uint256
    /// @return y 转换后的整数，类型为 int256
    function toInt256(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        if (y < 0) SafeCastOverflow.selector.revertWith();
    }

    /// @notice 将 uint256 转换为 int128，溢出时回滚（revert）
    /// @param x 要向下转换的 uint256
    /// @return 向下转换后的整数，类型为 int128
    function toInt128(uint256 x) internal pure returns (int128) {
        if (x >= 1 << 127) SafeCastOverflow.selector.revertWith();
        return int128(int256(x));
    }
}
