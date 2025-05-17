// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {TickBitmap} from "v4-core/src/libraries/TickBitmap.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

contract CreatePoolAndMintLiquidityScript is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using FullMath for uint256;

    /////////////////////////////////////
    // ---     .env Parameters     --- //
    /////////////////////////////////////

    // misc variables
    struct DeployData {
        string deploymentNetwork;
        uint256 TOKEN0_UNIT;
        uint256 TOKEN1_UNIT;
        int24 compressed;
        uint256 tokenAmountMultiplier;
        uint128 liquidity;
        uint256 amount0Max;
        uint256 amount1Max;
        uint256 valueToPass;
    }

    // params passed as arguments for tests or read in .env otherwise
    address private hookAddr;
    address private token0Addr;
    address private token1Addr;
    Currency private currency0;
    Currency private currency1;
    address private deployer;
    address private posmAddr;
    IHooks private hook;
    PositionManager private posm;

    // PERMIT2 address found in v3 docs (https://docs.uniswap.org/contracts/v3/reference/deployments/ethereum-deployments)
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));


    /////////////////////////////////////
    // --- Parameters to Configure --- //
    /////////////////////////////////////

    // --- pool configuration --- //
    // fees paid by swappers that accrue to liquidity providers
    uint24 lpFee;
    // tick spacing of the pool (LP granularity)
    int24 tickSpacing;

    // starting price of the pool, in sqrtPriceX96 (sqrtPriceX96 = floor(sqrt(token1/token0) * 2**96), with decimals taken into account)
    uint160 startingPrice1;
    uint160 startingPrice2;

    // --- liquidity position configuration --- //
    // CAREFUL WITH DECIMALS!! 
    uint256 public token0Amount;
    uint256 public token1Amount;

    // range of the position
    // for price 1 then tick 0 makes sense
    // for price 1e18/1500e6 the current tick is approx 203188
    int24 currentTick;
    int24 tickLower;
    int24 tickUpper;

    /////////////////////////////////////

    function run() external {
        DeployData memory data;

        data.deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(data.deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // get hook address from .env
        envVar = string.concat("HOOK_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        hookAddr = vm.envAddress(envVar);
        hook = IHooks(hookAddr);

        // get token0 address from .env
        envVar = string.concat("TOKEN0_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        token0Addr = vm.envAddress(envVar);

        // get token1 address from .env
        envVar = string.concat("TOKEN1_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        token1Addr = vm.envAddress(envVar);

        // --- pool parameter configuration --- //
        lpFee = LPFeeLibrary.DYNAMIC_FEE_FLAG; // = 8388608 (more than max), 3000 would be 0.30%
        tickSpacing = 60; // CLMM param defining LP granularity (the smaller the more granular)

        // CAREFUL WITH DECIMALS!!
        if(token0Addr == address(0)) {
            data.TOKEN0_UNIT = 10 ** 18;
        } else {
            data.TOKEN0_UNIT = 10 ** IERC20(token0Addr).decimals();
        }
        
        if(token1Addr == address(0)) {
            data.TOKEN1_UNIT = 10 ** 18;
        } else {
            data.TOKEN1_UNIT = 10 ** IERC20(token1Addr).decimals();
        }

        // floor(sqrt(token1/token0) * 2**96)
        startingPrice2 = 2505414483750479311864138015696; // price such that 1e8 token 0 (BTC decimals 8) per 100000e6 token 1 (USDC decimals 6)

        // Token amounts
        data.tokenAmountMultiplier = 100_000;
        token0Amount = data.tokenAmountMultiplier * data.TOKEN0_UNIT.mulDiv(1, 100000); // e.g. mulDiv(1, 100000) if price is 1BTC/100000USDC
        token1Amount = data.tokenAmountMultiplier * data.TOKEN1_UNIT;

        // range of the position
        // sqrtPriceX96 = 1.0001 ^ tickNb
        // for curPrice = 1, then curTick = 0 
        // for price 1e18/1500e6 the current tick is ~ 203188
        // tick bounds must be multiples of tick spacing !
        currentTick = TickMath.getTickAtSqrtPrice(startingPrice2);
        data.compressed = TickBitmap.compress(currentTick, tickSpacing);
        tickLower = (data.compressed - 100) * tickSpacing;
        tickUpper = (data.compressed + 100) * tickSpacing;

        currency0 = Currency.wrap(token0Addr);
        currency1 = Currency.wrap(token1Addr);

        // get deployer address from .env
        envVar = string.concat("DEPLOYER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        deployer = vm.envAddress(envVar);

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hook
        });

        PoolId poolId = pool.toId();
        bytes32 poolIdBytes = PoolId.unwrap(poolId);
        string memory poolIdString = toHex(poolIdBytes);
        console.log("Pool deployed ID:", poolIdString);

        bytes memory hookData = new bytes(0);

        // --------------------------------- //

        // Converts token amounts to liquidity units
        data.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice2,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        // slippage limits
        data.amount0Max = token0Amount + 1 wei;
        data.amount1Max = token1Amount + 1 wei;

        bytes memory actions;
        bytes[] memory mintParams;
        if(currency0.isAddressZero()) {
            (actions, mintParams) =
                _mintLiquidityParamsWithSweep(pool, tickLower, tickUpper, data.liquidity, data.amount0Max, data.amount1Max, deployer, hookData);
        } else {
            (actions, mintParams) =
                _mintLiquidityParams(pool, tickLower, tickUpper, data.liquidity, data.amount0Max, data.amount1Max, deployer, hookData);
        }

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // get posm address from .env
        envVar = string.concat("POSITION_MANAGER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        posmAddr = vm.envAddress(envVar);
        posm = PositionManager(payable(posmAddr));

        // initialize pool
        params[0] = abi.encodeWithSelector(posm.initializePool.selector, pool, startingPrice2, hookData);

        // mint liquidity
        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );

        // if the pool is an ETH pair, native tokens are to be transferred
        data.valueToPass = currency0.isAddressZero() ? data.amount0Max : 0;

        vm.startBroadcast();
        tokenApprovals();
        vm.stopBroadcast();

        // multicall to atomically create pool & add liquidity
        vm.broadcast();
        posm.multicall{value: data.valueToPass}(params);
    }

    /// @dev helper function for encoding mint liquidity operation
    /// @dev does NOT encode SWEEP, developers should take care when minting liquidity on an ETH pair
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }

    /// @dev helper function for encoding mint liquidity operation with SWEEP for ETH pairs
    function _mintLiquidityParamsWithSweep(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        // Add SWEEP action to recover any unused ETH
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(Currency.wrap(address(0)), recipient); // Sweep unused ETH back to recipient

        return (actions, params);
    }

    function tokenApprovals() public {
        if (!currency0.isAddressZero()) {
            IERC20(token0Addr).approve(address(PERMIT2), type(uint256).max);
            PERMIT2.approve(token0Addr, address(posm), type(uint160).max, type(uint48).max);
        }
        if (!currency1.isAddressZero()) {
            IERC20(token1Addr).approve(address(PERMIT2), type(uint256).max);
            PERMIT2.approve(token1Addr, address(posm), type(uint160).max, type(uint48).max);
        }
    }

    // Function to convert bytes32 to hex string
    function toHex(bytes32 data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(64);
        
        for (uint256 i = 0; i < 32; i++) {
            result[i * 2] = hexChars[uint8(data[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        
        return string(result);
    }
}
