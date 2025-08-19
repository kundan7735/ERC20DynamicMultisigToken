# ERC20 Token with Dynamic Multisig

A secure ERC20 token implementation with m-out-of-n multisignature functionality for administrative operations.

## Features

- **ERC20 Standard**: Full ERC20 implementation with mint and burn capabilities
- **Dynamic Multisig**: Requires m out of n signers to confirm administrative actions
- **Pausable**: Token transfers can be paused/unpaused via multisig
- **Signer Management**: Replace signers through multisig consensus
- **Transaction Queue**: Pending transactions with confirmation tracking

## Protected Functions

The following functions require m/n multisig approval:
- `mint()` - Create new tokens
- `burn()` - Burn tokens
- `pause()` - Pause all token transfers
- `unpause()` - Resume token transfers
- `updateNameAndSymbol()` - Change token metadata
- `replaceSigner()` - Replace one of the signers

## Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm (for OpenZeppelin contracts)

### Installation

1. Clone the repository:
```bash
git clone <your-repo>
cd <your-repo>
```

2. Install dependencies:
```bash
forge build
# or manually:
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
```

3. Copy and configure environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

## Testing

### Run all tests:
```bash
make test
# or
forge test -vvv
```

### Run specific test:
```bash
forge test --match-test test_MintExecution -vvv
```

### Run with gas report:
```bash
make test-gas
# or
forge test --gas-report
```

### Coverage report:
```bash
make coverage
# or
forge coverage
```

## Deployment

### Local Deployment (Anvil)

1. Start local node:
```bash
forge  anvil
```

2. Deploy in another terminal:
```bash
 forge script script/DeployDynamicMultisigToken.s.sol:DeployDynamicMultisigToken --rpc-url local --broadcast --verify -vv
```

### Sepolia Testnet Deployment

1. Configure `.env` file with:
   - `PRIVATE_KEY`: Deployer's private key
   - `SEPOLIA_RPC_URL`: Your Sepolia RPC endpoint
   - `ETHERSCAN_API_KEY`: For contract verification

2. Deploy:
```bash
forge script script/DeployDynamicMultisigToken.s.sol:DeployDynamicMultisigToken --rpc-url sepolia --broadcast --verify -vv
```

### Mainnet Deployment

⚠️ **CAUTION**: Mainnet deployment involves real funds!

1. Configure `.env` with mainnet settings:
   - `MAINNET_RPC_URL`
   - `MAINNET_SIGNER1`, `MAINNET_SIGNER2`, `MAINNET_SIGNER3`
   - `TOKEN_NAME`, `TOKEN_SYMBOL`



2. Deploy (will ask for confirmation):
```bash
forge script script/DeployDynamicMultisigToken.s.sol:DeployDynamicMultisigToken --rpc-url mainnet --broadcast --verify -vv
```

## Contract Interaction

### Using Cast Commands

Get current signers:
```bash
cast call $TOKEN_ADDRESS "getSigners()(address[3])" --rpc-url $RPC_URL
```

Get pending transactions:
```bash
cast call $TOKEN_ADDRESS "getPendingTransactions()(uint256[])" --rpc-url $RPC_URL
```

Submit mint proposal (as signer):
```bash
cast send $TOKEN_ADDRESS "submitMint(address,uint256)" $RECIPIENT $AMOUNT \
  --private-key $SIGNER_KEY --rpc-url $RPC_URL
```

Confirm transaction (as signer):
```bash
cast send $TOKEN_ADDRESS "confirmTransaction(uint256)" $TX_ID \
  --private-key $SIGNER_KEY --rpc-url $RPC_URL
```

## Multisig Workflow Example

### Minting Tokens

1. **Signer 1 submits mint proposal:**
```javascript
const txId = await token.submitMint(recipientAddress, amount);
```

2. **Signer 2 confirms (auto-executes at 2/3):**
```javascript
await token.confirmTransaction(txId);
// Tokens are minted automatically!
```

### Checking Transaction Status

```javascript
// Get transaction details
const tx = await token.getTransaction(txId);
console.log({
    type: tx.txType,
    confirmations: tx.confirmations,
    executed: tx.executed
});

// Check who has signed
const signer1Confirmed = await token.isTransactionConfirmed(txId, signer1);
const signer2Confirmed = await token.isTransactionConfirmed(txId, signer2);
```

## Security Considerations

1. **Signer Security**: 
   - Use hardware wallets for mainnet signers
   - Consider using multisig wallets as signers for additional security
   - Implement proper key management procedures

2. **Deployment Security**:
   - Always simulate mainnet deployments first
   - Verify constructor arguments are correct
   - Ensure signers are unique and valid addresses

3. **Operational Security**:
   - Regularly rotate signers if keys are compromised
   - Monitor pending transactions
   - Implement off-chain coordination for signers

## Gas Optimization

The contract is optimized for:
- Minimal storage operations
- Efficient confirmation tracking
- Automatic execution upon reaching threshold

## Verification

After deployment, verify on Etherscan:
```bash
forge verify-contract \
  --chain-id <chain-id> \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(string,string,address,address,address)" "Token Name" "TKN" $SIGNER1 $SIGNER2 $SIGNER3) \
  $TOKEN_ADDRESS \
  src/ERC20TokenMultisig.sol:ERC20TokenMultisig
```

## Project Structure

```
.
├── src/
│   └── ERC20TokenDynamicMultisig.sol    # Main contract
├── script/
│   └── DeployDynamicMultisigToken.s.sol # Deployment script
├── test/
│   └── ERC20TokenDynamicMultisig.t.sol  # Unit tests
├── .env.example                   # Environment variables template
├── remappings.txt                 # remappings for lib 
├── foundry.toml                   # Foundry configuration
└── README.md                      # This file
```

## Foundry Commands Reference

```bash
forge build          # Compile contracts
forge test           # Run tests
forge fmt            # Format code
forge snapshot       # Gas snapshots
forge script         # Run scripts
cast call            # Read from blockchain
cast send            # Write to blockchain
cast decode-abi      # Decode ABI data
anvil                # Local testnet
```

## License

MIT