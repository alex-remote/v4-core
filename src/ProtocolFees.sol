// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./types/Currency.sol";
import {CurrencyReserves} from "./libraries/CurrencyReserves.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolId} from "./types/PoolId.sol";
import {Pool} from "./libraries/Pool.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

/// @notice 负责协议手续费设置与累积的合约
abstract contract ProtocolFees is IProtocolFees, Owned {
    using ProtocolFeeLibrary for uint24;
    using Pool for Pool.State;
    using CustomRevert for bytes4;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    address public protocolFeeController;

    constructor(address initialOwner) Owned(initialOwner) {}

    /// @inheritdoc IProtocolFees
    function setProtocolFeeController(address controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(controller);
    }

    /// @inheritdoc IProtocolFees
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external {
        if (msg.sender != protocolFeeController) InvalidCaller.selector.revertWith();
        if (!newProtocolFee.isValidProtocolFee()) ProtocolFeeTooLarge.selector.revertWith(newProtocolFee);
        PoolId id = key.toId();
        _getPool(id).setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(id, newProtocolFee);
    }

    /// @inheritdoc IProtocolFees
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        if (msg.sender != protocolFeeController) InvalidCaller.selector.revertWith();
        if (!currency.isAddressZero() && CurrencyReserves.getSyncedCurrency() == currency) {
            // 防止在 sync 与 settle 两次 balanceOf 之间发生转账（原生代币结算使用 msg.value）
            ProtocolFeeCurrencySynced.selector.revertWith();
        }

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @dev 抽象内部函数，使 ProtocolFees 合约能够访问锁
    function _isUnlocked() internal virtual returns (bool);

    /// @dev 抽象内部函数，使 ProtocolFees 合约能够访问池子状态
    /// @dev 该函数在 PoolManager.sol 中被重写，以提供对 _pools 映射的访问
    function _getPool(PoolId id) internal virtual returns (Pool.State storage);

    function _updateProtocolFees(Currency currency, uint256 amount) internal {
        unchecked {
            protocolFeesAccrued[currency] += amount;
        }
    }
}
