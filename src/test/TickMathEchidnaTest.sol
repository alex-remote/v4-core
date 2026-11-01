// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TickMath} from "../libraries/TickMath.sol";

contract TickMathEchidnaTest {
    // 唯一性与递增顺序
    function checkGetSqrtPriceAtTickInvariants(int24 tick) external pure {
        uint160 price = TickMath.getSqrtPriceAtTick(tick);
        assert(TickMath.getSqrtPriceAtTick(tick - 1) < price && price < TickMath.getSqrtPriceAtTick(tick + 1));
        assert(price >= TickMath.MIN_SQRT_PRICE);
        assert(price <= TickMath.MAX_SQRT_PRICE);
    }

    // 价格总是位于返回的 tick 与返回的 tick+1 之间
    function checkGetTickAtSqrtPriceInvariants(uint160 price) external pure {
        int24 tick = TickMath.getTickAtSqrtPrice(price);
        assert(price >= TickMath.getSqrtPriceAtTick(tick) && price < TickMath.getSqrtPriceAtTick(tick + 1));
        assert(tick >= TickMath.MIN_TICK);
        assert(tick < TickMath.MAX_TICK);
    }
}
