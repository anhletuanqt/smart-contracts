// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract BoxV2 is UUPSUpgradeable {
    uint256 public val;

    function inc2() external {
        val += 10;
    }

    function getVal() external view returns (uint256) {
        return val;
    }

    function _authorizeUpgrade(address) internal override {}
}
