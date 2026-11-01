// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IHooks} from "./IHooks.sol";
import {IERC6909Claims} from "./external/IERC6909Claims.sol";
import {IProtocolFees} from "./IProtocolFees.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolId} from "../types/PoolId.sol";
import {IExtsload} from "./IExtsload.sol";
import {IExttload} from "./IExttload.sol";
import {ModifyLiquidityParams, SwapParams} from "../types/PoolOperation.sol";

/// @notice PoolManager 的接口
interface IPoolManager is IProtocolFees, IERC6909Claims, IExtsload, IExttload {
    /// @notice 当合约解锁流程结束后，仍有代币的 delta 未轧平（net out）时抛出
    error CurrencyNotSettled();

    /// @notice 尝试与未初始化的池子交互时抛出
    error PoolNotInitialized();

    /// @notice 调用 unlock 时合约已处于解锁状态则抛出
    error AlreadyUnlocked();

    /// @notice 调用需要合约处于解锁状态的函数、但合约尚未解锁时抛出
    error ManagerLocked();

    /// @notice 在 #initialize 中，池子的 tickSpacing 上限为 type(int16).max，以防止溢出
    error TickSpacingTooLarge(int24 tickSpacing);

    /// @notice 传给 #initialize 的 tickSpacing 必须为非零正数
    error TickSpacingTooSmall(int24 tickSpacing);

    /// @notice PoolKey 中的代币必须满足 address(currency0) < address(currency1)
    error CurrenciesOutOfOrderOrEqual(address currency0, address currency1);

    /// @notice 当 updateDynamicLPFee 的调用者不是该池子的 hook，
    /// 或目标池子未启用动态兑换手续费时抛出。
    error UnauthorizedDynamicLPFeeUpdate();

    /// @notice 尝试以 0 数量进行兑换时抛出
    error SwapAmountCannotBeZero();

    ///@notice 在非原生代币的结算中传入了原生代币时抛出
    error NonzeroNativeValue();

    /// @notice 调用 `clear` 时传入的数量不严格等于当前未结清的代币 delta 时抛出。
    error MustClearExactPositiveDelta();

    /// @notice 新池子初始化时触发
    /// @param id 新池子的池子 key 结构体经 abi 编码后的哈希
    /// @param currency0 按地址排序后池子的第一个代币
    /// @param currency1 按地址排序后池子的第二个代币
    /// @param fee 池子中每次兑换收取的手续费，单位为百分之一 bip
    /// @param tickSpacing 已初始化 tick 之间的最小 tick 间隔数
    /// @param hooks 池子的 hook 合约地址，若无则为 address(0)
    /// @param sqrtPriceX96 池子初始化时的价格
    /// @param tick 与初始化价格对应的池子初始 tick
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks,
        uint160 sqrtPriceX96,
        int24 tick
    );

    /// @notice 流动性头寸被修改时触发
    /// @param id 被修改池子的池子 key 结构体经 abi 编码后的哈希
    /// @param sender 修改池子的地址
    /// @param tickLower 头寸的下边界 tick
    /// @param tickUpper 头寸的上边界 tick
    /// @param liquidityDelta 添加或移除的流动性数量
    /// @param salt 用于使头寸唯一的额外数据
    event ModifyLiquidity(
        PoolId indexed id, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta, bytes32 salt
    );

    /// @notice currency0 与 currency1 之间发生兑换时触发
    /// @param id 被修改池子的池子 key 结构体经 abi 编码后的哈希
    /// @param sender 发起兑换调用并接收回调的地址
    /// @param amount0 池子 currency0 余额的 delta
    /// @param amount1 池子 currency1 余额的 delta
    /// @param sqrtPriceX96 兑换后池子的 sqrt(price)，Q64.96 格式
    /// @param liquidity 兑换后池子的流动性
    /// @param tick 兑换后池子价格以 1.0001 为底的对数
    /// @param fee 兑换手续费，单位为百分之一 bip
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    /// @notice 发生捐赠时触发
    /// @param id 接受捐赠的池子的池子 key 结构体经 abi 编码后的哈希
    /// @param sender 发起 donate 调用的地址
    /// @param amount0 捐赠的 currency0 数量
    /// @param amount1 捐赠的 currency1 数量
    event Donate(PoolId indexed id, address indexed sender, uint256 amount0, uint256 amount1);

    /// @notice 合约上所有涉及 delta 记账的交互都需要先解锁。调用 `unlock` 的调用者必须实现
    /// `IUnlockCallback(msg.sender).unlockCallback(data)`，并在其中与本合约的其余函数交互。
    /// @dev 无需解锁即可调用的函数只有 `initialize` 和 `updateDynamicLPFee`
    /// @param data 通过 `IUnlockCallback(msg.sender).unlockCallback(data)` 传给回调的任意数据
    /// @return 调用 `IUnlockCallback(msg.sender).unlockCallback(data)` 返回的数据
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice 初始化给定池子 ID 的状态
    /// @dev 若兑换手续费总计达到 MAX_SWAP_FEE（100%），精确输出兑换将无法进行，因为输入会被手续费完全消耗
    /// @param key 待初始化池子的池子 key
    /// @param sqrtPriceX96 初始平方根价格
    /// @return tick 池子的初始 tick
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice 修改给定池子的流动性
    /// @dev 传入为零的 liquidityDelta 调用即可对头寸进行 poke（刷新）
    /// @param key 要修改流动性的池子
    /// @param params 修改流动性所用的参数
    /// @param hookData 透传给 add/removeLiquidity hook 的数据
    /// @return callerDelta modifyLiquidity 调用者的余额差额。它是本金 delta、手续费 delta 以及（如适用）hook delta 的总和
    /// @return feesAccrued 该流动性区间内产生的手续费的余额差额，仅供参考
    /// @dev 注意 feesAccrued 可能被恶意行为者人为抬高，集成方在使用该值时应谨慎
    /// 对于只有单个流动性头寸的池子，行为者可以向自己捐赠来抬高 feeGrowthGlobal（进而抬高 feesAccrued）
    /// 在同一个 unlockCallback 中原子地捐赠并收取手续费，可能使被抬高的值更加极端
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);

    /// @notice 在给定池子中进行兑换
    /// @param key 进行兑换的池子
    /// @param params 兑换参数
    /// @param hookData 透传给兑换 hook 的数据
    /// @return swapDelta 执行兑换的地址的余额差额
    /// @dev 在低流动性池子中兑换时，若可用流动性小于 amountSpecified，可能导致意料之外的兑换数量。
    /// 另需注意，若与设置了 BEFORE_SWAP_RETURNS_DELTA_FLAG 或 AFTER_SWAP_RETURNS_DELTA_FLAG 的 hook 交互，
    /// 该 hook 可能会改变兑换的输入/输出。集成方应对返回的 swapDelta 进行检查。
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta swapDelta);

    /// @notice 将给定数量的代币捐赠给池子中处于价格区间内的流动性提供者
    /// @dev 对 donate 的调用可能被抢跑（frontrun）：攻击者添加即时（just-in-time）流动性，以分得部分捐赠资金。
    /// 捐赠者在设计捐赠机制时应考虑到这一点。
    /// @dev 本函数捐赠给 slot0.tick 处的区间内 LP。在兑换算法的某些边界情况下，池子的 `sqrtPrice`
    /// 可能位于 tick `n` 的下边界，而池子的 `slot0.tick` 已经是 `n - 1`。此时调用
    /// `donate` 会捐赠给 tick `n - 1`（slot0.tick），而不是 tick `n`（getTickAtSqrtPrice(slot0.sqrtPriceX96)）。
    /// 更多信息请阅读 `Pool.swap()` 中的注释。
    /// @param key 接受捐赠的池子的 key
    /// @param amount0 要捐赠的 currency0 数量
    /// @param amount1 要捐赠的 currency1 数量
    /// @param hookData 透传给 donate hook 的数据
    /// @return BalanceDelta 捐赠后调用者的 delta
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        returns (BalanceDelta);

    /// @notice 将指定代币当前的 ERC20 余额写入瞬态存储
    /// 用于为 manager 记录余额检查点，并据此推算调用者的 delta。
    /// @dev 在向合约转入任何 ERC20 代币之前必须（MUST）调用此函数；对于原生代币则可以跳过，
    /// 因为待结算的数量由发送的 value 决定。
    /// 不过，如果某个 ERC20 代币已同步但尚未结算，而调用者想改为结算
    /// 原生资金，则可以用原生代币调用此函数，随后即可结算原生代币
    function sync(Currency currency) external;

    /// @notice 由用户调用，提取欠用户的部分价值以轧平（net out）余额
    /// @dev 若请求的数量不可用将回滚（revert），可考虑改用 `mint`
    /// @dev 也可用作免费闪电贷的机制
    /// @param currency 要从 pool manager 提取的代币
    /// @param to 提取的目标地址
    /// @param amount 要提取的代币数量
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice 由用户调用，用于支付所欠款项
    /// @return paid 已结算的代币数量
    function settle() external payable returns (uint256 paid);

    /// @notice 由用户调用，代表另一地址进行支付
    /// @param recipient 该笔支付记入的地址
    /// @return paid 已结算的代币数量
    function settleFor(address recipient) external payable returns (uint256 paid);

    /// @notice 警告 - 任何被 clear 的代币都将无法取回，并被永久锁定在合约中。
    /// 调用 clear 会在没有（WITHOUT）任何对应转账的情况下将正余额清零。
    /// @dev 可用于清除被视为粉尘（dust）的余额。
    /// 此外，传入的数量必须恰好等于该正余额，以确保调用者清楚被清除的数量。
    function clear(Currency currency, uint256 amount) external;

    /// @notice 由用户调用，将价值转入 ERC6909 余额
    /// @param to 接收铸造代币的地址
    /// @param id 要铸造为 ERC6909 的代币地址，以 uint256 表示
    /// @param amount 要铸造的代币数量
    /// @dev id 会被转换为 uint160，以对应代币地址
    /// 若高 12 字节不为 0，将被清零
    function mint(address to, uint256 id, uint256 amount) external;

    /// @notice 由用户调用，将价值从 ERC6909 余额中转出
    /// @param from 销毁代币的来源地址
    /// @param id 要从 ERC6909 销毁的代币地址，以 uint256 表示
    /// @param amount 要销毁的代币数量
    /// @dev id 会被转换为 uint160，以对应代币地址
    /// 若高 12 字节不为 0，将被清零
    function burn(address from, uint256 id, uint256 amount) external;

    /// @notice 为已启用动态 LP 手续费的池子更新其 LP 手续费。
    /// @dev 若兑换手续费总计达到 MAX_SWAP_FEE（100%），精确输出兑换将无法进行，因为输入会被手续费完全消耗
    /// @param key 要更新动态 LP 手续费的池子的 key
    /// @param newDynamicLPFee 新的池子动态 LP 手续费
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external;
}
