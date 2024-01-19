// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockLybra} from "../src/MockLybra.sol";
import {MockStETH} from "../src/MockStETH.sol";
import {MockV3Aggregator} from "../src/MockV3Aggregator.sol";
import {DeployMockStEth} from "./DeployMockStEth.s.sol";

contract DeployMockLybra is Script {
    MockStETH stEth;

    function run() external returns (MockLybra, MockStETH, MockV3Aggregator) {
        HelperConfig helperConfig = new HelperConfig();

        (address ethUsdPriceFeed, uint256 deployerKey) = helperConfig
            .activeNetworkConfig();


        DeployMockStEth deployer = new DeployMockStEth();
        stEth = deployer.run();

        vm.startBroadcast(deployerKey);
        MockLybra lybra = new MockLybra(address(stEth), ethUsdPriceFeed);
        vm.stopBroadcast();
        return (lybra, stEth, MockV3Aggregator(ethUsdPriceFeed));
    }
}
