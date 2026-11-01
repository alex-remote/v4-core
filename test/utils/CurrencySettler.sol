// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "../../src/types/Currency.sol";
import {IERC20Minimal} from "../../src/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";

/// @notice 用于与 PoolManager.sol 交互、结算任何未结清 delta 的库。
/// 要结算正的 delta（用户的应收款），用户可以提取（take）或铸造（mint）。
/// 要结算负的 delta（用户的欠款），用户可以通过转账或销毁（burn）来偿还债务。
/// @dev 注意，在 `settle` 中进行任何 erc-20 转账之前都会先调用 sync()。
library CurrencySettler {
    /// @notice 向 PoolManager 结算（支付）一种代币
    /// @param currency 要结算的代币
    /// @param manager 结算的目标 IPoolManager
    /// @param payer 付款方地址，即代币发送方
    /// @param amount 要发送的数量
    /// @param burn 若为 true，则销毁 ERC-6909 代币，否则通过 ERC20 转账转给 PoolManager
    function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal {
        // 对于原生代币或销毁操作，无需调用 sync
        // 对 ERC-6909 销毁直接短路处理，以支持 ERC-6909 封装的原生代币
        if (burn) {
            manager.burn(payer, currency.toId(), amount);
        } else if (currency.isAddressZero()) {
            manager.settle{value: amount}();
        } else {
            manager.sync(currency);
            if (payer != address(this)) {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount);
            }
            manager.settle();
        }
    }

    /// @notice 从 PoolManager 提取（接收）一种代币
    /// @param currency 要提取的代币
    /// @param manager 提取来源的 IPoolManager
    /// @param recipient 接收方地址，即代币接收者
    /// @param amount 要接收的数量
    /// @param claims 若为 true，则铸造 ERC-6909 代币，否则通过 ERC20 转账从 PoolManager 转给接收方
    function take(Currency currency, IPoolManager manager, address recipient, uint256 amount, bool claims) internal {
        claims ? manager.mint(recipient, currency.toId(), amount) : manager.take(currency, recipient, amount);
    }
}
