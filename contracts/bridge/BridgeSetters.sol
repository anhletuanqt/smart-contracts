// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./BridgeState.sol";

contract BridgeSetters is BridgeState {
    function setOutstandingBridged(address token, uint256 outstanding) internal {
        _state.outstandingBridged[token] = outstanding;
    }

    function setEvmChainId(uint256 evmChainId) internal {
        require(evmChainId == block.chainid, "invalid evmChainId");
        _state.evmChainId = evmChainId;
    }
}
