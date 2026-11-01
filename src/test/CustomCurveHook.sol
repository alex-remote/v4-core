// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "../types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "../types/BeforeSwapDelta.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {CurrencySettler} from "../../test/utils/CurrencySettler.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";
import {Currency} from "../types/Currency.sol";

contract CustomCurveHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencySettler for Currency;

    error AddLiquidityDirectToHook();

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        (Currency inputCurrency, Currency outputCurrency, uint256 amount) = _getInputOutputAndAmount(key, params);

        // 这条“自定义曲线”是一条直线，兑换比例为 1:1
        // 提取全部输入数量，并支付全部输出数量
        manager.take(inputCurrency, address(this), amount);
        outputCurrency.settle(manager, address(this), amount, false);

        // 将 -amountSpecified 作为指定代币的 delta 返回，使集中流动性兑换（swap）成为空操作（no-op）
        BeforeSwapDelta hookDelta = toBeforeSwapDelta(int128(-params.amountSpecified), int128(params.amountSpecified));
        return (IHooks.beforeSwap.selector, hookDelta, 0);
    }

    function afterAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        ModifyLiquidityParams calldata, /* params **/
        BalanceDelta, /* delta **/
        BalanceDelta, /* feeDelta **/
        bytes calldata /* hookData **/
    ) external view override onlyPoolManager returns (bytes4, BalanceDelta) {
        revert AddLiquidityDirectToHook();
    }

    function _getInputOutputAndAmount(PoolKey calldata key, SwapParams calldata params)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
    }
}
