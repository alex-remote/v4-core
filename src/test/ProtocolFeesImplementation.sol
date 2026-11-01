// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ProtocolFees} from "../ProtocolFees.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {PoolId} from "../types/PoolId.sol";
import {Pool} from "../libraries/Pool.sol";
import {Slot0} from "../types/Slot0.sol";

contract ProtocolFeesImplementation is ProtocolFees {
    mapping(PoolId id => Pool.State) internal _pools;
    bool internal isUnlocked;

    constructor() ProtocolFees(msg.sender) {}

    // 用于设置池子的价格，假装该池子已被初始化，从而能够成功设置协议手续费
    function setPrice(PoolKey memory key, uint160 sqrtPriceX96) public {
        Pool.State storage pool = _getPool(key.toId());
        pool.slot0 = pool.slot0.setSqrtPriceX96(sqrtPriceX96);
    }

    function _getPool(PoolId id) internal view override returns (Pool.State storage) {
        return _pools[id];
    }

    function setIsUnlocked(bool newValue) public {
        isUnlocked = newValue;
    }

    function _isUnlocked() internal view override returns (bool) {
        return isUnlocked;
    }

    function updateProtocolFees(Currency currency, uint256 amount) public {
        ProtocolFees._updateProtocolFees(currency, amount);
    }
}
