// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC6909Claims} from "../ERC6909Claims.sol";

/// @notice 用于测试 ERC6909Claims 的 Mock 合约
contract MockERC6909Claims is ERC6909Claims {
    /// @notice 模拟的 mint 逻辑
    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount);
    }

    /// @notice 模拟的 burn 逻辑
    function burn(uint256 id, uint256 amount) public {
        _burn(msg.sender, id, amount);
    }

    /// @notice 模拟的 burn 逻辑，不检查 sender 的授权额度（allowance）
    function burnFrom(address from, uint256 id, uint256 amount) public {
        _burnFrom(from, id, amount);
    }
}
