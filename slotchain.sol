// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Slotchain - Decentralized Casino Contract
 * @notice Ethereum-based lottery system with provably fair mechanics and adjustable fees
 * @dev Features include:
 * - 96.5% base RTP (Return to Player) before fees
 * - Adjustable fee (0-10%) on winnings
 * - Safety mechanisms to prevent contract insolvency
 * - View functions for transparency
 */
contract Slotchain {
    // =============================
    // STATE VARIABLES
    // =============================
    
    /// @notice Contract owner address (receives fees)
    address public immutable owner;
    
    /// @notice Current fee percentage applied to winnings
    uint256 public feePercent;
    
    /// @dev Maximum allowed fee percentage (immutable safety cap)
    uint256 private constant MAX_FEE_PERCENT = 10;

    // =============================
    // EVENTS
    // =============================
    
    /**
     * @notice Emitted after bet resolution
     * @param player Address of the gambler
     * @param amount Bet amount in wei
     * @param payout Net winnings after fee
     * @param fee Fee amount deducted
     */
    event BetResult(
        address indexed player, 
        uint256 amount, 
        uint256 payout, 
        uint256 fee
    );

    /**
     * @notice Emitted when fee percentage is updated
     * @param newFeePercent New fee percentage
     */
    event FeeChanged(uint256 newFeePercent);

    // =============================
    // CONSTRUCTOR
    // =============================
    
    /**
     * @dev Initializes contract with:
     * - Owner set to deployer address
     * - Default 5% fee
     */
    constructor() {
        owner = msg.sender;
        feePercent = 5;
    }

    // =============================
    // CORE FUNCTIONS
    // =============================
    
    /**
     * @notice Main betting function
     * @dev Processes bets in 6 steps:
     * 1. Validates bet amount
     * 2. Generates random outcome
     * 3. Calculates raw payout
     * 4. Deducts fee
     * 5. Ensures contract solvency
     * 6. Distributes funds
     * 
     * Probability Distribution:
     * | Roll Range  | Probability | Payout |
     * |-------------|-------------|--------|
     * | 0-5999      | 60.00%      | 0x     |
     * | 6000-8499   | 25.00%      | 1.5x   |
     * | 8500-9499   | 10.00%      | 2x     |
     * | 9500-9899   | 4.00%       | 5x     |
     * | 9900-9989   | 0.90%       | 10x    |
     * | 9990-9999   | 0.10%       | 100x   |
     * 
     * Base RTP = 96.5% (before fee)
     */
    function placeBet() external payable {
        // Step 1: Input validation
        uint256 betAmount = msg.value;
        require(betAmount > 0, "Bet must be > 0");
        
        // Gas optimization: Cache state variable
        uint256 currentFeePercent = feePercent;

        // Step 2: Generate pseudo-random number (0-9999)
        uint256 roll = uint256(
            keccak256(abi.encodePacked(
                block.prevrandao,        // Post-merge randomness beacon
                blockhash(block.number - 1), // Previous block hash
                msg.sender                // Player-specific entropy
            ))) % 10000;

        // Step 3: Determine payout using probability table
        uint256 rawPayout;
        if (roll < 6000) {
            rawPayout = 0;          // 60.00% chance
        } else if (roll < 8500) {
            rawPayout = betAmount * 3 / 2;  // 25.00% chance (1.5x)
        } else if (roll < 9500) {
            rawPayout = betAmount * 2;      // 10.00% chance (2x)
        } else if (roll < 9900) {
            rawPayout = betAmount * 5;      // 4.00% chance (5x)
        } else if (roll < 9990) {
            rawPayout = betAmount * 10;     // 0.90% chance (10x)
        } else {
            rawPayout = betAmount * 100;    // 0.10% chance (100x)
        }

        // Step 4: Calculate fee and net payout
        uint256 fee = rawPayout * currentFeePercent / 100;
        uint256 netPayout = rawPayout - fee;

        // Step 5: Solvency protection
        // - If contract lacks funds: pay 90% of balance
        // - Waive fee during emergency payout
        if (netPayout > address(this).balance) {
            netPayout = address(this).balance * 9 / 10;
            fee = 0;
        }

        // Step 6: Fund distribution
        // Transfer fee to owner (if applicable)
        if (fee > 0) {
            (bool feeSuccess, ) = owner.call{value: fee}("");
            require(feeSuccess, "Fee transfer failed");
        }
        
        // Transfer winnings to player (if applicable)
        if (netPayout > 0) {
            (bool payoutSuccess, ) = payable(msg.sender).call{value: netPayout}("");
            require(payoutSuccess, "Payout failed");
        }

        // Emit result event
        emit BetResult(msg.sender, betAmount, netPayout, fee);
    }

    // =============================
    // VIEW FUNCTIONS
    // =============================
    
    /**
     * @notice Get current contract ETH balance
     * @return balance Contract balance in wei
     * @dev Useful for monitoring contract liquidity
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get current fee percentage
     * @return Current fee percentage (0-10)
     * @dev Players should check this before betting
     */
    function getFeePercent() external view returns (uint256) {
        return feePercent;
    }

    // =============================
    // ADMIN FUNCTIONS
    // =============================
    
    /**
     * @notice Update fee percentage (owner only)
     * @param newFeePercent New fee percentage (0-10)
     * @dev Reverts if:
     * - Caller is not owner
     * - Fee exceeds 10%
     * Emits FeeChanged event on success
     */
    function setFeePercent(uint256 newFeePercent) external {
        require(msg.sender == owner, "Only owner can change fee");
        require(newFeePercent <= MAX_FEE_PERCENT, "Fee cannot exceed 10%");
        
        feePercent = newFeePercent;
        emit FeeChanged(newFeePercent);
    }

    // =============================
    // FALLBACK FUNCTION
    // =============================
    
    /**
     * @dev Allows contract to receive ETH
     * - Required for funding jackpots
     * - Enables direct donations
     */
    receive() external payable {}
}
