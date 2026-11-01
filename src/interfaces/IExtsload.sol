// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice 用于访问合约中任意存储槽的函数接口
interface IExtsload {
    /// @notice 由外部合约调用，以访问细粒度的池子状态
    /// @param slot 要 sload 的存储槽的 key
    /// @return value 该存储槽的值，类型为 bytes32
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice 由外部合约调用，以访问细粒度的池子状态
    /// @param startSlot 开始 sload 的起始存储槽的 key
    /// @param nSlots 要加载到返回值中的存储槽数量
    /// @return values 已加载值的列表。
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values);

    /// @notice 由外部合约调用，以访问稀疏的池子状态
    /// @param slots 要执行 SLOAD 的存储槽列表。
    /// @return values 已加载值的列表。
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values);
}
