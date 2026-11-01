// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "./utils/Deployers.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "src/types/PoolOperation.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Position} from "src/libraries/Position.sol";
import {PoolId} from "src/types/PoolId.sol";
import {PoolModifyLiquidityTest} from "../src/test/PoolModifyLiquidityTest.sol";
import {Constants} from "./utils/Constants.sol";
import {Currency} from "src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {JavascriptFfi} from "./utils/JavascriptFfi.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {Fuzzers} from "../src/test/Fuzzers.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {toBalanceDelta} from "src/types/BalanceDelta.sol";
import {Logger} from "./utils/Logger.sol";

contract ModifyLiquidityTest is Test, Logger, Deployers, JavascriptFfi, Fuzzers {
    using StateLibrary for IPoolManager;

    PoolKey simpleKey; // 普通池子 key
    PoolId simplePoolId; // 普通池子 key 对应的 id

    bytes32 SALT = hex"CAFF";

    int128 constant ONE_PIP = 1e6;

    ModifyLiquidityParams public LIQ_PARAM_NO_SALT =
        ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: 0});

    ModifyLiquidityParams public LIQ_PARAM_SALT =
        ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: SALT});

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        (simpleKey, simplePoolId) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
    }

    /*//////////////////////////////////////////////////////////////
                            模糊测试：添加流动性
    //////////////////////////////////////////////////////////////*/

    /// forge-config: default.fuzz.runs = 10
    /// forge-config: pr.fuzz.runs = 10
    /// forge-config: ci.fuzz.runs = 500
    /// forge-config: debug.fuzz.runs = 10
    function test_ffi_fuzz_addLiquidity_defaultPool_ReturnsCorrectLiquidityDelta(ModifyLiquidityParams memory paramSeed)
        public
    {
        // 清洗模糊测试生成的参数，以得到有效的 tickLower、tickUpper 和 liquidityDelta。
        // 这里使用 SQRT_PRICE_1_1，因为 simpleKey 池子的初始 sqrtPrice 就是 SQRT_PRICE_1_1。
        ModifyLiquidityParams memory params = createFuzzyLiquidityParams(simpleKey, paramSeed, SQRT_PRICE_1_1);

        logParams(params);

        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(simpleKey, params, ZERO_BYTES);

        (int128 jsDelta0, int128 jsDelta1) = _modifyLiquidityJS(simplePoolId, params);

        _checkError(delta.amount0(), jsDelta0, "amount0 is off by more than one pip");
        _checkError(delta.amount1(), jsDelta1, "amount1 is off by more than one pip");
    }

    // 静态边界用例（非模糊测试），确保覆盖最大 tick 间距。
    function test_ffi_addLiqudity_weirdPool_0_returnsCorrectLiquidityDelta() public {
        // 使用 TickSpacing 为 MAX_TICK_SPACING 的池子
        (PoolKey memory wp0, PoolId wpId0) =
            initPool(currency0, currency1, IHooks(address(0)), 500, TickMath.MAX_TICK_SPACING, SQRT_PRICE_1_1);

        // 设置参数，在随机的 tick 边界上添加随机数量的流动性。
        int24 tickUpper = TickMath.MAX_TICK_SPACING * 4;
        int24 tickLower = TickMath.MAX_TICK_SPACING * -9;
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 16787899214600939458,
            salt: 0
        });

        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(wp0, params, ZERO_BYTES);

        (int128 jsDelta0, int128 jsDelta1) = _modifyLiquidityJS(wpId0, params);

        _checkError(delta.amount0(), jsDelta0, "amount0 is off by more than one pip");
        _checkError(delta.amount1(), jsDelta1, "amount1 is off by more than one pip");
    }

    // 静态边界用例（非模糊测试），确保覆盖最小 tick 间距。
    function test_ffi_addLiqudity_weirdPool_1_returnsCorrectLiquidityDelta() public {
        // 使用 TickSpacing 为 MIN_TICK_SPACING 的池子
        (PoolKey memory wp0, PoolId wpId0) =
            initPool(currency0, currency1, IHooks(address(0)), 551, TickMath.MIN_TICK_SPACING, SQRT_PRICE_1_1);

        // 设置参数，在随机的 tick 边界上添加随机数量的流动性。
        int24 tickUpper = TickMath.MIN_TICK_SPACING * 17;
        int24 tickLower = TickMath.MIN_TICK_SPACING * 9;
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 922871614499955267459963,
            salt: 0
        });

        params.tickLower = 10;

        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(wp0, params, ZERO_BYTES);

        (int128 jsDelta0, int128 jsDelta1) = _modifyLiquidityJS(wpId0, params);

        _checkError(delta.amount0(), jsDelta0, "amount0 is off by more than one pip");
        _checkError(delta.amount1(), jsDelta1, "amount1 is off by more than one pip");
    }

    function _modifyLiquidityJS(PoolId poolId, ModifyLiquidityParams memory params) public returns (int128, int128) {
        (uint256 price, int24 tick,,) = manager.getSlot0(poolId);

        string memory jsParameters = string(
            abi.encodePacked(
                vm.toString(params.tickLower),
                ",",
                vm.toString(params.tickUpper),
                ",",
                vm.toString(params.liquidityDelta),
                ",",
                vm.toString(tick),
                ",",
                vm.toString(price)
            )
        );

        string memory scriptName = "forge-test-getModifyLiquidityResult";
        bytes memory jsResult = runScript(scriptName, jsParameters);

        int128[] memory result = abi.decode(jsResult, (int128[]));
        int128 jsDelta0 = result[0];
        int128 jsDelta1 = result[1];
        return (jsDelta0, jsDelta1);
    }

    // 断言 solc/js 的结果最多相差 1/100 个 bip（即一个 pip）
    function _checkError(int128 solc, int128 js, string memory errMsg) public pure {
        if (solc != js) {
            // 确保在单边添加流动性时不会出现除以 0。
            (int128 gtResult, int128 ltResult) = js > solc ? (js, solc) : (solc, js);
            int128 resultsDiff = gtResult - ltResult;
            assertEq(resultsDiff * ONE_PIP / js, 0, errMsg);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Salt
    //////////////////////////////////////////////////////////////*/

    function test_modifyLiquidity_samePosition_zeroSalt_isUpdated() public {
        (uint128 liquidity,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );
        assertEq(liquidity, 0);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES);
        (liquidity,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        assertEq(liquidity, uint128(uint256(LIQ_PARAM_NO_SALT.liquidityDelta)));

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES);
        (uint128 liquidityUpdated,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );
        assertEq(liquidityUpdated, liquidity + uint128(uint256(LIQ_PARAM_NO_SALT.liquidityDelta)));
    }

    function test_modifyLiquidity_samePosition_withSalt_isUpdated() public {
        (uint128 liquidity,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(liquidity, 0);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        (liquidity,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(liquidity, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        (uint128 liquidityUpdated,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(liquidityUpdated, liquidity + uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
    }

    function test_modifyLiquidity_sameTicks_withDifferentSalt_isNotUpdated() public {
        (uint128 liquidityNoSalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        (uint128 liquiditySalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(liquidityNoSalt, 0);
        assertEq(liquiditySalt, 0);

        // 使用 salt 修改流动性。
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);

        (liquidityNoSalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        (liquiditySalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        assertEq(liquidityNoSalt, 0); // 该头寸没有流动性。
        assertEq(liquiditySalt, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta))); // 该头寸有流动性。

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES); // 现在两个头寸的流动性应当相同。

        (liquidityNoSalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        (liquiditySalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        // positionSalt 应当仍然只有最初存入的流动性
        assertEq(liquiditySalt, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
        assertEq(liquidityNoSalt, liquiditySalt);

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        (uint128 updatedLiquidityWithSalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        (uint128 updatedLiquidityNoSalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        assertEq(updatedLiquidityWithSalt, liquiditySalt + uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
        assertGt(updatedLiquidityWithSalt, updatedLiquidityNoSalt);
        assertEq(updatedLiquidityNoSalt, liquidityNoSalt);
    }

    function test_modifyLiquidity_sameSalt_differentLiquidityRouters_doNotEditSamePosition() public {
        // 设置新的路由合约。
        PoolModifyLiquidityTest modifyLiquidityRouter2 = new PoolModifyLiquidityTest(manager);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter2), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter2), Constants.MAX_UINT256);

        ModifyLiquidityParams memory LIQ_PARAM_SALT_2 =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 2e18, salt: SALT});

        // 获取尚未初始化的头寸，并断言它们没有流动性。
        (uint128 liquiditySalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        (uint128 liquiditySalt2,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter2), LIQ_PARAM_SALT_2.tickLower, LIQ_PARAM_SALT_2.tickUpper, SALT
        );

        assertEq(liquiditySalt, 0);
        assertEq(liquiditySalt2, 0);

        // 通过第一个路由合约，使用 salt 修改流动性。
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);

        (uint128 updatedLiquiditySalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        (uint128 updatedLiquiditySalt2,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter2), LIQ_PARAM_SALT_2.tickLower, LIQ_PARAM_SALT_2.tickUpper, SALT
        );

        // 断言只有第一个路由合约对应的流动性被更新。
        assertEq(updatedLiquiditySalt, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
        assertEq(updatedLiquiditySalt2, 0);

        // 通过第二个路由合约修改流动性。
        modifyLiquidityRouter2.modifyLiquidity(simpleKey, LIQ_PARAM_SALT_2, ZERO_BYTES);

        (updatedLiquiditySalt2,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter2), LIQ_PARAM_SALT_2.tickLower, LIQ_PARAM_SALT_2.tickUpper, SALT
        );
        (updatedLiquiditySalt,,) = manager.getPositionInfo(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        // 断言只有第二个路由合约对应的流动性被更新。
        assertEq(updatedLiquiditySalt2, uint128(uint256(LIQ_PARAM_SALT_2.liquidityDelta)));
        assertEq(updatedLiquiditySalt, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
    }

    function test_gas_modifyLiquidity_newPosition() public {
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        vm.snapshotGasLastCall("create new liquidity to a position with salt");
    }

    function test_gas_modifyLiquidity_updateSamePosition_withSalt() public {
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        vm.snapshotGasLastCall("add liquidity to already existing position with salt");
    }
}
