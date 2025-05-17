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
import {AlphixV0} from "../../src/AlphixV0.sol";

contract DynamicFeeScript is Script {
    using FullMath for uint256;
    /////////////////////////////////////
    // ---     .env Parameters     --- //
    /////////////////////////////////////

    // misc variables
    struct DeployData {
        string deploymentNetwork;
    }

    Currency private currency0;
    Currency private currency1;
    address private posmAddr;
    PositionManager private posm;

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

        AlphixV0 hook = AlphixV0(address(hooks));

        uint24 oldFee = hook.getDynamicFee(poolKey);
        console.log("fee before change:", oldFee);

        uint24 newFee = oldFee * 2;
        vm.broadcast(msg.sender);
        hook.setDynamicFeeAdminVersion(poolKey, newFee);
        console.log("fee after change:", hook.getDynamicFee(poolKey));
    }
}
