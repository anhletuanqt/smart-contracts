// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract BridgeUpgradeable is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;

    enum Status {
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    struct Order {
        address user;
        uint64 txIndex;
        uint64 fromChainId;
        uint64 toChainId;
        address fromToken;
        uint256 fromAmount;
        address recipient;
        address toToken;
        uint256 toAmount;
        uint256 exchangeRate;
        uint256 createdAt;
        string depositTxHash;
        string withdrawTxHash;
        string refundTxHash;
        Status status;
    }

    event CashEvent(
        address user,
        uint256 txIndex,
        uint256 fromChainId,
        address fromToken,
        uint256 fromAmount,
        address recipient,
        uint256 toChainId,
        address toToken
    );

    string constant NULL_TX = "0x0";
    uint256 constant NULL_AMOUNT = 0;
    address constant NATIVE = address(0x0);
    mapping(address => Order[]) booking;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Pausable_init();
        __Ownable_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function cashOut(
        address recipient,
        uint64 toChainId,
        address toToken
    ) external payable nonReentrant whenNotPaused {
        address user = msg.sender;
        uint64 txIndex = uint64(booking[user].length);
        uint256 fromAmount = msg.value;
        uint64 fromChainId;

        assembly {
            fromChainId := chainid()
        }

        booking[user].push(
            Order(
                user,
                txIndex,
                fromChainId,
                toChainId,
                NATIVE,
                fromAmount,
                recipient,
                toToken,
                NULL_AMOUNT, //toAmount
                NULL_AMOUNT, //exchangeRate
                block.timestamp, //createdAt
                NULL_TX, // depositTxHash
                NULL_TX, // withdrawTxHash
                NULL_TX, // refundTxHash
                Status.SUBMITTED
            )
        );

        emit CashEvent(
            user,
            txIndex,
            fromChainId,
            NATIVE,
            fromAmount,
            recipient,
            toChainId,
            toToken
        );
    }

    function cashIn(
        uint256 fromAmount,
        address fromToken,
        address recipient,
        uint64 toChainId
    ) external nonReentrant whenNotPaused {
        require(fromAmount > 0, "You need to sell at least 1 token");

        address user = msg.sender;
        ERC20Upgradeable(fromToken).transferFrom(
            user,
            address(this),
            fromAmount
        );

        uint64 txIndex = uint64(booking[user].length);
        uint64 fromChainId;

        assembly {
            fromChainId := chainid()
        }

        booking[user].push(
            Order(
                user,
                txIndex,
                fromChainId,
                toChainId,
                fromToken,
                fromAmount,
                recipient,
                NATIVE,
                NULL_AMOUNT, // toAmount
                NULL_AMOUNT, // exchangeRate
                block.timestamp, // createdAt
                NULL_TX, // depositTxHash
                NULL_TX, // withdrawTxHash
                NULL_TX, // refundTxHash
                Status.SUBMITTED
            )
        );

        emit CashEvent(
            user,
            txIndex,
            fromChainId,
            fromToken,
            fromAmount,
            recipient,
            toChainId,
            NATIVE
        );
    }

    function listUserOrders(address user) public view returns (Order[] memory) {
        return booking[user];
    }

    function readUserOrder(address user, uint256 txIndex)
        public
        view
        returns (Order memory)
    {
        return booking[user][txIndex];
    }

    function completeOrder(
        address user,
        uint256 txIndex,
        uint256 toAmount,
        uint256 exchangeRate,
        string memory depositTxHash,
        string memory withdrawTxHash
    ) external payable onlyOwner {
        booking[user][txIndex].toAmount = toAmount;
        booking[user][txIndex].exchangeRate = exchangeRate;
        booking[user][txIndex].depositTxHash = depositTxHash;
        booking[user][txIndex].withdrawTxHash = withdrawTxHash;
        booking[user][txIndex].status = Status.COMPLETED;
    }

    function cancelOrder(
        address user,
        uint256 txIndex,
        uint256 toAmount,
        uint256 exchangeRate,
        string memory depositTxHash,
        string memory refundTxHash
    ) external payable onlyOwner {
        booking[user][txIndex].toAmount = toAmount;
        booking[user][txIndex].exchangeRate = exchangeRate;
        booking[user][txIndex].depositTxHash = depositTxHash;
        booking[user][txIndex].refundTxHash = refundTxHash;
        booking[user][txIndex].status = Status.CANCELLED;
    }

    function transfer(
        address payable recipient,
        address token,
        uint256 amount
    ) public {
        if (token == NATIVE) {
            payable(recipient).transfer(amount);
        } else {
            ERC20Upgradeable(token).transfer(recipient, amount);
        }
    }
}
