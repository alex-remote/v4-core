// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 用于访问合约中任意瞬态存储槽的函数接口
interface IExttload {
    /// @notice 由外部合约调用，以访问本合约的瞬态存储
    /// @param slot 要 tload 的存储槽的 key
    /// @return value 该存储槽的值，类型为 bytes32
    function exttload(bytes32 slot) external view returns (bytes32 value);

    /// @notice 由外部合约调用，以访问稀疏的瞬态池子状态
    /// @param slots 要执行 tload 的存储槽列表
    /// @return values 已加载值的列表
    function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory values);
}
