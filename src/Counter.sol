// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice A permissionless counter with no administrative powers or payments.
contract Counter {
    /// @notice The number of successful increments, initially zero.
    uint256 public count;

    /// @notice Emitted once for each successful increment.
    event Incremented(address indexed caller, uint256 newCount);

    /// @notice Add one to the count. Reverts on uint256 overflow.
    function increment() external {
        count += 1;
        emit Incremented(msg.sender, count);
    }
}
