// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title 供 Uniswap 使用的最小化 ERC20 接口
/// @notice 包含 Uniswap V3 中用到的完整 ERC20 接口的一个子集
interface IERC20Minimal {
    /// @notice 返回某个账户持有的该代币余额
    /// @param account 要查询其持有代币数量（即余额）的账户
    /// @return 该账户持有的代币数量
    function balanceOf(address account) external view returns (uint256);

    /// @notice 将指定数量的代币从 `msg.sender` 转给接收者
    /// @param recipient 接收转账金额的账户
    /// @param amount 从发送者转给接收者的代币数量
    /// @return 转账成功返回 true，失败返回 false
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @notice 返回所有者授予某个花费者（spender）的当前授权额度
    /// @param owner 代币所有者的账户
    /// @param spender 代币花费者的账户
    /// @return `owner` 授予 `spender` 的当前授权额度
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice 将 `msg.sender` 授予某个花费者的授权额度设置为 `amount`
    /// @param spender 将被允许花费所有者一定数量代币的账户
    /// @param amount 允许 `spender` 使用的代币数量
    /// @return 授权成功返回 true，失败返回 false
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice 在授予 `msg.sender` 的授权额度内，将 `amount` 个代币从 `sender` 转给 `recipient`
    /// @param sender 转账的发起账户（代币转出方）
    /// @param recipient 转账的接收者
    /// @param amount 转账数量
    /// @return 转账成功返回 true，失败返回 false
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /// @notice 当代币通过 `#transfer` 或 `#transferFrom` 从一个地址转到另一个地址时触发的事件。
    /// @param from 代币转出的账户，即余额减少的一方
    /// @param to 代币转入的账户，即余额增加的一方
    /// @param value 转移的代币数量
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice 当某个所有者的代币对某个花费者的授权额度发生变化时触发的事件。
    /// @param owner 批准他人花费其代币的账户
    /// @param spender 花费授权额度被修改的账户
    /// @param value 所有者授予花费者的新授权额度
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
