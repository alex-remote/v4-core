// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "../types/PoolOperation.sol";
import {BeforeSwapDelta} from "../types/BeforeSwapDelta.sol";

/// @notice V4 通过检查 hook 合约所部署地址的最低有效位（least significant bits），
/// 来决定是否调用特定的 hook。
/// 例如，部署在地址 0x0000000000000000000000000000000000002400 的 hook 合约，
/// 其最低位为 '10 0100 0000 0000'，这会使 'before initialize' 和 'after add liquidity' 两个 hook 被启用。
/// 完整规范请参阅 Hooks 库。
/// @dev 只应由 v4 PoolManager 调用。
interface IHooks {
    /// @notice 在池子状态初始化之前调用的 hook
    /// @param sender initialize 调用的初始 msg.sender
    /// @param key 正在初始化的池子的 key
    /// @param sqrtPriceX96 池子的 sqrt(price)，格式为 Q64.96
    /// @return bytes4 该 hook 的函数选择器
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) external returns (bytes4);

    /// @notice 在池子状态初始化之后调用的 hook
    /// @param sender initialize 调用的初始 msg.sender
    /// @param key 正在初始化的池子的 key
    /// @param sqrtPriceX96 池子的 sqrt(price)，格式为 Q64.96
    /// @param tick 池子状态初始化之后的当前 tick
    /// @return bytes4 该 hook 的函数选择器
    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        returns (bytes4);

    /// @notice 在添加流动性之前调用的 hook
    /// @param sender 添加流动性调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param params 添加流动性的参数
    /// @param hookData 由流动性提供者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice 在添加流动性之后调用的 hook
    /// @param sender 添加流动性调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param params 添加流动性的参数
    /// @param delta 添加流动性后调用者的余额差额；等于本金 delta、累积的手续费与 hook delta 之和
    /// @param feesAccrued 自上次从该头寸收取手续费以来累积的手续费
    /// @param hookData 由流动性提供者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    /// @return BalanceDelta hook 在 token0 和 token1 上的 delta。正值：hook 应收/已提取代币；负值：hook 应付/已发送代币
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta);

    /// @notice 在移除流动性之前调用的 hook
    /// @param sender 移除流动性调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param params 移除流动性的参数
    /// @param hookData 由流动性提供者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice 在移除流动性之后调用的 hook
    /// @param sender 移除流动性调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param params 移除流动性的参数
    /// @param delta 移除流动性后调用者的余额差额；等于本金 delta、累积的手续费与 hook delta 之和
    /// @param feesAccrued 自上次从该头寸收取手续费以来累积的手续费
    /// @param hookData 由流动性提供者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    /// @return BalanceDelta hook 在 token0 和 token1 上的 delta。正值：hook 应收/已提取代币；负值：hook 应付/已发送代币
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta);

    /// @notice 在兑换（swap）之前调用的 hook
    /// @param sender swap 调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param params 兑换的参数
    /// @param hookData 由兑换者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    /// @return BeforeSwapDelta hook 在指定代币与非指定代币上的 delta。正值：hook 应收/已提取代币；负值：hook 应付/已发送代币
    /// @return uint24 可选地覆盖 LP 手续费，仅在同时满足以下三个条件时生效：1. 池子使用动态手续费；2. 该值的次高位已置位（第 23 位，0x400000）；3. 该值小于或等于最大手续费（1 million，即 100 万）
    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24);

    /// @notice 在兑换（swap）之后调用的 hook
    /// @param sender swap 调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param params 兑换的参数
    /// @param delta 欠调用者的数额（正值）或欠池子的数额（负值）
    /// @param hookData 由兑换者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    /// @return int128 hook 在非指定代币上的 delta。正值：hook 应收/已提取代币；负值：hook 应付/已发送代币
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);

    /// @notice 在捐赠（donate）之前调用的 hook
    /// @param sender donate 调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param amount0 被捐赠的 token0 数量
    /// @param amount1 被捐赠的 token1 数量
    /// @param hookData 由捐赠者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice 在捐赠（donate）之后调用的 hook
    /// @param sender donate 调用的初始 msg.sender
    /// @param key 池子的 key
    /// @param amount0 被捐赠的 token0 数量
    /// @param amount1 被捐赠的 token1 数量
    /// @param hookData 由捐赠者传入 PoolManager、再转交给 hook 的任意数据
    /// @return bytes4 该 hook 的函数选择器
    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (bytes4);
}
