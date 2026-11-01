// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Deployers} from "./utils/Deployers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Currency} from "../src/types/Currency.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {IUnlockCallback} from "../src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "../src/types/PoolOperation.sol";
import {ActionsRouter, Actions} from "../src/test/ActionsRouter.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {CurrencyReserves} from "../src/libraries/CurrencyReserves.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../src/libraries/TransientStateLibrary.sol";
import {NativeERC20} from "../src/test/NativeERC20.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {CurrencyLibrary} from "../src/types/Currency.sol";

contract SyncTest is Test, Deployers {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    // PoolManager 不持有任何 currency2 余额。
    Currency currency2;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
        currency2 = deployMintAndApproveCurrency();
    }

    function test_sync_multiple_unlocked() public noIsolate {
        manager.sync(currency1);
        assertEq(Currency.unwrap(currency1), Currency.unwrap(manager.getSyncedCurrency()));
        manager.sync(currency0);
        assertEq(Currency.unwrap(currency0), Currency.unwrap(manager.getSyncedCurrency()));
    }

    function test_sync_balanceIsZero() public {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        Actions[] memory actions = new Actions[](2);
        bytes[] memory params = new bytes[](2);

        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency2);

        actions[1] = Actions.ASSERT_RESERVES_EQUALS;
        params[1] = abi.encode(0);

        actionsRouter.executeActions(actions, params);

        assertEq(currency2.balanceOf(address(manager)), uint256(0));
    }

    function test_sync_balanceIsNonzero() public {
        uint256 currency0Balance = currency0.balanceOf(address(manager));
        assertGt(currency0Balance, uint256(0));

        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);

        actions[0] = Actions.ASSERT_RESERVES_EQUALS;
        params[0] = abi.encode(0);

        actions[1] = Actions.SYNC;
        params[1] = abi.encode(currency0);

        actions[2] = Actions.ASSERT_RESERVES_EQUALS;
        params[2] = abi.encode(currency0Balance);

        actionsRouter.executeActions(actions, params);

        uint256 balance = currency0.balanceOf(address(manager));
        assertEq(balance, currency0Balance, "balance not equal");
    }

    function test_settle_withStartingBalance() public {
        assertGt(currency0.balanceOf(address(manager)), uint256(0));

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        // 尚未调用 sync。
        assertEq(manager.getSyncedReserves(), 0);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, new bytes(0));
        (uint256 balanceCurrency0) = currency0.balanceOf(address(manager));

        Actions[] memory actions = new Actions[](2);
        bytes[] memory params = new bytes[](2);

        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency0);

        actions[1] = Actions.ASSERT_RESERVES_EQUALS;
        params[1] = abi.encode(balanceCurrency0);

        actionsRouter.executeActions(actions, params);
    }

    function test_settle_withNoStartingBalance() public {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        (Currency cur0, Currency cur1) = currency0 < currency2 ? (currency0, currency2) : (currency2, currency0);
        PoolKey memory key2 =
            PoolKey({currency0: cur0, currency1: cur1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});

        manager.initialize(key2, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(key2, ModifyLiquidityParams(-60, 60, 100, 0), new bytes(0));
        (uint256 balanceCurrency2) = currency2.balanceOf(address(manager));

        Actions[] memory actions = new Actions[](2);
        bytes[] memory params = new bytes[](2);

        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency2);

        actions[1] = Actions.ASSERT_RESERVES_EQUALS;
        params[1] = abi.encode(balanceCurrency2);

        actionsRouter.executeActions(actions, params);
    }

    function test_settle_payOnBehalf(address taker, uint256 amount) public {
        vm.assume(taker != address(actionsRouter));
        amount = bound(amount, 1, uint256(int256(type(int128).max)));
        MockERC20(Currency.unwrap(currency2)).approve(address(actionsRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency2)).mint(address(manager), amount);

        Actions[] memory actions = new Actions[](6);
        bytes[] memory params = new bytes[](6);

        actions[0] = Actions.PRANK_TAKE_FROM;
        params[0] = abi.encode(currency2, taker, taker, amount);

        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency2, taker, int256(amount) * -1);

        actions[2] = Actions.SYNC;
        params[2] = abi.encode(currency2);

        actions[3] = Actions.TRANSFER_FROM;
        params[3] = abi.encode(currency2, address(this), address(manager), amount);

        actions[4] = Actions.SETTLE_FOR;
        params[4] = abi.encode(taker);

        actions[5] = Actions.ASSERT_DELTA_EQUALS;
        params[5] = abi.encode(currency2, taker, 0);

        actionsRouter.executeActions(actions, params);
    }

    /// @notice 当没有余额且储备被设为 0 时，不应记入任何 delta。
    function test_settle_noBalanceInPool_shouldNotApplyDelta() public {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        Actions[] memory actions = new Actions[](4);
        bytes[] memory params = new bytes[](4);

        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency2);

        actions[1] = Actions.ASSERT_RESERVES_EQUALS;
        params[1] = abi.encode(0);

        actions[2] = Actions.SETTLE;

        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency2, address(actionsRouter), 0);

        actionsRouter.executeActions(actions, params);
    }

    /// @notice 当存在余额时，不应记入任何 delta。
    function test_settle_balanceInPool_shouldNotApplyDelta() public {
        uint256 currency0Balance = currency0.balanceOf(address(manager));
        assertGt(currency0Balance, uint256(0));

        Actions[] memory actions = new Actions[](5);
        bytes[] memory params = new bytes[](5);

        actions[0] = Actions.ASSERT_RESERVES_EQUALS;
        params[0] = abi.encode(0);

        actions[1] = Actions.SYNC;
        params[1] = abi.encode(currency0);

        actions[2] = Actions.ASSERT_RESERVES_EQUALS;
        params[2] = abi.encode(currency0Balance);

        actions[3] = Actions.SETTLE;

        actions[4] = Actions.ASSERT_DELTA_EQUALS;
        params[4] = abi.encode(currency0, address(actionsRouter), 0);

        actionsRouter.executeActions(actions, params);
    }

    // @notice 测试在对非原生代币结算前不调用 sync 时的预期行为。（即未正确地与 pool manager 交互，可能会损失资金。）
    function test_settle_nonNative_withoutSync_loseFunds() public {
        MockERC20(Currency.unwrap(currency0)).approve(address(actionsRouter), type(uint256).max);
        uint256 managerCurrency0BalanceBefore = currency0.balanceOf(address(manager));
        uint256 userCurrency0BalanceBefore = currency0.balanceOf(address(this));

        Actions[] memory actions = new Actions[](9);
        bytes[] memory params = new bytes[](9);

        vm.startSnapshotGas("getReserves");
        uint256 reserves = manager.getSyncedReserves();
        vm.stopSnapshotGas();
        assertEq(reserves, 0); // 储备为 0。

        actions[0] = Actions.TAKE;
        params[0] = abi.encode(currency0, address(this), 10);

        // 断言 actionsRouter 上未结清的 delta 为 -10。（用户欠池子 10）。
        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency0, address(actionsRouter), -10);

        actions[2] = Actions.TRANSFER_FROM; // 发送代币前未进行同步（sync）
        params[2] = abi.encode(currency0, address(this), manager, 10);

        actions[3] = Actions.SETTLE; // 未 sync 就调用 settle 时预期结算的是原生代币，但 msg.value == 0，因此结算金额为 0。

        actions[4] = Actions.ASSERT_DELTA_EQUALS;
        params[4] = abi.encode(currency0, address(actionsRouter), -10);

        actions[5] = Actions.SYNC;
        params[5] = abi.encode(currency0);

        // 现在要结算该 delta，用户欠池子 10。
        actions[6] = Actions.TRANSFER_FROM;
        params[6] = abi.encode(currency0, address(this), manager, 10);

        actions[7] = Actions.SETTLE;

        actions[8] = Actions.ASSERT_DELTA_EQUALS;
        params[8] = abi.encode(currency0, address(actionsRouter), 0);

        actionsRouter.executeActions(actions, params);

        // manager 多得了 10 个 currency0。
        assertEq(currency0.balanceOf(address(manager)), managerCurrency0BalanceBefore + 10);
        // 用户损失了 10 个 currency0，且永远无法取回。
        assertEq(currency0.balanceOf(address(this)), userCurrency0BalanceBefore - 10);
    }

    function test_settle_failsWithNativeERC20IfNotSyncedInOrder(uint256 value) public {
        value = bound(value, 1, uint256(int256(type(int128).max / 2)));
        vm.deal(address(this), value);
        vm.deal(address(manager), value);
        NativeERC20 nativeERC20 = new NativeERC20();

        uint256 nativeERC20Balance = nativeERC20.balanceOf(address(manager));

        Actions[] memory actions = new Actions[](3);
        bytes[] memory params = new bytes[](3);

        actions[0] = Actions.SYNC;
        params[0] = abi.encode(nativeERC20);

        actions[1] = Actions.ASSERT_RESERVES_EQUALS;
        params[1] = abi.encode(nativeERC20Balance);

        actions[2] = Actions.SETTLE_NATIVE;
        params[2] = abi.encode(value);

        vm.expectRevert(IPoolManager.NonzeroNativeValue.selector);
        actionsRouter.executeActions{value: value}(actions, params);

        // 仅供参考 - 见 OZ C01 报告 - 此前用于确认该漏洞的测试
        // uint256 balanceBefore = address(this).balance;

        // actions[1] = Actions.SETTLE;
        // params[1] = abi.encode(Currency.wrap(address(nativeERC20)));

        // actions[2] = Actions.ASSERT_DELTA_EQUALS;
        // params[2] = abi.encode(Currency.wrap(address(0)), address(actionsRouter), value);

        // actions[3] = Actions.ASSERT_DELTA_EQUALS;
        // params[3] = abi.encode(Currency.wrap(address(nativeERC20)), address(actionsRouter), value);

        // actions[4] = Actions.TAKE;
        // params[4] = abi.encode(Currency.wrap(address(0)), address(this), value);

        // actions[5] = Actions.TAKE;
        // params[5] = abi.encode(Currency.wrap(address(nativeERC20)), address(this), value);

        // uint256 balanceAfter = address(this).balance;
        // assertEq(balanceAfter - balanceBefore, value);
    }

    function test_settle_native_afterERC20Sync_succeeds(uint256 currency2Balance, uint256 ethBalance) public {
        currency2Balance = bound(currency2Balance, 1, uint256(int256(type(int128).max / 2)));
        ethBalance = bound(ethBalance, 1, uint256(int256(type(int128).max / 2)));

        vm.deal(address(this), ethBalance);
        // 确保储备余额不为 0
        currency2.transfer(address(manager), currency2Balance);

        Actions[] memory actions = new Actions[](8);
        bytes[] memory params = new bytes[](8);

        actions[0] = Actions.ASSERT_RESERVES_EQUALS;
        params[0] = abi.encode(0);

        actions[1] = Actions.SYNC;
        params[1] = abi.encode(currency2);

        actions[2] = Actions.ASSERT_RESERVES_EQUALS;
        params[2] = abi.encode(currency2Balance);

        actions[3] = Actions.SYNC;
        params[3] = abi.encode(CurrencyLibrary.ADDRESS_ZERO);

        // 底层实际值非零，但当代币为 address(0) 时，我们的瞬态状态库会覆盖该值
        actions[4] = Actions.ASSERT_RESERVES_EQUALS;
        params[4] = abi.encode(0);

        // 这里以 ethBalance 作为 value 调用 settle。由于 synedCurrency 槽为 address(0)，该调用应成功在原生代币上记入一个正的 delta。
        actions[5] = Actions.SETTLE_NATIVE;
        params[5] = abi.encode(ethBalance);

        actions[6] = Actions.ASSERT_DELTA_EQUALS;
        params[6] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, address(actionsRouter), ethBalance);

        // 提取 eth 以结清 delta
        actions[7] = Actions.TAKE;
        params[7] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, address(this), ethBalance);

        actionsRouter.executeActions{value: ethBalance}(actions, params);
    }

    function test_settle_twice_doesNotApplyDelta(uint256 value) public {
        value = bound(value, 1, uint256(int256(type(int128).max / 2)));
        currency2.transfer(address(manager), value);

        Actions[] memory actions = new Actions[](8);
        bytes[] memory params = new bytes[](8);

        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency2);

        actions[1] = Actions.ASSERT_RESERVES_EQUALS;
        params[1] = abi.encode(value);

        actions[2] = Actions.TRANSFER_FROM;
        params[2] = abi.encode(currency2, address(this), address(manager), value);

        // 这会结算 syncedCurrency，即 currency2。
        actions[3] = Actions.SETTLE;

        actions[4] = Actions.ASSERT_DELTA_EQUALS;
        params[4] = abi.encode(currency2, address(actionsRouter), value);

        actions[5] = Actions.TAKE;
        params[5] = abi.encode(currency2, address(this), value);

        // 这会结算 syncedCurrency，它此时已被清为 address(0)。
        actions[6] = Actions.SETTLE;

        // 在不附带 value 的情况下对 address(0) 调用 settle 不会记入 delta。
        actions[7] = Actions.ASSERT_DELTA_EQUALS;
        params[7] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, address(actionsRouter), 0);

        actionsRouter.executeActions(actions, params);
    }
}
