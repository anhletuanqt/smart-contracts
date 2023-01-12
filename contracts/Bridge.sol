pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Bridge {
    event CompleleteTransferred(
        uint256 fromChainId,
        address to,
        uint256 toChainId,
        uint256 amount,
        address tokenAddress,
        uint256 expiredAt
    );

    event BridgeTransferred(
        address from,
        uint256 fromChainId,
        address to,
        uint256 toChainId,
        uint256 amount,
        address tokenAddress,
        bool isNativeCoin
    );

    function depositETH(
        uint256 fromChainId,
        address to,
        uint256 toChainId,
        uint256 amount
    ) external payable {
        emit BridgeTransferred(
            msg.sender,
            fromChainId,
            to,
            toChainId,
            amount,
            address(0),
            true
        );
    }

    function depositTokens(
        uint256 fromChainId,
        address to,
        uint256 toChainId,
        uint256 amount,
        address tokenAddress
    ) external {
        emit BridgeTransferred(
            msg.sender,
            fromChainId,
            to,
            toChainId,
            amount,
            tokenAddress,
            false
        );
    }

    function completeTransfer(
        uint256 fromChainId,
        address to,
        uint256 toChainId,
        uint256 amount,
        address tokenAddress,
        uint256 expiredAt
    ) external {
        emit CompleleteTransferred(
            fromChainId,
            to,
            toChainId,
            amount,
            tokenAddress,
            expiredAt
        );
    }
}
