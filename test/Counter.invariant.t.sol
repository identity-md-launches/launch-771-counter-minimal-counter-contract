// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Counter} from "../src/Counter.sol";

contract CounterHandler is Test {
    Counter public immutable counter;
    uint256 public successfulCalls;
    uint256 public observedEvents;

    constructor(Counter target) {
        counter = target;
    }

    function increment(address caller) external {
        _increment(caller);
    }

    function incrementFromReturningActor(uint256 actorSeed) external {
        // Small reusable pool exercises the same callers in different orders.
        _increment(address(uint160(0x10000 + bound(actorSeed, 0, 7))));
    }

    function _increment(address caller) internal {
        vm.recordLogs();
        vm.prank(caller);
        counter.increment();
        ++successfulCalls;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one event for every successful call");
        assertEq(logs[0].emitter, address(counter));
        assertEq(logs[0].topics.length, 2, "only caller is indexed");
        assertEq(logs[0].topics[0], keccak256("Incremented(address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(caller))));
        assertEq(logs[0].data, abi.encode(successfulCalls));
        observedEvents += logs.length;
    }

    function rejectedPayment(uint256 value, uint256 entryPoint) external {
        value = bound(value, 1, type(uint256).max);
        entryPoint = bound(entryPoint, 0, 2);
        bytes memory data;
        if (entryPoint == 0) data = abi.encodeCall(Counter.increment, ());
        else if (entryPoint == 1) data = abi.encodeWithSignature("count()");
        else data = new bytes(0);
        _assertRejected(data, value);
    }

    function rejectedUnknownSelector(bytes4 selector, bytes32 payload) external {
        if (selector == Counter.increment.selector || selector == bytes4(keccak256("count()"))) {
            selector = bytes4(0xffffffff);
        }
        _assertRejected(abi.encodePacked(selector, payload), 0);
    }

    function readCount(address caller) external {
        vm.recordLogs();
        vm.prank(caller);
        (bool success, bytes memory result) = address(counter).call(abi.encodeWithSignature("count()"));
        assertTrue(success);
        assertEq(result, abi.encode(successfulCalls));
        assertEq(counter.count(), successfulCalls);
        assertEq(vm.getRecordedLogs().length, 0, "reads must not emit");
    }

    function _assertRejected(bytes memory data, uint256 value) internal {
        vm.deal(address(this), value);
        vm.recordLogs();
        (bool success,) = address(counter).call{value: value}(data);
        assertFalse(success, "unsupported call must revert");
        assertEq(counter.count(), successfulCalls, "rejection must preserve count");
        assertEq(address(counter).balance, 0);
        assertEq(address(this).balance, value);
        assertEq(vm.getRecordedLogs().length, 0, "rejection must not emit");
    }
}

contract CounterInvariantTest is StdInvariant, Test {
    Counter internal counter;
    CounterHandler internal handler;

    function setUp() public {
        counter = new Counter();
        handler = new CounterHandler(counter);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = CounterHandler.increment.selector;
        selectors[1] = CounterHandler.rejectedPayment.selector;
        selectors[2] = CounterHandler.incrementFromReturningActor.selector;
        selectors[3] = CounterHandler.rejectedUnknownSelector.selector;
        selectors[4] = CounterHandler.readCount.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_CountEqualsSuccessfulCallsAndAcceptsNoPayments() public view {
        assertEq(counter.count(), handler.successfulCalls());
        assertEq(handler.observedEvents(), handler.successfulCalls());
        // Ordinary calls only: forced balance credits are covered separately.
        assertEq(address(counter).balance, 0);
    }
}
