// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Pool} from "../libraries/Pool.sol";

contract TickOverflowSafetyEchidnaTest {
    using Pool for Pool.State;

    int24 private constant MIN_TICK = -16;
    int24 private constant MAX_TICK = 16;

    Pool.State private pool;
    int24 private tick = 0;

    // 手续费增长量已达到上限的一半，该值允许溢出
    uint256 feeGrowthGlobal0X128 = type(uint256).max / 2;
    uint256 feeGrowthGlobal1X128 = type(uint256).max / 2;

    // 用于追踪已添加的流动性总量，永远不应为负
    int256 totalLiquidity = 0;
    // 已发生的总增长量，该值不能溢出
    uint256 private totalGrowth0 = 0;
    uint256 private totalGrowth1 = 0;

    function increaseFeeGrowthGlobal0X128(uint256 amount) external {
        require(totalGrowth0 + amount > totalGrowth0); // 溢出检查
        feeGrowthGlobal0X128 += amount; // 此处有意允许溢出
        totalGrowth0 += amount;
    }

    function increaseFeeGrowthGlobal1X128(uint256 amount) external {
        require(totalGrowth1 + amount > totalGrowth1); // 溢出检查
        feeGrowthGlobal1X128 += amount; // 此处有意允许溢出
        totalGrowth1 += amount;
    }

    function setPosition(int24 tickLower, int24 tickUpper, int128 liquidityDelta) external {
        require(tickLower > MIN_TICK);
        require(tickUpper < MAX_TICK);
        require(tickLower < tickUpper);
        (bool flippedLower,) = pool.updateTick(tickLower, liquidityDelta, false);
        (bool flippedUpper,) = pool.updateTick(tickUpper, liquidityDelta, true);

        if (flippedLower) {
            if (liquidityDelta < 0) {
                assert(pool.ticks[tickLower].liquidityGross == 0);
                pool.clearTick(tickLower);
            } else {
                assert(pool.ticks[tickLower].liquidityGross > 0);
            }
        }

        if (flippedUpper) {
            if (liquidityDelta < 0) {
                assert(pool.ticks[tickUpper].liquidityGross == 0);
                pool.clearTick(tickUpper);
            } else {
                assert(pool.ticks[tickUpper].liquidityGross > 0);
            }
        }

        totalLiquidity += liquidityDelta;
        // 前面的 require 本应阻止这种情况
        assert(totalLiquidity >= 0);

        if (totalLiquidity == 0) {
            totalGrowth0 = 0;
            totalGrowth1 = 0;
        }
    }

    function moveToTick(int24 target) external {
        require(target > MIN_TICK);
        require(target < MAX_TICK);
        while (tick != target) {
            if (tick < target) {
                if (pool.ticks[tick + 1].liquidityGross > 0) {
                    pool.crossTick(tick + 1, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
                }
                tick++;
            } else {
                if (pool.ticks[tick].liquidityGross > 0) {
                    pool.crossTick(tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
                }
                tick--;
            }
        }
    }
}
