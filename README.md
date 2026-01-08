# BondMM-A on Mantle Network - Complete Development Reference

## Project Overview

BondMM-A is a **decentralized fixed-income Automated Market Maker (AMM)** that enables **fixed-rate lending and borrowing for arbitrary maturities within a single liquidity pool**. This is a 7-day MVP deployment on Mantle Network based on peer-reviewed research.

**One-line pitch:** BondMM-A is the first AMM that brings real bond markets on-chain — fixed rates, any maturity, one pool.

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Core Mathematical Foundation](#core-mathematical-foundation)
3. [System Architecture](#system-architecture)
4. [Smart Contract Design](#smart-contract-design)
5. [7-Day Development Plan](#7-day-development-plan)
6. [Setup Instructions](#setup-instructions)
7. [Core Features Implementation](#core-features-implementation)
8. [Testing Strategy](#testing-strategy)
9. [Deployment Guide](#deployment-guide)
10. [Security Considerations](#security-considerations)

---

## Problem Statement

### Why BondMM-A Matters

- **Global bond market**: $141T (larger than $115T equity market)
- **DeFi lending market**: $54.6B but lacks true fixed-income products
- **Current limitations**:
  - Variable-rate dominance (Aave, Compound, MakerDAO)
  - Single-maturity fixed-rate designs (Yield, Notional)
  - Liquidity fragmentation across tenors
  - Poor capital efficiency for LPs
  - Pricing instability and negative-rate edge cases

### The Core Challenge

Time introduces complexity:
- Interest depends on time-to-maturity
- Bond prices evolve continuously
- LPs face duration risk
- AMMs must remain solvent under all maturities

**BondMM-A solves this structurally.**

---

## Core Mathematical Foundation

### 1. Fixed-Income Representation

A fixed-income instrument is a pair of cash flows:
- Cash outflow at t = 0: −P (bond price)
- Cash inflow at t = T: +F (face value)

Under continuous compounding:

```
P · e^(rT) = F
```

Where:
- `P` = bond price
- `F` = face value
- `r` = continuously compounded annualized rate
- `T` = time to maturity

### 2. Present Value Conservation (Key Insight)

Instead of conserving bond face value, BondMM-A conserves **present value**:

```
X = x · p = x · e^(-rt)
```

Where:
- `x` = bond face value in pool
- `p` = bond price = e^(-rt)
- `X` = present value of bonds

### 3. Rate Function

```
r = R(ψ) = κ ln(ψ) + r*
```

Where:
- `ψ = X / y` (present value to cash ratio)
- `κ` controls rate sensitivity (typically 0.02)
- `r*` is the anchor rate (market rate)

### 4. Core Invariant

For a given maturity `t`:

```
K · x^α + y^α = C
```

Where:
- `α = 1 / (1 + κt)`
- `K = e^(-t · r* · α)`
- `C` is constant for pool initialization

Alternative form (present value invariant):

```
y^α · (X/y + 1) = C
```

### 5. Trade Pricing Equations

**Given Δx (change in bond face value), calculate Δy (change in cash):**

```
Δy = [C - K(x + Δx)^α]^(1/α) - y
```

Or equivalently:

```
Δy = y · [(X/y + 1) - ((X/y)^(1/α) + e^(-r*t) · Δx/y)^α]^(1/α) - y
```

**Given Δy, calculate Δx:**

```
Δx = e^(r*t) · y · [(X/y + 1 - (Δy/y + 1)^α)^(1/α) - (X/y)^(1/α)]
```

### 6. Solvency Constraint

Let:
- `L` = present value of all outstanding borrows
- `E` = net equity = y + L

**Critical safety check:**

```
Reject lending when: E < 0.99 · y₀
```

This ensures the pool remains solvent.

### 7. Properties Guaranteed by Design

1. **Operability**: Balances never negative
2. **Computability**: Δx ↔ Δy solvable in O(1)
3. **Par redemption**: Bond redeems 1:1 at maturity (r=0, p=1)
4. **Path independence**: Trade order doesn't matter
5. **Economic soundness**: No negative rates

---

## System Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────┐
│                   Frontend/CLI                      │
│         (User Interface - Minimal for MVP)          │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────┐
│              BondMM-A Core Contract                 │
│  ┌──────────────────────────────────────────────┐   │
│  │  State Variables                             │   │
│  │  - cash (y)                                  │   │
│  │  - pvBonds (X)                               │   │
│  │  - netLiabilities (L)                        │   │
│  │  - parameters (κ, r*)                        │   │
│  └──────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │  Core Functions                              │   │
│  │  - lend(amount, maturity)                    │   │
│  │  - borrow(amount, maturity)                  │   │
│  │  - repay(positionId)                         │   │
│  │  - redeem(positionId)                        │   │
│  └──────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │  Math Library                                │   │
│  │  - calculateDeltaY(deltaX, maturity)         │   │
│  │  - calculateDeltaX(deltaY, maturity)         │   │
│  │  - checkSolvency()                           │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────┐
│              Position NFT Contract                  │
│         (ERC-721 for position tracking)             │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────┐
│                Oracle Contract                      │
│         (TWAP-based market rate feed)               │
└─────────────────────────────────────────────────────┘
```

### Data Flow

1. **Lending Flow**:
   ```
   User → lend(amount, maturity) → Calculate Δx → Check solvency → 
   Transfer cash → Mint position NFT → Update state (X, y, L)
   ```

2. **Borrowing Flow**:
   ```
   User → borrow(amount, maturity) → Calculate Δx → Check collateral → 
   Transfer cash to user → Mint position NFT → Update state (X, y, L)
   ```

3. **Redemption/Repayment Flow**:
   ```
   User → redeem/repay(positionId) → Calculate amount → 
   Transfer funds → Burn NFT → Update state
   ```

---

## Smart Contract Design

### Contract Structure

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BondMMA {
    // Core state variables
    uint256 public cash;              // y - cash in pool
    uint256 public pvBonds;           // X - present value of bonds
    uint256 public netLiabilities;    // L - present value of borrows
    uint256 public initialCash;       // y₀ - for solvency check
    
    // Parameters (fixed for MVP)
    uint256 public constant KAPPA = 20;      // κ = 0.02 (scaled by 1000)
    uint256 public constant KAPPA_SCALE = 1000;
    uint256 public rStar;              // r* - anchor rate (from oracle)
    
    // Oracle
    address public oracle;
    
    // Position tracking
    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions;
    
    struct Position {
        address owner;
        uint256 faceValue;      // bond face value
        uint256 maturity;       // timestamp
        bool isBorrow;          // true = borrow, false = lend
        bool isActive;
    }
    
    // Events
    event Lend(address indexed user, uint256 positionId, uint256 amount, uint256 maturity);
    event Borrow(address indexed user, uint256 positionId, uint256 amount, uint256 maturity);
    event Repay(uint256 indexed positionId, uint256 amount);
    event Redeem(uint256 indexed positionId, uint256 amount);
}
```

### Key Functions to Implement

#### 1. Initialization

```solidity
function initialize(uint256 _initialCash, address _oracle) external {
    cash = _initialCash;
    initialCash = _initialCash;
    pvBonds = _initialCash;  // X₀ = y₀
    netLiabilities = 0;
    oracle = _oracle;
    rStar = IOracle(oracle).getRate();
}
```

#### 2. Core Math Functions

```solidity
function calculateAlpha(uint256 timeToMaturity) internal pure returns (uint256) {
    // α = 1 / (1 + κt)
    // Returns scaled value
}

function calculateK(uint256 timeToMaturity, uint256 anchorRate) internal pure returns (uint256) {
    // K = e^(-t · r* · α)
}

function calculateC() internal view returns (uint256) {
    // C = y^α · (X/y + 1)
}

function calculateDeltaY(
    uint256 deltaX, 
    uint256 timeToMaturity,
    bool isPositive  // true = buying bonds
) internal view returns (uint256) {
    // Implement equation (6) from paper
}

function calculateDeltaX(
    uint256 deltaY, 
    uint256 timeToMaturity,
    bool isPositive
) internal view returns (uint256) {
    // Implement equation (7) from paper
}
```

#### 3. Solvency Check

```solidity
function checkSolvency() internal view returns (bool) {
    uint256 equity = cash + netLiabilities;
    uint256 minEquity = (initialCash * 99) / 100;  // 99% threshold
    return equity >= minEquity;
}

modifier requireSolvency() {
    require(checkSolvency(), "Pool insolvent");
    _;
}
```

#### 4. Lending Function

```solidity
function lend(uint256 amount, uint256 maturity) external requireSolvency returns (uint256 positionId) {
    require(maturity > block.timestamp, "Invalid maturity");
    require(amount > 0, "Zero amount");
    
    // Calculate time to maturity
    uint256 timeToMaturity = maturity - block.timestamp;
    
    // Calculate bond face value (Δx)
    uint256 deltaX = calculateDeltaX(amount, timeToMaturity, true);
    
    // Update state
    cash += amount;
    pvBonds -= deltaX * calculatePrice(timeToMaturity);
    
    // Check solvency after update
    require(checkSolvency(), "Would cause insolvency");
    
    // Create position
    positionId = nextPositionId++;
    positions[positionId] = Position({
        owner: msg.sender,
        faceValue: deltaX,
        maturity: maturity,
        isBorrow: false,
        isActive: true
    });
    
    // Transfer cash from user
    require(stablecoin.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    
    emit Lend(msg.sender, positionId, amount, maturity);
}
```

#### 5. Borrowing Function

```solidity
function borrow(uint256 amount, uint256 maturity) external returns (uint256 positionId) {
    require(maturity > block.timestamp, "Invalid maturity");
    require(amount > 0, "Zero amount");
    
    // In MVP, require collateral (150%)
    uint256 requiredCollateral = (amount * 150) / 100;
    // Implement collateral handling
    
    uint256 timeToMaturity = maturity - block.timestamp;
    uint256 deltaX = calculateDeltaX(amount, timeToMaturity, false);
    
    // Update state
    cash -= amount;
    pvBonds += deltaX * calculatePrice(timeToMaturity);
    netLiabilities += deltaX * calculatePrice(timeToMaturity);
    
    // Create position
    positionId = nextPositionId++;
    positions[positionId] = Position({
        owner: msg.sender,
        faceValue: deltaX,
        maturity: maturity,
        isBorrow: true,
        isActive: true
    });
    
    // Transfer cash to user
    require(stablecoin.transfer(msg.sender, amount), "Transfer failed");
    
    emit Borrow(msg.sender, positionId, amount, maturity);
}
```

#### 6. Redemption Function

```solidity
function redeem(uint256 positionId) external {
    Position storage position = positions[positionId];
    require(position.isActive, "Position inactive");
    require(position.owner == msg.sender, "Not owner");
    require(!position.isBorrow, "Cannot redeem borrow");
    require(block.timestamp >= position.maturity, "Not yet mature");
    
    // At maturity, 1 bond = 1 cash (par redemption)
    uint256 cashAmount = position.faceValue;
    
    // Update state
    position.isActive = false;
    cash -= cashAmount;
    
    // Transfer cash to user
    require(stablecoin.transfer(msg.sender, cashAmount), "Transfer failed");
    
    emit Redeem(positionId, cashAmount);
}
```

#### 7. Repayment Function

```solidity
function repay(uint256 positionId) external {
    Position storage position = positions[positionId];
    require(position.isActive, "Position inactive");
    require(position.owner == msg.sender, "Not owner");
    require(position.isBorrow, "Not a borrow position");
    
    uint256 repayAmount;
    
    if (block.timestamp >= position.maturity) {
        // At maturity: repay face value
        repayAmount = position.faceValue;
    } else {
        // Before maturity: calculate current value
        uint256 timeToMaturity = position.maturity - block.timestamp;
        uint256 currentPrice = calculatePrice(timeToMaturity);
        repayAmount = (position.faceValue * currentPrice) / 1e18;
    }
    
    // Update state
    position.isActive = false;
    cash += repayAmount;
    netLiabilities -= position.faceValue * calculatePrice(0); // Remove from liabilities
    
    // Transfer cash from user
    require(stablecoin.transferFrom(msg.sender, address(this), repayAmount), "Transfer failed");
    
    emit Repay(positionId, repayAmount);
}
```

---

## 7-Day Development Plan

### Day 1: Math & Invariants ✓

**Objective**: Implement core mathematical functions

**Tasks**:
- [ ] Create `BondMMMath.sol` library
- [ ] Implement `calculateAlpha()`
- [ ] Implement `calculateK()`
- [ ] Implement `calculateC()`
- [ ] Implement `calculateDeltaY()` (equation 6)
- [ ] Implement `calculateDeltaX()` (equation 7)
- [ ] Implement `calculatePrice()` (p = e^(-rt))
- [ ] Write unit tests for all math functions
- [ ] Verify invariants hold: `K·x^α + y^α = C`

**Deliverables**:
- `BondMMMath.sol` with 100% test coverage
- Test file: `BondMMMath.test.js`

---

### Day 2: Core Contract Skeleton ✓

**Objective**: Build the main contract structure

**Tasks**:
- [ ] Create `BondMMA.sol` contract
- [ ] Define state variables (cash, pvBonds, netLiabilities)
- [ ] Implement initialization function
- [ ] Implement solvency check
- [ ] Add access control (basic Ownable)
- [ ] Create Position struct
- [ ] Setup events
- [ ] Write deployment script

**Deliverables**:
- `BondMMA.sol` with core structure
- `deploy.js` script
- Basic unit tests

---

### Day 3: Oracle Integration ✓

**Objective**: Implement TWAP-based market rate oracle

**Tasks**:
- [ ] Create `BondMMOracle.sol`
- [ ] Implement TWAP calculation
- [ ] Add rate update mechanism
- [ ] Implement staleness check
- [ ] Add emergency pause on oracle failure
- [ ] Integrate oracle with main contract
- [ ] Test oracle edge cases

**Deliverables**:
- `BondMMOracle.sol`
- Oracle integration tests
- Fallback mechanisms

---

### Day 4: Lending & Borrowing ✓

**Objective**: Implement core trading functions

**Tasks**:
- [ ] Implement `lend()` function
- [ ] Implement `borrow()` function
- [ ] Add maturity restrictions (30d, 90d, 180d)
- [ ] Implement position NFT minting
- [ ] Add collateral handling for borrows
- [ ] Test multi-maturity scenarios
- [ ] Verify invariants after trades

**Deliverables**:
- Complete `lend()` and `borrow()` functions
- Position management system
- Integration tests

---

### Day 5: Repayment & Redemption ✓

**Objective**: Complete the lending lifecycle

**Tasks**:
- [ ] Implement `repay()` function
- [ ] Implement `redeem()` function
- [ ] Add liability decay: `L(t+Δt) = L(t)·e^(rΔt)`
- [ ] Implement position burning
- [ ] Add maturity checks
- [ ] Test full lifecycle (lend → wait → redeem)
- [ ] Test full lifecycle (borrow → repay)

**Deliverables**:
- Complete repayment/redemption functions
- Lifecycle tests
- Edge case handling

---

### Day 6: Adversarial Testing ✓

**Objective**: Stress test the system

**Tasks**:
- [ ] Fuzz testing with Foundry
- [ ] Oracle failure scenarios
- [ ] Stress lending (approach solvency limit)
- [ ] Stress borrowing
- [ ] Rapid maturity approach
- [ ] Gas optimization
- [ ] Security audit checklist

**Test scenarios**:
1. Sequential trades at different maturities
2. Large trades that approach solvency limits
3. Oracle goes stale mid-transaction
4. Attempt to redeem before maturity
5. Mass redemptions at maturity
6. Rate volatility stress test

**Deliverables**:
- Comprehensive test suite
- Gas optimization report
- Security assessment

---

### Day 7: Demo & Documentation ✓

**Objective**: Deploy and demonstrate

**Tasks**:
- [ ] Deploy to Mantle testnet
- [ ] Create minimal CLI interface
- [ ] Write deployment documentation
- [ ] Create demo script showing:
  - Multi-maturity lending
  - Stable rate pricing
  - Solvency protection
  - Full position lifecycle
- [ ] Prepare judge presentation
- [ ] Record demo video

**Demo scenarios**:
1. Initialize pool with 100,000 DAI
2. User A lends 10,000 DAI for 90 days
3. User B lends 5,000 DAI for 180 days
4. User C borrows 8,000 DAI for 30 days
5. Show rate stability across maturities
6. Attempt to over-lend (rejected by solvency check)
7. Fast-forward to maturity and redeem
8. Show equity remains stable

**Deliverables**:
- Deployed testnet contract
- CLI tool
- Complete documentation
- Demo video
- Judge reference document

---

## Setup Instructions

### Prerequisites

```bash
# Required software
- Node.js v18+
- npm or yarn
- Git
- Foundry (for testing)
```

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-repo/bondmm-a-mantle.git
cd bondmm-a-mantle

# 2. Install dependencies
npm install

# 3. Install Foundry (if not installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 4. Setup environment
cp .env.example .env
# Edit .env with your Mantle RPC URL and private key
```

### Project Structure

```
bondmm-a-mantle/
├── contracts/
│   ├── BondMMA.sol              # Main AMM contract
│   ├── BondMMMath.sol           # Math library
│   ├── BondMMOracle.sol         # Rate oracle
│   ├── PositionNFT.sol          # ERC-721 for positions
│   └── interfaces/
│       └── IBondMMA.sol
├── scripts/
│   ├── deploy.js                # Deployment script
│   ├── demo.js                  # Demo scenarios
│   └── utils/
├── test/
│   ├── BondMMMath.test.js
│   ├── BondMMA.test.js
│   ├── BondMMOracle.test.js
│   └── Integration.test.js
├── cli/
│   └── bondmm-cli.js            # Command line interface
├── hardhat.config.js
├── foundry.toml
├── package.json
└── README.md
```

### Configuration

**hardhat.config.js**:

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    mantleTestnet: {
      url: process.env.MANTLE_RPC_URL || "https://rpc.testnet.mantle.xyz",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 5001
    },
    mantleMainnet: {
      url: process.env.MANTLE_RPC_URL || "https://rpc.mantle.xyz",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 5000
    }
  },
  etherscan: {
    apiKey: {
      mantleTestnet: process.env.MANTLE_API_KEY || ""
    }
  }
};
```

---

## Core Features Implementation

### Feature 1: Multi-Maturity Support

**Implementation approach**:
- Store maturity with each position
- Calculate parameters (α, K, C) per trade
- No pool-level maturity constraint

**Code example**:

```solidity
function lend(uint256 amount, uint256 maturityTimestamp) external {
    uint256 timeToMaturity = maturityTimestamp - block.timestamp;
    require(timeToMaturity >= MIN_MATURITY && timeToMaturity <= MAX_MATURITY, 
            "Invalid maturity");
    
    // Calculate trade-specific parameters
    uint256 alpha = calculateAlpha(timeToMaturity);
    uint256 k = calculateK(timeToMaturity, rStar);
    // ... rest of implementation
}
```

### Feature 2: Unified Liquidity Pool

**Key insight**: All positions share the same `(X, y)` state

**Benefits**:
- LPs provide liquidity once for all maturities
- No capital fragmentation
- Better capital efficiency

### Feature 3: Solvency Protection

**Implementation**:

```solidity
function checkSolvency() internal view returns (bool) {
    // E = y + L
    uint256 equity = cash + netLiabilities;
    
    // Reject if E < 0.99 · y₀
    uint256 minEquity = (initialCash * 99) / 100;
    
    return equity >= minEquity;
}
```

**When to check**:
- Before every lending operation
- After updating liabilities
- On position maturity

### Feature 4: Position Tracking

**Two implementation options**:

**Option A (MVP)**: On-chain struct storage
```solidity
struct Position {
    address owner;
    uint256 faceValue;
    uint256 maturity;
    bool isBorrow;
    bool isActive;
}
```

**Option B (Future)**: ERC-721 NFT per position
- More gas efficient for transfers
- Better composability with other protocols
- Enables secondary markets

### Feature 5: Oracle-Based Pricing

**TWAP implementation**:

```solidity
contract BondMMOracle {
    uint256 public constant OBSERVATION_PERIOD = 1 hours;
    uint256[] public rateHistory;
    uint256[] public timestamps;
    
    function updateRate(uint256 newRate) external onlyUpdater {
        rateHistory.push(newRate);
        timestamps.push(block.timestamp);
        
        // Keep only last 24 observations
        if (rateHistory.length > 24) {
            // Remove oldest
        }
    }
    
    function getRate() external view returns (uint256) {
        require(!isStale(), "Oracle stale");
        
        // Calculate TWAP
        uint256 sum = 0;
        for (uint i = 0; i < rateHistory.length; i++) {
            sum += rateHistory[i];
        }
        return sum / rateHistory.length;
    }
    
    function isStale() public view returns (bool) {
        return block.timestamp - timestamps[timestamps.length - 1] > OBSERVATION_PERIOD;
    }
}
```

---

## Testing Strategy

### Unit Tests

```javascript
describe("BondMMMath", function() {
  it("should calculate alpha correctly", async function() {
    // Test: α = 1 / (1 + κt)
    // For t = 90 days (7776000 seconds), κ = 0.02
    const timeToMaturity = 90 * 24 * 3600;
    const alpha = await math.calculateAlpha(timeToMaturity);
    // Verify result
  });
  
  it("should preserve invariant after trade", async function() {
    // Setup initial state
    // Execute trade
    // Verify: K·x^α + y^α = C holds
  });
  
  it("should ensure par redemption at maturity", async function() {
    // At t=0, verify r=0 and p=1
  });
});
```

### Integration Tests

```javascript
describe("BondMMA Integration", function() {
  it("should support multiple maturities", async function() {
    // User A lends for 30 days
    // User B lends for 90 days
    // User C lends for 180 days
    // Verify rates are different but stable
  });
  
  it("should reject lending on insolvency", async function() {
    // Lend until close to solvency limit
    // Next lend should fail
  });
  
  it("should handle full lifecycle", async function() {
    // Lend → wait → redeem
    // Verify cash flows
  });
});
```

### Fuzz Tests (Foundry)

```solidity
// test/FuzzTest.t.sol
contract BondMMAFuzzTest is Test {
    function testFuzz_LendingPreservesInvariant(
        uint256 amount,
        uint256 maturity
    ) public {
        // Bound inputs
        amount = bound(amount, 1e18, 1000000e18);
        maturity = bound(maturity, 30 days, 365 days);
        
        // Record state before
        uint256 CBefore = bondMMA.calculateC();
        
        // Execute trade
        bondMMA.lend(amount, block.timestamp + maturity);
        
        // Verify invariant holds
        uint256 CAfter = bondMMA.calculateC();
        assertEq(CBefore, CAfter);
    }
}
```

---

## Deployment Guide

### Step 1: Deploy Math Library

```bash
npx hardhat run scripts/deployMath.js --network mantleTestnet
```

### Step 2: Deploy Oracle

```bash
npx hardhat run scripts/deployOracle.js --network mantleTestnet
```

### Step 3: Deploy Main Contract

```bash
npx hardhat run scripts/deployBondMMA.js --network mantleTestnet
```

### Step 4: Initialize Pool

```javascript
// scripts/initialize.js
const initialCash = ethers.utils.parseUnits("100000", 18); // 100k DAI
const oracleAddress = "0x..."; // From step 2

await bondMMA.initialize(initialCash, oracleAddress);
```

### Step 5: Verify on Explorer

```bash
npx hardhat verify --network mantleTestnet CONTRACT_ADDRESS CONSTRUCTOR_ARGS
```

---

## Security Considerations

### Critical Checks

1. **Solvency enforcement**: MUST reject lending when E < 0.99·y₀
2. **Maturity validation**: Positions cannot be redeemed before maturity
3. **Ownership verification**: Only position owner can repay/redeem
4. **Oracle staleness**: Pause borrowing if oracle is stale
5. **Reentrancy**: Use OpenZeppelin's ReentrancyGuard

### Attack Vectors to Test

1. **Oracle manipulation**: What if attacker feeds bad rates?
   - Mitigation: TWAP + staleness checks
   
2. **Solvency drain**: What if sequential trades drain equity?
   - Mitigation: 99% equity floor
   
3. **Flash loan attacks**: Can attacker manipulate rates in one block?
   - Mitigation: TWAP makes this expensive
   
4. **Rounding errors**: Can attacker drain via repeated small trades?
   - Mitigation: Minimum trade amounts

### Audit Checklist

- [ ] Integer overflow/underflow (use Solidity 0.8+)
- [ ] Reentrancy protection
- [ ] Access control on admin functions
- [ ] Input validation on all external functions
- [ ] Emergency pause mechanism
- [ ] Oracle failure handling
- [ ] Gas optimization for math operations
- [ ] Front-running considerations

---

## Known Limitations (MVP)

### What MVP Does NOT Include

1. **DAO governance**: No voting on parameters
2. **Multi-asset support**: Only one stablecoin (DAI/USDC)
3. **Liquidation markets**: Simple collateral model
4. **Yield curve shaping**: r* is uniform across maturities
5. **Secondary markets**: No bond trading before maturity
6. **Rate derivatives**: No options or futures
7. **Upgradeability**: Immutable contracts

### Post-MVP Roadmap

**Phase 2 (Weeks 2-4)**:
- Add bounded governance
- Multi-asset collateral
- Yield curve calibration

**Phase 3 (Months 2-3)**:
- Secondary bond markets
- Interest rate derivatives
- Cross-chain bridges

**Phase 4 (Months 4-6)**:
- DAO transition
- Institutional features
- Advanced liquidations

---

## Risk Analysis

### Governance Risk
- **Threat**: Admin could manipulate r*
- **Mitigation**: MVP has NO governance
- **Future**: Timelock + multisig + DAO

### Oracle Risk
- **Threat**: Oracle provides bad rates
- **Mitigation**: TWAP, staleness checks, pause on failure
- **Future**: Multiple oracle sources, Chainlink integration

### Insolvency Risk
- **Threat**: Massive borrows drain pool
- **Mitigation**: 99% equity floor, collateral requirements
- **Future**: Dynamic collateral ratios, liquidation markets

### Smart Contract Risk
- **Threat**: Bugs in math or logic
- **Mitigation**: Extensive testing, minimal surface area
- **Future**: Professional audit, bug bounty

---

## CLI Usage

### Basic Commands

```bash
# Check pool status
npx bondmm status

# Lend 1000 DAI for 90 days
npx bondmm lend --amount 1000 --maturity 90d

# Borrow 500 DAI for 30 days
npx bondmm borrow --amount 500 --maturity 30d --collateral 750

# Check your positions
npx bondmm positions --address YOUR_ADDRESS

# Redeem position
npx bondmm redeem --position-id 123

# Repay borrow
npx bondmm repay --position-id 456
```

### Demo Script

```bash
# Run complete demo
npm run demo

# This will:
# 1. Deploy contracts to testnet
# 2. Initialize pool with 100k DAI
# 3. Execute multi-maturity trades
# 4. Show rate stability
# 5. Test solvency protection
# 6. Complete lifecycle (lend → redeem)
```

---

## Mathematical Verification

### Invariant Proofs

**Property**: Path independence

*Proof sketch*:
1. Invariant: `K·x^α + y^α = C`
2. For trade (Δx, Δy): `K·(x+Δx)^α + (y+Δy)^α = C`
3. Therefore: `K·x^α + y^α = K·(x+Δx)^α + (y+Δy)^α`
4. This holds regardless of intermediate states
5. Thus: Trade order doesn't matter ∎

**Property**: Par redemption

*Proof sketch*:
1. At maturity: t → 0
2. α = 1/(1+κ·0) = 1
3. K = e^(-0·r*·1) = 1
4. Invariant becomes: x + y = C
5. Price: p = e^(-r·0) = 1
6. Thus: 1 bond = 1 cash ∎

---

## Performance Metrics

### Gas Costs (Estimated)

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| Initialize | ~200k | One-time |
| Lend | ~150k | With NFT mint |
| Borrow | ~180k | With collateral |
| Repay | ~100k | With NFT burn |
| Redeem | ~100k | With NFT burn |
| Oracle update | ~50k | Per update |

### Throughput

- **Target**: 100+ positions per hour
- **Rate updates**: Every hour (oracle)
- **Maturity options**: 30d, 90d, 180d (MVP)

---

## References

### Primary Source
- **BondMM-A Research Paper**: "Design of a Decentralized Fixed-Income Lending Automated Market Maker Protocol Supporting Arbitrary Maturities" by Tianyi Ma (arXiv:2512.16080v1)

### Related Protocols
- Yield Protocol: https://yield.is
- Notional Protocol: https://notional.finance
- BondMM (original): IEEE ICBC 2024 paper by Tran et al.

### Mathematical Background
- Cox-Ingersoll-Ross Model: Econometrica 1985
- Fixed-income pricing theory: Hull, "Options, Futures, and Other Derivatives"

---

## FAQ

**Q: Why Mantle Network?**
A: EVM compatibility + low gas fees + fast finality. Heavy math operations are practical here.

**Q: Why not use existing protocols?**
A: They only support single-maturity or have capital inefficiency. BondMM-A unifies liquidity.

**Q: Is this production-ready?**
A: MVP demonstrates feasibility. Production requires audits, governance, and more features.

**Q: How do you prevent negative rates?**
A: r = κ ln(X/y) + r* with r* > 0 ensures r > 0 when X/y > e^(-r*/κ).

**Q: What if the oracle fails?**
A: Borrowing is paused. Existing positions can still be redeemed/repaid.

**Q: Can positions be transferred?**
A: MVP uses simple structs. Future versions will use ERC-721 for transferability.

---

## Contact & Support

- **Developer**: Brooklyn (working in Monad ecosystem)
- **Repository**: https://github.com/your-repo/bondmm-a-mantle
- **Paper**: arXiv:2512.16080v1
- **Demo**: [Deploy on Mantle Testnet]

---

## Appendix: Key Equations Reference

### 1. Present Value
```
X = x · e^(-rt)
```

### 2. Rate Function
```
r = κ ln(X/y) + r*
```

### 3. Core Invariant
```
K·x^α + y^α = C
where:
  α = 1/(1 + κt)
  K = e^(-tr*α)
  C = y₀^α · (X₀/y₀ + 1)
```

### 4. Trade Pricing (Given Δx)
```
Δy = [C - K(x+Δx)^α]^(1/α) - y
```

### 5. Trade Pricing (Given Δy)
```
Δx = e^(r*t) · y · [(X/y + 1 - (Δy/y + 1)^α)^(1/α) - (X/y)^(1/α)]
```

### 6. Solvency Check
```
E = y + L ≥ 0.99 · y₀
```

### 7. Liability Decay
```
L(t+Δt) = L(t) · e^(r·Δt)
```

---

**End of Development Reference**

This document serves as the complete blueprint for building BondMM-A on Mantle Network. Follow the 7-day plan sequentially, implement all core features, and ensure all mathematical properties hold through rigorous testing.

**Remember**: This is a mathematically-driven protocol. The math MUST be perfect, or the entire system fails. Test relentlessly.