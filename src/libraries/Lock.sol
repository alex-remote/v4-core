// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @notice 这是一个临时库，让我们能够使用瞬态存储（tstore/tload）
/// TODO: 当 solidity 支持 transient 关键字后，即可删除此库。
library Lock {
    // 以瞬态方式保存解锁状态的存储槽。bytes32(uint256(keccak256("Unlocked")) - 1)
    bytes32 internal constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;

    function unlock() internal {
        assembly ("memory-safe") {
            // 解锁
            tstore(IS_UNLOCKED_SLOT, true)
        }
    }

    function lock() internal {
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, false)
        }
    }

    function isUnlocked() internal view returns (bool unlocked) {
        assembly ("memory-safe") {
            unlocked := tload(IS_UNLOCKED_SLOT)
        }
    }
}
