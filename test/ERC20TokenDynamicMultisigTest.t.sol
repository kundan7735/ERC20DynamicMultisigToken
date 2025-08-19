// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Token} from "../src/ERC20Token.sol";

contract ERC20TokenTest is Test {
    ERC20Token public token;
    
    // Test accounts
    address public deployer;
    address public signer1;
    address public signer2;
    address public signer3;
    address public nonSigner;
    address public recipient;
    
    // Events to test
    event TransactionSubmitted(uint256 indexed txId, ERC20Token.TransactionType txType, address indexed submitter);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event TransactionRevoked(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event SignerReplaced(address indexed oldSigner, address indexed newSigner);
    event SignerAdded(address indexed newSigner);
    event SignerRemoved(address indexed removedSigner);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TokensBurned(address indexed from, uint256 amount); // NEW
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        // Setup test accounts
        deployer = address(this);
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");
        signer3 = makeAddr("signer3");
        nonSigner = makeAddr("nonSigner");
        recipient = makeAddr("recipient");
        
        // Create signers array
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        
        // Deploy token contract with 2-of-3 multisig
        token = new ERC20Token(
            "Test Dynamic Multisig Token",
            "TDMT",
            signers,
            2  // Required confirmations
        );
        
        // Fund signers with ETH for gas
        vm.deal(signer1, 10 ether);
        vm.deal(signer2, 10 ether);
        vm.deal(signer3, 10 ether);
        vm.deal(nonSigner, 10 ether);
    }
    
    // ============ Constructor Tests ============
    
    function test_Constructor() public view {
        assertEq(token.name(), "Test Dynamic Multisig Token");
        assertEq(token.symbol(), "TDMT");
        assertEq(token.totalSupply(), 10_000_000_000 * 10**18);
        assertEq(token.balanceOf(deployer), 10_000_000_000 * 10**18);
        
        address[] memory signers = token.getSigners();
        assertEq(signers.length, 3);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertEq(signers[2], signer3);
        
        assertTrue(token.isSigner(signer1));
        assertTrue(token.isSigner(signer2));
        assertTrue(token.isSigner(signer3));
        assertFalse(token.isSigner(nonSigner));
        
        assertEq(token.getRequiredConfirmations(), 2);
        assertEq(token.getSignerCount(), 3);
    }
    
    function test_Constructor_RevertEmptySigners() public {
        address[] memory emptySigners = new address[](0);
        
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        new ERC20Token("Token", "TKN", emptySigners, 1);
    }
    
    function test_Constructor_RevertZeroAddress() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = address(0);
        
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        new ERC20Token("Token", "TKN", signers, 1);
    }
    
    function test_Constructor_RevertDuplicateSigners() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer1;
        
        vm.expectRevert(ERC20Token.DuplicateSigner.selector);
        new ERC20Token("Token", "TKN", signers, 1);
    }
    
    function test_Constructor_RevertInvalidThreshold() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;
        
        vm.expectRevert(ERC20Token.InvalidThreshold.selector);
        new ERC20Token("Token", "TKN", signers, 0);
        
        vm.expectRevert(ERC20Token.InvalidThreshold.selector);
        new ERC20Token("Token", "TKN", signers, 3);
    }
    
    // ============ Mint Tests ============
    
    function test_SubmitMint() public {
        vm.prank(signer1);
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(0, ERC20Token.TransactionType.MINT, signer1);
        uint256 txId = token.submitMint(recipient, 1000 * 10**18);
        
        assertEq(txId, 0);
        assertEq(token.getTransactionCount(), 1);
        
        (
            ERC20Token.TransactionType txType,
            address target,
            uint256 amount,
            ,  // string memory data1 - unused
            ,  // string memory data2 - unused
            bool executed,
            uint256 confirmations
        ) = token.getTransaction(txId);
        
        assertEq(uint(txType), uint(ERC20Token.TransactionType.MINT));
        assertEq(target, recipient);
        assertEq(amount, 1000 * 10**18);
        assertEq(executed, false);
        assertEq(confirmations, 1);
        assertTrue(token.isTransactionConfirmed(txId, signer1));
        console2.log("Transaction ID:", txId);
        console2.log("Transaction Type:", uint(txType));
        console2.log("Target Address:", target);
        console2.log("Amount:", amount);
        console2.log("Executed:", executed);
        console2.log("Confirmations:", confirmations);
        
    }
    
    function test_MintExecution() public {
        // Signer 1 submits mint
        vm.prank(signer1);
        uint256 txId = token.submitMint(recipient, 1000 * 10**18);
        
        // Check recipient balance before
        assertEq(token.balanceOf(recipient), 0);
        
        // Signer 2 confirms (should auto-execute)
        vm.prank(signer2);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txId);
        token.confirmTransaction(txId);
        
        // Check execution results
        (,,,,,bool executed,) = token.getTransaction(txId);
        assertTrue(executed);
        assertEq(token.balanceOf(recipient), 1000 * 10**18);
        assertEq(token.totalSupply(), 10_000_000_000 * 10**18 + 1000 * 10**18);
    }
    
    function test_MintRevertZeroAddress() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidRecipient.selector);
        token.submitMint(address(0), 1000 * 10**18);
    }
    
    // ============ Burn Tests (NEW) ============
    
    function test_SubmitBurn() public {
        // First, transfer some tokens to recipient for burning
        vm.prank(deployer);
        token.transfer(recipient, 2000 * 10**18);
        
        vm.prank(signer1);
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(0, ERC20Token.TransactionType.BURN, signer1);
        uint256 txId = token.submitBurn(recipient, 1000 * 10**18);
        
        assertEq(txId, 0);
        assertEq(token.getTransactionCount(), 1);
        
        (
            ERC20Token.TransactionType txType,
            address target,
            uint256 amount,
            ,  // string memory data1 - unused
            ,  // string memory data2 - unused
            bool executed,
            uint256 confirmations
        ) = token.getTransaction(txId);
        
        assertEq(uint(txType), uint(ERC20Token.TransactionType.BURN));
        assertEq(target, recipient);
        assertEq(amount, 1000 * 10**18);
        assertEq(executed, false);
        assertEq(confirmations, 1);
        assertTrue(token.isTransactionConfirmed(txId, signer1));
    }
    
    function test_BurnExecution() public {
        // First, transfer some tokens to recipient for burning
        vm.prank(deployer);
        token.transfer(recipient, 2000 * 10**18);
        
        uint256 initialBalance = token.balanceOf(recipient);
        uint256 initialSupply = token.totalSupply();
        uint256 burnAmount = 1000 * 10**18;
        
        // Signer 1 submits burn
        vm.prank(signer1);
        uint256 txId = token.submitBurn(recipient, burnAmount);
        
        // Signer 2 confirms (should auto-execute)
        vm.prank(signer2);
        vm.expectEmit(true, false, false, true);
        emit TokensBurned(recipient, burnAmount);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txId);
        token.confirmTransaction(txId);
        
        // Check execution results
        (,,,,,bool executed,) = token.getTransaction(txId);
        assertTrue(executed);
        assertEq(token.balanceOf(recipient), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
    }
    
    function test_BurnRevertZeroAddress() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidRecipient.selector);
        token.submitBurn(address(0), 1000 * 10**18);
    }
    
    function test_BurnRevertZeroAmount() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidBurnAmount.selector);
        token.submitBurn(recipient, 0);
    }
    
    function test_BurnRevertInsufficientBalance() public {
        // Recipient has no tokens
        assertEq(token.balanceOf(recipient), 0);
        
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidBurnAmount.selector);
        token.submitBurn(recipient, 1000 * 10**18);
    }
    
    // ============ Pause/Unpause Tests ============
    
    function test_PauseUnpause() public {
        // Submit pause
        vm.prank(signer1);
        uint256 pauseTxId = token.submitPause();
        
        // Confirm pause with signer2
        vm.prank(signer2);
        token.confirmTransaction(pauseTxId);
        
        // Check paused state
        assertTrue(token.paused());
        
        // Try to transfer while paused (should fail)
        vm.prank(deployer);
        vm.expectRevert();
        token.transfer(recipient, 100 * 10**18);
        
        // Submit unpause
        vm.prank(signer1);
        uint256 unpauseTxId = token.submitUnpause();
        
        // Confirm unpause with signer3
        vm.prank(signer3);
        token.confirmTransaction(unpauseTxId);
        
        // Check unpaused state
        assertFalse(token.paused());
        
        // Transfer should work now
        vm.prank(deployer);
        token.transfer(recipient, 100 * 10**18);
        assertEq(token.balanceOf(recipient), 100 * 10**18);
    }
    
    // ============ Update Name/Symbol Tests ============
    
    function test_UpdateNameAndSymbol() public {
        // Submit update
        vm.prank(signer1);
        uint256 txId = token.submitUpdateNameAndSymbol("New Token Name", "NTN");
        
        // Check values before execution
        assertEq(token.name(), "Test Dynamic Multisig Token");
        assertEq(token.symbol(), "TDMT");
        
        // Confirm with signer2
        vm.prank(signer2);
        token.confirmTransaction(txId);
        
        // Check updated values
        assertEq(token.name(), "New Token Name");
        assertEq(token.symbol(), "NTN");
    }
    
    // ============ Replace Signer Tests ============
    
    function test_ReplaceSigner() public {
        address newSigner = makeAddr("newSigner");
        
        // Submit replace signer
        vm.prank(signer1);
        uint256 txId = token.submitReplaceSigner(signer3, newSigner);
        
        // Verify old state
        assertTrue(token.isSigner(signer3));
        assertFalse(token.isSigner(newSigner));
        
        // Confirm with signer2
        vm.prank(signer2);
        vm.expectEmit(true, true, false, true);
        emit SignerReplaced(signer3, newSigner);
        token.confirmTransaction(txId);
        
        // Verify new state
        assertFalse(token.isSigner(signer3));
        assertTrue(token.isSigner(newSigner));
        
        address[] memory signers = token.getSigners();
        assertEq(signers[2], newSigner);
    }
    
    function test_ReplaceSigner_RevertInvalidOldSigner() public {
        address newSigner = makeAddr("newSigner");
        
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        token.submitReplaceSigner(nonSigner, newSigner);
    }
    
    function test_ReplaceSigner_RevertAlreadySigner() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        token.submitReplaceSigner(signer3, signer2);
    }
    
    function test_ReplaceSigner_RevertZeroAddress() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        token.submitReplaceSigner(signer3, address(0));
    }
    
    // ============ Add Signer Tests ============
    
    function test_AddSigner() public {
        address newSigner = makeAddr("newSigner");
        
        // Initial state
        assertEq(token.getSignerCount(), 3);
        assertFalse(token.isSigner(newSigner));
        
        // Submit add signer
        vm.prank(signer1);
        uint256 txId = token.submitAddSigner(newSigner);
        
        // Confirm with signer2
        vm.prank(signer2);
        vm.expectEmit(true, false, false, true);
        emit SignerAdded(newSigner);
        token.confirmTransaction(txId);
        
        // Verify new state
        assertEq(token.getSignerCount(), 4);
        assertTrue(token.isSigner(newSigner));
        
        address[] memory signers = token.getSigners();
        assertEq(signers[3], newSigner);
    }
    
    function test_AddSigner_RevertAlreadySigner() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        token.submitAddSigner(signer2);
    }
    
    function test_AddSigner_RevertZeroAddress() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        token.submitAddSigner(address(0));
    }
    
    // ============ Remove Signer Tests ============
    
    function test_RemoveSigner() public {
        // Initial state
        assertEq(token.getSignerCount(), 3);
        assertTrue(token.isSigner(signer3));
        
        // Submit remove signer
        vm.prank(signer1);
        uint256 txId = token.submitRemoveSigner(signer3);
        
        // Confirm with signer2
        vm.prank(signer2);
        vm.expectEmit(true, false, false, true);
        emit SignerRemoved(signer3);
        token.confirmTransaction(txId);
        
        // Verify new state
        assertEq(token.getSignerCount(), 2);
        assertFalse(token.isSigner(signer3));
        
        // Verify signer3 was removed from array
        address[] memory signers = token.getSigners();
        assertEq(signers.length, 2);
        // The last signer should have replaced signer3's position
        assertTrue(signers[0] == signer1 || signers[1] == signer1);
        assertTrue(signers[0] == signer2 || signers[1] == signer2);
    }
    
    function test_RemoveSigner_RevertNotSigner() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidSigner.selector);
        token.submitRemoveSigner(nonSigner);
    }
    
   function test_RemoveSigner_RevertLastSigner() public {
    // First remove signer3 to get to 2 signers
    vm.prank(signer1);
    uint256 txId1 = token.submitRemoveSigner(signer3);
    vm.prank(signer2);
    token.confirmTransaction(txId1);
    
    // Verify we now have 2 signers
    assertEq(token.getSignerCount(), 2);
    
    // Now reduce the threshold to 1 first, so we can remove another signer
    vm.prank(signer1);
    uint256 thresholdTxId = token.submitUpdateThreshold(1);
    vm.prank(signer2);
    token.confirmTransaction(thresholdTxId);
    
    // Verify threshold is now 1
    assertEq(token.getRequiredConfirmations(), 1);
    
    // Now remove signer2 to get to 1 signer
    vm.prank(signer1);
     token.submitRemoveSigner(signer2);
    // Since threshold is 1, signer1's confirmation is enough
    
    // Verify we now have 1 signer
    assertEq(token.getSignerCount(), 1);
    
    // Now try to remove the last signer - this should fail
    vm.prank(signer1);
    vm.expectRevert(ERC20Token.CannotRemoveLastSigner.selector);
    token.submitRemoveSigner(signer1);
}
    
    function test_RemoveSigner_RevertBreakThreshold() public {
        // Add a 4th signer first, then set threshold to 4
        address newSigner = makeAddr("newSigner");
        vm.prank(signer1);
        uint256 addTxId = token.submitAddSigner(newSigner);
        vm.prank(signer2);
        token.confirmTransaction(addTxId);
        
        // Update threshold to 4
        vm.prank(signer1);
        uint256 thresholdTxId = token.submitUpdateThreshold(4);
        vm.prank(signer2);
        token.confirmTransaction(thresholdTxId);
        
        // Now try to remove a signer (would leave 3 signers but need 4 confirmations)
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.ThresholdTooHigh.selector);
        token.submitRemoveSigner(signer3);
    }
    
    // ============ Update Threshold Tests ============
    
    function test_UpdateThreshold() public {
        assertEq(token.getRequiredConfirmations(), 2);
        
        // Submit threshold update
        vm.prank(signer1);
        uint256 txId = token.submitUpdateThreshold(3);
        
        // Confirm with signer2
        vm.prank(signer2);
        vm.expectEmit(false, false, false, true);
        emit ThresholdUpdated(2, 3);
        token.confirmTransaction(txId);
        
        // Verify new threshold
        assertEq(token.getRequiredConfirmations(), 3);
    }
    
    function test_UpdateThreshold_RevertInvalidThreshold() public {
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidThreshold.selector);
        token.submitUpdateThreshold(0);
        
        vm.prank(signer1);
        vm.expectRevert(ERC20Token.InvalidThreshold.selector);
        token.submitUpdateThreshold(4); // More than current signers
    }
    
    // ============ Confirmation Tests ============
    
    function test_ConfirmTransaction() public {
        // Signer1 submits
        vm.prank(signer1);
        uint256 txId = token.submitMint(recipient, 1000 * 10**18);
        
        // Signer2 confirms
        vm.prank(signer2);
        vm.expectEmit(true, true, false, true);
        emit TransactionConfirmed(txId, signer2);
        token.confirmTransaction(txId);
        
        assertTrue(token.isTransactionConfirmed(txId, signer2));
    }
    
    function test_ConfirmTransaction_RevertNonSigner() public {
        vm.prank(signer1);
        uint256 txId = token.submitMint(recipient, 1000 * 10**18);
        
        vm.prank(nonSigner);
        vm.expectRevert(ERC20Token.NotASigner.selector);
        token.confirmTransaction(txId);
    }
    
    function test_RevokeConfirmation() public {
        // Signer1 submits
        vm.prank(signer1);
        uint256 txId = token.submitMint(recipient, 1000 * 10**18);
        
        assertTrue(token.isTransactionConfirmed(txId, signer1));
        (,,,,,, uint256 confirmations) = token.getTransaction(txId);
        assertEq(confirmations, 1);
        
        // Signer1 revokes
        vm.prank(signer1);
        vm.expectEmit(true, true, false, true);
        emit TransactionRevoked(txId, signer1);
        token.revokeConfirmation(txId);
        
        assertFalse(token.isTransactionConfirmed(txId, signer1));
        (,,,,,, confirmations) = token.getTransaction(txId);
        assertEq(confirmations, 0);
    }
    
    // ============ View Functions Tests ============
    
    function test_GetPendingTransactions() public {
        // Create multiple transactions
        vm.prank(signer1);
        uint256 tx1 = token.submitMint(recipient, 1000 * 10**18);
        
        vm.prank(signer2);
        uint256 tx2 = token.submitPause();
        
        vm.prank(signer3);
        uint256 tx3 = token.submitUnpause();
        
        // Debug: Check initial state
        console2.log("=== Initial State ===");
        console2.log("tx1:", tx1);
        console2.log("tx2:", tx2);
        console2.log("tx3:", tx3);
        
        // Get pending transactions
        uint256[] memory pending = token.getPendingTransactions();
        console2.log("Initial pending length:", pending.length);
        for (uint256 i = 0; i < pending.length; i++) {
            console2.log("pending[", i, "]:", pending[i]);
        }
        
        assertEq(pending.length, 3);
        assertEq(pending[0], tx1);
        assertEq(pending[1], tx2);
        assertEq(pending[2], tx3);
        
        // Check confirmation states before execution
        console2.log("=== Before Confirmation ===");
        (,,,,,bool executed1, uint256 confirmations1) = token.getTransaction(tx1);
        (,,,,,bool executed2, uint256 confirmations2) = token.getTransaction(tx2);
        (,,,,,bool executed3, uint256 confirmations3) = token.getTransaction(tx3);
        
        console2.log("tx1 executed:", executed1, "confirmations:", confirmations1);
        console2.log("tx2 executed:", executed2, "confirmations:", confirmations2);
        console2.log("tx3 executed:", executed3, "confirmations:", confirmations3);
        
        // Execute one transaction by having signer3 confirm tx1
        vm.prank(signer3);
        token.confirmTransaction(tx1); // This should execute tx1
        
        // Check states after execution
        console2.log("=== After Confirmation ===");
        (,,,,,executed1, confirmations1) = token.getTransaction(tx1);
        (,,,,,executed2, confirmations2) = token.getTransaction(tx2);
        (,,,,,executed3, confirmations3) = token.getTransaction(tx3);
        
        console2.log("tx1 executed:", executed1, "confirmations:", confirmations1);
        console2.log("tx2 executed:", executed2, "confirmations:", confirmations2);
        console2.log("tx3 executed:", executed3, "confirmations:", confirmations3);
        
        // Check pending again
        pending = token.getPendingTransactions();
        console2.log("Final pending length:", pending.length);
        for (uint256 i = 0; i < pending.length; i++) {
            console2.log("pending[", i, "]:", pending[i]);
        }
        
        // tx1 should be executed, tx2 and tx3 should still be pending
        assertTrue(executed1, "tx1 should be executed");
        assertFalse(executed2, "tx2 should not be executed");
        assertFalse(executed3, "tx3 should not be executed");
        
        assertEq(pending.length, 2, "Should have 2 pending transactions");
        // After removing tx1, the array uses swap-and-pop, so order may change
        assertTrue(pending[0] == tx2 || pending[0] == tx3, "First pending should be tx2 or tx3");
        assertTrue(pending[1] == tx2 || pending[1] == tx3, "Second pending should be tx2 or tx3");
        assertTrue(pending[0] != pending[1], "Pending transactions should be different");
    }
    
    function test_GetMultisigConfig() public view {
        (uint256 required, uint256 total) = token.getMultisigConfig();
        assertEq(required, 2);
        assertEq(total, 3);
    }
    
    function test_GetPendingTransactionCount() public {
        // Initially no pending transactions
        assertEq(token.getPendingTransactionCount(), 0);
        
        // Create some transactions
        vm.prank(signer1);
        token.submitMint(recipient, 1000 * 10**18);
        assertEq(token.getPendingTransactionCount(), 1);
        
        vm.prank(signer2);
        token.submitPause();
        assertEq(token.getPendingTransactionCount(), 2);
    }
    
    // ============ Complex Workflow Tests ============
    
    function test_DynamicMultisigWorkflow() public {
        // 1. Start with 3 signers, 2 required
        assertEq(token.getSignerCount(), 3);
        assertEq(token.getRequiredConfirmations(), 2);
        
        // 2. Add a 4th signer
        address signer4 = makeAddr("signer4");
        vm.prank(signer1);
        uint256 addTxId = token.submitAddSigner(signer4);
        vm.prank(signer2);
        token.confirmTransaction(addTxId);
        
        assertEq(token.getSignerCount(), 4);
        assertTrue(token.isSigner(signer4));
        
        // 3. Update threshold to 3-of-4
        vm.prank(signer1);
        uint256 thresholdTxId = token.submitUpdateThreshold(3);
        vm.prank(signer2);
        token.confirmTransaction(thresholdTxId);
        
        assertEq(token.getRequiredConfirmations(), 3);
        
        // 4. Now a mint transaction requires 3 confirmations
        vm.prank(signer1);
        uint256 mintTxId = token.submitMint(recipient, 5000 * 10**18);
        
        // Two confirmations shouldn't execute
        vm.prank(signer2);
        token.confirmTransaction(mintTxId);
        
        (,,,,,bool executed,) = token.getTransaction(mintTxId);
        assertFalse(executed);
        
        // Third confirmation should execute
        vm.prank(signer3);
        token.confirmTransaction(mintTxId);
        
        (,,,,,executed,) = token.getTransaction(mintTxId);
        assertTrue(executed);
        assertEq(token.balanceOf(recipient), 5000 * 10**18);
        
        // 5. Remove a signer (signer4)
        vm.prank(signer1);
        uint256 removeTxId = token.submitRemoveSigner(signer4);
        vm.prank(signer2);
        token.confirmTransaction(removeTxId);
        vm.prank(signer3);
        token.confirmTransaction(removeTxId);
        
        assertEq(token.getSignerCount(), 3);
        assertFalse(token.isSigner(signer4));
        
        // 6. Reduce threshold back to 2
        vm.prank(signer1);
        uint256 reduceTxId = token.submitUpdateThreshold(2);
        vm.prank(signer2);
        token.confirmTransaction(reduceTxId);
        
        // Third confirmation should still be needed since threshold hasn't changed yet
        vm.prank(signer3);
        token.confirmTransaction(reduceTxId);
        
        assertEq(token.getRequiredConfirmations(), 2);
    }
    
    // ============ Complex Burn Workflow Test (NEW) ============
    
    function test_BurnWorkflow() public {
        // 1. Transfer tokens to multiple addresses
        vm.startPrank(deployer);
        token.transfer(signer1, 5000 * 10**18);
        token.transfer(signer2, 3000 * 10**18);
        token.transfer(recipient, 2000 * 10**18);
        vm.stopPrank();
        
        uint256 initialSupply = token.totalSupply();
        
        // 2. Submit burn from signer1's balance
        vm.prank(signer1);
        uint256 burnTx1 = token.submitBurn(signer1, 1000 * 10**18);
        
        // 3. Submit burn from recipient's balance
        vm.prank(signer2);
        uint256 burnTx2 = token.submitBurn(recipient, 500 * 10**18);
        
        // 4. Execute first burn
        vm.prank(signer3);
        token.confirmTransaction(burnTx1);
        
        assertEq(token.balanceOf(signer1), 4000 * 10**18);
        assertEq(token.totalSupply(), initialSupply - 1000 * 10**18);
        
        // 5. Execute second burn
        vm.prank(signer1);
        token.confirmTransaction(burnTx2);
        
        assertEq(token.balanceOf(recipient), 1500 * 10**18);
        assertEq(token.totalSupply(), initialSupply - 1500 * 10**18);
    }
    
    // ============ ERC20 Functionality Tests ============
    
    function test_Transfer() public {
        uint256 amount = 1000 * 10**18;
        
        vm.prank(deployer);
        token.transfer(recipient, amount);
        
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), token.totalSupply() - amount);
    }
    
    function test_Burn() public {
        uint256 burnAmount = 1000 * 10**18;
        uint256 initialSupply = token.totalSupply();
        
        vm.prank(deployer);
        token.burn(burnAmount);
        
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(deployer), initialSupply - burnAmount);
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_MintAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint256).max / 2);
        
        vm.prank(signer1);
        uint256 txId = token.submitMint(recipient, amount);
        
        vm.prank(signer2);
        token.confirmTransaction(txId);
        
        assertEq(token.balanceOf(recipient), amount);
    }
    
    function testFuzz_BurnAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 * 10**18);
        
        // First transfer tokens to recipient
        vm.prank(deployer);
        token.transfer(recipient, 1000 * 10**18);
        
        uint256 initialBalance = token.balanceOf(recipient);
        uint256 initialSupply = token.totalSupply();
        
        vm.prank(signer1);
        uint256 txId = token.submitBurn(recipient, amount);
        
        vm.prank(signer2);
        token.confirmTransaction(txId);
        
        assertEq(token.balanceOf(recipient), initialBalance - amount);
        assertEq(token.totalSupply(), initialSupply - amount);
    }
    
    function testFuzz_ThresholdUpdate(uint8 newThreshold) public {
        vm.assume(newThreshold >= 1 && newThreshold <= 3);
        
        vm.prank(signer1);
        uint256 txId = token.submitUpdateThreshold(newThreshold);
        
        vm.prank(signer2);
        token.confirmTransaction(txId);
        
        assertEq(token.getRequiredConfirmations(), newThreshold);
    }
}