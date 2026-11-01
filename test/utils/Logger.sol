// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ModifyLiquidityParams} from "../../src/types/PoolOperation.sol";

import "forge-std/console2.sol";

// 用于打印模糊测试中的真实取值。对于失败的模糊测试，foundry 记录的是未经处理（unsanitized）的原始参数。
contract Logger {
    function logParams(ModifyLiquidityParams memory params) public pure {
        console2.log("ModifyLiquidity.tickLower", params.tickLower);
        console2.log("ModifyLiquidity.tickUpper", params.tickUpper);
        console2.log("ModifyLiquidity.liquidityDelta", params.liquidityDelta);
        console2.log("ModifyLiquidity.salt");
        console2.logBytes32(params.salt);
    }
}
