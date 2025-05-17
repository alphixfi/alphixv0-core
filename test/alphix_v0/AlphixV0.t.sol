// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {AlphixV0} from "../../src/AlphixV0.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "../utils/EasyPosm.sol";
import {Fixtures} from "../utils/Fixtures.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract AlphixV0Test is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    AlphixV0 hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address alphixManager;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_INITIALIZE_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        alphixManager = makeAddr("alphixManager");
        bytes memory constructorArgs = abi.encode(manager, alphixManager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("AlphixV0.sol:AlphixV0", constructorArgs, flags);
        hook = AlphixV0(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 1_000e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testInitialDynamicFee() public view {
        uint24 expectedFee = 2000; // 0.2%
        assertEq(hook.getDynamicFee(key), expectedFee);
    }

    function testSetDynamicFee() public {
        // Fast forward time to meet cooldown
        vm.warp(block.timestamp + 1 days);
        uint24 newFee = 3000; // 0.3%
        hook.setDynamicFee(key, newFee);
        assertEq(hook.getDynamicFee(key), newFee);
    }

    function testSetDynamicFeeOutOfBounds() public {
        // Fast forward time to meet cooldown
        vm.warp(block.timestamp + 1 days);
        uint24 outOfBoundsFee = 11000; // Exceeds max fee
        vm.expectRevert("Fee out of bounds");
        hook.setDynamicFee(key, outOfBoundsFee);
    }

    function testSetDynamicFeeCooldown() public {
        // Attempt to set fee again before cooldown
        vm.expectRevert("Cooldown period not met");
        uint24 newFee = 4000; // 0.4%
        hook.setDynamicFee(key, newFee);

        // Fast forward time to meet cooldown
        vm.warp(block.timestamp + 1 days);

        // Now it should succeed
        hook.setDynamicFee(key, newFee); // 0.4%
        assertEq(hook.getDynamicFee(key), newFee);
    }

    function testSetDynamicFeeAdmin() public {
        uint24 newFee = 5000; // 0.5%
        vm.prank(alphixManager); // Simulate admin calling the function
        hook.setDynamicFeeAdminVersion(key, newFee);
        assertEq(hook.getDynamicFee(key), newFee);
    }

    function testSwapFeeApplication() public {
        // Set up a swap scenario
        uint24 expectedFee = hook.getDynamicFee(key);
        assertEq(expectedFee, 2000, "Initial fee should be 0.2%");
        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e16; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified, "Swap Amount 0 is wrong");
        assertTrue(int256(swapDelta.amount1()) < 1e16 && int256(swapDelta.amount1()) > 9e15, "Swap Amount 1 is wrong");

        address feeReceiver = makeAddr("feeReceiver");

        uint256 balTok0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(feeReceiver);
        uint256 balTok1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(feeReceiver);

        BalanceDelta collect = posm.collect(tokenId, MAX_SLIPPAGE_REMOVE_LIQUIDITY, MAX_SLIPPAGE_REMOVE_LIQUIDITY, feeReceiver, block.timestamp + 1, ZERO_BYTES);

        uint256 balTok0After = MockERC20(Currency.unwrap(currency0)).balanceOf(feeReceiver);
        uint256 balTok1After = MockERC20(Currency.unwrap(currency1)).balanceOf(feeReceiver);

        assertEq(balTok0After, balTok0Before + uint256(int256(collect.amount0())), "fee collected tok 0 wrong");
        assertEq(balTok1After, balTok1Before + uint256(int256(collect.amount1())), "fee collected tok 1 wrong");
        assertApproxEqRel(balTok0After, balTok0Before + 1e16 * uint256(expectedFee) / 1e6, 1e10, "fee collected tok 0 different than expected");
    }
}
