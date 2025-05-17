// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

contract RouterSwapScript is Script {
    using FullMath for uint256;
    /////////////////////////////////////
    // ---     .env Parameters     --- //
    /////////////////////////////////////

    // misc variables
    struct DeployData {
        string deploymentNetwork;
        uint256 TOKEN0_UNIT;
        uint256 TOKEN1_UNIT;
        int256 amountSpecified;
        uint256 valueToPass;
    }

    Currency private currency0;
    Currency private currency1;
    address private posmAddr;
    PositionManager private posm;
    address private swapRouterAddr;
    PoolSwapTest swapRouter;
    address private poolManagerAddr;

    // slippage tolerance to allow for unlimited price impact
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;
    // PERMIT2 address found in v3 docs (https://docs.uniswap.org/contracts/v3/reference/deployments/ethereum-deployments)
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    function run() external {
        DeployData memory data;

        data.deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(data.deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // get posm address from .env
        envVar = string.concat("POSITION_MANAGER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        posmAddr = vm.envAddress(envVar);
        posm = PositionManager(payable(posmAddr));

        // bytes25 of the poolId of the pool that we previously initialized
        bytes25 poolId = 0xbcc20db9b797e211e508500469e553111c6fa8d80f7896e6db;

        uint24 fee;
        int24 tickSpacing;
        IHooks hooks;
        // Access the PoolKey and other components using the function call
        (currency0, currency1, fee, tickSpacing, hooks) = posm.poolKeys(poolId);

        // Create the PoolKey from the returned values
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
        
        // CAREFUL WITH DECIMALS!!
        if(currency0.isAddressZero()) {
            data.TOKEN0_UNIT = 10 ** 18;
        } else {
            data.TOKEN0_UNIT = 10 ** IERC20(Currency.unwrap(currency0)).decimals();
        }
        
        if(currency1.isAddressZero()) {
            data.TOKEN1_UNIT = 10 ** 18;
        } else {
            data.TOKEN1_UNIT = 10 ** IERC20(Currency.unwrap(currency1)).decimals();
        }

        // swap token 0 (ETH) for token 1 (USDC)
        bool zeroForOne = true;
        if(zeroForOne) {
            data.amountSpecified = -int256(data.TOKEN0_UNIT / 1000); // 1/1000 of what we LPed
        } else {
            data.amountSpecified = -int256(100_000 * data.TOKEN1_UNIT / 1000); // 1/1000 of what we LPed
        }

        // get pool swap test router address from .env
        envVar = string.concat("POOL_SWAP_TEST_ROUTER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        swapRouterAddr = vm.envAddress(envVar);
        swapRouter = PoolSwapTest(swapRouterAddr);

        // get pool manager address from .env
        envVar = string.concat("POOL_MANAGER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        poolManagerAddr = vm.envAddress(envVar);

        // approve token to the swap router
        vm.startBroadcast();
        if(zeroForOne) {
            if(!currency0.isAddressZero()) {
                IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), stdMath.abs(data.amountSpecified));
            }
        } else {
            IERC20(Currency.unwrap(currency1)).approve(address(swapRouter), stdMath.abs(data.amountSpecified));
        }
        vm.stopBroadcast();

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: data.amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
        });

        // Execute the swap
        // in v4, users have the option to receieve native ERC20s or wrapped ERC1155 tokens
        // here, we'll take the ERC20s
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
    
        // if the pool is an ETH pair, native tokens are to be transferred
        data.valueToPass = currency0.isAddressZero() ? stdMath.abs(data.amountSpecified) : 0;

        bytes memory hookData = new bytes(0);
        vm.broadcast();
        swapRouter.swap{value: data.valueToPass}(poolKey, params, testSettings, hookData);
    }

    function tokenApproval(Currency currency, uint256 amount, address spender) public {
        if (!currency.isAddressZero()) {
            IERC20(Currency.unwrap(currency)).approve(address(PERMIT2), amount);
            PERMIT2.approve(Currency.unwrap(currency), spender, type(uint160).max, type(uint48).max);
        }
    }
}
