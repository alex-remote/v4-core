// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NonzeroDeltaCount} from "../../src/libraries/NonzeroDeltaCount.sol";

contract NonzeroDeltaCountTest is Test {
    function test_incrementNonzeroDeltaCount() public {
        assertEq(NonzeroDeltaCount.read(), 0);
        NonzeroDeltaCount.increment();
        assertEq(NonzeroDeltaCount.read(), 1);
    }

    function test_decrementNonzeroDeltaCount() public {
        assertEq(NonzeroDeltaCount.read(), 0);
        NonzeroDeltaCount.increment();
        assertEq(NonzeroDeltaCount.read(), 1);
        NonzeroDeltaCount.decrement();
        assertEq(NonzeroDeltaCount.read(), 0);
    }

    // 从右往左读取。比特位为 0：调用 increase；比特位为 1：调用 decrease。
    // 该库允许溢出/下溢，因此这里不做相应检查
    function test_fuzz_nonzeroDeltaCount(uint256 instructions) public {
        assertEq(NonzeroDeltaCount.read(), 0);
        uint256 expectedCount;
        for (uint256 i = 0; i < 256; i++) {
            if ((instructions & (1 << i)) == 0) {
                NonzeroDeltaCount.increment();
                unchecked {
                    expectedCount++;
                }
            } else {
                NonzeroDeltaCount.decrement();
                unchecked {
                    expectedCount--;
                }
            }
            assertEq(NonzeroDeltaCount.read(), expectedCount);
        }
    }

    function test_nonzeroDeltaCountSlot() public pure {
        assertEq(bytes32(uint256(keccak256("NonzeroDeltaCount")) - 1), NonzeroDeltaCount.NONZERO_DELTA_COUNT_SLOT);
    }
}
