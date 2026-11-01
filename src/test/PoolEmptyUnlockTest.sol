// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";

contract PoolEmptyUnlockTest is IUnlockCallback {
    event UnlockCallback();

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function unlock() external {
        manager.unlock("");
    }

    /// @notice 当 manager 被解锁时，由 pool manager 在 `msg.sender` 上调用
    function unlockCallback(bytes calldata) external override returns (bytes memory) {
        emit UnlockCallback();
        return "";
    }
}
