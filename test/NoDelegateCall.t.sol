// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {ProxyPoolManager} from "../src/test/ProxyPoolManager.sol";
import {NoDelegateCallTest} from "../src/test/NoDelegateCallTest.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {NoDelegateCall} from "../src/NoDelegateCall.sol";
import {Deployers} from "./utils/Deployers.sol";

contract TestDelegateCall is Test, Deployers {
    // 重写以使用 ProxyPoolManager
    function deployFreshManager() internal virtual override {
        IPoolManager delegateManager = new PoolManager(address(this));
        manager = new ProxyPoolManager(address(delegateManager));
    }

    NoDelegateCallTest noDelegateCallTest;

    function setUp() public {
        deployFreshManagerAndRouters();

        noDelegateCallTest = new NoDelegateCallTest();
    }

    function test_gas_noDelegateCall() public {
        vm.snapshotValue(
            "NoDelegateCall",
            noDelegateCallTest.getGasCostOfCannotBeDelegateCalled()
                - noDelegateCallTest.getGasCostOfCanBeDelegateCalled()
        );
    }

    function test_delegateCallNoModifier() public {
        (bool success,) =
            address(noDelegateCallTest).delegatecall(abi.encode(noDelegateCallTest.canBeDelegateCalled.selector));
        assertTrue(success);
    }

    function test_delegateCallWithModifier_revertsWithDelegateCallNotAllowed() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        (bool success,) =
            address(noDelegateCallTest).delegatecall(abi.encode(noDelegateCallTest.cannotBeDelegateCalled.selector));
        // 注意：vm.expectRevert 会反转 success，因此这里结果为 true 表示调用发生了回滚（revert）
        assertTrue(success);
    }

    function test_externalCallToPrivateMethodWithModifier_succeeds() public view {
        noDelegateCallTest.callsIntoNoDelegateCallFunction();
    }

    function test_delegateCallFromExternalToPrivateMethodWithModifier_revertsWithDelegateCallNotAllowed() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        (bool success,) = address(noDelegateCallTest).delegatecall(
            abi.encode(noDelegateCallTest.callsIntoNoDelegateCallFunction.selector)
        );
        // 注意：vm.expectRevert 会反转 success，因此这里结果为 true 表示调用发生了回滚（revert）
        assertTrue(success);
    }

    function test_modifyLiquidity_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, LIQUIDITY_PARAMS, ZERO_BYTES);

        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_swap_noDelegateCall() public {
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_donate_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }
}
