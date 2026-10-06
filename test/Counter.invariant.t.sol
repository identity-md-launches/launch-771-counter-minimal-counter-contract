// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Counter} from "../src/Counter.sol";

contract CounterHandler is Test {
    Counter public immutable counter;
    uint256 public successfulCalls;

    constructor(Counter target) {
        counter = target;
    }

    function increment(address caller) external {
        vm.prank(caller);
        counter.increment();
        ++successfulCalls;
    }

    function rejectedPayment() external {
        vm.deal(address(this), 1);
        (bool success,) = address(counter).call{value: 1}(abi.encodeCall(Counter.increment, ()));
        assertFalse(success);
        assertEq(address(this).balance, 1);
    }
}

contract CounterInvariantTest is StdInvariant, Test {
    Counter internal counter;
    CounterHandler internal handler;

    function setUp() public {
        counter = new Counter();
        handler = new CounterHandler(counter);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = CounterHandler.increment.selector;
        selectors[1] = CounterHandler.rejectedPayment.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_CountEqualsSuccessfulCallsAndAcceptsNoPayments() public view {
        assertEq(counter.count(), handler.successfulCalls());
        assertEq(address(counter).balance, 0);
    }
}
