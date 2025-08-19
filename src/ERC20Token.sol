// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ERC20Token
 * @notice A multisig-controlled ERC20 token with dynamic signer management and advanced governance features
 * @dev Implements ERC20, ERC20Burnable, ERC20Pausable with multisig governance for all administrative functions
 * @author Smart Contract Developer
 */
contract ERC20Token is ERC20, ERC20Burnable, ERC20Pausable, ReentrancyGuard {

    /// @notice Token name storage
    string private _name;
    
    /// @notice Token symbol storage
    string private _symbol;

    /**
     * @notice Multisig configuration struct for gas optimization
     * @dev Packed struct to save storage slots
     */
    struct MultisigConfig {
        uint128 requiredConfirmations;  /// @dev Number of required confirmations for transaction execution
        uint128 transactionCount;       /// @dev Total number of submitted transactions
    }
    
    /// @notice Current multisig configuration
    MultisigConfig public config;
    
    /// @notice Array of current signers
    address[] public signers;
    
    /// @notice Mapping to check if address is a signer
    mapping(address => bool) public isSigner;
    
    /// @notice Mapping of transaction ID to signer to confirmation status
    mapping(uint256 => mapping(address => bool)) private transactionConfirmations;
    
    /// @notice Mapping to track pending transactions
    mapping(uint256 => bool) public isPending;
    
    /// @notice Array of pending transaction IDs for efficient retrieval
    uint256[] private pendingTransactionIds;

    /**
     * @notice Enumeration of possible transaction types
     * @dev Used to identify the type of multisig transaction
     */
    enum TransactionType { 
        PAUSE,              /// @dev Pause token transfers
        UNPAUSE,            /// @dev Unpause token transfers
        UPDATE_NAME_SYMBOL, /// @dev Update token name and symbol
        MINT,               /// @dev Mint new tokens
        BURN,               /// @dev Burn existing tokens
        REPLACE_SIGNER,     /// @dev Replace an existing signer
        ADD_SIGNER,         /// @dev Add a new signer
        REMOVE_SIGNER,      /// @dev Remove an existing signer
        UPDATE_THRESHOLD    /// @dev Update confirmation threshold
    }

    /**
     * @notice Structure representing a multisig transaction
     * @dev Optimized struct packing for gas efficiency
     */
    struct Transaction {
        TransactionType txType;     /// @dev Type of transaction (1 byte)
        bool executed;              /// @dev Whether transaction has been executed (1 byte)
        uint16 confirmations;       /// @dev Number of confirmations received (2 bytes)
        uint32 timestamp;           /// @dev Transaction submission timestamp (4 bytes)
        address target;             /// @dev Target address for transaction (20 bytes)
        uint256 amount;             /// @dev Amount involved in transaction (32 bytes)
        string data1;               /// @dev First data field (dynamic)
        string data2;               /// @dev Second data field (dynamic)
    }

    /// @notice Mapping of transaction ID to transaction data
    mapping(uint256 => Transaction) public transactions;

    // Events
    /**
     * @notice Emitted when a new transaction is submitted
     * @param txId The transaction ID
     * @param txType The type of transaction
     * @param submitter The address that submitted the transaction
     */
    event TransactionSubmitted(uint256 indexed txId, TransactionType txType, address indexed submitter);
    
    /**
     * @notice Emitted when a transaction is confirmed by a signer
     * @param txId The transaction ID
     * @param signer The address that confirmed the transaction
     */
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    
    /**
     * @notice Emitted when a confirmation is revoked
     * @param txId The transaction ID
     * @param signer The address that revoked confirmation
     */
    event TransactionRevoked(uint256 indexed txId, address indexed signer);
    
    /**
     * @notice Emitted when a transaction is executed
     * @param txId The transaction ID
     */
    event TransactionExecuted(uint256 indexed txId);
    
    /**
     * @notice Emitted when a signer is replaced
     * @param oldSigner The address of the old signer
     * @param newSigner The address of the new signer
     */
    event SignerReplaced(address indexed oldSigner, address indexed newSigner);
    
    /**
     * @notice Emitted when a new signer is added
     * @param newSigner The address of the new signer
     */
    event SignerAdded(address indexed newSigner);
    
    /**
     * @notice Emitted when a signer is removed
     * @param removedSigner The address of the removed signer
     */
    event SignerRemoved(address indexed removedSigner);
    
    /**
     * @notice Emitted when the confirmation threshold is updated
     * @param oldThreshold The previous threshold
     * @param newThreshold The new threshold
     */
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    
    /**
     * @notice Emitted when tokens are burned through multisig
     * @param from The address tokens were burned from
     * @param amount The amount of tokens burned
     */
    event TokensBurned(address indexed from, uint256 amount);

    // Custom errors for gas optimization
    error NotASigner();
    error TransactionNotFound();
    error TransactionAlreadyExecuted();
    error TransactionAlreadyConfirmed();
    error TransactionNotConfirmed();
    error InsufficientConfirmations();
    error InvalidSigner();
    error DuplicateSigner();
    error InvalidThreshold();
    error InvalidRecipient();
    error CannotRemoveLastSigner();
    error ThresholdTooHigh();
    error InvalidBurnAmount();

    /**
     * @notice Restricts function access to multisig signers only
     * @dev Reverts with NotASigner if caller is not a signer
     */
    modifier onlyMultisig() {
        if (!isSigner[msg.sender]) revert NotASigner();
        _;
    }

    /**
     * @notice Ensures transaction exists
     * @dev Reverts with TransactionNotFound if transaction doesn't exist
     * @param _txId The transaction ID to check
     */
    modifier txExists(uint256 _txId) {
        if (_txId >= config.transactionCount) revert TransactionNotFound();
        _;
    }

    /**
     * @notice Ensures transaction has not been executed
     * @dev Reverts with TransactionAlreadyExecuted if transaction is already executed
     * @param _txId The transaction ID to check
     */
    modifier notExecuted(uint256 _txId) {
        if (transactions[_txId].executed) revert TransactionAlreadyExecuted();
        _;
    }

    /**
     * @notice Ensures caller has not already confirmed the transaction
     * @dev Reverts with TransactionAlreadyConfirmed if caller already confirmed
     * @param _txId The transaction ID to check
     */
    modifier notConfirmed(uint256 _txId) {
        if (transactionConfirmations[_txId][msg.sender]) revert TransactionAlreadyConfirmed();
        _;
    }

    /**
     * @notice Initializes the multisig token contract
     * @dev Sets up initial signers, threshold, and mints initial supply
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param _signers Array of initial signer addresses
     * @param _requiredConfirmations Number of required confirmations for transaction execution
     */
    constructor(
        string memory name_, 
        string memory symbol_,
        address[] memory _signers,
        uint256 _requiredConfirmations
    ) ERC20(name_, symbol_) {
        uint256 signersLength = _signers.length;
        if (signersLength == 0) revert InvalidSigner();
        if (_requiredConfirmations == 0 || _requiredConfirmations > signersLength) revert InvalidThreshold();
        
        // Gas optimization: cache array length and use unchecked arithmetic where safe
        unchecked {
            for (uint256 i = 0; i < signersLength; ++i) {
                address signer = _signers[i];
                if (signer == address(0)) revert InvalidSigner();
                if (isSigner[signer]) revert DuplicateSigner();
                
                signers.push(signer);
                isSigner[signer] = true;
            }
        }
        
        _name = name_;
        _symbol = symbol_;
        config.requiredConfirmations = uint128(_requiredConfirmations);
        config.transactionCount = 0;
        
        // Initial mint: 10 billion tokens
        _mint(msg.sender, 10_000_000_000 * 10 ** decimals());
    }

    /**
     * @notice Submits a transaction to pause token transfers
     * @dev Only callable by multisig signers
     * @return txId The ID of the submitted transaction
     */
    function submitPause() external onlyMultisig returns (uint256) {
        return _submitTransaction(TransactionType.PAUSE, address(0), 0, "", "");
    }

    /**
     * @notice Submits a transaction to unpause token transfers
     * @dev Only callable by multisig signers
     * @return txId The ID of the submitted transaction
     */
    function submitUnpause() external onlyMultisig returns (uint256) {
        return _submitTransaction(TransactionType.UNPAUSE, address(0), 0, "", "");
    }

    /**
     * @notice Submits a transaction to update token name and symbol
     * @dev Only callable by multisig signers
     * @param newName The new token name
     * @param newSymbol The new token symbol
     * @return txId The ID of the submitted transaction
     */
    function submitUpdateNameAndSymbol(string calldata newName, string calldata newSymbol) 
        external 
        onlyMultisig 
        returns (uint256) 
    {
        return _submitTransaction(TransactionType.UPDATE_NAME_SYMBOL, address(0), 0, newName, newSymbol);
    }

    /**
     * @notice Submits a transaction to mint new tokens
     * @dev Only callable by multisig signers
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     * @return txId The ID of the submitted transaction
     */
    function submitMint(address to, uint256 amount) external onlyMultisig returns (uint256) {
        if (to == address(0)) revert InvalidRecipient();
        return _submitTransaction(TransactionType.MINT, to, amount, "", "");
    }

    /**
     * @notice Submits a transaction to burn tokens from a specific address
     * @dev Only callable by multisig signers. Validates burn amount and target balance
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     * @return txId The ID of the submitted transaction
     */
    function submitBurn(address from, uint256 amount) external onlyMultisig returns (uint256) {
        if (from == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidBurnAmount();
        if (balanceOf(from) < amount) revert InvalidBurnAmount();
        return _submitTransaction(TransactionType.BURN, from, amount, "", "");
    }

    /**
     * @notice Submits a transaction to replace an existing signer
     * @dev Only callable by multisig signers
     * @param oldSigner The address of the signer to replace
     * @param newSigner The address of the new signer
     * @return txId The ID of the submitted transaction
     */
    function submitReplaceSigner(address oldSigner, address newSigner) external onlyMultisig returns (uint256) {
        if (!isSigner[oldSigner]) revert InvalidSigner();
        if (isSigner[newSigner] || newSigner == address(0)) revert InvalidSigner();
        return _submitTransaction(TransactionType.REPLACE_SIGNER, oldSigner, uint256(uint160(newSigner)), "", "");
    }

    /**
     * @notice Submits a transaction to add a new signer
     * @dev Only callable by multisig signers
     * @param newSigner The address of the new signer to add
     * @return txId The ID of the submitted transaction
     */
    function submitAddSigner(address newSigner) external onlyMultisig returns (uint256) {
        if (isSigner[newSigner] || newSigner == address(0)) revert InvalidSigner();
        return _submitTransaction(TransactionType.ADD_SIGNER, newSigner, 0, "", "");
    }

    /**
     * @notice Submits a transaction to remove an existing signer
     * @dev Only callable by multisig signers. Ensures at least one signer remains and threshold is maintainable
     * @param signerToRemove The address of the signer to remove
     * @return txId The ID of the submitted transaction
     */
    function submitRemoveSigner(address signerToRemove) external onlyMultisig returns (uint256) {
        if (!isSigner[signerToRemove]) revert InvalidSigner();
        uint256 signersLength = signers.length;
        if (signersLength <= 1) revert CannotRemoveLastSigner();
        if (signersLength - 1 < config.requiredConfirmations) revert ThresholdTooHigh();
        return _submitTransaction(TransactionType.REMOVE_SIGNER, signerToRemove, 0, "", "");
    }

    /**
     * @notice Submits a transaction to update the confirmation threshold
     * @dev Only callable by multisig signers
     * @param newThreshold The new confirmation threshold
     * @return txId The ID of the submitted transaction
     */
    function submitUpdateThreshold(uint256 newThreshold) external onlyMultisig returns (uint256) {
        if (newThreshold == 0 || newThreshold > signers.length) revert InvalidThreshold();
        return _submitTransaction(TransactionType.UPDATE_THRESHOLD, address(0), newThreshold, "", "");
    }

    /**
     * @notice Internal function to submit a new transaction
     * @dev Creates new transaction, adds to pending list, and auto-confirms for submitter
     * @param _txType The type of transaction
     * @param _target The target address for the transaction
     * @param _amount The amount involved in the transaction
     * @param _data1 First data field
     * @param _data2 Second data field
     * @return txId The ID of the submitted transaction
     */
    function _submitTransaction(
        TransactionType _txType,
        address _target,
        uint256 _amount,
        string memory _data1,
        string memory _data2
    ) private returns (uint256) {
        uint256 txId = config.transactionCount;
        
        // Gas optimization: direct assignment instead of storage modification
        config.transactionCount = uint128(txId + 1);
        
        Transaction storage newTx = transactions[txId];
        newTx.txType = _txType;
        newTx.target = _target;
        newTx.amount = _amount;
        newTx.data1 = _data1;
        newTx.data2 = _data2;
        newTx.executed = false;
        newTx.confirmations = 0;
        newTx.timestamp = uint32(block.timestamp);

        // Add to pending transactions
        isPending[txId] = true;
        pendingTransactionIds.push(txId);

        emit TransactionSubmitted(txId, _txType, msg.sender);
        
        // Auto-confirm for submitter
        _confirmTransaction(txId);
        
        return txId;
    }

    /**
     * @notice Confirms a submitted transaction
     * @dev Only callable by multisig signers. Auto-executes if threshold is reached
     * @param _txId The ID of the transaction to confirm
     */
    function confirmTransaction(uint256 _txId) 
        external 
        onlyMultisig 
        txExists(_txId) 
        notExecuted(_txId) 
        notConfirmed(_txId) 
        nonReentrant
    {
        _confirmTransaction(_txId);
    }

    /**
     * @notice Internal function to confirm a transaction
     * @dev Updates confirmation status and executes if threshold is met
     * @param _txId The ID of the transaction to confirm
     */
    function _confirmTransaction(uint256 _txId) private {
        transactionConfirmations[_txId][msg.sender] = true;
        
        Transaction storage txn = transactions[_txId];
        unchecked {
            txn.confirmations++;
        }
        
        emit TransactionConfirmed(_txId, msg.sender);
        
        if (txn.confirmations >= config.requiredConfirmations) {
            _executeTransaction(_txId);
        }
    }

    /**
     * @notice Revokes a previous confirmation for a transaction
     * @dev Only callable by multisig signers who have previously confirmed
     * @param _txId The ID of the transaction to revoke confirmation for
     */
    function revokeConfirmation(uint256 _txId) 
        external 
        onlyMultisig 
        txExists(_txId) 
        notExecuted(_txId) 
        nonReentrant
    {
        if (!transactionConfirmations[_txId][msg.sender]) revert TransactionNotConfirmed();
        
        transactionConfirmations[_txId][msg.sender] = false;
        
        Transaction storage txn = transactions[_txId];
        unchecked {
            txn.confirmations--;
        }
        
        emit TransactionRevoked(_txId, msg.sender);
    }

    /**
     * @notice Manually executes a transaction if it has enough confirmations
     * @dev Only callable by multisig signers
     * @param _txId The ID of the transaction to execute
     */
    function executeTransaction(uint256 _txId) 
        external 
        onlyMultisig 
        txExists(_txId) 
        notExecuted(_txId) 
        nonReentrant
    {
        if (transactions[_txId].confirmations < config.requiredConfirmations) revert InsufficientConfirmations();
        _executeTransaction(_txId);
    }

    /**
     * @notice Internal function to execute a confirmed transaction
     * @dev Performs the actual transaction logic based on transaction type
     * @param _txId The ID of the transaction to execute
     */
    function _executeTransaction(uint256 _txId) private {
        Transaction storage txn = transactions[_txId];
        txn.executed = true;
        
        // Remove from pending transactions
        _removePendingTransaction(_txId);
        
        TransactionType txType = txn.txType;
        
        if (txType == TransactionType.PAUSE) {
            _pause();
        } else if (txType == TransactionType.UNPAUSE) {
            _unpause();
        } else if (txType == TransactionType.UPDATE_NAME_SYMBOL) {
            _name = txn.data1;
            _symbol = txn.data2;
        } else if (txType == TransactionType.MINT) {
            _mint(txn.target, txn.amount);
        } else if (txType == TransactionType.BURN) {
            _burn(txn.target, txn.amount);
            emit TokensBurned(txn.target, txn.amount);
        } else if (txType == TransactionType.REPLACE_SIGNER) {
            _replaceSigner(txn.target, address(uint160(txn.amount)));
        } else if (txType == TransactionType.ADD_SIGNER) {
            _addSigner(txn.target);
        } else if (txType == TransactionType.REMOVE_SIGNER) {
            _removeSigner(txn.target);
        } else if (txType == TransactionType.UPDATE_THRESHOLD) {
            _updateThreshold(txn.amount);
        }
        
        emit TransactionExecuted(_txId);
    }

    /**
     * @notice Internal function to replace a signer
     * @dev Updates signers array and mapping
     * @param oldSigner The address of the signer to replace
     * @param newSigner The address of the new signer
     */
    function _replaceSigner(address oldSigner, address newSigner) private {
        uint256 length = signers.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (signers[i] == oldSigner) {
                    signers[i] = newSigner;
                    break;
                }
            }
        }
        
        isSigner[oldSigner] = false;
        isSigner[newSigner] = true;
        
        emit SignerReplaced(oldSigner, newSigner);
    }

    /**
     * @notice Internal function to add a new signer
     * @dev Adds signer to array and mapping
     * @param newSigner The address of the new signer
     */
    function _addSigner(address newSigner) private {
        signers.push(newSigner);
        isSigner[newSigner] = true;
        emit SignerAdded(newSigner);
    }

    /**
     * @notice Internal function to remove a signer
     * @dev Removes signer from array and mapping using swap-and-pop
     * @param signerToRemove The address of the signer to remove
     */
    function _removeSigner(address signerToRemove) private {
        uint256 length = signers.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (signers[i] == signerToRemove) {
                    signers[i] = signers[length - 1];
                    signers.pop();
                    break;
                }
            }
        }
        
        isSigner[signerToRemove] = false;
        emit SignerRemoved(signerToRemove);
    }

    /**
     * @notice Internal function to update the confirmation threshold
     * @dev Updates the required confirmations in config
     * @param newThreshold The new confirmation threshold
     */
    function _updateThreshold(uint256 newThreshold) private {
        uint256 oldThreshold = config.requiredConfirmations;
        config.requiredConfirmations = uint128(newThreshold);
        emit ThresholdUpdated(oldThreshold, newThreshold);
    }

    /**
     * @notice Internal function to remove a transaction from pending list
     * @dev Uses swap-and-pop for gas efficiency
     * @param _txId The transaction ID to remove from pending list
     */
    function _removePendingTransaction(uint256 _txId) private {
        if (!isPending[_txId]) return;
        
        isPending[_txId] = false;
        
        uint256 length = pendingTransactionIds.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (pendingTransactionIds[i] == _txId) {
                    pendingTransactionIds[i] = pendingTransactionIds[length - 1];
                    pendingTransactionIds.pop();
                    break;
                }
            }
        }
    }

    /**
     * @notice Gets detailed information about a transaction
     * @dev Returns all transaction data except confirmations mapping
     * @param _txId The transaction ID to query
     * @return txType The type of transaction
     * @return target The target address
     * @return amount The amount involved
     * @return data1 First data field
     * @return data2 Second data field
     * @return executed Whether transaction is executed
     * @return confirmations Number of confirmations received
     */
    function getTransaction(uint256 _txId) 
        external 
        view 
        txExists(_txId) 
        returns (
            TransactionType txType,
            address target,
            uint256 amount,
            string memory data1,
            string memory data2,
            bool executed,
            uint256 confirmations
        ) 
    {
        Transaction storage txn = transactions[_txId];
        return (
            txn.txType,
            txn.target,
            txn.amount,
            txn.data1,
            txn.data2,
            txn.executed,
            txn.confirmations
        );
    }

    /**
     * @notice Checks if a specific signer has confirmed a transaction
     * @dev Returns confirmation status for given transaction and signer
     * @param _txId The transaction ID to check
     * @param _signer The signer address to check
     * @return confirmed True if signer has confirmed the transaction
     */
    function isTransactionConfirmed(uint256 _txId, address _signer) 
        external 
        view 
        txExists(_txId) 
        returns (bool) 
    {
        return transactionConfirmations[_txId][_signer];
    }

    /**
     * @notice Gets the current list of signers
     * @dev Returns array of all current signer addresses
     * @return Array of signer addresses
     */
    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    /**
     * @notice Gets the current number of signers
     * @dev Returns length of signers array
     * @return Number of current signers
     */
    function getSignerCount() external view returns (uint256) {
        return signers.length;
    }

    /**
     * @notice Gets the current required confirmation threshold
     * @dev Returns number of confirmations needed to execute transactions
     * @return Number of required confirmations
     */
    function getRequiredConfirmations() external view returns (uint256) {
        return config.requiredConfirmations;
    }

    /**
     * @notice Gets the current multisig configuration
     * @dev Returns both required confirmations and total signer count
     * @return required Number of required confirmations
     * @return total Total number of signers
     */
    function getMultisigConfig() external view returns (uint256 required, uint256 total) {
        return (config.requiredConfirmations, signers.length);
    }

    /**
     * @notice Gets the total number of transactions submitted
     * @dev Returns total transaction count including executed and pending
     * @return Total number of transactions
     */
    function getTransactionCount() external view returns (uint256) {
        return config.transactionCount;
    }

    /**
     * @notice Gets list of pending transaction IDs
     * @dev Returns array of transaction IDs that haven't been executed
     * @return Array of pending transaction IDs
     */
    function getPendingTransactions() external view returns (uint256[] memory) {
        return pendingTransactionIds;
    }

    /**
     * @notice Gets the number of pending transactions
     * @dev Returns count of transactions waiting for execution
     * @return Number of pending transactions
     */
    function getPendingTransactionCount() external view returns (uint256) {
        return pendingTransactionIds.length;
    }

    /**
     * @notice Returns the token name
     * @dev Overrides ERC20 name function to use custom storage
     * @return The token name
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @notice Returns the token symbol
     * @dev Overrides ERC20 symbol function to use custom storage
     * @return The token symbol
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Internal function called before token transfers
     * @dev Overrides both ERC20 and ERC20Pausable _update functions
     * @param from The sender address
     * @param to The recipient address
     * @param value The amount being transferred
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}