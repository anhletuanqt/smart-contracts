// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./BridgeGetters.sol";
import "./BridgeSetters.sol";

contract BridgeUpgradeable is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    BridgeGetters,
    BridgeSetters,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using AddressUpgradeable for address;

    // Context of the request on originating chain
    struct RequestContext {
        bytes32 txhash;
        address from;
        uint256 fromChainID;
        uint256 nonce;
    }

    struct TransferResult {
        uint256 tokenChain;
        address tokenAddress;
        // Amount being transferred
        uint256 normalizedAmount;
        // Portion of msg.value to be paid as the core bridge fee
        uint256 wormholeFee;
    }

    event CashEvent(
        address user,
        uint256 fromChainId,
        address fromToken,
        uint256 fromAmount,
        address indexed recipient,
        uint256 toChainId,
        uint256 nonce
    );

    event WithdrawalFinalized(
        bytes32 indexed txhash,
        address indexed from,
        address indexed to,
        uint256 fromChainID,
        uint256 nonce,
        uint256 amount
    );

    event Withdraw(address token, address to, uint256 amount);

    address public multiSig;
    address constant NATIVE = address(0x0);

    mapping(bytes32 => bool) public execCompleted;
    uint256 nonce;

    modifier onlyMultiSig() {
        require(isMultiSig(msg.sender), "Caller is not multi-sig wallet");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function isMultiSig(address _account) public view returns (bool) {
        return multiSig == _account;
    }

    function initialize(address _multiSig, uint256 evmChainId)
        public
        initializer
    {
        __Pausable_init();
        __Ownable_init();
        multiSig = _multiSig;
        //        setWETH(WETH);

        setEvmChainId(evmChainId);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyMultiSig {
        _unpause();
    }

    function cashOut(address recipient, uint256 toChainId)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        TransferResult memory transferResult = _transferETH();
        logTransfer(
            transferResult.tokenChain,
            transferResult.tokenAddress,
            transferResult.normalizedAmount,
            toChainId,
            recipient,
            transferResult.wormholeFee
        );
    }

    function _transferETH()
        internal
        returns (TransferResult memory transferResult)
    {
        uint256 amount = msg.value;

        // track and check outstanding token amounts
        bridgeOut(NATIVE, amount);

        transferResult = TransferResult({
            tokenChain: evmChainId(),
            tokenAddress: NATIVE,
            normalizedAmount: amount,
            wormholeFee: 0
        });
    }

    /*
     *  @notice Send ERC20 token through portal.
     */
    function cashIn(
        uint256 amount,
        address token,
        address recipient,
        uint256 toChainId
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "You need to sell at least 1 token");
        TransferResult memory transferResult = _transferTokens(token, amount);
        logTransfer(
            transferResult.tokenChain,
            transferResult.tokenAddress,
            transferResult.normalizedAmount,
            toChainId,
            recipient,
            transferResult.wormholeFee
        );
    }

    /*
     *  @notice Initiate a transfer
     */
    function _transferTokens(address token, uint256 amount)
        internal
        returns (TransferResult memory transferResult)
    {
        require(token.isContract(), "NOT_CONTRACT");
        // determine token parameters
        uint256 tokenChain = evmChainId();

        // transfer tokens
        SafeERC20Upgradeable.safeTransferFrom(
            ERC20Upgradeable(token),
            msg.sender,
            address(this),
            amount
        );

        // track and check outstanding token amounts
        bridgeOut(token, amount);

        transferResult = TransferResult({
            tokenChain: tokenChain,
            tokenAddress: token,
            normalizedAmount: amount,
            wormholeFee: 0
        });
    }

    function logTransfer(
        uint256 fromChainId,
        address tokenAddress,
        uint256 amount,
        uint256 toChainId,
        address recipient,
        uint256 fee
    ) internal {
        require(fee <= amount, "fee exceeds amount");

        nonce++;
        emit CashEvent(
            msg.sender,
            fromChainId,
            tokenAddress,
            amount,
            recipient,
            toChainId,
            nonce
        );
    }

    function bridgeOut(address token, uint256 normalizedAmount) internal {
        uint256 outstanding = outstandingBridged(token);
        require(
            outstanding + normalizedAmount <= type(uint64).max,
            "transfer exceeds max outstanding bridged token amount"
        );
        setOutstandingBridged(token, outstanding + normalizedAmount);
    }

    /**
        @notice Execute a cross chain transfer
        @param ctx The context of the request on originating chain
    */
    function withdraw(
        address payable recipient,
        address token,
        uint256 amount,
        RequestContext memory ctx
    ) external whenNotPaused onlyOwner {
        address _from = ctx.from;

        bytes32 uniqueID = calcUniqueID(
            ctx.txhash,
            _from,
            ctx.fromChainID,
            ctx.nonce
        );
        require(!execCompleted[uniqueID], "exec completed");

        if (token == NATIVE) {
            recipient.transfer(amount);
        } else {
            ERC20Upgradeable(token).transfer(recipient, amount);
        }
        emit WithdrawalFinalized(
            ctx.txhash,
            _from,
            recipient,
            ctx.fromChainID,
            ctx.nonce,
            amount
        );

        execCompleted[uniqueID] = true;
    }

    function transfer(
        address payable recipient,
        address token,
        uint256 amount
    ) public onlyMultiSig {
        if (token == NATIVE) {
            payable(recipient).transfer(amount);
        } else {
            ERC20Upgradeable(token).transfer(recipient, amount);
        }
        emit Withdraw(token, recipient, amount);
    }

    // @notice Calculate unique ID
    function calcUniqueID(
        bytes32 _txhash,
        address _from,
        uint256 _fromChainID,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_txhash, _from, _fromChainID, _nonce));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}
}
