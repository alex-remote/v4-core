// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

/// @notice `ModifyLiquidity` 池子操作的参数结构体
struct ModifyLiquidityParams {
    // 头寸的下界 tick 与上界 tick
    int24 tickLower;
    int24 tickUpper;
    // 如何修改流动性
    int256 liquidityDelta;
    // 若希望在同一价格区间内拥有相互独立的流动性头寸，可设置此值
    bytes32 salt;
}

/// @notice `Swap` 池子操作的参数结构体
struct SwapParams {
    /// 是用 token0 兑换 token1，还是反过来
    bool zeroForOne;
    /// 为负时表示期望的输入数量（exactIn），为正时表示期望的输出数量（exactOut）
    int256 amountSpecified;
    /// 平方根价格限制：一旦达到该价格，兑换（swap）将停止执行
    uint160 sqrtPriceLimitX96;
}
