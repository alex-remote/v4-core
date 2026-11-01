// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "./utils/Deployers.sol";
import {FeeTakingHook} from "../src/test/FeeTakingHook.sol";
import {LPFeeTakingHook} from "../src/test/LPFeeTakingHook.sol";
import {CustomCurveHook} from "../src/test/CustomCurveHook.sol";
import {DeltaReturningHook} from "../src/test/DeltaReturningHook.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {SwapParams} from "../src/types/PoolOperation.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Currency} from "../src/types/Currency.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";

contract CustomAccountingTest is Test, Deployers {
    using SafeCast for *;

    address hook;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }

    function _setUpDeltaReturnFuzzPool() internal {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        address impl = address(new DeltaReturningHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _setUpCustomCurvePool() internal {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        address impl = address(new CustomCurveHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _setUpFeeTakingPool() internal {
        address hookAddr = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
            )
        );
        address impl = address(new FeeTakingHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _setUpLPFeeTakingPool() internal {
        address hookAddr = address(
            uint160(
                Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
            )
        );
        address impl = address(new LPFeeTakingHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _etchHookAndInitPool(address hookAddr, address implAddr) internal {
        vm.etch(hookAddr, implAddr.code);
        hook = hookAddr;

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 100, SQRT_PRICE_1_1);
    }

    // ------------------------ 兑换（SWAP）  ------------------------

    function test_swap_afterSwapFeeOnUnspecified_exactInput() public {
        _setUpFeeTakingPool();
        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 1000;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -int256(amountToSwap), sqrtPriceLimitX96: SQRT_PRICE_1_2});
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap CA fee on unspecified");

        // 在当前可用流动性下，输入 1000 可得到 998 的输出
        // 再加上对非指定（输出）代币收取的 1.23% 手续费 => (998*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + (998 - 12), "amount 1");
    }

    function test_swap_afterSwapFeeOnUnspecified_exactOutput() public {
        _setUpFeeTakingPool();

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 1000;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: int256(amountToSwap), sqrtPriceLimitX96: SQRT_PRICE_1_2});
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // 在当前可用流动性下，输入 1002 可得到 1000 的输出
        // 再加上对非指定（输入）代币收取的 1.23% 手续费 => (1002*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - 1002 - 12, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + amountToSwap, "amount 1");
    }

    function test_swap_beforeSwapNoOpsSwap_exactInput() public {
        _setUpCustomCurvePool();

        // 通过直接向合约转入代币来添加流动性
        key.currency0.transfer(hook, 10e18);
        key.currency1.transfer(hook, 10e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 123456;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -int256(amountToSwap), sqrtPriceLimitX96: SQRT_PRICE_1_2});
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap CA custom curve + swap noop");

        // 该自定义曲线 hook 是 1-1 线性的
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + amountToSwap, "amount 1");
    }

    function test_swap_beforeSwapNoOpsSwap_exactOutput() public {
        _setUpCustomCurvePool();

        // 通过直接向合约转入代币来添加流动性
        key.currency0.transfer(hook, 10e18);
        key.currency1.transfer(hook, 10e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 123456;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: int256(amountToSwap), sqrtPriceLimitX96: SQRT_PRICE_1_2});
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // 该自定义曲线 hook 是 1-1 线性的
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + amountToSwap, "amount 1");
    }

    // test_fuzz_swap_beforeSwap_returnsDeltaSpecified 中所用池子在每个方向上的最大可用流动性
    int128 maxPossibleIn_fuzz_test = -6018336102428409;
    int128 maxPossibleOut_fuzz_test = 5981737760509662;

    function test_fuzz_swap_beforeSwap_returnsDeltaSpecified(
        int128 hookDeltaSpecified,
        int256 amountSpecified,
        bool zeroForOne
    ) public {
        // ------------------------ 准备（SETUP） ------------------------
        Currency specifiedCurrency;
        bool isExactIn;
        _setUpDeltaReturnFuzzPool();

        // 初始化池子，并给 hook 转入代币，用于在兑换中支付
        key.currency0.transfer(hook, type(uint128).max);
        key.currency1.transfer(hook, type(uint128).max);

        // 将指定数量限定为明显小于我们所拥有的流动性数量
        amountSpecified = int128(bound(amountSpecified, -3e11, 3e11));
        isExactIn = amountSpecified < 0;
        specifiedCurrency = (isExactIn == zeroForOne) ? key.currency0 : key.currency1;

        // 限定指定代币一侧的 delta，使其既不超过可用储备，也不等于 int 最小值，以
        // 防止 hook 在提取/结算（take/settle）时回滚（revert）
        uint128 reservesOfSpecified = uint128(specifiedCurrency.balanceOf(address(manager)));
        hookDeltaSpecified = int128(bound(hookDeltaSpecified, type(int128).min + 1, int128(reservesOfSpecified)));
        DeltaReturningHook(hook).setDeltaSpecified(hookDeltaSpecified);

        // 设置兑换所需的变量
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: (zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT)
        });

        // ------------------------ 模糊测试用例（FUZZING CASES） ------------------------
        // 指定数量为 0 时：交易回滚（revert）
        if (amountSpecified == 0) {
            vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // 交易为精确输入 n 时：hook 从输入中取走（TAKE，hookDeltaSpecified 为正）的数量不能超过 n
            // 否则用户将不得不输入超过 n 的数量
        } else if (isExactIn && (hookDeltaSpecified > -amountSpecified)) {
            vm.expectRevert(Hooks.HookDeltaExceedsSwapAmount.selector);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // 精确输出 n 时：hook 在输出中给出（GIVE，hookDeltaSpecified 为负）的数量不能超过 n
            // 否则用户收到的输出将超过 n
        } else if (!isExactIn && (amountSpecified < -hookDeltaSpecified)) {
            vm.expectRevert(Hooks.HookDeltaExceedsSwapAmount.selector);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // 兑换成功的情况！
        } else {
            uint256 balanceThisBefore = specifiedCurrency.balanceOf(address(this));
            uint256 balanceHookBefore = specifiedCurrency.balanceOf(hook);
            uint256 balanceManagerBefore = specifiedCurrency.balanceOf(address(manager));

            BalanceDelta delta = swapRouter.swap(key, params, testSettings, ZERO_BYTES);
            int128 deltaSpecified = (zeroForOne == isExactIn) ? delta.amount0() : delta.amount1();

            // 所有情况下 hook 都会得到其取走的数量，用户则得到兑换的输出 delta（下方有更多检查）
            assertEq(
                balanceHookBefore.toInt256() + hookDeltaSpecified,
                specifiedCurrency.balanceOf(hook).toInt256(),
                "hook balance change incorrect"
            );
            assertEq(
                balanceThisBefore.toInt256() + deltaSpecified,
                specifiedCurrency.balanceOf(address(this)).toInt256(),
                "swapper balance change incorrect"
            );

            // 精确输入，且可用的输入储备不足以同时支付兑换和 hook
            // 注意：这 3 个值都是负数，所以使用 <
            if (isExactIn && (hookDeltaSpecified + amountSpecified < maxPossibleIn_fuzz_test)) {
                // hook 将从 maxPossibleIn 中取走 hookDeltaSpecified
                assertEq(deltaSpecified, maxPossibleIn_fuzz_test - hookDeltaSpecified, "deltaSpecified exact input");
                // manager 收到了所有可能的输入代币
                assertEq(
                    balanceManagerBefore.toInt256() - maxPossibleIn_fuzz_test,
                    specifiedCurrency.balanceOf(address(manager)).toInt256(),
                    "manager balance change exact input"
                );

                // 精确输出，且可用的输出储备不足以同时支付兑换和 hook
            } else if (!isExactIn && (hookDeltaSpecified + amountSpecified > maxPossibleOut_fuzz_test)) {
                // hook 将从 maxPossibleOut 中取走 hookDeltaSpecified
                assertEq(deltaSpecified, maxPossibleOut_fuzz_test - hookDeltaSpecified, "deltaSpecified exact output");
                // manager 送出了所有可能的输出代币
                assertEq(
                    balanceManagerBefore.toInt256() - maxPossibleOut_fuzz_test,
                    specifiedCurrency.balanceOf(address(manager)).toInt256(),
                    "manager balance change exact output"
                );

                // 可用储备充足，因此用户得到了期望的数量
            } else {
                assertEq(deltaSpecified, amountSpecified, "deltaSpecified not amountSpecified");
                assertEq(
                    balanceManagerBefore.toInt256() - amountSpecified - hookDeltaSpecified,
                    specifiedCurrency.balanceOf(address(manager)).toInt256(),
                    "manager balance change not"
                );
            }
        }
    }

    // ------------------------ 修改流动性（MODIFY LIQUIDITY） ------------------------

    function test_addLiquidity_withFeeTakingHook() public {
        _setUpFeeTakingPool();

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);
        uint256 managerBalanceBefore0 = currency0.balanceOf(address(manager));
        uint256 managerBalanceBefore1 = currency1.balanceOf(address(manager));
        // console2.log(address(key.hooks));
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.snapshotGasLastCall("addLiquidity CA fee");

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;
        uint256 thisLoss0 = balanceBefore0 - currency0.balanceOf(address(this));
        uint256 thisLoss1 = balanceBefore1 - currency1.balanceOf(address(this));
        uint256 managerGain0 = currency0.balanceOf(address(manager)) - managerBalanceBefore0;
        uint256 managerGain1 = currency1.balanceOf(address(manager)) - managerBalanceBefore1;

        // 断言 hook 获得了所添加流动性的 5.43%
        assertEq(hookGain0, managerGain0 * 543 / 10000, "hook amount 0");
        assertEq(hookGain1, managerGain1 * 543 / 10000, "hook amount 1");
        assertEq(thisLoss0 - hookGain0, managerGain0, "manager amount 0");
        assertEq(thisLoss1 - hookGain1, managerGain1, "manager amount 1");
    }

    function test_removeLiquidity_withFeeTakingHook() public {
        _setUpFeeTakingPool();

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);
        uint256 managerBalanceBefore0 = currency0.balanceOf(address(manager));
        uint256 managerBalanceBefore1 = currency1.balanceOf(address(manager));

        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.snapshotGasLastCall("removeLiquidity CA fee");

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;
        uint256 thisGain0 = currency0.balanceOf(address(this)) - balanceBefore0;
        uint256 thisGain1 = currency1.balanceOf(address(this)) - balanceBefore1;
        uint256 managerLoss0 = managerBalanceBefore0 - currency0.balanceOf(address(manager));
        uint256 managerLoss1 = managerBalanceBefore1 - currency1.balanceOf(address(manager));

        // 断言 hook 获得了所移除流动性的 5.43%
        assertEq(hookGain0, managerLoss0 * 543 / 10000, "hook amount 0");
        assertEq(hookGain1, managerLoss1 * 543 / 10000, "hook amount 1");
        assertEq(thisGain0 + hookGain0, managerLoss0, "manager amount 0");
        assertEq(thisGain1 + hookGain1, managerLoss1, "manager amount 1");
    }

    function test_fuzz_addLiquidity_withLPFeeTakingHook(uint128 feeRevenue0, uint128 feeRevenue1) public {
        feeRevenue0 = uint128(bound(feeRevenue0, 0, type(uint128).max / 2));
        feeRevenue1 = uint128(bound(feeRevenue1, 0, type(uint128).max / 2));
        _setUpLPFeeTakingPool(); // 准备过程中会创建流动性

        // 捐赠以产生手续费收入
        donateRouter.donate(key, feeRevenue0, feeRevenue1, ZERO_BYTES);

        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);

        // 再次添加流动性以触发 hook，hook 应当拿走手续费收入
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;

        // 断言 hook 拿走了全部手续费收入，仅有 1 wei 的精度误差
        assertApproxEqAbs(hookGain0, feeRevenue0, 1 wei);
        assertApproxEqAbs(hookGain1, feeRevenue1, 1 wei);
        assertTrue(hookGain0 <= feeRevenue0);
        assertTrue(hookGain1 <= feeRevenue1);
    }

    function test_fuzz_removeLiquidity_withLPFeeTakingHook(uint128 feeRevenue0, uint128 feeRevenue1) public {
        // 当手续费收入接近 int128.max 时测试会失败，因为 PoolManager 受（本金 + 手续费）的限制
        feeRevenue0 = uint128(bound(feeRevenue0, 0, type(uint128).max / 3));
        feeRevenue1 = uint128(bound(feeRevenue1, 0, type(uint128).max / 3));
        _setUpLPFeeTakingPool(); // 准备过程中会创建流动性

        // 捐赠以产生手续费收入
        donateRouter.donate(key, feeRevenue0, feeRevenue1, ZERO_BYTES);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);
        uint256 managerBalanceBefore0 = currency0.balanceOf(address(manager));
        uint256 managerBalanceBefore1 = currency1.balanceOf(address(manager));

        // 移除流动性以触发 hook，hook 应当拿走手续费收入
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;
        uint256 thisGain0 = currency0.balanceOf(address(this)) - balanceBefore0;
        uint256 thisGain1 = currency1.balanceOf(address(this)) - balanceBefore1;
        uint256 managerLoss0 = managerBalanceBefore0 - currency0.balanceOf(address(manager));
        uint256 managerLoss1 = managerBalanceBefore1 - currency1.balanceOf(address(manager));

        // 断言 hook 拿走了全部手续费收入，仅有 1 wei 的精度误差
        assertApproxEqAbs(hookGain0, feeRevenue0, 1 wei);
        assertApproxEqAbs(hookGain1, feeRevenue1, 1 wei);
        assertTrue(hookGain0 <= feeRevenue0);
        assertTrue(hookGain1 <= feeRevenue1);
        assertEq(thisGain0 + hookGain0, managerLoss0, "manager amount 0");
        assertEq(thisGain1 + hookGain1, managerLoss1, "manager amount 1");
    }
}
