// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Counter} from "../src/Counter.sol";

contract CounterCaller {
    function increment(Counter counter) external {
        counter.increment();
    }
}

contract CounterTest is Test {
    Counter internal counter;

    event Incremented(address indexed caller, uint256 newCount);

    function setUp() public {
        counter = new Counter();
    }

    function test_InitialState() public view {
        assertEq(counter.count(), 0);
        assertEq(address(counter).balance, 0);
    }

    function test_RepeatedIncrements() public {
        counter.increment();
        assertEq(counter.count(), 1);
        counter.increment();
        assertEq(counter.count(), 2);
    }

    function test_EventHasExactTopicsDataAndEmitter() public {
        address caller = address(0xA11CE);
        vm.recordLogs();
        vm.startPrank(caller);
        counter.increment();
        counter.increment();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "one event per increment");
        for (uint256 i; i < logs.length; ++i) {
            assertEq(logs[i].emitter, address(counter));
            assertEq(logs[i].topics.length, 2, "only caller is indexed");
            assertEq(logs[i].topics[0], keccak256("Incremented(address,uint256)"));
            assertEq(logs[i].topics[1], bytes32(uint256(uint160(caller))));
            assertEq(logs[i].data, abi.encode(i + 1));
        }
    }

    function test_ManyDistinctAndReturningCallers() public {
        for (uint256 round; round < 2; ++round) {
            for (uint256 i; i < 64; ++i) {
                address caller = address(uint160(0x10000 + i));
                uint256 expected = round * 64 + i + 1;
                vm.expectEmit(true, false, false, true, address(counter));
                emit Incremented(caller, expected);
                vm.prank(caller);
                counter.increment();
                assertEq(counter.count(), expected);
            }
        }
        assertEq(address(counter).balance, 0);
    }

    function test_ContractCallerIsRecordedInsteadOfOrigin() public {
        CounterCaller caller = new CounterCaller();
        vm.expectEmit(true, false, false, true, address(counter));
        emit Incremented(address(caller), 1);
        vm.prank(address(0xA11CE), address(0xA11CE));
        caller.increment(counter);
        assertEq(counter.count(), 1);
    }

    function testFuzz_IncrementFromAnyNonMaxState(address caller, uint256 priorCount) public {
        vm.assume(priorCount < type(uint256).max);
        // Only a test can seed storage: the application exposes no setter.
        vm.store(address(counter), bytes32(0), bytes32(priorCount));
        vm.expectEmit(true, false, false, true, address(counter));
        emit Incremented(caller, priorCount + 1);
        vm.prank(caller);
        counter.increment();
        assertEq(counter.count(), priorCount + 1);
    }

    function testFuzz_InterleavedCallers(address[16] memory callers) public {
        for (uint256 i; i < 32; ++i) {
            // Repeat the same callers in reverse order on the second pass.
            address caller = callers[i < 16 ? i : 31 - i];
            vm.expectEmit(true, false, false, true, address(counter));
            emit Incremented(caller, i + 1);
            vm.prank(caller);
            counter.increment();
            assertEq(counter.count(), i + 1);
        }
    }

    function test_MaximumValueThenOverflowRevertsWithoutStateChangeOrEvent() public {
        vm.store(address(counter), bytes32(0), bytes32(type(uint256).max - 1));
        vm.expectEmit(true, false, false, true, address(counter));
        emit Incremented(address(this), type(uint256).max);
        counter.increment();
        assertEq(counter.count(), type(uint256).max);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
        counter.increment();
        assertEq(counter.count(), type(uint256).max);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_IncrementRejectsEther() public {
        _assertRejected(abi.encodeCall(Counter.increment, ()), 1);
        counter.increment();
        assertEq(counter.count(), 2, "a rejected payment must not block future calls");
    }

    function test_GetterRejectsEther() public {
        _assertRejected(abi.encodeWithSignature("count()"), 1);
    }

    function test_PlainEtherTransferReverts() public {
        _assertRejected("", 1);
    }

    function test_EmptyCalldataReverts() public {
        _assertRejected("", 0);
    }

    function test_TruncatedSelectorReverts() public {
        _assertRejected(hex"d09de0", 0);
    }

    function testFuzz_UnknownSelectorReverts(bytes4 selector) public {
        vm.assume(selector != Counter.increment.selector);
        vm.assume(selector != bytes4(keccak256("count()")));
        _assertRejected(abi.encodePacked(selector), 0);
    }

    function test_DeploymentRejectsEther() public {
        vm.deal(address(this), 1);
        bytes memory initCode = type(Counter).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(initCode, 32), mload(initCode))
        }
        assertEq(deployed, address(0), "nonpayable creation must fail");
        assertEq(address(this).balance, 1, "failed creation must not retain value");
    }

    function test_Create2DeploymentNeedsNoArgumentsOrInitialization() public {
        bytes32 salt = keccak256("counter-local-deployment-test");
        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(type(Counter).creationCode))
                    )
                )
            )
        );
        Counter deployed = new Counter{salt: salt}();
        assertEq(address(deployed), expected);
        assertEq(address(deployed).code, address(counter).code);
        assertEq(deployed.count(), 0);
        vm.prank(address(0xB0B));
        deployed.increment();
        assertEq(deployed.count(), 1);
    }

    function test_UnsolicitedBalanceDoesNotAffectCounting() public {
        // Model a balance credited without a call (e.g. a forced transfer).
        vm.deal(address(counter), 1);
        counter.increment();
        assertEq(counter.count(), 1);
        assertEq(address(counter).balance, 1);
    }

    function _assertRejected(bytes memory data, uint256 value) internal {
        counter.increment();
        vm.deal(address(this), value);
        vm.recordLogs();
        (bool success,) = address(counter).call{value: value}(data);
        assertFalse(success, "unsupported call must revert");
        assertEq(counter.count(), 1, "rejection must preserve existing state");
        assertEq(address(counter).balance, 0, "rejection must not retain value");
        assertEq(address(this).balance, value);
        assertEq(vm.getRecordedLogs().length, 0, "rejection must not emit");
    }
}
