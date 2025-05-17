// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {AlphixV0} from "../../src/AlphixV0.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/// @notice Mines the address and deploys the AlphixV0.sol Hook contract
contract AlphixV0Script is Script {
    // misc variables
    struct DeployData {
        string deploymentNetwork;
    }

    // params passed as arguments for tests or read in .env otherwise
    address private poolManagerAddr;
    address private create2DeployerAddr;
    address private alphixManager;

    function run() public {
        DeployData memory data;

        data.deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(data.deploymentNetwork).length == 0) {
            revert("DEPLOYMENT_NETWORK is not set in .env file");
        }

        string memory envVar;

        // get pool manager address from .env
        envVar = string.concat("POOL_MANAGER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        poolManagerAddr = vm.envAddress(envVar);

        // get create2 deployer from .env
        envVar = string.concat("CREATE2_DEPLOYER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        create2DeployerAddr = vm.envAddress(envVar);

        // get alphixManager from .env
        envVar = string.concat("ALPHIX_MANAGER_", data.deploymentNetwork);
        if (bytes(vm.envString(envVar)).length == 0) {
            revert(string.concat(envVar, " is not set in .env file"));
        }
        alphixManager = vm.envAddress(envVar);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        IPoolManager poolManager = IPoolManager(poolManagerAddr);
        bytes memory constructorArgs = abi.encode(poolManager, alphixManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(create2DeployerAddr, flags, type(AlphixV0).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        AlphixV0 alphixV0 = new AlphixV0{salt: salt}(poolManager, alphixManager);
        require(address(alphixV0) == hookAddress, "PersoAlphixV0Script: hook address mismatch");
        console.log("AlphixV0 deployed at:", address(alphixV0));
    }
}
