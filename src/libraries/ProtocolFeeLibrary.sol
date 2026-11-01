// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice 与协议手续费相关的函数库
library ProtocolFeeLibrary {
    /// @notice 协议手续费上限为 0.1%（1000 pips）
    /// @dev 增大这些值可能导致 Pool.swap 中发生溢出
    uint16 public constant MAX_PROTOCOL_FEE = 1000;

    /// @notice 用于对协议手续费进行优化边界检查的阈值
    uint24 internal constant FEE_0_THRESHOLD = 1001;
    uint24 internal constant FEE_1_THRESHOLD = 1001 << 12;

    /// @notice 协议手续费以百分之一基点（hundredths of a bip，即 pip）为单位表示
    uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self & 0xfff);
    }

    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }

    function isValidProtocolFee(uint24 self) internal pure returns (bool valid) {
        // 等价于：getZeroForOneFee(self) <= MAX_PROTOCOL_FEE && getOneForZeroFee(self) <= MAX_PROTOCOL_FEE
        assembly ("memory-safe") {
            let isZeroForOneFeeOk := lt(and(self, 0xfff), FEE_0_THRESHOLD)
            let isOneForZeroFeeOk := lt(and(self, 0xfff000), FEE_1_THRESHOLD)
            valid := and(isZeroForOneFeeOk, isOneForZeroFeeOk)
        }
    }

    // 先从输入金额中收取协议手续费，再从剩余部分中收取 LP 手续费
    // 兑换（swap）手续费上限为 100%
    // 等价于 protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000（向上取整）
    /// @dev 这里的 `self` 只是单一方向的协议手续费，而不是打包了 2 个协议手续费的类型
    function calculateSwapFee(uint16 self, uint24 lpFee) internal pure returns (uint24 swapFee) {
        // protocolFee + lpFee - (protocolFee * lpFee / 1_000_000)
        assembly ("memory-safe") {
            self := and(self, 0xfff)
            lpFee := and(lpFee, 0xffffff)
            let numerator := mul(self, lpFee)
            swapFee := sub(add(self, lpFee), div(numerator, PIPS_DENOMINATOR))
        }
    }
}
