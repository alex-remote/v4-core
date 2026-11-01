// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {DynamicReturnFeeTestHook} from "../src/test/DynamicReturnFeeTestHook.sol";
import {Currency} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {FullMath} from "../src/libraries/FullMath.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";

contract TestDynamicReturnFees is Test, Deployers {
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    DynamicReturnFeeTestHook dynamicReturnFeesHook = DynamicReturnFeeTestHook(
        address(uint160(uint256(type(uint160).max) & clearAllHookPermissionsMask | Hooks.BEFORE_SWAP_FLAG))
    );

    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    function setUp() public {
        DynamicReturnFeeTestHook impl = new DynamicReturnFeeTestHook();
        vm.etch(address(dynamicReturnFeesHook), address(impl).code);

        deployFreshManagerAndRouters();
        dynamicReturnFeesHook.setManager(IPoolManager(manager));

        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(dynamicReturnFeesHook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
    }

    function test_fuzz_dynamicReturnSwapFee(uint24 fee) public {
        // hook 会负责添加覆盖（override）标志位
        dynamicReturnFeesHook.setFee(fee);

        uint24 actualFee = fee.removeOverrideFlag();

        int256 amountSpecified = -10000;
        BalanceDelta result;
        if (actualFee > LPFeeLibrary.MAX_LP_FEE) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, actualFee));
            result = swap(key, true, amountSpecified, ZERO_BYTES);
            return;
        } else {
            result = swap(key, true, amountSpecified, ZERO_BYTES);
        }
        // BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);
        assertEq(result.amount0(), amountSpecified);

        if (actualFee > LPFeeLibrary.MAX_LP_FEE) {
            // 如果手续费过大，则不会使用 beforeSwap 返回的手续费（手续费保持为 0，即默认值）
            assertApproxEqAbs(uint256(int256(result.amount1())), uint256(int256(-result.amount0())), 1 wei);
        } else {
            assertApproxEqAbs(
                uint256(int256(result.amount1())),
                FullMath.mulDiv(uint256(-amountSpecified), (1e6 - actualFee), 1e6),
                1 wei
            );
        }
    }

    function test_returnDynamicSwapFee_beforeSwap_succeeds_gas() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        dynamicReturnFeesHook.setFee(123);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap with return dynamic fee");

        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_dynamicReturnSwapFee_initializeZeroSwapFee() public {
        key.tickSpacing = 30;
        manager.initialize(key, SQRT_PRICE_1_1);
        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_dynamicReturnSwapFee_notUsedIfPoolIsStaticFee() public {
        key.fee = 3000; // 静态手续费
        dynamicReturnFeesHook.setFee(1000); // 由于池子使用静态手续费，0.10% 的手续费不会被使用

        initPoolAndAddLiquidity(currency0, currency1, IHooks(address(dynamicReturnFeesHook)), 3000, SQRT_PRICE_1_1);
        assertEq(_fetchPoolSwapFee(key), 3000);

        // 尽管返回了有效的兑换手续费（1000），实际仍使用静态手续费
        int256 amountSpecified = -10000;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);

        // 以约 1:1 兑换后，输出数量（amount1）应比指定数量少约 0.30%
        assertEq(result.amount0(), amountSpecified);
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - 3000), 1e6), 1 wei
        );
    }

    function test_dynamicReturnSwapFee_notStored() public {
        // beforeSwap 返回的手续费不会写入存储

        // 创建一个初始手续费为 123 的新池子
        key.tickSpacing = 30;
        manager.initialize(key, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        uint24 initialFee = 123;
        dynamicReturnFeesHook.forcePoolFeeUpdate(key, initialFee);
        assertEq(_fetchPoolSwapFee(key), initialFee);

        // 使用不同的手续费进行兑换
        uint24 newFee = 3000;
        dynamicReturnFeesHook.setFee(newFee);

        int256 amountSpecified = -10000;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - newFee), 1e6), 1 wei
        );

        // beforeSwap 返回的手续费不会被存储
        assertEq(_fetchPoolSwapFee(key), initialFee);
    }

    function test_dynamicReturnSwapFee_revertIfLPFeeTooLarge() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        // hook 会添加覆盖（override）标志位
        uint24 fee = 1000001;
        dynamicReturnFeesHook.setFee(fee);

        // 过大的手续费不会被使用
        int256 amountSpecified = -10000;
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee));
        swap(key, true, amountSpecified, ZERO_BYTES);
    }

    function _fetchPoolSwapFee(PoolKey memory _key) internal view returns (uint256 swapFee) {
        PoolId id = _key.toId();
        (,,, swapFee) = manager.getSlot0(id);
    }
}
