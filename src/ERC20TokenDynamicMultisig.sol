// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

contract ERC20TokenDynamicMultisig is ERC20, ERC20Burnable, ERC20Pausable {

    string private _name;
    string private _symbol;

    // Dynamic multisig variables
    address[] public signers;
    mapping(address => bool) public isSigner;
    uint256 public requiredConfirmations;
    uint256 private transactionCount;

    enum TransactionType { 
        PAUSE, 
        UNPAUSE, 
        UPDATE_NAME_SYMBOL, 
        MINT,
        REPLACE_SIGNER,
        ADD_SIGNER,
        REMOVE_SIGNER,
        UPDATE_THRESHOLD
    }

    struct Transaction {
        TransactionType txType;
        address target;
        uint256 amount;
        string data1;
        string data2;
        bool executed;
        uint256 confirmations;
        mapping(address => bool) confirmed;
    }

    mapping(uint256 => Transaction) public transactions;

    // Events
    event TransactionSubmitted(uint256 indexed txId, TransactionType txType, address indexed submitter);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event TransactionRevoked(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event SignerReplaced(address indexed oldSigner, address indexed newSigner);
    event SignerAdded(address indexed newSigner);
    event SignerRemoved(address indexed removedSigner);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    modifier onlyMultisig() {
        require(isSigner[msg.sender], "Not a signer");
        _;
    }

    modifier txExists(uint256 _txId) {
        require(_txId < transactionCount, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].executed, "Transaction already executed");
        _;
    }

    modifier notConfirmed(uint256 _txId) {
        require(!transactions[_txId].confirmed[msg.sender], "Transaction already confirmed");
        _;
    }

    constructor(
        string memory name_, 
        string memory symbol_,
        address[] memory _signers,
        uint256 _requiredConfirmations
    ) ERC20(name_, symbol_) {
        require(_signers.length >= 1, "Must have at least one signer");
        require(_requiredConfirmations >= 1 && _requiredConfirmations <= _signers.length, 
                "Invalid confirmation threshold");
        
        // Check for duplicate signers and zero addresses
        for (uint256 i = 0; i < _signers.length; i++) {
            require(_signers[i] != address(0), "Invalid signer address");
            require(!isSigner[_signers[i]], "Duplicate signer");
            
            signers.push(_signers[i]);
            isSigner[_signers[i]] = true;
        }
        
        _name = name_;
        _symbol = symbol_;
        requiredConfirmations = _requiredConfirmations;
        
        _mint(msg.sender, 10_000_000_000 * 10 ** decimals());  // 10 Billion
    }

    // Submit transaction functions
    function submitPause() external onlyMultisig returns (uint256) {
        uint256 txId = _submitTransaction(TransactionType.PAUSE, address(0), 0, "", "");
        return txId;
    }

    function submitUnpause() external onlyMultisig returns (uint256) {
        uint256 txId = _submitTransaction(TransactionType.UNPAUSE, address(0), 0, "", "");
        return txId;
    }

    function submitUpdateNameAndSymbol(string memory newName, string memory newSymbol) 
        external 
        onlyMultisig 
        returns (uint256) 
    {
        uint256 txId = _submitTransaction(TransactionType.UPDATE_NAME_SYMBOL, address(0), 0, newName, newSymbol);
        return txId;
    }

    function submitMint(address to, uint256 amount) external onlyMultisig returns (uint256) {
        require(to != address(0), "Invalid recipient");
        uint256 txId = _submitTransaction(TransactionType.MINT, to, amount, "", "");
        return txId;
    }

    function submitReplaceSigner(address oldSigner, address newSigner) external onlyMultisig returns (uint256) {
        require(isSigner[oldSigner], "Old address is not a signer");
        require(!isSigner[newSigner], "New address is already a signer");
        require(newSigner != address(0), "Invalid new signer");
        uint256 txId = _submitTransaction(TransactionType.REPLACE_SIGNER, oldSigner, uint256(uint160(newSigner)), "", "");
        return txId;
    }

    function submitAddSigner(address newSigner) external onlyMultisig returns (uint256) {
        require(!isSigner[newSigner], "Address is already a signer");
        require(newSigner != address(0), "Invalid signer address");
        uint256 txId = _submitTransaction(TransactionType.ADD_SIGNER, newSigner, 0, "", "");
        return txId;
    }

    function submitRemoveSigner(address signerToRemove) external onlyMultisig returns (uint256) {
        require(isSigner[signerToRemove], "Address is not a signer");
        require(signers.length > 1, "Cannot remove the last signer");
        require(signers.length - 1 >= requiredConfirmations, "Removing signer would break threshold");
        uint256 txId = _submitTransaction(TransactionType.REMOVE_SIGNER, signerToRemove, 0, "", "");
        return txId;
    }

    function submitUpdateThreshold(uint256 newThreshold) external onlyMultisig returns (uint256) {
        require(newThreshold >= 1 && newThreshold <= signers.length, "Invalid threshold");
        uint256 txId = _submitTransaction(TransactionType.UPDATE_THRESHOLD, address(0), newThreshold, "", "");
        return txId;
    }

    function _submitTransaction(
        TransactionType _txType,
        address _target,
        uint256 _amount,
        string memory _data1,
        string memory _data2
    ) private returns (uint256) {
        uint256 txId = transactionCount++;
        
        Transaction storage newTx = transactions[txId];
        newTx.txType = _txType;
        newTx.target = _target;
        newTx.amount = _amount;
        newTx.data1 = _data1;
        newTx.data2 = _data2;
        newTx.executed = false;
        newTx.confirmations = 0;

        emit TransactionSubmitted(txId, _txType, msg.sender);
        
        // Auto-confirm for submitter
        confirmTransaction(txId);
        
        return txId;
    }

    function confirmTransaction(uint256 _txId) 
        public 
        onlyMultisig 
        txExists(_txId) 
        notExecuted(_txId) 
        notConfirmed(_txId) 
    {
        transactions[_txId].confirmed[msg.sender] = true;
        transactions[_txId].confirmations++;
        
        emit TransactionConfirmed(_txId, msg.sender);
        
        if (transactions[_txId].confirmations >= requiredConfirmations) {
            executeTransaction(_txId);
        }
    }

    function revokeConfirmation(uint256 _txId) 
        external 
        onlyMultisig 
        txExists(_txId) 
        notExecuted(_txId) 
    {
        require(transactions[_txId].confirmed[msg.sender], "Transaction not confirmed");
        
        transactions[_txId].confirmed[msg.sender] = false;
        transactions[_txId].confirmations--;
        
        emit TransactionRevoked(_txId, msg.sender);
    }

    function executeTransaction(uint256 _txId) 
        public 
        onlyMultisig 
        txExists(_txId) 
        notExecuted(_txId) 
    {
        require(transactions[_txId].confirmations >= requiredConfirmations, "Not enough confirmations");
        
        Transaction storage txn = transactions[_txId];
        txn.executed = true;
        
        if (txn.txType == TransactionType.PAUSE) {
            _pause();
        } else if (txn.txType == TransactionType.UNPAUSE) {
            _unpause();
        } else if (txn.txType == TransactionType.UPDATE_NAME_SYMBOL) {
            _name = txn.data1;
            _symbol = txn.data2;
        } else if (txn.txType == TransactionType.MINT) {
            _mint(txn.target, txn.amount);
        } else if (txn.txType == TransactionType.REPLACE_SIGNER) {
            address oldSigner = txn.target;
            address newSigner = address(uint160(txn.amount));
            
            // Find and replace signer in array
            for (uint256 i = 0; i < signers.length; i++) {
                if (signers[i] == oldSigner) {
                    signers[i] = newSigner;
                    break;
                }
            }
            
            isSigner[oldSigner] = false;
            isSigner[newSigner] = true;
            
            emit SignerReplaced(oldSigner, newSigner);
        } else if (txn.txType == TransactionType.ADD_SIGNER) {
            address newSigner = txn.target;
            signers.push(newSigner);
            isSigner[newSigner] = true;
            
            emit SignerAdded(newSigner);
        } else if (txn.txType == TransactionType.REMOVE_SIGNER) {
            address signerToRemove = txn.target;
            
            // Remove from array
            for (uint256 i = 0; i < signers.length; i++) {
                if (signers[i] == signerToRemove) {
                    signers[i] = signers[signers.length - 1];
                    signers.pop();
                    break;
                }
            }
            
            isSigner[signerToRemove] = false;
            
            emit SignerRemoved(signerToRemove);
        } else if (txn.txType == TransactionType.UPDATE_THRESHOLD) {
            uint256 oldThreshold = requiredConfirmations;
            requiredConfirmations = txn.amount;
            
            emit ThresholdUpdated(oldThreshold, txn.amount);
        }
        
        emit TransactionExecuted(_txId);
    }

    // View functions
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

    function isTransactionConfirmed(uint256 _txId, address _signer) 
        external 
        view 
        txExists(_txId) 
        returns (bool) 
    {
        return transactions[_txId].confirmed[_signer];
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    function getSignerCount() external view returns (uint256) {
        return signers.length;
    }

    function getRequiredConfirmations() external view returns (uint256) {
        return requiredConfirmations;
    }

    function getMultisigConfig() external view returns (uint256 required, uint256 total) {
        return (requiredConfirmations, signers.length);
    }

    function getTransactionCount() external view returns (uint256) {
        return transactionCount;
    }

    function getPendingTransactions() external view returns (uint256[] memory) {
        uint256 pendingCount = 0;
        
        // Count pending transactions
        for (uint256 i = 0; i < transactionCount; i++) {
            if (!transactions[i].executed) {
                pendingCount++;
            }
        }
        
        // Create array of pending transaction IDs
        uint256[] memory pendingTxs = new uint256[](pendingCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < transactionCount; i++) {
            if (!transactions[i].executed) {
                pendingTxs[index++] = i;
            }
        }
        
        return pendingTxs;
    }

    // Override functions
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}