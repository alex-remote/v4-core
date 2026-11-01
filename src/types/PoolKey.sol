// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./Currency.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {PoolIdLibrary} from "./PoolId.sol";

using PoolIdLibrary for PoolKey global;

/// @notice 返回用于标识一个池子的 key
struct PoolKey {
    /// @notice 池子中按数值排序较小的代币
    Currency currency0;
    /// @notice 池子中按数值排序较大的代币
    Currency currency1;
    /// @notice 池子的 LP 手续费，上限为 1_000_000。若最高位为 1，则该池子使用动态手续费，且该值必须恰好等于 0x800000
    uint24 fee;
    /// @notice 涉及头寸的 tick 必须是 tick 间距的整数倍
    int24 tickSpacing;
    /// @notice 池子的 hook 合约
    IHooks hooks;
}
