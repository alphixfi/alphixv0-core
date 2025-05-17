// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockFaucet, MockERC20} from "../mocks/MockFaucet.sol";

contract MockFaucetScript is Script {
    /////////////////////////////////////
    // ---     .env Parameters     --- //
    /////////////////////////////////////

    // misc variables
    struct DeployData {
        string deploymentNetwork;
    }

    MockFaucet private faucet;
    address private token0Addr;
    MockERC20 private token0;
    address private token1Addr;
    MockERC20 private token1;

    function run() public {
        DeployData memory data;
        // get deployment network from .env
        data.deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(data.deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // get token0 address from .env
        envVar = string.concat("TOKEN0_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        token0Addr = vm.envAddress(envVar);
        token0 = MockERC20(token0Addr);

        // get token1 address from .env
        envVar = string.concat("TOKEN1_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        token1Addr = vm.envAddress(envVar);
        token1 = MockERC20(token1Addr);

        /// DEPLOYING FAUCET ///
        vm.broadcast();
        faucet = new MockFaucet(token0, token1);
        console.log("Faucet Address:", address(faucet));

        /// USING FAUCET ///
        vm.broadcast();
        faucet.faucet();
    }
}
