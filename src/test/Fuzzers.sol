// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "../types/PoolOperation.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {Pool} from "../libraries/Pool.sol";
import {PoolModifyLiquidityTest} from "./PoolModifyLiquidityTest.sol";
import {LiquidityAmounts} from "../../test/utils/LiquidityAmounts.sol";
import {SafeCast} from "../../src/libraries/SafeCast.sol";

contract Fuzzers is StdUtils {
    using SafeCast for uint256;

    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function boundLiquidityDelta(PoolKey memory key, int256 liquidityDeltaUnbounded, int256 liquidityMaxByAmount)
        internal
        pure
        returns (int256)
    {
        int256 liquidityMaxPerTick = int256(uint256(Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing)));

        // 最后，用每个 tick 的流动性上限或头寸区间允许的数量（取较小者）来约束种子流动性。
        int256 liquidityMax = liquidityMaxByAmount > liquidityMaxPerTick ? liquidityMaxPerTick : liquidityMaxByAmount;
        _vm.assume(liquidityMax != 0);
        return bound(liquidityDeltaUnbounded, 1, liquidityMax);
    }

    // 使用 tickSpacingToMaxLiquidityPerTick/2 作为可能的上界之一。
    // 对于触及同一 tick 的多个头寸，可能需要将该值调整得更严格。
    function boundLiquidityDeltaTightly(
        PoolKey memory key,
        int256 liquidityDeltaUnbounded,
        int256 liquidityMaxByAmount,
        uint256 maxPositions
    ) internal pure returns (int256) {
        // 除以一半以更严格地约束流动性。TODO：可能有更好的做法。
        int256 liquidityMaxTightBound =
            int256(uint256(Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing)) / maxPositions);

        // 最后，用每个 tick 的流动性上限或头寸区间允许的数量（取较小者）来约束种子流动性。
        int256 liquidityMax =
            liquidityMaxByAmount > liquidityMaxTightBound ? liquidityMaxTightBound : liquidityMaxByAmount;
        _vm.assume(liquidityMax != 0);
        return bound(liquidityDeltaUnbounded, 1, liquidityMax);
    }

    function getLiquidityDeltaFromAmounts(int24 tickLower, int24 tickUpper, uint160 sqrtPriceX96)
        internal
        pure
        returns (int256)
    {
        // 首先获取在该区间内可存入的最大 amount0 和最大 amount1。
        (uint256 maxAmount0, uint256 maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(type(int128).max)
        );

        // 将最大数量（由头寸区间决定）与类型容器所限制的最大数量进行比较。
        // 真正的最大值应取两者中的较小者。
        // （即如果头寸区间允许任一代币存入超过 int128.max 的数量，则此处将其上限截断为 int128.max。）

        uint256 amount0 = uint256(type(uint128).max / 2);
        uint256 amount1 = uint256(type(uint128).max / 2);

        maxAmount0 = maxAmount0 > amount0 ? amount0 : maxAmount0;
        maxAmount1 = maxAmount1 > amount1 ? amount1 : maxAmount1;

        int256 liquidityMaxByAmount = uint256(
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                maxAmount0,
                maxAmount1
            )
        ).toInt256();

        return liquidityMaxByAmount;
    }

    function boundTicks(int24 tickLower, int24 tickUpper, int24 tickSpacing) internal pure returns (int24, int24) {
        tickLower = int24(
            bound(
                int256(tickLower),
                int256(TickMath.minUsableTick(tickSpacing)),
                int256(TickMath.maxUsableTick(tickSpacing))
            )
        );
        tickUpper = int24(
            bound(
                int256(tickUpper),
                int256(TickMath.minUsableTick(tickSpacing)),
                int256(TickMath.maxUsableTick(tickSpacing))
            )
        );

        // 将 tick 向下取整（对齐到 tick 间距）
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;

        (tickLower, tickUpper) = tickLower < tickUpper ? (tickLower, tickUpper) : (tickUpper, tickLower);

        if (tickLower == tickUpper) {
            if (tickLower != TickMath.minUsableTick(tickSpacing)) tickLower = tickLower - tickSpacing;
            else tickUpper = tickUpper + tickSpacing;
        }

        return (tickLower, tickUpper);
    }

    function boundTicks(PoolKey memory key, int24 tickLower, int24 tickUpper) internal pure returns (int24, int24) {
        return boundTicks(tickLower, tickUpper, key.tickSpacing);
    }

    function createRandomSqrtPriceX96(int24 tickSpacing, int256 seed) internal pure returns (uint160) {
        int256 min = int256(TickMath.minUsableTick(tickSpacing));
        int256 max = int256(TickMath.maxUsableTick(tickSpacing));
        int256 randomTick = bound(seed, min + 1, max - 1);
        return TickMath.getSqrtPriceAtTick(int24(randomTick));
    }

    /// @dev 获取用于创建流动性的、经过模糊测试且已约束的参数
    /// @param key 池子 key
    /// @param params IPoolManager.ModifyLiquidityParams 注意这些参数是未经约束的
    /// @param sqrtPriceX96 当前的平方根价格
    function createFuzzyLiquidityParams(PoolKey memory key, ModifyLiquidityParams memory params, uint160 sqrtPriceX96)
        internal
        pure
        returns (ModifyLiquidityParams memory result)
    {
        (result.tickLower, result.tickUpper) = boundTicks(key, params.tickLower, params.tickUpper);
        int256 liquidityDeltaFromAmounts =
            getLiquidityDeltaFromAmounts(result.tickLower, result.tickUpper, sqrtPriceX96);
        result.liquidityDelta = boundLiquidityDelta(key, params.liquidityDelta, liquidityDeltaFromAmounts);
    }

    // 以更严格的上界创建流动性参数。当池子上会初始化多个头寸、且 tick 可能重叠时应使用此函数。
    function createFuzzyLiquidityParamsWithTightBound(
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        uint160 sqrtPriceX96,
        uint256 maxPositions
    ) internal pure returns (ModifyLiquidityParams memory result) {
        (result.tickLower, result.tickUpper) = boundTicks(key, params.tickLower, params.tickUpper);
        int256 liquidityDeltaFromAmounts =
            getLiquidityDeltaFromAmounts(result.tickLower, result.tickUpper, sqrtPriceX96);

        result.liquidityDelta =
            boundLiquidityDeltaTightly(key, params.liquidityDelta, liquidityDeltaFromAmounts, maxPositions);
    }

    function createFuzzyLiquidity(
        PoolModifyLiquidityTest modifyLiquidityRouter,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        uint160 sqrtPriceX96,
        bytes memory hookData
    ) internal returns (ModifyLiquidityParams memory result, BalanceDelta delta) {
        result = createFuzzyLiquidityParams(key, params, sqrtPriceX96);
        delta = modifyLiquidityRouter.modifyLiquidity(key, result, hookData);
    }

    // 池子中可能已存在头寸，因此收紧流动性的边界。
    function createFuzzyLiquidityWithTightBound(
        PoolModifyLiquidityTest modifyLiquidityRouter,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        uint160 sqrtPriceX96,
        bytes memory hookData,
        uint256 maxPositions
    ) internal returns (ModifyLiquidityParams memory result, BalanceDelta delta) {
        result = createFuzzyLiquidityParamsWithTightBound(key, params, sqrtPriceX96, maxPositions);
        delta = modifyLiquidityRouter.modifyLiquidity(key, result, hookData);
    }
}
