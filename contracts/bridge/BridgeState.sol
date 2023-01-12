// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract BridgeState {
    BridgeStorage.State _state;
}

contract BridgeStorage {
    struct State {
        // Mapping of consumed token transfers
        mapping(bytes32 => bool) completedTransfers;

        // Mapping of native assets to amount outstanding on other chains
        mapping(address => uint256) outstandingBridged;

        // EIP-155 Chain ID
        uint256 evmChainId;
    }
}
