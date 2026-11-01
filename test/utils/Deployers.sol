// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {ModifyLiquidityParams, SwapParams} from "../../src/types/PoolOperation.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {Constants} from "../utils/Constants.sol";
import {SortTokens} from "./SortTokens.sol";
import {PoolModifyLiquidityTest} from "../../src/test/PoolModifyLiquidityTest.sol";
import {PoolModifyLiquidityTestNoChecks} from "../../src/test/PoolModifyLiquidityTestNoChecks.sol";
import {PoolSwapTest} from "../../src/test/PoolSwapTest.sol";
import {SwapRouterNoChecks} from "../../src/test/SwapRouterNoChecks.sol";
import {PoolDonateTest} from "../../src/test/PoolDonateTest.sol";
import {PoolNestedActionsTest} from "../../src/test/PoolNestedActionsTest.sol";
import {PoolTakeTest} from "../../src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "../../src/test/PoolClaimsTest.sol";
import {ActionsRouter} from "../../src/test/ActionsRouter.sol";
import {LiquidityAmounts} from "../../test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";

contract Deployers is Test {
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    // 实用的测试常量
    bytes constant ZERO_BYTES = Constants.ZERO_BYTES;
    uint160 constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;
    uint160 constant SQRT_PRICE_1_2 = Constants.SQRT_PRICE_1_2;
    uint160 constant SQRT_PRICE_2_1 = Constants.SQRT_PRICE_2_1;
    uint160 constant SQRT_PRICE_1_4 = Constants.SQRT_PRICE_1_4;
    uint160 constant SQRT_PRICE_4_1 = Constants.SQRT_PRICE_4_1;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    ModifyLiquidityParams public LIQUIDITY_PARAMS =
        ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: 0});
    ModifyLiquidityParams public REMOVE_LIQUIDITY_PARAMS =
        ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1e18, salt: 0});
    SwapParams public SWAP_PARAMS =
        SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_2});

    // 全局变量
    Currency internal currency0;
    Currency internal currency1;
    IPoolManager manager;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolModifyLiquidityTestNoChecks modifyLiquidityNoChecks;
    SwapRouterNoChecks swapRouterNoChecks;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;
    PoolTakeTest takeRouter;
    ActionsRouter actionsRouter;

    PoolClaimsTest claimsRouter;
    PoolNestedActionsTest nestedActionRouter;
    address feeController;

    PoolKey key;
    PoolKey nativeKey;
    PoolKey uninitializedKey;
    PoolKey uninitializedNativeKey;

    // 新增 hook 标志位时请更新此值。
    uint160 hookPermissionCount = 14;
    uint160 clearAllHookPermissionsMask = ~uint160(0) << (hookPermissionCount);

    modifier noIsolate() {
        if (msg.sender != address(this)) {
            (bool success,) = address(this).call(msg.data);
            require(success);
        } else {
            _;
        }
    }

    function deployFreshManager() internal virtual {
        manager = new PoolManager(address(this));
    }

    function deployFreshManagerAndRouters() internal {
        deployFreshManager();
        swapRouter = new PoolSwapTest(manager);
        swapRouterNoChecks = new SwapRouterNoChecks(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        claimsRouter = new PoolClaimsTest(manager);
        nestedActionRouter = new PoolNestedActionsTest(manager);
        feeController = makeAddr("feeController");
        actionsRouter = new ActionsRouter(manager);

        manager.setProtocolFeeController(feeController);
    }

    // 必须先用 deployFreshManagerAndRouters 初始化各路由合约
    // 如果只需要代币（不需要授权），请调用 deployAndMint2Currencies
    function deployMintAndApprove2Currencies() internal returns (Currency, Currency) {
        Currency _currencyA = deployMintAndApproveCurrency();
        Currency _currencyB = deployMintAndApproveCurrency();

        (currency0, currency1) =
            SortTokens.sort(MockERC20(Currency.unwrap(_currencyA)), MockERC20(Currency.unwrap(_currencyB)));
        return (currency0, currency1);
    }

    function deployMintAndApproveCurrency() internal returns (Currency currency) {
        MockERC20 token = deployTokens(1, 2 ** 255)[0];

        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], Constants.MAX_UINT256);
        }

        return Currency.wrap(address(token));
    }

    function deployAndMint2Currencies() internal returns (Currency, Currency) {
        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);
        return SortTokens.sort(tokens[0], tokens[1]);
    }

    function deployTokens(uint8 count, uint256 totalSupply) internal returns (MockERC20[] memory tokens) {
        tokens = new MockERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new MockERC20("TEST", "TEST", 18);
            tokens[i].mint(address(this), totalSupply);
        }
    }

    function initPool(Currency _currency0, Currency _currency1, IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        internal
        returns (PoolKey memory _key, PoolId id)
    {
        _key = PoolKey(_currency0, _currency1, fee, fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2), hooks);
        id = _key.toId();
        manager.initialize(_key, sqrtPriceX96);
    }

    function initPool(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal returns (PoolKey memory _key, PoolId id) {
        _key = PoolKey(_currency0, _currency1, fee, tickSpacing, hooks);
        id = _key.toId();
        manager.initialize(_key, sqrtPriceX96);
    }

    function initPoolAndAddLiquidity(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(_currency0, _currency1, hooks, fee, sqrtPriceX96);
        modifyLiquidityRouter.modifyLiquidity{value: msg.value}(_key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function initPoolAndAddLiquidityETH(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        uint256 msgValue
    ) internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(_currency0, _currency1, hooks, fee, sqrtPriceX96);
        modifyLiquidityRouter.modifyLiquidity{value: msgValue}(_key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    // 部署 manager 和所有测试路由合约，并创建 2 个池子：分别包含和不包含原生代币
    function initializeManagerRoutersAndPoolsWithLiq(IHooks hooks) internal {
        deployFreshManagerAndRouters();
        // 设置全局的代币和 key
        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hooks, 3000, SQRT_PRICE_1_1);
        nestedActionRouter.executor().setKey(key);
        (nativeKey,) =
            initPoolAndAddLiquidityETH(CurrencyLibrary.ADDRESS_ZERO, currency1, hooks, 3000, SQRT_PRICE_1_1, 1 ether);
        uninitializedKey = key;
        uninitializedNativeKey = nativeKey;
        uninitializedKey.fee = 100;
        uninitializedNativeKey.fee = 100;
    }

    /// @notice 用于简单 ERC20 兑换（swap）的辅助函数，允许无限制的价格影响
    function swap(PoolKey memory _key, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        returns (BalanceDelta)
    {
        // 精确输入时允许原生代币作为输入，其他情况引导用户使用 `swapNativeInput` 函数
        bool isNativeInput = zeroForOne && _key.currency0.isAddressZero();
        if (isNativeInput) require(0 > amountSpecified, "Use swapNativeInput() for native-token exact-output swaps");

        uint256 value = isNativeInput ? uint256(-amountSpecified) : 0;

        return swapRouter.swap{value: value}(
            _key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }

    /// @notice 用于增加 pool manager 余额的辅助函数。
    /// 使用默认的 LIQUIDITY_PARAMS 区间。
    function seedMoreLiquidity(PoolKey memory _key, uint256 amount0, uint256 amount1) internal {
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(_key.toId());
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickUpper),
            amount0,
            amount1
        );

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: LIQUIDITY_PARAMS.tickLower,
            tickUpper: LIQUIDITY_PARAMS.tickUpper,
            liquidityDelta: int128(liquidityDelta),
            salt: 0
        });

        modifyLiquidityRouter.modifyLiquidity(_key, params, ZERO_BYTES);
    }

    /// @notice 用于简单原生代币兑换（swap）的辅助函数，允许无限制的价格影响
    function swapNativeInput(
        PoolKey memory _key,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData,
        uint256 msgValue
    ) internal returns (BalanceDelta) {
        require(_key.currency0.isAddressZero(), "currency0 is not native. Use swap() instead");
        if (zeroForOne == false) require(msgValue == 0, "msgValue must be 0 for oneForZero swaps");

        return swapRouter.swap{value: msgValue}(
            _key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }

    // 用于接收测试辅助函数退回的多余 eth
    receive() external payable {}
}
