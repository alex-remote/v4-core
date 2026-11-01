// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice 对合约余额的 claims 凭证的接口，以 ERC6909 的形式封装
interface IERC6909Claims {
    /*//////////////////////////////////////////////////////////////
                                 事件
    //////////////////////////////////////////////////////////////*/

    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);

    event Transfer(address caller, address indexed from, address indexed to, uint256 indexed id, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 函数
    //////////////////////////////////////////////////////////////*/

    /// @notice 所有者在某个 id 上的余额。
    /// @param owner 所有者的地址。
    /// @param id 代币的 id。
    /// @return amount 该代币的余额。
    function balanceOf(address owner, uint256 id) external view returns (uint256 amount);

    /// @notice 花费者在某个 id 上的授权额度。
    /// @param owner 所有者的地址。
    /// @param spender 花费者的地址。
    /// @param id 代币的 id。
    /// @return amount 该代币的授权额度。
    function allowance(address owner, address spender, uint256 id) external view returns (uint256 amount);

    /// @notice 检查某个花费者是否被所有者批准为操作员（operator）
    /// @param owner 所有者的地址。
    /// @param spender 花费者的地址。
    /// @return approved 批准状态。
    function isOperator(address owner, address spender) external view returns (bool approved);

    /// @notice 将某个 id 的一定数量代币从调用者转给接收者。
    /// @param receiver 接收者的地址。
    /// @param id 代币的 id。
    /// @param amount 代币的数量。
    /// @return bool 始终返回 True，除非函数回滚（revert）
    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool);

    /// @notice 将某个 id 的一定数量代币从发送者转给接收者。
    /// @param sender 发送者的地址。
    /// @param receiver 接收者的地址。
    /// @param id 代币的 id。
    /// @param amount 代币的数量。
    /// @return bool 始终返回 True，除非函数回滚（revert）
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external returns (bool);

    /// @notice 向某个花费者授权某个 id 的一定数量代币。
    /// @param spender 花费者的地址。
    /// @param id 代币的 id。
    /// @param amount 代币的数量。
    /// @return bool 始终返回 True
    function approve(address spender, uint256 id, uint256 amount) external returns (bool);

    /// @notice 为调用者设置或移除一个操作员。
    /// @param operator 操作员的地址。
    /// @param approved 批准状态。
    /// @return bool 始终返回 True
    function setOperator(address operator, bool approved) external returns (bool);
}
