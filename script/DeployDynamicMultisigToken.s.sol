// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20TokenDynamicMultisig} from "../src/ERC20TokenDynamicMultisig.sol";

contract DeployDynamicMultisigToken is Script {
    // Configuration struct for deployment
    struct DeployConfig {
        string name;
        string symbol;
        address[] signers;
        uint256 requiredConfirmations;
    }

    // Deployed contract address tracking
    ERC20TokenDynamicMultisig public token;

    function run() external {
        // Determine which network we're deploying to
        uint256 chainId = block.chainid;
        DeployConfig memory config;

        if (chainId == 11155111) {
            // Sepolia testnet configuration
            console2.log("Deploying to Sepolia Testnet...");
            config = getSepoliaConfig();
        } else if (chainId == 1) {
            // Ethereum mainnet configuration
            console2.log("Deploying to Ethereum Mainnet...");
            config = getMainnetConfig();
        } else if (chainId == 31337) {
            // Local Anvil/Hardhat configuration
            console2.log("Deploying to Local Network...");
            config = getAnvilConfig();
        } else if (chainId == 137) {
            // Polygon mainnet configuration
            console2.log("Deploying to Polygon Mainnet...");
            config = getPolygonConfig();
        } else if (chainId == 56) {
            // BSC mainnet configuration
            console2.log("Deploying to BSC Mainnet...");
            config = getBscConfig();
        } else {
            revert("Unsupported chain ID");
        }

        // Validate configuration
        validateConfig(config);

        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deployer address:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        // Verify minimum balance for deployment
        require(deployer.balance > 0, "Insufficient balance for deployment");

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        token = new ERC20TokenDynamicMultisig(
            config.name,
            config.symbol,
            config.signers,
            config.requiredConfirmations
        );

        vm.stopBroadcast();

        // Log deployment information
        logDeploymentInfo( deployer);

        // Save deployment info to file
        saveDeploymentInfo(chainId, config);

        // Print verification command
        printVerificationCommand(chainId, config);
    }

    function getSepoliaConfig() internal pure returns (DeployConfig memory) {
        address[] memory signers = new address[](3);
        signers[0] = 0x449C852e95c65de31E961980c1F1093e01af5A01;
        signers[1] = 0xBE7a1Fba3F1F7e273Ab67208B5E841693631a723;
        signers[2] = 0xB1DBdF93c79e578fB6e7849bBF624E7E944Ac680;

        return DeployConfig({
            name: "Dynamic Multisig Token Sepolia",
            symbol: "DMTS",
            signers: signers,
            requiredConfirmations: 2
        });
    }

    function getMainnetConfig() internal view returns (DeployConfig memory) {
        // For mainnet, read from environment variables for security
        string memory signerEnv = vm.envString("MAINNET_SIGNERS"); // Comma-separated addresses
        address[] memory signers = parseSignerAddresses(signerEnv);

        return DeployConfig({
            name: vm.envString("TOKEN_NAME"),
            symbol: vm.envString("TOKEN_SYMBOL"),
            signers: signers,
            requiredConfirmations: vm.envUint("REQUIRED_CONFIRMATIONS")
        });
    }

    function getAnvilConfig() internal pure returns (DeployConfig memory) {
        // Default Anvil test addresses
        address[] memory signers = new address[](5);
        signers[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;  // Account 0
        signers[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;  // Account 1
        signers[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;  // Account 2
        signers[3] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;  // Account 3
        signers[4] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;  // Account 4

        return DeployConfig({
            name: "Dynamic Multisig Token Local",
            symbol: "DMTL",
            signers: signers,
            requiredConfirmations: 3
        });
    }

    function getPolygonConfig() internal view returns (DeployConfig memory) {
        string memory signerEnv = vm.envString("POLYGON_SIGNERS");
        address[] memory signers = parseSignerAddresses(signerEnv);

        return DeployConfig({
            name: "Dynamic Multisig Token Polygon",
            symbol: "DMTP",
            signers: signers,
            requiredConfirmations: vm.envUint("POLYGON_REQUIRED_CONFIRMATIONS")
        });
    }

    function getBscConfig() internal view returns (DeployConfig memory) {
        string memory signerEnv = vm.envString("BSC_SIGNERS");
        address[] memory signers = parseSignerAddresses(signerEnv);

        return DeployConfig({
            name: "Dynamic Multisig Token BSC",
            symbol: "DMTB",
            signers: signers,
            requiredConfirmations: vm.envUint("BSC_REQUIRED_CONFIRMATIONS")
        });
    }

    function parseSignerAddresses(string memory signerString) internal pure returns (address[] memory) {
        // Simple parser for comma-separated addresses
        // In a real implementation, you might want a more robust parser
        bytes memory signerBytes = bytes(signerString);
        uint256 commaCount = 0;
        
        // Count commas to determine array size
        for (uint256 i = 0; i < signerBytes.length; i++) {
            if (signerBytes[i] == ',') {
                commaCount++;
            }
        }
        
        new address[](commaCount + 1);
        
        // This is a simplified implementation
        // For production, use a more robust CSV parser or pass addresses individually
        // For now, we'll require exactly 3 addresses for simplicity
        require(commaCount == 2, "Expected exactly 3 signer addresses separated by commas");
        
        // For production deployment, you would implement proper CSV parsing here
        // or handle signers differently (e.g., separate env vars for each signer)
        revert("Implement proper CSV parsing for production use");
    }

    function validateConfig(DeployConfig memory config) internal pure {
        require(bytes(config.name).length > 0, "Token name cannot be empty");
        require(bytes(config.symbol).length > 0, "Token symbol cannot be empty");
        require(config.signers.length >= 1, "Must have at least one signer");
        require(config.requiredConfirmations >= 1, "Required confirmations must be at least 1");
        require(config.requiredConfirmations <= config.signers.length, "Required confirmations cannot exceed signer count");
        
        // Check for duplicate signers and zero addresses
        for (uint256 i = 0; i < config.signers.length; i++) {
            require(config.signers[i] != address(0), "Signer cannot be zero address");
            
            // Check for duplicates
            for (uint256 j = i + 1; j < config.signers.length; j++) {
                require(config.signers[i] != config.signers[j], "Duplicate signer addresses not allowed");
            }
        }
    }

    function logDeploymentInfo( address deployer) internal view {
        console2.log("=====================================");
        console2.log("Dynamic Multisig Token Deployed Successfully!");
        console2.log("=====================================");
        console2.log("Contract Address:", address(token));
        console2.log("Token Name:", token.name());
        console2.log("Token Symbol:", token.symbol());
        console2.log("Total Supply:", token.totalSupply());
        console2.log("Deployer Balance:", token.balanceOf(deployer));
        console2.log("");
        console2.log("Multisig Configuration:");
        console2.log("  Required Confirmations:", token.getRequiredConfirmations());
        console2.log("  Total Signers:", token.getSignerCount());
        console2.log("");
        console2.log("Signers:");
        
        address[] memory signers = token.getSigners();
        for (uint256 i = 0; i < signers.length; i++) {
            console2.log("  Signer", i + 1, ":", signers[i]);
        }
        
        console2.log("");
        console2.log("Transaction Types Available:");
        console2.log("  - PAUSE/UNPAUSE");
        console2.log("  - UPDATE_NAME_SYMBOL");
        console2.log("  - MINT");
        console2.log("  - REPLACE_SIGNER");
        console2.log("  - ADD_SIGNER");
        console2.log("  - REMOVE_SIGNER");
        console2.log("  - UPDATE_THRESHOLD");
        console2.log("=====================================");
    }

    function saveDeploymentInfo(uint256 chainId, DeployConfig memory config) internal {
        string memory chainName = getChainName(chainId);

        // Create deployment info JSON
        string memory json = "deployment";
        vm.serializeAddress(json, "tokenAddress", address(token));
        vm.serializeString(json, "tokenName", token.name());
        vm.serializeString(json, "tokenSymbol", token.symbol());
        vm.serializeUint(json, "totalSupply", token.totalSupply());
        vm.serializeUint(json, "chainId", chainId);
        vm.serializeString(json, "chainName", chainName);
        vm.serializeUint(json, "requiredConfirmations", token.getRequiredConfirmations());
        vm.serializeUint(json, "signerCount", token.getSignerCount());
        
        // Serialize signers array
        address[] memory signers = token.getSigners();
        for (uint256 i = 0; i < signers.length; i++) {
            string memory signerKey = string.concat("signer", vm.toString(i + 1));
            vm.serializeAddress(json, signerKey, signers[i]);
        }

        vm.serializeUint(json, "deploymentTimestamp", block.timestamp);

        // Create filename with timestamp
        // string memory fileName = string.concat(
        //     "deployments/dynamic-multisig-",
        //     chainName,
        //     "-",
        //     vm.toString(block.timestamp),
        //     ".json"
        // );
        
        // vm.writeJson(finalJson, fileName);
        // console2.log("Deployment info saved to:", fileName);
    }

    function printVerificationCommand(uint256 chainId, DeployConfig memory config) internal view {
        console2.log("");
        console2.log("=====================================");
        console2.log("Contract Verification Command:");
        console2.log("=====================================");
        console2.log("forge verify-contract \\");
        console2.log("  --chain-id", chainId, "\\");
        console2.log("  --constructor-args $(cast abi-encode \"constructor(string,string,address[],uint256)\" \\");
        console2.log("    \"", config.name, "\" \\");
        console2.log("    \"", config.symbol, "\" \\");
        
        console2.log("    \"[");
        for (uint256 i = 0; i < config.signers.length; i++) {
            if (i > 0) console2.log(",");
            console2.log("      ", config.signers[i]);
        }
        console2.log("    ]\" \\");
        
        console2.log("    ", config.requiredConfirmations, ") \\");
        console2.log("  ", address(token), " \\");
        console2.log("  src/ERC20TokenDynamicMultisig.sol:ERC20TokenDynamicMultisig \\");
        console2.log("  --etherscan-api-key $ETHERSCAN_API_KEY");
        console2.log("=====================================");
    }

    function getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) return "mainnet";
        else if (chainId == 11155111) return "sepolia";
        else if (chainId == 31337) return "local";
        else if (chainId == 137) return "polygon";
        else if (chainId == 56) return "bsc";
        else return "unknown";
    }
}

// Separate script for interacting with deployed contract
contract InteractWithDynamicMultisig is Script {
    ERC20TokenDynamicMultisig public token;
    
    function run() external {
        // Load contract address from environment
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        token = ERC20TokenDynamicMultisig(tokenAddress);
        
        uint256 signerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console2.log("Interacting with token at:", tokenAddress);
        console2.log("Current multisig config:");
        
        (uint256 required, uint256 total) = token.getMultisigConfig();
        console2.log("  Required confirmations:", required);
        console2.log("  Total signers:", total);
        
        vm.startBroadcast(signerPrivateKey);
        
        // Example: Submit a mint transaction
        uint256 txId = token.submitMint(
            vm.envAddress("SIGNER1"),
            vm.envUint("MINT_AMOUNT")
        );
        
        console2.log("Submitted mint transaction with ID:", txId);
        
        vm.stopBroadcast();
        
        // Show pending transactions
        uint256[] memory pending = token.getPendingTransactions();
        console2.log("Pending transactions:", pending.length);
        for (uint256 i = 0; i < pending.length; i++) {
            console2.log("  Transaction ID:", pending[i]);
        }
    }
}

// Script for emergency operations
contract EmergencyDynamicMultisig is Script {
    ERC20TokenDynamicMultisig public token;
    
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        token = ERC20TokenDynamicMultisig(tokenAddress);
        
        uint256 signerPrivateKey = vm.envUint("EMERGENCY_SIGNER_KEY");
        
        vm.startBroadcast(signerPrivateKey);
        
        // Emergency pause
        if (vm.envBool("EMERGENCY_PAUSE")) {
            uint256 pauseTxId = token.submitPause();
            console2.log("Emergency pause submitted with ID:", pauseTxId);
        }
        
        // Emergency signer replacement
        if (vm.envBool("EMERGENCY_REPLACE_SIGNER")) {
            address oldSigner = vm.envAddress("OLD_SIGNER");
            address newSigner = vm.envAddress("NEW_SIGNER");
            
            uint256 replaceTxId = token.submitReplaceSigner(oldSigner, newSigner);
            console2.log("Emergency signer replacement submitted with ID:", replaceTxId);
        }
        
        vm.stopBroadcast();
    }
}

// Script for batch operations
contract BatchDynamicMultisigOperations is Script {
    ERC20TokenDynamicMultisig public token;
    
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        token = ERC20TokenDynamicMultisig(tokenAddress);
        
        uint256 signerPrivateKey = vm.envUint("BATCH_SIGNER_KEY");
        
        vm.startBroadcast(signerPrivateKey);
        
        // Batch confirm multiple transactions
         vm.envString("TX_IDS_TO_CONFIRM");
        // Parse comma-separated transaction IDs
        // This is simplified - you'd want proper CSV parsing
        
        console2.log("Batch confirming transactions...");
        
        // Example: Confirm transactions 0, 1, 2
        for (uint256 i = 0; i < 3; i++) {
            try token.confirmTransaction(i) {
                console2.log("Confirmed transaction:", i);
            } catch {
                console2.log("Failed to confirm transaction:", i);
            }
        }
        
        vm.stopBroadcast();
        
        // Show updated pending transactions
        uint256[] memory pending = token.getPendingTransactions();
        console2.log("Remaining pending transactions:", pending.length);
    }
}