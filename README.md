# MultiTokenVesting

A gas-optimized, multi-token vesting contract written in Solidity. This contract allows an admin (Owner) to create linear vesting schedules with optional cliffs for multiple beneficiaries across different ERC20 tokens.

## ⚡ Features

* **Multi-Token Support:** One contract can handle vesting for any number of different ERC20 tokens (USDC, WETH, UNI, etc.).
* **Gas Optimized:**
* Uses **Custom Errors** (`error InvalidIndex()`) instead of expensive string revert messages.
* **Direct Indexing:** Removes redundant `keccak256` ID hashing; uses array indices for O(1) gas efficiency during claims.


* **Linear Vesting:** Tokens vest linearly over a duration, starting after a defined cliff.
* **Safety:**
* Uses OpenZeppelin's `SafeERC20` for reliable token transfers.
* Protected by `Ownable` for administrative actions.
* Checks for zero-address and zero-amount inputs.



## 🪙 Supported Tokens

This contract is designed exclusively for **ERC20 tokens**.

* **Supported:** Any standard ERC20 token (e.g., USDC, UNI, LINK, WETH).
* **Not Supported:** Native chain currencies (e.g., ETH, MATIC, BNB, SOL) are **not supported directly**.

### How to Vest Native Tokens (ETH, MATIC, etc.)

To vest native assets, you must **wrap** them first. This ensures maximum security and compatibility with the contract's standard logic.

1. **Wrap:** Convert your Native ETH to **Wrapped ETH (WETH)** via the canonical WETH contract on your chain.
2. **Approve:** Approve the Vesting contract to spend your WETH.
3. **Create:** Call `createVestingSchedule` using the WETH contract address.
4. **Claim:** Beneficiaries claim WETH, which they can unwrap back to ETH 1:1 at any time.

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

* **Cliff:** A duration (in seconds) during which no tokens can be claimed. Once the cliff passes, the tokens for that elapsed time vest immediately.
* **Duration:** The total time (in seconds) for the vesting period.

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
// Params:
// 1. Beneficiary Address
// 2. Token Address
// 3. Amount (in Wei)
// 4. Start Timestamp (Unix Epoch)
// 5. Cliff Duration (Seconds)
// 6. Total Duration (Seconds)

vestingContract.createVestingSchedule(
    0x123...,           // Beneficiary
    0xToken...,         // Token Address
    1000 * 10**18,      // 1000 Tokens
    block.timestamp,    // Start Now
    2592000,            // 30 Day Cliff
    31536000            // 1 Year Duration
);

```

* **Returns:** `uint256 index` (The ID of the schedule).
* **Emits:** `ScheduleCreated(uint256 indexed scheduleIndex, ...)`

### 2. Claiming Tokens (Beneficiary Only)

Beneficiaries claim their available tokens by passing the `scheduleIndex`.

```solidity
// The index is the one emitted in the ScheduleCreated event
uint256 scheduleIndex = 0; 

vestingContract.claim(scheduleIndex);

```

* **Emits:** `TokensClaimed(address indexed beneficiary, uint256 indexed scheduleIndex, uint256 amount)`

### 3. Reading Data

**Get Releasable Amount:**
Check how many tokens are currently waiting to be claimed.

```solidity
uint256 amount = vestingContract.calculateReleasableAmount(scheduleIndex);

```

**Get User's Schedules:**

```solidity
// Get total count of schedules for a user
uint256 count = vestingContract.getScheduleCountByUser(userAddress);

// Get specific schedule details
VestingSchedule memory schedule = vestingContract.getScheduleByUserAtIndex(userAddress, 0);

```

---

## 📦 API Reference

### Structs

```solidity
struct VestingSchedule {
    address beneficiary;
    uint64 start;
    address token;
    uint64 duration;
    uint64 cliff;
    uint256 totalAmount;
    uint256 amountClaimed;
}

```

### Errors

| Error | Description |
| --- | --- |
| `InvalidAddress` | Beneficiary or Token address is `address(0)`. |
| `InvalidAmount` | Vesting amount is 0. |
| `InvalidDuration` | Duration is 0. |
| `InvalidCliff` | Cliff is longer than the Duration. |
| `Unauthorized` | Caller is not the beneficiary of the schedule. |
| `ScheduleClaimed` | All tokens have already been claimed. |
| `NothingToClaim` | Current releasable amount is 0 (e.g., inside cliff). |
| `InvalidIndex` | The provided schedule index does not exist. |

---

## 🛡 Security & Audit Info

* **Solidity Version:** `^0.8.20`
* **SafeMath Not Required:** This contract uses Solidity 0.8.0+, which includes built-in overflow/underflow protection for arithmetic operations. External `SafeMath` libraries are redundant and would waste gas.
* **SafeERC20:** Used for all token transfers to handle non-compliant ERC20s (tokens that don't return bools).
* **Reentrancy:** Not explicitly used (no `ReentrancyGuard`) because `claim` follows the **Checks-Effects-Interactions** pattern:
1. **Check:** Releasable > 0.
2. **Effect:** `schedule.amountClaimed` is updated *before* transfer.
3. **Interaction:** Tokens are transferred.



---

## 📜 License
### TODO