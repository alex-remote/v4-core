// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC6909} from "./ERC6909.sol";

/// @notice ERC6909Claims 继承 ERC6909，并实现了一个内部的 burnFrom 函数
abstract contract ERC6909Claims is ERC6909 {
    /// @notice 从 `from` 处销毁 `amount` 数量、代币类型为 `id` 的代币。
    /// @dev 如果 sender 不是 `from`，则其必须是 operator 或拥有足够的授权额度（allowance）。
    /// @param from 被销毁代币的地址。
    /// @param id 要销毁的代币。
    /// @param amount 要销毁的数量。
    function _burnFrom(address from, uint256 id, uint256 amount) internal {
        address sender = msg.sender;
        if (from != sender && !isOperator[from][sender]) {
            uint256 senderAllowance = allowance[from][sender][id];
            if (senderAllowance != type(uint256).max) {
                allowance[from][sender][id] = senderAllowance - amount;
            }
        }
        _burn(from, id, amount);
    }
}
