// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {DeployArcticArchitecture, ERC20, Deployer} from "script/ArchitectureDeployments/DeployArcticArchitecture.sol";
import {AddressToBytes32Lib} from "src/helper/AddressToBytes32Lib.sol";
import {BinanceSmartChainAddresses} from "test/resources/BinanceSmartChainAddresses.sol";

// Import Decoder and Sanitizer to deploy.
import {LombardBtcDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/LombardBtcDecoderAndSanitizer.sol";

/**
 *  source .env && forge script script/ArchitectureDeployments/BinanceSmartChain/DeployLombardBtc.s.sol:DeployLombardBtcScript --evm-version london --broadcast --etherscan-api-key $BSCSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployLombardBtcScript is DeployArcticArchitecture, BinanceSmartChainAddresses {
    using AddressToBytes32Lib for address;

    uint256 public privateKey;

    // Deployment parameters
    string public boringVaultName = "Lombard BTC Vault";
    string public boringVaultSymbol = "LBTCv";
    uint8 public boringVaultDecimals = 8;
    address public owner = dev0Address;

    function setUp() external {
        privateKey = vm.envUint("ETHERFI_LIQUID_DEPLOYER");
        vm.createSelectFork("bsc");
    }

    function run() external {
        // Configure the deployment.
        configureDeployment.deployContracts = true;
        configureDeployment.setupRoles = true;
        configureDeployment.setupDepositAssets = true;
        configureDeployment.setupWithdrawAssets = true;
        configureDeployment.finishSetup = true;
        configureDeployment.setupTestUser = true;
        configureDeployment.saveDeploymentDetails = true;
        configureDeployment.deployerAddress = deployerAddress;
        configureDeployment.balancerVault = balancerVault;
        configureDeployment.WETH = address(WBNB);

        // Save deployer.
        deployer = Deployer(configureDeployment.deployerAddress);

        // Define names to determine where contracts are deployed.
        names.rolesAuthority = LombardBtcRolesAuthorityName;
        names.lens = ArcticArchitectureLensName;
        names.boringVault = LombardBtcName;
        names.manager = LombardBtcManagerName;
        names.accountant = LombardBtcAccountantName;
        names.teller = LombardBtcTellerName;
        names.rawDataDecoderAndSanitizer = LombardBtcDecoderAndSanitizerName;
        names.delayedWithdrawer = LombardBtcDelayedWithdrawer;

        // Define Accountant Parameters.
        accountantParameters.payoutAddress = liquidPayoutAddress;
        accountantParameters.base = WBTC;
        // Decimals are in terms of `base`.
        accountantParameters.startingExchangeRate = 1.00377152e8;
        //  4 decimals
        accountantParameters.platformFee = 0.015e4;
        accountantParameters.performanceFee = 0;
        accountantParameters.allowedExchangeRateChangeLower = 0.995e4;
        accountantParameters.allowedExchangeRateChangeUpper = 1.005e4;
        // Minimum time(in seconds) to pass between updated without triggering a pause.
        accountantParameters.minimumUpateDelayInSeconds = 1 days / 4;

        // Define Decoder and Sanitizer deployment details.
        bytes memory creationCode = type(LombardBtcDecoderAndSanitizer).creationCode;
        bytes memory constructorArgs =
            abi.encode(deployer.getAddress(names.boringVault), uniswapV3NonFungiblePositionManager);

        // Setup extra deposit assets.
        depositAssets.push(
            DepositAsset({
                asset: LBTC,
                isPeggedToBase: true,
                rateProvider: address(0),
                genericRateProviderName: "",
                target: address(0),
                selector: bytes4(0),
                params: [bytes32(0), 0, 0, 0, 0, 0, 0, 0]
            })
        );
        // Setup withdraw assets.
        withdrawAssets.push(
            WithdrawAsset({
                asset: LBTC,
                withdrawDelay: 3 days,
                completionWindow: 7 days,
                withdrawFee: 0,
                maxLoss: 0.01e4
            })
        );

        withdrawAssets.push(
            WithdrawAsset({
                asset: WBTC,
                withdrawDelay: 3 days,
                completionWindow: 7 days,
                withdrawFee: 0,
                maxLoss: 0.01e4
            })
        );

        bool allowPublicDeposits = true;
        bool allowPublicWithdraws = true;
        uint64 shareLockPeriod = 1 days;
        address delayedWithdrawFeeAddress = liquidPayoutAddress;

        vm.startBroadcast(privateKey);

        _deploy(
            "BinanceSmartChain/LombardBtcDeployment.json",
            owner,
            boringVaultName,
            boringVaultSymbol,
            boringVaultDecimals,
            creationCode,
            constructorArgs,
            delayedWithdrawFeeAddress,
            allowPublicDeposits,
            allowPublicWithdraws,
            shareLockPeriod,
            dev1Address
        );

        vm.stopBroadcast();
    }
}
