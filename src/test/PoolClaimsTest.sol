// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencySettler} from "../../test/utils/CurrencySettler.sol";

contract PoolClaimsTest is PoolTestBase {
    using CurrencySettler for Currency;
    using SafeCast for uint256;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        address user;
        Currency currency;
        uint256 amount;
        bool deposit;
    }

    /// @notice 将 ERC20 转换为可认领的 6909 claims 凭证
    function deposit(Currency currency, address user, uint256 amount) external payable {
        manager.unlock(abi.encode(CallbackData(msg.sender, user, currency, amount, true)));
    }

    /// @notice 将可认领的 6909 claims 凭证赎回为 ERC20
    function withdraw(Currency currency, address user, uint256 amount) external payable {
        manager.unlock(abi.encode(CallbackData(msg.sender, user, currency, amount, false)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.deposit) {
            data.currency.take(manager, data.user, data.amount, true); // 铸造 6909
            data.currency.settle(manager, data.user, data.amount, false); // 转入 ERC20
        } else {
            data.currency.settle(manager, data.user, data.amount, true); // 销毁 6909
            data.currency.take(manager, data.user, data.amount, false); // 领取 ERC20
        }

        return abi.encode(0);
    }
}
