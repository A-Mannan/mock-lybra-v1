// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MockStETH} from "../src/MockStETH.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMockStEth is Script {
    function run() public returns (MockStETH) {
        HelperConfig helperConfig = new HelperConfig();

        (, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        MockStETH mockStEth = new MockStETH();
        vm.stopBroadcast();
        return mockStEth;
    }
}
