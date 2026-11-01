// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Slot0 是 solidity 结构体的打包版本。
 * 使用打包版本可以节省 gas，因为无需把结构体的各字段分别存放在各自的内存槽中。
 *
 * 布局：
 * 24 bits empty | 24 bits lpFee | 12 bits protocolFee 1->0 | 12 bits protocolFee 0->1 | 24 bits tick | 160 bits sqrtPriceX96
 *
 * 从最低有效位开始依次排列的字段：
 *
 * 当前价格
 * uint160 sqrtPriceX96;
 *
 * 当前 tick
 * int24 tick;
 *
 * 协议手续费，以百分之一 bip 为单位，高 12 位用于 1->0 方向，低 12 位用于 0->1 方向
 * 最大值为 1000，即协议手续费最高为 0.1%
 * 先从输入中收取 protocolFee，再从剩余输入中收取 lpFee
 * uint24 protocolFee;
 *
 * 池子当前的 LP 手续费。若池子为动态手续费池，此值不包含动态手续费标志位。
 * uint24 lpFee;
 */
type Slot0 is bytes32;

using Slot0Library for Slot0 global;

/// @notice 用于读取和设置 Slot0 类型中各值的库
library Slot0Library {
    uint160 internal constant MASK_160_BITS = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    uint8 internal constant TICK_OFFSET = 160;
    uint8 internal constant PROTOCOL_FEE_OFFSET = 184;
    uint8 internal constant LP_FEE_OFFSET = 208;

    // #### 读取函数（GETTERS） ####
    function sqrtPriceX96(Slot0 _packed) internal pure returns (uint160 _sqrtPriceX96) {
        assembly ("memory-safe") {
            _sqrtPriceX96 := and(MASK_160_BITS, _packed)
        }
    }

    function tick(Slot0 _packed) internal pure returns (int24 _tick) {
        assembly ("memory-safe") {
            _tick := signextend(2, shr(TICK_OFFSET, _packed))
        }
    }

    function protocolFee(Slot0 _packed) internal pure returns (uint24 _protocolFee) {
        assembly ("memory-safe") {
            _protocolFee := and(MASK_24_BITS, shr(PROTOCOL_FEE_OFFSET, _packed))
        }
    }

    function lpFee(Slot0 _packed) internal pure returns (uint24 _lpFee) {
        assembly ("memory-safe") {
            _lpFee := and(MASK_24_BITS, shr(LP_FEE_OFFSET, _packed))
        }
    }

    // #### 设置函数（SETTERS） ####
    function setSqrtPriceX96(Slot0 _packed, uint160 _sqrtPriceX96) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(and(not(MASK_160_BITS), _packed), and(MASK_160_BITS, _sqrtPriceX96))
        }
    }

    function setTick(Slot0 _packed, int24 _tick) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(and(not(shl(TICK_OFFSET, MASK_24_BITS)), _packed), shl(TICK_OFFSET, and(MASK_24_BITS, _tick)))
        }
    }

    function setProtocolFee(Slot0 _packed, uint24 _protocolFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(PROTOCOL_FEE_OFFSET, MASK_24_BITS)), _packed),
                    shl(PROTOCOL_FEE_OFFSET, and(MASK_24_BITS, _protocolFee))
                )
        }
    }

    function setLpFee(Slot0 _packed, uint24 _lpFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(LP_FEE_OFFSET, MASK_24_BITS)), _packed), shl(LP_FEE_OFFSET, and(MASK_24_BITS, _lpFee)))
        }
    }
}
