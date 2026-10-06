// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

/// @notice Additional failure and boundary tests for the accepted implementation.
contract CounterAdversarialTest is Test {
    Counter internal counter;
    bytes4 internal constant COUNT_SELECTOR = bytes4(keccak256("count()"));

    function setUp() public {
        counter = new Counter();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_PaymentsRevertOnEveryEntryPointAndCountingRemainsLive(uint256 value, uint256 priorCount) public {
        value = bound(value, 1, type(uint256).max);
        priorCount = bound(priorCount, 0, type(uint256).max - 1);
        _seedCount(priorCount);

        _assertRejected(abi.encodeCall(Counter.increment, ()), value, priorCount);
        _assertRejected(abi.encodeWithSelector(COUNT_SELECTOR), value, priorCount);
        _assertRejected("", value, priorCount);
        _assertRejected(hex"ffffffff", value, priorCount);

        counter.increment();
        assertEq(counter.count(), priorCount + 1, "failed payments cannot disable counting");
        assertEq(address(counter).balance, 0);
    }

    function test_MaximumPaymentIsRejectedWithoutLosingFunds() public {
        counter.increment();
        _assertRejected(abi.encodeCall(Counter.increment, ()), type(uint256).max, 1);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_GetterIsCallerIndependentAndReadOnly(address caller, uint256 priorCount) public {
        _seedCount(priorCount);
        bytes memory data = abi.encodeWithSelector(COUNT_SELECTOR);

        vm.recordLogs();
        vm.prank(caller);
        (bool success, bytes memory result) = address(counter).call(data);
        assertTrue(success, "any caller can read");
        assertEq(result, abi.encode(priorCount), "getter returns exactly one uint256");
        assertEq(counter.count(), priorCount, "ordinary getter call must not write");
        assertEq(vm.getRecordedLogs().length, 0, "reads must not emit events");

        vm.prank(caller);
        (success, result) = address(counter).staticcall(data);
        assertTrue(success, "getter works in a static context");
        assertEq(result, abi.encode(priorCount));
    }

    function test_StaticIncrementRevertsAndPreservesExistingCount() public {
        counter.increment();
        vm.recordLogs();
        // Cap forwarded gas: SSTORE under STATICCALL consumes the callee's gas.
        (bool success,) = address(counter).staticcall{gas: 100_000}(abi.encodeCall(Counter.increment, ()));
        assertFalse(success, "increment requires a writable context");
        assertEq(counter.count(), 1);
        assertEq(vm.getRecordedLogs().length, 0);
        counter.increment();
        assertEq(counter.count(), 2, "failed static call must not block later increments");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnknownSelectorWithPayloadReverts(bytes4 selector, bytes memory payload, uint256 priorCount)
        public
    {
        if (selector == Counter.increment.selector || selector == COUNT_SELECTOR) {
            selector = bytes4(0xffffffff);
        }
        _seedCount(priorCount);
        _assertRejected(abi.encodePacked(selector, payload), 0, priorCount);
    }

    function test_EveryShortPrefixOfBothSelectorsReverts() public {
        counter.increment();
        bytes4[2] memory selectors = [Counter.increment.selector, COUNT_SELECTOR];
        for (uint256 i; i < selectors.length; ++i) {
            for (uint256 length; length < 4; ++length) {
                bytes memory prefix = new bytes(length);
                for (uint256 j; j < length; ++j) {
                    prefix[j] = selectors[i][j];
                }
                _assertRejected(prefix, 0, 1);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_OverflowRemainsTerminalAcrossCallers(address[4] memory callers) public {
        _seedCount(type(uint256).max - 1);
        counter.increment();
        for (uint256 i; i < callers.length; ++i) {
            vm.recordLogs();
            vm.prank(callers[i]);
            (bool success, bytes memory result) = address(counter).call(abi.encodeCall(Counter.increment, ()));
            assertFalse(success, "overflow must never wrap or silently succeed");
            assertEq(result, abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
            assertEq(counter.count(), type(uint256).max);
            assertEq(vm.getRecordedLogs().length, 0, "overflow must not emit");
        }
    }

    function _seedCount(uint256 value) internal {
        // The sole uint256 occupies slot zero. Only this test harness can seed it;
        // reaching the arithmetic boundary via real increments is impractical.
        vm.store(address(counter), bytes32(0), bytes32(value));
    }

    function _assertRejected(bytes memory data, uint256 value, uint256 expectedCount) internal {
        vm.deal(address(this), value);
        vm.recordLogs();
        (bool success,) = address(counter).call{value: value}(data);
        assertFalse(success, "unsupported call must revert");
        assertEq(counter.count(), expectedCount, "rejection must preserve existing count");
        assertEq(address(counter).balance, 0, "rejection must not retain funds");
        assertEq(address(this).balance, value, "rejection must refund the caller");
        assertEq(vm.getRecordedLogs().length, 0, "rejection must not emit");
    }
}
