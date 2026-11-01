// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "../types/Currency.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

/// @notice 池子管理器（pool manager）中所有与协议手续费相关的函数的接口
interface IProtocolFees {
    /// @notice 当协议手续费设置过高时抛出
    error ProtocolFeeTooLarge(uint24 fee);

    /// @notice 当 collectProtocolFees 或 setProtocolFee 不是由控制者（controller）调用时抛出。
    error InvalidCaller();

    /// @notice 当尝试对一个已同步（synced）的代币调用 collectProtocolFees 时抛出。
    error ProtocolFeeCurrencySynced();

    /// @notice 在 setProtocolFeeController 中更新协议手续费控制者地址时触发。
    event ProtocolFeeControllerUpdated(address indexed protocolFeeController);

    /// @notice 当某个池子的协议手续费被更新时触发。
    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFee);

    /// @notice 给定一个代币地址，返回以该代币累积的协议手续费
    /// @param currency 要查询的代币
    /// @return amount 以该代币累积的协议手续费数量
    function protocolFeesAccrued(Currency currency) external view returns (uint256 amount);

    /// @notice 为给定池子设置协议手续费
    /// @param key 要设置协议手续费的池子的 key
    /// @param newProtocolFee 要设置的手续费
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external;

    /// @notice 设置协议手续费控制者
    /// @param controller 新的协议手续费控制者
    function setProtocolFeeController(address controller) external;

    /// @notice 为给定的接收者和代币收取协议手续费，并返回收取的数量
    /// @dev 如果合约处于解锁状态，调用将回滚（revert）
    /// @param recipient 接收协议手续费的地址
    /// @param currency 要提取的代币
    /// @param amount 要提取的代币数量
    /// @return amountCollected 成功提取的代币数量
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected);

    /// @notice 返回当前的协议手续费控制者地址
    /// @return address 当前的协议手续费控制者地址
    function protocolFeeController() external view returns (address);
}
