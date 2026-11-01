// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice 某个地址解锁池子管理器时所执行的回调的接口
interface IUnlockCallback {
    /// @notice 当管理器被解锁时，由池子管理器在 `msg.sender` 上调用
    /// @param data 传给 unlock 调用的数据
    /// @return 任何你希望从 unlock 调用中返回的数据
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}
