// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract AlphixV0 is BaseHook {
    // State variables
    mapping(PoolId => uint24) public dynamicFees; // Store dynamic fees for each pool
    mapping(PoolId => uint256) public lastFeeUpdate; // Store last update timestamp for each pool

    // Variables
    /** @dev Address of this hook's manager */
    address private alphixManager;

    // Constants
    uint24 public constant MIN_FEE = 100; // 0.01%
    uint24 public constant MAX_FEE = 10_000; // 1%
    uint256 public constant MIN_PERIOD = 1 days;

    // Events
    event FeeUpdated(PoolId indexed poolId, uint24 newFee);

    // Errors

    error InvalidCaller();

    // Constructor
    constructor(IPoolManager _poolManager, address _alphixManager) BaseHook(_poolManager) {
        alphixManager = _alphixManager;
    }

    modifier onlyAlphixManager() {
        if(msg.sender != alphixManager) {
            revert InvalidCaller();
        }
        _;
    }

    // Modifiers
    modifier onlyAfterCooldown(PoolId poolId) {
        require(block.timestamp >= lastFeeUpdate[poolId] + MIN_PERIOD, "Cooldown period not met");
        _;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Hook Methods
    function _afterInitialize(address, PoolKey calldata key, uint160, int24)
        internal
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        // Update the dynamic fee
        uint24 newFee = 2_000; // 0.2%
        dynamicFees[poolId] = newFee;
        lastFeeUpdate[poolId] = block.timestamp;
        poolManager.updateDynamicLPFee(key, newFee);
        emit FeeUpdated(poolId, newFee);
        return BaseHook.afterInitialize.selector;
    }

    function setDynamicFee(PoolKey calldata key, uint24 newFee) external onlyAfterCooldown(key.toId()) {
        require(newFee >= MIN_FEE && newFee <= MAX_FEE, "Fee out of bounds");
        _setDynamicFee(key, newFee);
    }

    function setDynamicFeeAdminVersion(PoolKey calldata key, uint24 newFee) external onlyAlphixManager {
        _setDynamicFee(key, newFee);
    }

    function _setDynamicFee(PoolKey calldata key, uint24 newFee) internal {
        PoolId poolId = key.toId();
        // Update the dynamic fee
        dynamicFees[poolId] = newFee;
        lastFeeUpdate[poolId] = block.timestamp;

        // Call the pool manager to update the fee
        poolManager.updateDynamicLPFee(key, newFee);
        emit FeeUpdated(poolId, newFee);
    }

    function getDynamicFee(PoolKey calldata key) external view returns (uint24) {
        return dynamicFees[key.toId()];
    }
}
