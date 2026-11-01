// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SafeCast} from "./SafeCast.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {Position} from "./Position.sol";
import {UnsafeMath} from "./UnsafeMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";
import {TickMath} from "./TickMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";
import {SwapMath} from "./SwapMath.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {Slot0} from "../types/Slot0.sol";
import {ProtocolFeeLibrary} from "./ProtocolFeeLibrary.sol";
import {LiquidityMath} from "./LiquidityMath.sol";
import {LPFeeLibrary} from "./LPFeeLibrary.sol";
import {CustomRevert} from "./CustomRevert.sol";

/// @notice 包含可对池子执行的所有操作的库
library Pool {
    using SafeCast for *;
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.State);
    using Position for Position.State;
    using Pool for State;
    using ProtocolFeeLibrary for *;
    using LPFeeLibrary for uint24;
    using CustomRevert for bytes4;

    /// @notice 当 tickLower 不小于 tickUpper 时抛出
    /// @param tickLower 无效的 tickLower
    /// @param tickUpper 无效的 tickUpper
    error TicksMisordered(int24 tickLower, int24 tickUpper);

    /// @notice 当 tickLower 小于最小 tick 时抛出
    /// @param tickLower 无效的 tickLower
    error TickLowerOutOfBounds(int24 tickLower);

    /// @notice 当 tickUpper 超过最大 tick 时抛出
    /// @param tickUpper 无效的 tickUpper
    error TickUpperOutOfBounds(int24 tickUpper);

    /// @notice 在当前 tick 间距下，该 tick 的流动性过多
    error TickLiquidityOverflow(int24 tick);

    /// @notice 尝试初始化一个已初始化的池子时抛出
    error PoolAlreadyInitialized();

    /// @notice 尝试与未初始化的池子交互时抛出
    error PoolNotInitialized();

    /// @notice 当兑换（swap）的 sqrtPriceLimitX96 已超出其限制时抛出
    /// @param sqrtPriceCurrentX96 无效的、已被越过的 sqrtPriceLimitX96
    /// @param sqrtPriceLimitX96 已被越过的价格限制
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);

    /// @notice 当 sqrtPriceLimitX96 位于有效 tick/价格范围之外时抛出
    /// @param sqrtPriceLimitX96 无效的、越界的 sqrtPriceLimitX96
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    /// @notice 当前流动性为 0 时由 donate 抛出，因为手续费不会流向任何流动性提供者
    error NoLiquidityToReceiveFees();

    /// @notice 尝试以最大 LP 手续费进行兑换（swap）并指定输出数量时抛出
    error InvalidFeeForExactOut();

    // 为每个已初始化的 tick 单独存储的信息
    struct TickInfo {
        // 引用该 tick 的所有头寸流动性总量
        uint128 liquidityGross;
        // 当 tick 从左向右（从右向左）被穿越时增加（减少）的净流动性数量，
        int128 liquidityNet;
        // 该 tick _另一侧_（相对于当前 tick）每单位流动性的手续费增长量
        // 仅具有相对意义而非绝对意义——其数值取决于该 tick 何时被初始化
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    /// @notice 池子的状态
    /// @dev 注意 feeGrowthGlobal 可能被人为抬高
    /// 对于只有单个流动性头寸的池子，参与者可以向自己捐赠来随意抬高 feeGrowthGlobal
    /// 在同一个 unlockCallback 中原子地捐赠并收取手续费，可能使抬高后的数值更加极端
    struct State {
        Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 liquidity;
        mapping(int24 tick => TickInfo) ticks;
        mapping(int16 wordPos => uint256) tickBitmap;
        mapping(bytes32 positionKey => Position.State) positions;
    }

    /// @dev 对 tick 输入有效性的通用检查。
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper) TicksMisordered.selector.revertWith(tickLower, tickUpper);
        if (tickLower < TickMath.MIN_TICK) TickLowerOutOfBounds.selector.revertWith(tickLower);
        if (tickUpper > TickMath.MAX_TICK) TickUpperOutOfBounds.selector.revertWith(tickUpper);
    }

    function initialize(State storage self, uint160 sqrtPriceX96, uint24 lpFee) internal returns (int24 tick) {
        if (self.slot0.sqrtPriceX96() != 0) PoolAlreadyInitialized.selector.revertWith();

        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // 初始 protocolFee 为 0，因此无需设置
        self.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick).setLpFee(lpFee);
    }

    function setProtocolFee(State storage self, uint24 protocolFee) internal {
        self.checkPoolInitialized();
        self.slot0 = self.slot0.setProtocolFee(protocolFee);
    }

    /// @notice 只有动态手续费池子才能更新 LP 手续费。
    function setLPFee(State storage self, uint24 lpFee) internal {
        self.checkPoolInitialized();
        self.slot0 = self.slot0.setLpFee(lpFee);
    }

    struct ModifyLiquidityParams {
        // 拥有该头寸的地址
        address owner;
        // 头寸的下界 tick 和上界 tick
        int24 tickLower;
        int24 tickUpper;
        // 流动性的任意变化量
        int128 liquidityDelta;
        // tick 之间的间距
        int24 tickSpacing;
        // 用于区分同一所有者在相同 tick 区间内的不同头寸
        bytes32 salt;
    }

    struct ModifyLiquidityState {
        bool flippedLower;
        uint128 liquidityGrossAfterLower;
        bool flippedUpper;
        uint128 liquidityGrossAfterUpper;
    }

    /// @notice 对池子中的某个头寸施加变更
    /// @dev PoolManager 在调用前会检查池子是否已初始化
    /// @param params 头寸详情以及要施加于该头寸流动性的变化量
    /// @return delta 流动性变化所产生的池子代币余额 delta
    /// @return feeDelta 该流动性区间产生的手续费
    function modifyLiquidity(State storage self, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta, BalanceDelta feeDelta)
    {
        int128 liquidityDelta = params.liquidityDelta;
        int24 tickLower = params.tickLower;
        int24 tickUpper = params.tickUpper;
        checkTicks(tickLower, tickUpper);

        {
            ModifyLiquidityState memory state;

            // 如果需要更新 tick，则执行更新
            if (liquidityDelta != 0) {
                (state.flippedLower, state.liquidityGrossAfterLower) =
                    updateTick(self, tickLower, liquidityDelta, false);
                (state.flippedUpper, state.liquidityGrossAfterUpper) = updateTick(self, tickUpper, liquidityDelta, true);

                // 此处 `>` 与 `>=` 在逻辑上等价，但 `>=` 更省 gas
                if (liquidityDelta >= 0) {
                    uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                    if (state.liquidityGrossAfterLower > maxLiquidityPerTick) {
                        TickLiquidityOverflow.selector.revertWith(tickLower);
                    }
                    if (state.liquidityGrossAfterUpper > maxLiquidityPerTick) {
                        TickLiquidityOverflow.selector.revertWith(tickUpper);
                    }
                }

                if (state.flippedLower) {
                    self.tickBitmap.flipTick(tickLower, params.tickSpacing);
                }
                if (state.flippedUpper) {
                    self.tickBitmap.flipTick(tickUpper, params.tickSpacing);
                }
            }

            {
                (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
                    getFeeGrowthInside(self, tickLower, tickUpper);

                Position.State storage position = self.positions.get(params.owner, tickLower, tickUpper, params.salt);
                (uint256 feesOwed0, uint256 feesOwed1) =
                    position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

                // 计算并返回提供流动性（LP）所赚取的手续费
                feeDelta = toBalanceDelta(feesOwed0.toInt128(), feesOwed1.toInt128());
            }

            // 清除所有不再需要的 tick 数据
            if (liquidityDelta < 0) {
                if (state.flippedLower) {
                    clearTick(self, tickLower);
                }
                if (state.flippedUpper) {
                    clearTick(self, tickUpper);
                }
            }
        }

        if (liquidityDelta != 0) {
            Slot0 _slot0 = self.slot0;
            (int24 tick, uint160 sqrtPriceX96) = (_slot0.tick(), _slot0.sqrtPriceX96());
            if (tick < tickLower) {
                // 当前 tick 低于传入的区间；流动性只能通过从左向
                // 右穿越才会进入区间，届时我们需要 _更多_ currency0（它正在升值），因此用户必须提供它
                delta = toBalanceDelta(
                    SqrtPriceMath.getAmount0Delta(
                        TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta
                    ).toInt128(),
                    0
                );
            } else if (tick < tickUpper) {
                delta = toBalanceDelta(
                    SqrtPriceMath.getAmount0Delta(sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta)
                        .toInt128(),
                    SqrtPriceMath.getAmount1Delta(TickMath.getSqrtPriceAtTick(tickLower), sqrtPriceX96, liquidityDelta)
                        .toInt128()
                );

                self.liquidity = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
            } else {
                // 当前 tick 高于传入的区间；流动性只能通过从右向
                // 左穿越才会进入区间，届时我们需要 _更多_ currency1（它正在升值），因此用户必须提供它
                delta = toBalanceDelta(
                    0,
                    SqrtPriceMath.getAmount1Delta(
                        TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta
                    ).toInt128()
                );
            }
        }
    }

    // 在整个兑换（swap）过程中跟踪池子的状态，并在兑换结束时返回这些值
    struct SwapResult {
        // 当前的 sqrt(price)
        uint160 sqrtPriceX96;
        // 与当前价格对应的 tick
        int24 tick;
        // 当前区间内的流动性
        uint128 liquidity;
    }

    struct StepComputations {
        // 该步开始时的价格
        uint160 sqrtPriceStartX96;
        // 沿兑换方向从当前 tick 出发要兑换到的下一个 tick
        int24 tickNext;
        // tickNext 是否已初始化
        bool initialized;
        // 下一个 tick 的 sqrt(price)（1/0）
        uint160 sqrtPriceNextX96;
        // 本步中兑换输入的数量
        uint256 amountIn;
        // 兑换输出的数量
        uint256 amountOut;
        // 支付的手续费数量
        uint256 feeAmount;
        // 输入代币的全局手续费增长量。在兑换结束时更新到 storage 中
        uint256 feeGrowthGlobalX128;
    }

    struct SwapParams {
        int256 amountSpecified;
        int24 tickSpacing;
        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
        uint24 lpFeeOverride;
    }

    /// @notice 基于该状态执行一次兑换（swap），并返回池子的数量 delta
    /// @dev PoolManager 在调用前会检查池子是否已初始化
    function swap(State storage self, SwapParams memory params)
        internal
        returns (BalanceDelta swapDelta, uint256 amountToProtocol, uint24 swapFee, SwapResult memory result)
    {
        Slot0 slot0Start = self.slot0;
        bool zeroForOne = params.zeroForOne;

        uint256 protocolFee =
            zeroForOne ? slot0Start.protocolFee().getZeroForOneFee() : slot0Start.protocolFee().getOneForZeroFee();

        // 输入/输出资产中剩余待兑换输入/输出的数量。初始值为 amountSpecified
        int256 amountSpecifiedRemaining = params.amountSpecified;
        // 输出/输入资产中已兑换输出/输入的数量。初始值为 0
        int256 amountCalculated = 0;
        // 初始化为当前的 sqrt(price)
        result.sqrtPriceX96 = slot0Start.sqrtPriceX96();
        // 初始化为当前 tick
        result.tick = slot0Start.tick();
        // 初始化为当前流动性
        result.liquidity = self.liquidity;

        // 如果 beforeSwap hook 返回了有效的手续费覆盖值，则将其用作 LP 手续费，否则从 storage 中加载
        // lpFee、swapFee 和 protocolFee 的单位均为 pips
        {
            uint24 lpFee = params.lpFeeOverride.isOverride()
                ? params.lpFeeOverride.removeOverrideFlagAndValidate()
                : slot0Start.lpFee();

            swapFee = protocolFee == 0 ? lpFee : uint16(protocolFee).calculateSwapFee(lpFee);
        }

        // 总计达到 MAX_SWAP_FEE（100%）的兑换手续费会使精确输出兑换无法进行，因为输入会被手续费完全消耗
        if (swapFee >= SwapMath.MAX_SWAP_FEE) {
            // 如果是 exactOutput（精确输出）
            if (params.amountSpecified > 0) {
                InvalidFeeForExactOut.selector.revertWith();
            }
        }

        // swapFee 是池子以 pips 为单位的手续费（LP 手续费 + 协议手续费）
        // 当兑换数量为 0 时，不收取 protocolFee，支付给协议的手续费数量设为 0
        if (params.amountSpecified == 0) return (BalanceDeltaLibrary.ZERO_DELTA, 0, swapFee, result);

        if (zeroForOne) {
            if (params.sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96()) {
                PriceLimitAlreadyExceeded.selector.revertWith(slot0Start.sqrtPriceX96(), params.sqrtPriceLimitX96);
            }
            // 除池子初始化时外，兑换永远不会发生在 MIN_TICK，只会发生在 MIN_TICK + 1
            // 在下文所述的某些情况下，tick 会预先到达 MIN_TICK，但并不在那里发生兑换
            if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_PRICE) {
                PriceLimitOutOfBounds.selector.revertWith(params.sqrtPriceLimitX96);
            }
        } else {
            if (params.sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96()) {
                PriceLimitAlreadyExceeded.selector.revertWith(slot0Start.sqrtPriceX96(), params.sqrtPriceLimitX96);
            }
            if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_PRICE) {
                PriceLimitOutOfBounds.selector.revertWith(params.sqrtPriceLimitX96);
            }
        }

        StepComputations memory step;
        step.feeGrowthGlobalX128 = zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128;

        // 只要尚未用完全部输入/输出且尚未到达价格限制，就继续兑换
        while (!(amountSpecifiedRemaining == 0 || result.sqrtPriceX96 == params.sqrtPriceLimitX96)) {
            step.sqrtPriceStartX96 = result.sqrtPriceX96;

            (step.tickNext, step.initialized) =
                self.tickBitmap.nextInitializedTickWithinOneWord(result.tick, params.tickSpacing, zeroForOne);

            // 确保不会越过最小/最大 tick，因为 tick 位图并不知道这些边界
            if (step.tickNext <= TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            }
            if (step.tickNext >= TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // 获取下一个 tick 的价格
            step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);

            // 计算兑换到目标 tick、价格限制或输入/输出数量耗尽点所需的各项数值
            (result.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                result.sqrtPriceX96,
                SwapMath.getSqrtPriceTarget(zeroForOne, step.sqrtPriceNextX96, params.sqrtPriceLimitX96),
                result.liquidity,
                amountSpecifiedRemaining,
                swapFee
            );

            // 如果是 exactOutput（精确输出）
            if (params.amountSpecified > 0) {
                unchecked {
                    amountSpecifiedRemaining -= step.amountOut.toInt256();
                }
                amountCalculated -= (step.amountIn + step.feeAmount).toInt256();
            } else {
                // 这是安全的，因为我们在 SwapMath 中检验了 amountSpecified > amountIn + feeAmount
                unchecked {
                    amountSpecifiedRemaining += (step.amountIn + step.feeAmount).toInt256();
                }
                amountCalculated += step.amountOut.toInt256();
            }

            // 如果开启了协议手续费，则计算应付金额，减少 feeAmount，并增加 protocolFee
            if (protocolFee > 0) {
                unchecked {
                    // step.amountIn 不包含兑换手续费，因为手续费已从中扣除，
                    // 所以要把它加回以得到总 amountIn，并用其计算应付给协议的手续费数量
                    // 由于 protocolFee 和 params.amountSpecified 的大小受限，不会溢出
                    // 这里向下取整，使 LP 相对于协议更有利
                    uint256 delta = (swapFee == protocolFee)
                        ? step.feeAmount // LP 手续费为 0，因此全部手续费改为归协议所有
                        : (step.amountIn + step.feeAmount) * protocolFee / ProtocolFeeLibrary.PIPS_DENOMINATOR;
                    // 从总手续费中减去它，并加到协议手续费中
                    step.feeAmount -= delta;
                    amountToProtocol += delta;
                }
            }

            // 更新全局手续费跟踪值
            if (result.liquidity > 0) {
                unchecked {
                    // 无需使用 FullMath.mulDiv，因为代币的最大供应量为 type(uint128).max，分子不会溢出 uint256
                    step.feeGrowthGlobalX128 +=
                        UnsafeMath.simpleMulDiv(step.feeAmount, FixedPoint128.Q128, result.liquidity);
                }
            }

            // 如果到达了下一个价格则移动 tick，对于 zeroForOne 兑换则预先减为 tickNext - 1。
            // 如果兑换不再继续（amountRemaining == 0 或达到 sqrtPriceLimit），slot0.tick 将比
            // getTickAtSqrtPrice(slot0.sqrtPrice) 小 1。这不会影响兑换，但捐赠调用应同时校验
            // 价格和 tick，以奖励正确的 LP。
            if (result.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // 如果该 tick 已初始化，则执行 tick 转换
                if (step.initialized) {
                    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = zeroForOne
                        ? (step.feeGrowthGlobalX128, self.feeGrowthGlobal1X128)
                        : (self.feeGrowthGlobal0X128, step.feeGrowthGlobalX128);
                    int128 liquidityNet =
                        Pool.crossTick(self, step.tickNext, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
                    // 如果向左移动，则将 liquidityNet 解释为相反符号
                    // 这是安全的，因为 liquidityNet 不可能为 type(int128).min
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }

                    result.liquidity = LiquidityMath.addDelta(result.liquidity, liquidityNet);
                }

                unchecked {
                    result.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
                }
            } else if (result.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // 重新计算，除非我们位于 tick 下边界（即已完成 tick 转换）且未移动
                result.tick = TickMath.getTickAtSqrtPrice(result.sqrtPriceX96);
            }
        }

        self.slot0 = slot0Start.setTick(result.tick).setSqrtPriceX96(result.sqrtPriceX96);

        // 若流动性发生变化则更新
        if (self.liquidity != result.liquidity) self.liquidity = result.liquidity;

        // 更新全局手续费增长量
        if (!zeroForOne) {
            self.feeGrowthGlobal1X128 = step.feeGrowthGlobalX128;
        } else {
            self.feeGrowthGlobal0X128 = step.feeGrowthGlobalX128;
        }

        unchecked {
            // “如果指定的是 currency1”
            if (zeroForOne != (params.amountSpecified < 0)) {
                swapDelta = toBalanceDelta(
                    amountCalculated.toInt128(), (params.amountSpecified - amountSpecifiedRemaining).toInt128()
                );
            } else {
                swapDelta = toBalanceDelta(
                    (params.amountSpecified - amountSpecifiedRemaining).toInt128(), amountCalculated.toInt128()
                );
            }
        }
    }

    /// @notice 向池子捐赠给定数量的 currency0 和 currency1
    function donate(State storage state, uint256 amount0, uint256 amount1) internal returns (BalanceDelta delta) {
        uint128 liquidity = state.liquidity;
        if (liquidity == 0) NoLiquidityToReceiveFees.selector.revertWith();
        unchecked {
            // 取负是安全的，因为 amount0 和 amount1 始终为正
            delta = toBalanceDelta(-(amount0.toInt128()), -(amount1.toInt128()));
            // 无需使用 FullMath.mulDiv，因为分子上限为 type(int128).max * Q128，小于 type(uint256).max
            if (amount0 > 0) {
                state.feeGrowthGlobal0X128 += UnsafeMath.simpleMulDiv(amount0, FixedPoint128.Q128, liquidity);
            }
            if (amount1 > 0) {
                state.feeGrowthGlobal1X128 += UnsafeMath.simpleMulDiv(amount1, FixedPoint128.Q128, liquidity);
            }
        }
    }

    /// @notice 获取手续费增长量数据
    /// @param self Pool 状态结构体
    /// @param tickLower 头寸的 tick 下边界
    /// @param tickUpper 头寸的 tick 上边界
    /// @return feeGrowthInside0X128 头寸 tick 边界内、每单位流动性的 token0 历史累计手续费增长量
    /// @return feeGrowthInside1X128 头寸 tick 边界内、每单位流动性的 token1 历史累计手续费增长量
    function getFeeGrowthInside(State storage self, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        TickInfo storage lower = self.ticks[tickLower];
        TickInfo storage upper = self.ticks[tickUpper];
        int24 tickCurrent = self.slot0.tick();

        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 = lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upper.feeGrowthOutside0X128 - lower.feeGrowthOutside0X128;
                feeGrowthInside1X128 = upper.feeGrowthOutside1X128 - lower.feeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 =
                    self.feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    self.feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            }
        }
    }

    /// @notice 更新一个 tick，若该 tick 从已初始化翻转为未初始化（或反之），则返回 true
    /// @param self 包含所有已初始化 tick 信息的 mapping
    /// @param tick 将被更新的 tick
    /// @param liquidityDelta 当 tick 从左向右（从右向左）被穿越时要增加（减少）的新流动性数量
    /// @param upper 为 true 表示更新头寸的上界 tick，为 false 表示更新头寸的下界 tick
    /// @return flipped 该 tick 是否从已初始化翻转为未初始化，或反之
    /// @return liquidityGrossAfter 更新后引用该 tick 的所有头寸的流动性总量
    function updateTick(State storage self, int24 tick, int128 liquidityDelta, bool upper)
        internal
        returns (bool flipped, uint128 liquidityGrossAfter)
    {
        TickInfo storage info = self.ticks[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        int128 liquidityNetBefore = info.liquidityNet;

        liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // 按照约定，我们假设 tick 初始化之前的所有增长都发生在该 tick _下方_
            if (tick <= self.slot0.tick()) {
                info.feeGrowthOutside0X128 = self.feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = self.feeGrowthGlobal1X128;
            }
        }

        // 当下界（上界）tick 从左向右被穿越时，必须增加（移除）流动性
        // 当下界（上界）tick 从右向左被穿越时，必须移除（增加）流动性
        int128 liquidityNet = upper ? liquidityNetBefore - liquidityDelta : liquidityNetBefore + liquidityDelta;
        assembly ("memory-safe") {
            // liquidityGrossAfter 和 liquidityNet 被打包在 `info` 的第一个存储槽中
            // 因此我们可以先自行打包，再用一次 sstore 将它们写入
            sstore(
                info.slot,
                // 按位 OR，用于打包 liquidityGrossAfter 和 liquidityNet
                or(
                    // 将 liquidityGrossAfter 放在低位，并清除高位
                    and(liquidityGrossAfter, 0xffffffffffffffffffffffffffffffff),
                    // 左移 liquidityNet 将其放到高位（由于是左移，无需 signextend）
                    shl(128, liquidityNet)
                )
            )
        }
    }

    /// @notice 根据给定的 tick 间距推导每个 tick 的最大流动性
    /// @dev 在添加流动性时执行
    /// @param tickSpacing 所要求的 tick 间隔，以 `tickSpacing` 的倍数实现
    ///     例如，tickSpacing 为 3 时要求每隔 3 个 tick 初始化一次，即 ..., -6, -3, 0, 3, 6, ...
    /// @return result 每个 tick 的最大流动性
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128 result) {
        // 等价于：
        // int24 minTick = (TickMath.MIN_TICK / tickSpacing);
        // if (TickMath.MIN_TICK  % tickSpacing != 0) minTick--;
        // int24 maxTick = (TickMath.MAX_TICK / tickSpacing);
        // uint24 numTicks = maxTick - minTick + 1;
        // return type(uint128).max / numTicks;
        int24 MAX_TICK = TickMath.MAX_TICK;
        int24 MIN_TICK = TickMath.MIN_TICK;
        // tick 间距永远不会为 0，因为 TickMath.MIN_TICK_SPACING 为 1
        assembly ("memory-safe") {
            tickSpacing := signextend(2, tickSpacing)
            let minTick := sub(sdiv(MIN_TICK, tickSpacing), slt(smod(MIN_TICK, tickSpacing), 0))
            let maxTick := sdiv(MAX_TICK, tickSpacing)
            let numTicks := add(sub(maxTick, minTick), 1)
            result := div(sub(shl(128, 1), 1), numTicks)
        }
    }

    /// @notice 若给定池子尚未初始化则回滚（revert）
    function checkPoolInitialized(State storage self) internal view {
        if (self.slot0.sqrtPriceX96() == 0) PoolNotInitialized.selector.revertWith();
    }

    /// @notice 清除 tick 数据
    /// @param self 包含所有已初始化 tick 信息的 mapping
    /// @param tick 将被清除的 tick
    function clearTick(State storage self, int24 tick) internal {
        delete self.ticks[tick];
    }

    /// @notice 根据价格变动的需要转换到下一个 tick
    /// @param self Pool 状态结构体
    /// @param tick 转换的目标 tick
    /// @param feeGrowthGlobal0X128 每单位流动性的 token0 历史累计全局手续费增长量
    /// @param feeGrowthGlobal1X128 每单位流动性的 token1 历史累计全局手续费增长量
    /// @return liquidityNet 当 tick 从左向右（从右向左）被穿越时增加（减少）的流动性数量
    function crossTick(State storage self, int24 tick, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128)
        internal
        returns (int128 liquidityNet)
    {
        unchecked {
            TickInfo storage info = self.ticks[tick];
            info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
            info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
            liquidityNet = info.liquidityNet;
        }
    }
}
