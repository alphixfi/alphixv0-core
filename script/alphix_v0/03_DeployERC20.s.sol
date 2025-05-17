// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeployERC20Script is Script {
    /////////////////////////////////////
    // ---     .env Parameters     --- //
    /////////////////////////////////////

    // misc variables
    struct DeployData {
        string deploymentNetwork;
    }

    address private token0Addr;
    address private token1Addr;
    uint8 private decimals0;
    uint8 private decimals1;
    MockERC20 private token0;
    MockERC20 private token1;
    address private deployer;
    address private satoshui;

    function run() public {
        DeployData memory data;
        // get deployment network from .env
        data.deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(data.deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // get deployer address from .env
        envVar = string.concat("DEPLOYER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        deployer = vm.envAddress(envVar);

        // get deployer address from .env
        envVar = string.concat("SATOSHUI_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        satoshui = vm.envAddress(envVar);


        // get token0 decimals from .env
        envVar = string.concat("TOKEN0_DECIMALS_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        decimals0 = uint8(vm.envUint(envVar));

        // get token1 decimals from .env
        envVar = string.concat("TOKEN1_DECIMALS_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        decimals1 = uint8(vm.envUint(envVar));

        if (decimals0 < 6 || decimals1 < 6) {
            revert("Decimals cannot be zero");
        }
        if (decimals0 > 18 || decimals1 > 18) {
            revert("Decimals cannot be greater than 18");
        }

        vm.startBroadcast();
        token0 = new MockERC20("BITCARL", "BTCRL", decimals0);
        token1 = new MockERC20("YANUSDC", "YUSDC", decimals1);
        token0.mint(deployer, 10 * 10**decimals0);
        token1.mint(deployer, 1_000_000 * 10**decimals1);
        token0.mint(satoshui, 10 * 10**decimals0);
        token1.mint(satoshui, 1_000_000 * 10**decimals1);
        token0Addr = address(token0);
        token1Addr = address(token1);
        console.log("Token0 Address: ", token0Addr);
        console.log("Token1 Address: ", token1Addr);
        vm.stopBroadcast();
    }
}
