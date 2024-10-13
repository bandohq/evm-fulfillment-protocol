// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import { ScriptBase } from "./ScriptBase.sol";
import { CREATE3UUPSProxy } from "create3-proxy/CREATE3UUPSProxy.sol";

contract DeployUUPSScriptBase is ScriptBase {
    address internal predicted;
    bytes32 internal salt;

    constructor(string memory contractName) {
        string memory saltPrefix = vm.envString("DEPLOYSALT");
        salt = keccak256(abi.encodePacked(saltPrefix, contractName));
    }

    function getInitializerArgs() internal virtual returns (bytes memory) {}

    function deploy(
        bytes memory creationCode,
        bytes memory initializerSelector
    ) internal virtual returns (address payable deployed) {
        bytes memory initArgs = getInitializerArgs();
        bytes memory initializerCode = bytes.concat(initializerSelector, initArgs);
        vm.startBroadcast(deployerPrivateKey);

        deployed = payable(
            CREATE3UUPSProxy.deploy(
                salt,
                creationCode,
                initializerCode
            )
        );

        vm.stopBroadcast();
    }

    function isContract(address _contractAddr) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(_contractAddr)
        }
        return size > 0;
    }

    function isDeployed() internal view returns (bool) {
        return isContract(predicted);
    }
}
