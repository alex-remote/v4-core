// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../types/Currency.sol";
import {CurrencyReserves} from "./CurrencyReserves.sol";
import {NonzeroDeltaCount} from "./NonzeroDeltaCount.sol";
import {Lock} from "./Lock.sol";

/// @notice 一个辅助库，提供基于 exttload 的状态读取函数
library TransientStateLibrary {
    /// @notice 返回已同步代币的储备
    /// @param manager PoolManager 合约。

    /// @return uint256 该代币的储备。
    /// @dev 若储备未同步或其值为 0，则返回 0。
    /// 通过检查已同步的代币，确保只返回有效的储备值（在同步之后、结算之前）。
    function getSyncedReserves(IPoolManager manager) internal view returns (uint256) {
        if (getSyncedCurrency(manager).isAddressZero()) return 0;
        return uint256(manager.exttload(CurrencyReserves.RESERVES_OF_SLOT));
    }

    function getSyncedCurrency(IPoolManager manager) internal view returns (Currency) {
        return Currency.wrap(address(uint160(uint256(manager.exttload(CurrencyReserves.CURRENCY_SLOT)))));
    }

    /// @notice 返回 PoolManager 上未结清的非零 delta 数量，这些 delta 必须在合约锁定前清零
    function getNonzeroDeltaCount(IPoolManager manager) internal view returns (uint256) {
        return uint256(manager.exttload(NonzeroDeltaCount.NONZERO_DELTA_COUNT_SLOT));
    }

    /// @notice 获取某调用者在给定代币上的当前 delta
    /// @param target 被记账的账户地址
    /// @param currency 要查询 delta 的代币
    function currencyDelta(IPoolManager manager, address target, Currency currency) internal view returns (int256) {
        bytes32 key;
        assembly ("memory-safe") {
            mstore(0, and(target, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(32, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
            key := keccak256(0, 64)
        }
        return int256(uint256(manager.exttload(key)));
    }

    /// @notice 返回合约当前是否处于解锁状态
    function isUnlocked(IPoolManager manager) internal view returns (bool) {
        return manager.exttload(Lock.IS_UNLOCKED_SLOT) != 0x0;
    }
}
