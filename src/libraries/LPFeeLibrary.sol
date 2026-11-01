// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CustomRevert} from "./CustomRevert.sol";

/// @notice 池子 LP 手续费相关的辅助函数库
library LPFeeLibrary {
    using LPFeeLibrary for uint24;
    using CustomRevert for bytes4;

    /// @notice 当池子的静态或动态手续费超过 100% 时抛出。
    error LPFeeTooLarge(uint24 fee);

    /// @notice LP 手续费恰好为 0b1000000... 时表示动态手续费池子。它不是有效的静态手续费，因为它 > MAX_LP_FEE
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;

    /// @notice beforeSwap 返回的手续费的第二位用于表示本次兑换是否应覆盖已存储的 LP 手续费
    // 只有动态手续费池子才能通过 beforeSwap hook 返回手续费
    uint24 public constant OVERRIDE_FEE_FLAG = 0x400000;

    /// @notice 掩码，用于从 beforeSwap hook 返回的手续费中移除 override 手续费标志位
    uint24 public constant REMOVE_OVERRIDE_MASK = 0xBFFFFF;

    /// @notice LP 手续费以百分之一基点（hundredths of a bip）为单位表示，因此最大值即 100%
    uint24 public constant MAX_LP_FEE = 1000000;

    /// @notice 若池子的 LP 手续费表明该池子使用动态手续费，则返回 true
    /// @param self 待检查的手续费
    /// @return bool 若手续费是动态的则为 true
    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self == DYNAMIC_FEE_FLAG;
    }

    /// @notice 若 LP 手续费有效（即不超过允许的最大手续费），则返回 true
    /// @param self 待检查的手续费
    /// @return bool 若手续费有效则为 true
    function isValid(uint24 self) internal pure returns (bool) {
        return self <= MAX_LP_FEE;
    }

    /// @notice 校验 LP 手续费是否超过最大值，若无效则回滚（revert）
    /// @param self 待校验的手续费
    function validate(uint24 self) internal pure {
        if (!self.isValid()) LPFeeTooLarge.selector.revertWith(self);
    }

    /// @notice 获取并校验池子的初始 LP 手续费。动态手续费池子的初始手续费为 0。
    /// @dev 如果动态手续费池子希望初始手续费不为 0，应在 afterInitialize hook 中调用 `updateDynamicLPFee`
    /// @param self 用于获取初始 LP 手续费的手续费值
    /// @return initialFee 若手续费是动态的则为 0，否则为该手续费（若有效）
    function getInitialLPFee(uint24 self) internal pure returns (uint24) {
        // 动态手续费池子的初始手续费为 0
        if (self.isDynamicFee()) return 0;
        self.validate();
        return self;
    }

    /// @notice 若手续费设置了 override 标志位（uint24 的次高位），则返回 true
    /// @param self 待检查的手续费
    /// @return bool 若手续费设置了 override 标志位则为 true
    function isOverride(uint24 self) internal pure returns (bool) {
        return self & OVERRIDE_FEE_FLAG != 0;
    }

    /// @notice 返回移除了 override 标志位后的手续费
    /// @param self 需要移除 override 标志位的手续费
    /// @return fee 未设置 override 标志位的手续费
    function removeOverrideFlag(uint24 self) internal pure returns (uint24) {
        return self & REMOVE_OVERRIDE_MASK;
    }

    /// @notice 移除 override 标志位并校验手续费（若手续费过大则回滚）
    /// @param self 需要先移除 override 标志位、再进行校验的手续费
    /// @return fee 未设置 override 标志位的手续费（若有效）
    function removeOverrideFlagAndValidate(uint24 self) internal pure returns (uint24 fee) {
        fee = self.removeOverrideFlag();
        fee.validate();
    }
}
