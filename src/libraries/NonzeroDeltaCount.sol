// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @notice 这是一个临时库，让我们能够使用瞬态存储（tstore/tload）
/// 来记录非零 delta 的数量。
/// TODO: 当 solidity 支持 transient 关键字后，即可删除此库。
library NonzeroDeltaCount {
    // 保存非零 delta 数量的存储槽。bytes32(uint256(keccak256("NonzeroDeltaCount")) - 1)
    bytes32 internal constant NONZERO_DELTA_COUNT_SLOT =
        0x7d4b3164c6e45b97e7d87b7125a44c5828d005af88f9d751cfd78729c5d99a0b;

    function read() internal view returns (uint256 count) {
        assembly ("memory-safe") {
            count := tload(NONZERO_DELTA_COUNT_SLOT)
        }
    }

    function increment() internal {
        assembly ("memory-safe") {
            let count := tload(NONZERO_DELTA_COUNT_SLOT)
            count := add(count, 1)
            tstore(NONZERO_DELTA_COUNT_SLOT, count)
        }
    }

    /// @notice 存在下溢的可能。集成该库的合约需执行检查，确保这种情况不会发生。
    /// 当前的用法保证不会发生下溢，因为我们在已知边界内调用 decrement（调用次数最多等于调用 increment 的次数）。
    function decrement() internal {
        assembly ("memory-safe") {
            let count := tload(NONZERO_DELTA_COUNT_SLOT)
            count := sub(count, 1)
            tstore(NONZERO_DELTA_COUNT_SLOT, count)
        }
    }
}
