// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./BridgeState.sol";

contract BridgeGetters is BridgeState {
    function evmChainId() public view returns (uint256) {
        return _state.evmChainId;
    }

    function outstandingBridged(address token) public view returns (uint256){
        return _state.outstandingBridged[token];
    }
}
