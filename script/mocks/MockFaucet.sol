// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract MockFaucet {
    // State variables
    MockERC20 public token0;
    MockERC20 public token1;
    uint256 public token0Amount;
    uint256 public token1Amount;

    // Mapping to track the last withdrawal time for each address
    mapping(address => uint256) public lastCalled;

    // Events
    event TokensSent(address indexed user, uint256 amountToken0, uint256 amountToken1);

    // Constructor to set the token addresses
    constructor(MockERC20 _token0, MockERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
        token0Amount = 10 ** MockERC20(token0).decimals() / 1000;
        token1Amount = 100000 * 10 ** MockERC20(token1).decimals() / 1000;
    }

    // Function to send tokens to caller
    function faucet() external {
        require(block.timestamp >= lastCalled[msg.sender] + 1 days, "Can only use the faucet once per day");

        // Transfer tokens to the caller
        token0.mint(msg.sender, token0Amount);
        token1.mint(msg.sender, token1Amount);

        // Update the last called timestamp
        lastCalled[msg.sender] = block.timestamp;

        // Emit an event
        emit TokensSent(msg.sender, token0Amount, token1Amount);
    }
}
