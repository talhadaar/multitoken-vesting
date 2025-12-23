# MultiTokenVesting

A gas-optimized, multi-token vesting contract written in Solidity. This contract allows an admin (Owner) to create revocable, linear vesting schedules with optional cliffs for multiple beneficiaries across different ERC20 tokens.

## ⚡ Features

* **Multi-Token Support:** One contract can handle vesting for any number of different ERC20 tokens (USDC, WETH, UNI, etc.).
* **Revocable:** The Owner can revoke a schedule at any time.
* **Vested** tokens are immediately sent to the beneficiary.
* **Unvested** tokens are refunded to the Owner.


* **Gas Optimized:**
* **Packed Structs:** Booleans (`revoked`, `claimed`) and addresses are tightly packed to save storage costs.
* **Custom Errors:** Uses `error ScheduleWasRevoked()` instead of expensive string revert messages.
* **Direct Indexing:** Uses array indices for O(1) gas efficiency during claims.


* **Linear Vesting:** Tokens vest linearly over a duration, starting after a defined cliff.

## 🪙 Supported Tokens

This contract is designed exclusively for **ERC20 tokens**.

* **Supported:** Any standard ERC20 token (e.g., USDC, UNI, LINK, WETH).
* **Not Supported:** Native chain currencies (e.g., AGNG, PEAQ) are **not supported directly**.

---

## 📐 Vesting Logic

The vesting logic follows a standard linear release schedule:

1. **Before Cliff:** 0 tokens are releasable.
2. **After Cliff, Before End:** Tokens are released linearly based on time passed since `start`.
3. **After End:** 100% of tokens are releasable.

**Formula:**

```text
VestedAmount = (TotalAmount * (CurrentTime - StartTime)) / Duration

```

### Example Scenario

* **Total:** 1,000 Tokens
* **Duration:** 1,000 Seconds
* **Cliff:** 250 Seconds (25%)

| Time (s) | Status | Vested Amount |
| --- | --- | --- |
| 0s | Started | 0 |
| 200s | Inside Cliff | 0 |
| 250s | Cliff Ends | 250 (25%) |
| 500s | Linear Vesting | 500 (50%) |
| 1000s | Finished | 1,000 (100%) |

---

## 🚀 Installation & Setup

This project uses **Foundry**. Ensure you have [Foundry installed](https://book.getfoundry.sh/getting-started/installation).

### 1. Clone the Repo

```bash
git clone <your-repo-url>
cd multi-token-vesting

```

### 2. Install Dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit

```

### 3. Build

```bash
forge build

```

### 4. Run Tests

```bash
forge test -vv

```

---

## 🛠 Usage

### 1. Creating a Schedule (Owner Only)

Only the contract owner can create new schedules. The owner must have approved the Vesting Contract to spend the tokens beforehand.

```solidity
vestingContract.createVestingSchedule(
    0xBeneficiary...,   // Beneficiary Address
    0xToken...,         // Token Address
    1000 * 10**18,      // Amount
    block.timestamp,    // Start Time
    2592000,            // Cliff Duration (e.g., 30 days)
    31536000            // Total Duration (e.g., 1 year)
);

```

### 2. Claiming Tokens (Beneficiary Only)

Beneficiaries claim their available tokens by passing the `scheduleIndex`.

```solidity
// The index is emitted in the ScheduleCreated event
uint256 scheduleIndex = 0; 
vestingContract.claim(scheduleIndex);

```

### 3. Revoking a Schedule (Owner Only)

The owner can stop a schedule early.

```solidity
vestingContract.revoke(scheduleIndex);

```

* **Result:** The beneficiary receives all tokens earned *up to this exact second*. The remaining tokens are sent back to the Owner's wallet.

### 4. Reading Data

```solidity
// Check claimable amount
uint256 amount = vestingContract.calculateReleasableAmount(scheduleIndex);

// Get User's Schedules
uint256 count = vestingContract.getScheduleCountByUser(userAddress);
VestingSchedule memory schedule = vestingContract.getScheduleByUserAtIndex(userAddress, 0);

```

---

## 📦 API Reference

### Structs

The `VestingSchedule` struct is packed to minimize storage costs.

```solidity
struct VestingSchedule {
    address beneficiary;    // Address of the user
    uint64 start;           // Start timestamp
    bool revoked;           // Has the schedule been revoked?
    bool claimed;           // Have all tokens been claimed?
    address token;          // Token contract address
    uint64 duration;        // Duration of vesting in seconds
    uint64 cliff;           // Cliff duration in seconds
    uint256 totalAmount;    // Total tokens allocated
    uint256 amountClaimed;  // Total tokens withdrawn so far
}

```

### Errors

| Error | Description |
| --- | --- |
| `InvalidAddress` | Beneficiary or Token address is `address(0)`. |
| `InvalidAmount` | Vesting amount is 0. |
| `InvalidDuration` | Duration is 0. |
| `InvalidCliff` | Cliff is longer than the Duration. |
| `Unauthorized` | Caller is not the beneficiary. |
| `ScheduleClaimed` | All tokens have already been claimed. |
| `NothingToClaim` | Current releasable amount is 0 (e.g., inside cliff). |
| `InvalidIndex` | The provided schedule index does not exist. |
| `ScheduleWasRevoked` | The schedule has been revoked and is closed. |

---

## 🛡 Security & Audit Info

* **Solidity Version:** `^0.8.20`
* **Centralization Risk:** This contract allows the Owner to **revoke** schedules. This means beneficiaries must trust the Owner not to revoke schedules maliciously.
* **SafeMath:** Not required (Solidity 0.8+ has built-in overflow protection).
* **SafeERC20:** Used for all token transfers to handle non-compliant ERC20s (tokens that don't return bools).
* **Reentrancy:** The `claim` function follows the **Checks-Effects-Interactions** pattern, updating state before transferring tokens.

---

## 📜 License

SPDX-License-Identifier: MIT