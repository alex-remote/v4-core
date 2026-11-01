// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolId} from "../types/PoolId.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Position} from "./Position.sol";

/// @notice 一个使用 extsload 提供状态读取函数（getter）的辅助库
library StateLibrary {
    /// @notice pools 映射在 PoolManager 中的索引（存储槽位置）
    bytes32 public constant POOLS_SLOT = bytes32(uint256(6));

    /// @notice feeGrowthGlobal0X128 在 Pool.State 中的索引
    uint256 public constant FEE_GROWTH_GLOBAL0_OFFSET = 1;

    // feeGrowthGlobal1X128 在 Pool.State 中的偏移量 = 2

    /// @notice liquidity 在 Pool.State 中的索引
    uint256 public constant LIQUIDITY_OFFSET = 3;

    /// @notice TicksInfo 映射在 Pool.State 中的索引：mapping(int24 => TickInfo) ticks;
    uint256 public constant TICKS_OFFSET = 4;

    /// @notice tickBitmap 映射在 Pool.State 中的索引
    uint256 public constant TICK_BITMAP_OFFSET = 5;

    /// @notice Position.State 映射在 Pool.State 中的索引：mapping(bytes32 => Position.State) positions;
    uint256 public constant POSITIONS_OFFSET = 6;

    /**
     * @notice 获取池子的 Slot0：sqrtPriceX96、tick、protocolFee、lpFee
     * @dev 对应 pools[poolId].slot0
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @return sqrtPriceX96 池子价格的平方根，Q96 精度。
     * @return tick 池子的当前 tick。
     * @return protocolFee 池子的协议手续费。
     * @return lpFee 池子的兑换（swap）手续费。
     */
    function getSlot0(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        // Pool.State 值所在的存储槽 key：`pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        bytes32 data = manager.extsload(stateSlot);

        //   24 bits  |24bits|24bits      |24 bits|160 bits
        // 0x000000   |000bb8|000000      |ffff75 |0000000000000000fe3aa841ba359daa0ea9eff7
        // ---------- | fee  |protocolfee | tick  | sqrtPriceX96
        assembly ("memory-safe") {
            // data 的最低 160 位
            sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            // data 的接下来 24 位
            tick := signextend(2, shr(160, data))
            // data 的再接下来 24 位
            protocolFee := and(shr(184, data), 0xFFFFFF)
            // data 的最后 24 位
            lpFee := and(shr(208, data), 0xFFFFFF)
        }
    }

    /**
     * @notice 获取池子在指定 tick 处的 tick 信息。
     * @dev 对应 pools[poolId].ticks[tick]
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param tick 要获取信息的 tick。
     * @return liquidityGross 引用该 tick 的头寸流动性总量
     * @return liquidityNet 当从左向右（从右向左）穿越该 tick 时净增加（减少）的流动性数量
     * @return feeGrowthOutside0X128 该 tick _另一侧_（相对于当前 tick）的单位流动性手续费增长量
     * @return feeGrowthOutside1X128 该 tick _另一侧_（相对于当前 tick）的单位流动性手续费增长量
     */
    function getTickInfo(IPoolManager manager, PoolId poolId, int24 tick)
        internal
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128
        )
    {
        bytes32 slot = _getTickInfoSlot(poolId, tick);

        // 读取 TickInfo 结构体的全部 3 个字（word）
        bytes32[] memory data = manager.extsload(slot, 3);
        assembly ("memory-safe") {
            let firstWord := mload(add(data, 32))
            liquidityNet := sar(128, firstWord)
            liquidityGross := and(firstWord, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            feeGrowthOutside0X128 := mload(add(data, 64))
            feeGrowthOutside1X128 := mload(add(data, 96))
        }
    }

    /**
     * @notice 获取池子在指定 tick 处的流动性信息。
     * @dev 对应 pools[poolId].ticks[tick].liquidityGross 与 pools[poolId].ticks[tick].liquidityNet。是 getTickInfo 更省 gas 的版本
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param tick 要获取流动性的 tick。
     * @return liquidityGross 引用该 tick 的头寸流动性总量
     * @return liquidityNet 当从左向右（从右向左）穿越该 tick 时净增加（减少）的流动性数量
     */
    function getTickLiquidity(IPoolManager manager, PoolId poolId, int24 tick)
        internal
        view
        returns (uint128 liquidityGross, int128 liquidityNet)
    {
        bytes32 slot = _getTickInfoSlot(poolId, tick);

        bytes32 value = manager.extsload(slot);
        assembly ("memory-safe") {
            liquidityNet := sar(128, value)
            liquidityGross := and(value, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /**
     * @notice 获取池子某个 tick 外侧的手续费增长量
     * @dev 对应 pools[poolId].ticks[tick].feeGrowthOutside0X128 与 pools[poolId].ticks[tick].feeGrowthOutside1X128。是 getTickInfo 更省 gas 的版本
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param tick 要获取手续费增长量的 tick。
     * @return feeGrowthOutside0X128 该 tick _另一侧_（相对于当前 tick）的单位流动性手续费增长量
     * @return feeGrowthOutside1X128 该 tick _另一侧_（相对于当前 tick）的单位流动性手续费增长量
     */
    function getTickFeeGrowthOutside(IPoolManager manager, PoolId poolId, int24 tick)
        internal
        view
        returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128)
    {
        bytes32 slot = _getTickInfoSlot(poolId, tick);

        // 偏移 1 个字（word），因为第一个字存放的是 liquidityGross + liquidityNet
        bytes32[] memory data = manager.extsload(bytes32(uint256(slot) + 1), 2);
        assembly ("memory-safe") {
            feeGrowthOutside0X128 := mload(add(data, 32))
            feeGrowthOutside1X128 := mload(add(data, 64))
        }
    }

    /**
     * @notice 获取池子的全局手续费增长量。
     * @dev 对应 pools[poolId].feeGrowthGlobal0X128 与 pools[poolId].feeGrowthGlobal1X128
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @return feeGrowthGlobal0 token0 的全局手续费增长量。
     * @return feeGrowthGlobal1 token1 的全局手续费增长量。
     * @dev 注意：feeGrowthGlobal 可能被人为抬高
     * 对于只有单个流动性头寸的池子，参与者可以向自己捐赠，从而随意抬高 feeGrowthGlobal
     * 在同一个 unlockCallback 中原子地捐赠并收取手续费，可能使被抬高的数值更加极端
     */
    function getFeeGrowthGlobals(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1)
    {
        // Pool.State 值所在的存储槽 key：`pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State 中的 `uint256 feeGrowthGlobal0X128`
        bytes32 slot_feeGrowthGlobal0X128 = bytes32(uint256(stateSlot) + FEE_GROWTH_GLOBAL0_OFFSET);

        // 读取 feeGrowthGlobal 的 2 个字（word）
        bytes32[] memory data = manager.extsload(slot_feeGrowthGlobal0X128, 2);
        assembly ("memory-safe") {
            feeGrowthGlobal0 := mload(add(data, 32))
            feeGrowthGlobal1 := mload(add(data, 64))
        }
    }

    /**
     * @notice 获取池子的总流动性。
     * @dev 对应 pools[poolId].liquidity
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @return liquidity 池子的流动性。
     */
    function getLiquidity(IPoolManager manager, PoolId poolId) internal view returns (uint128 liquidity) {
        // Pool.State 值所在的存储槽 key：`pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State 中的 `uint128 liquidity`
        bytes32 slot = bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET);

        liquidity = uint128(uint256(manager.extsload(slot)));
    }

    /**
     * @notice 获取池子在指定 tick 处的 tick 位图。
     * @dev 对应 pools[poolId].tickBitmap[tick]
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param tick 要获取位图的 tick。
     * @return tickBitmap 该 tick 对应的位图。
     */
    function getTickBitmap(IPoolManager manager, PoolId poolId, int16 tick)
        internal
        view
        returns (uint256 tickBitmap)
    {
        // Pool.State 值所在的存储槽 key：`pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State 中的 `mapping(int16 => uint256) tickBitmap;`
        bytes32 tickBitmapMapping = bytes32(uint256(stateSlot) + TICK_BITMAP_OFFSET);

        // 该映射 key 所在的存储槽 id：`pools[poolId].tickBitmap[tick]
        bytes32 slot = keccak256(abi.encodePacked(int256(tick), tickBitmapMapping));

        tickBitmap = uint256(manager.extsload(slot));
    }

    /**
     * @notice 获取池子中某个头寸的信息，无需事先计算 `positionId`。
     * @dev 对应 pools[poolId].positions[positionId]
     * @param poolId 池子的 ID。
     * @param owner 该流动性头寸的所有者。
     * @param tickLower 流动性区间的下界 tick。
     * @param tickUpper 流动性区间的上界 tick。
     * @param salt 用于进一步区分头寸状态的 bytes32 随机值。
     * @return liquidity 头寸的流动性。
     * @return feeGrowthInside0LastX128 头寸区间内 token0 的手续费增长量。
     * @return feeGrowthInside1LastX128 头寸区间内 token1 的手续费增长量。
     */
    function getPositionInfo(
        IPoolManager manager,
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal view returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) {
        // positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))
        bytes32 positionKey = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);

        (liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128) = getPositionInfo(manager, poolId, positionKey);
    }

    /**
     * @notice 获取池子中指定头寸 ID 的头寸信息。
     * @dev 对应 pools[poolId].positions[positionId]
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param positionId 头寸的 ID。
     * @return liquidity 头寸的流动性。
     * @return feeGrowthInside0LastX128 头寸区间内 token0 的手续费增长量。
     * @return feeGrowthInside1LastX128 头寸区间内 token1 的手续费增长量。
     */
    function getPositionInfo(IPoolManager manager, PoolId poolId, bytes32 positionId)
        internal
        view
        returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
    {
        bytes32 slot = _getPositionInfoSlot(poolId, positionId);

        // 读取 Position.State 结构体的全部 3 个字（word）
        bytes32[] memory data = manager.extsload(slot, 3);

        assembly ("memory-safe") {
            liquidity := mload(add(data, 32))
            feeGrowthInside0LastX128 := mload(add(data, 64))
            feeGrowthInside1LastX128 := mload(add(data, 96))
        }
    }

    /**
     * @notice 获取某个头寸的流动性。
     * @dev 对应 pools[poolId].positions[positionId].liquidity。若只需获取流动性，相比 getPositionInfo 更省 gas
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param positionId 头寸的 ID。
     * @return liquidity 头寸的流动性。
     */
    function getPositionLiquidity(IPoolManager manager, PoolId poolId, bytes32 positionId)
        internal
        view
        returns (uint128 liquidity)
    {
        bytes32 slot = _getPositionInfoSlot(poolId, positionId);
        liquidity = uint128(uint256(manager.extsload(slot)));
    }

    /**
     * @notice 计算池子某个 tick 区间内的手续费增长量
     * @dev Position.State 中的 pools[poolId].feeGrowthInside0LastX128 是缓存值，可能已过时。本函数会计算最新的 feeGrowthInside
     * @param manager 池子管理器（pool manager）合约。
     * @param poolId 池子的 ID。
     * @param tickLower 区间的下界 tick。
     * @param tickUpper 区间的上界 tick。
     * @return feeGrowthInside0X128 该 tick 区间内 token0 的手续费增长量。
     * @return feeGrowthInside1X128 该 tick 区间内 token1 的手续费增长量。
     */
    function getFeeGrowthInside(IPoolManager manager, PoolId poolId, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = getFeeGrowthGlobals(manager, poolId);

        (uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128) =
            getTickFeeGrowthOutside(manager, poolId, tickLower);
        (uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128) =
            getTickFeeGrowthOutside(manager, poolId, tickUpper);
        (, int24 tickCurrent,,) = getSlot0(manager, poolId);
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            }
        }
    }

    function _getPoolStateSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
    }

    function _getTickInfoSlot(PoolId poolId, int24 tick) internal pure returns (bytes32) {
        // Pool.State 值所在的存储槽 key：`pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State 中的 `mapping(int24 => TickInfo) ticks`
        bytes32 ticksMappingSlot = bytes32(uint256(stateSlot) + TICKS_OFFSET);

        // 该 tick key 所在的存储槽 key：`pools[poolId].ticks[tick]
        return keccak256(abi.encodePacked(int256(tick), ticksMappingSlot));
    }

    function _getPositionInfoSlot(PoolId poolId, bytes32 positionId) internal pure returns (bytes32) {
        // Pool.State 值所在的存储槽 key：`pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State 中的 `mapping(bytes32 => Position.State) positions;`
        bytes32 positionMapping = bytes32(uint256(stateSlot) + POSITIONS_OFFSET);

        // 该映射 key 所在的存储槽：`pools[poolId].positions[positionId]
        return keccak256(abi.encodePacked(positionId, positionMapping));
    }
}
