// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {TellerWithMultiAssetSupport, ERC20} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {MessageLib} from "src/base/Roles/CrossChain/MessageLib.sol";

abstract contract CrossChainTellerWithGenericBridge is TellerWithMultiAssetSupport {
    using MessageLib for uint256;
    using MessageLib for MessageLib.Message;

    //============================== ERRORS ===============================

    error CrossChainTellerWithGenericBridge__UnsafeCastToUint96();

    //============================== EVENTS ===============================

    event MessageSent(bytes32 indexed messageId, uint256 shareAmount, address indexed to);
    event MessageReceived(bytes32 indexed messageId, uint256 shareAmount, address indexed to);

    //============================== IMMUTABLES ===============================

    constructor(address _owner, address _vault, address _accountant, address _weth)
        TellerWithMultiAssetSupport(_owner, _vault, _accountant, _weth)
    {}

    // ========================================= PUBLIC FUNCTIONS =========================================

    /**
     * @notice Deposit an asset and bridge the shares to another chain.
     * @dev This function will REVERT if `beforeTransfer` hook reverts from:
     *     - shares being locked
     *     - allow list
     * @dev Since call to `bridge` is public, msg.sig is not updated which means any role capabilities regarding this function
     *      are also granted to the `bridge` function.
     */
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata bridgeWildCard,
        ERC20 feeToken,
        uint256 maxFee
    )
        external
        payable
        requiresAuth
        nonReentrant
        revertOnNativeDeposit(address(depositAsset))
        returns (uint256 sharesBridged)
    {
        // Deposit
        Asset memory asset = _beforeDeposit(depositAsset);
        sharesBridged = _erc20Deposit(depositAsset, depositAmount, minimumMint, msg.sender, msg.sender, asset);
        _afterPublicDeposit(msg.sender, depositAsset, depositAmount, sharesBridged, shareLockPeriod);

        // Bridge shares
        if (sharesBridged > type(uint96).max) revert CrossChainTellerWithGenericBridge__UnsafeCastToUint96();
        _bridge(uint96(sharesBridged), to, bridgeWildCard, feeToken, maxFee);
    }

    /**
     * @notice Deposit an asset and bridge the shares to another chain using a permit.
     * @dev This function will REVERT if `beforeTransfer` hook reverts from:
     *     - shares being locked
     *     - allow list
     * @dev Since calls to `depositWithPermit` and `bridge` are public, msg.sig is not updated which means any role capabilities regarding this function
     *      are also granted to the `depositWithPermit` and `bridge` function.
     */
    function depositAndBridgeWithPermit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address to,
        bytes calldata bridgeWildCard,
        ERC20 feeToken,
        uint256 maxFee
    )
        external
        payable
        requiresAuth
        nonReentrant
        revertOnNativeDeposit(address(depositAsset))
        returns (uint256 sharesBridged)
    {
        // Permit deposit
        {
            Asset memory asset = _beforeDeposit(depositAsset);
            _handlePermit(depositAsset, depositAmount, deadline, v, r, s);
            sharesBridged = _erc20Deposit(depositAsset, depositAmount, minimumMint, msg.sender, msg.sender, asset);
        }
        _afterPublicDeposit(msg.sender, depositAsset, depositAmount, sharesBridged, shareLockPeriod);

        // Bridge shares
        if (sharesBridged > type(uint96).max) revert CrossChainTellerWithGenericBridge__UnsafeCastToUint96();
        _bridge(uint96(sharesBridged), to, bridgeWildCard, feeToken, maxFee);
    }

    /**
     * @notice Bridge shares to another chain.
     * @param shareAmount The amount of shares to bridge.
     * @param to The address to send the shares to on the other chain.
     * @param bridgeWildCard The bridge specific data to configure message.
     * @param feeToken The token to pay the bridge fee in.
     * @param maxFee The maximum fee to pay the bridge.
     */
    function bridge(uint96 shareAmount, address to, bytes calldata bridgeWildCard, ERC20 feeToken, uint256 maxFee)
        external
        payable
        requiresAuth
        nonReentrant
    {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();
        _bridge(shareAmount, to, bridgeWildCard, feeToken, maxFee);
    }

    /**
     * @notice Preview fee required to bridge shares in a given feeToken.
     */
    function previewFee(uint96 shareAmount, address to, bytes calldata bridgeWildCard, ERC20 feeToken)
        external
        view
        returns (uint256 fee)
    {
        MessageLib.Message memory m = MessageLib.Message(shareAmount, to);
        uint256 message = m.messageToUint256();

        return _previewFee(message, bridgeWildCard, feeToken);
    }

    // ========================================= INTERNAL BRIDGE FUNCTIONS =========================================

    /**
     * @notice Implement the bridge logic.
     */
    function _bridge(uint96 shareAmount, address to, bytes calldata bridgeWildCard, ERC20 feeToken, uint256 maxFee)
        internal
    {
        // Since shares are directly burned, call `beforeTransfer` to enforce before transfer hooks.
        beforeTransfer(msg.sender, address(0), msg.sender);

        // Burn shares from sender
        vault.exit(address(0), ERC20(address(0)), 0, msg.sender, shareAmount);

        // Send the message.
        MessageLib.Message memory m = MessageLib.Message(shareAmount, to);
        // `messageToUnit256` reverts on overflow, eventhough it is not possible to overflow.
        // This was done for future proofing.
        uint256 message = m.messageToUint256();

        bytes32 messageId = _sendMessage(message, bridgeWildCard, feeToken, maxFee);

        emit MessageSent(messageId, shareAmount, to);
    }

    /**
     * @notice Complete the message receive process, should be called in child contract once
     *         message has been confirmed as legit.`
     */
    function _completeMessageReceive(bytes32 messageId, uint256 message) internal {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();

        MessageLib.Message memory m = message.uint256ToMessage();

        // Mint shares to message.to
        vault.enter(address(0), ERC20(address(0)), 0, m.to, m.shareAmount);

        emit MessageReceived(messageId, m.shareAmount, m.to);
    }

    /**
     * @notice Send the message to the bridge implementation.
     * @dev This function should handle reverting if maxFee exceeds the fee required to send the message.
     * @dev This function should handle collecting the fee.
     * @param message The message to send.
     * @param bridgeWildCard The bridge specific data to configure message.
     * @param feeToken The token to pay the bridge fee in.
     * @param maxFee The maximum fee to pay the bridge.
     */
    function _sendMessage(uint256 message, bytes calldata bridgeWildCard, ERC20 feeToken, uint256 maxFee)
        internal
        virtual
        returns (bytes32 messageId);

    /**
     * @notice Preview fee required to bridge shares in a given token.
     */
    function _previewFee(uint256 message, bytes calldata bridgeWildCard, ERC20 feeToken)
        internal
        view
        virtual
        returns (uint256 fee);
}
