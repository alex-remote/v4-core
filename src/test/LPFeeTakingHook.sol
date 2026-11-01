// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "../types/PoolOperation.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";

/// @notice 一个提取全部 LP 手续费收入的 hook
/// @dev 一个示例测试 hook，用于验证数据是否被正确提供
contract LPFeeTakingHook is BaseTestHooks {
    using Hooks for IHooks;
    using SafeCast for uint256;
    using SafeCast for int128;

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    function afterRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        ModifyLiquidityParams calldata, /* params **/
        BalanceDelta,
        BalanceDelta feeDelta,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        uint128 feeAmount0 = uint128(feeDelta.amount0());
        uint128 feeAmount1 = uint128(feeDelta.amount1());

        if (0 < feeAmount0) manager.take(key.currency0, address(this), feeAmount0);
        if (0 < feeAmount1) manager.take(key.currency1, address(this), feeAmount1);

        return (IHooks.afterRemoveLiquidity.selector, toBalanceDelta(int128(feeAmount0), int128(feeAmount1)));
    }

    function afterAddLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        ModifyLiquidityParams calldata, /* params **/
        BalanceDelta,
        BalanceDelta feeDelta,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        uint128 feeAmount0 = uint128(feeDelta.amount0());
        uint128 feeAmount1 = uint128(feeDelta.amount1());

        if (0 < feeAmount0) manager.take(key.currency0, address(this), feeAmount0);
        if (0 < feeAmount1) manager.take(key.currency1, address(this), feeAmount1);

        return (IHooks.afterAddLiquidity.selector, toBalanceDelta(int128(feeAmount0), int128(feeAmount1)));
    }
}
