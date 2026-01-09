# BondMM-A Backend (Foundry)

Pure Foundry setup for BondMM-A protocol smart contracts.

## Project Structure

```
backend/
├── src/
│   ├── BondMMA.sol              # Main AMM contract
│   ├── libraries/
│   │   └── BondMMMath.sol       # Math library (PRBMath-based)
│   ├── BondMMOracle.sol         # TWAP oracle
│   └── interfaces/
│       └── IBondMMA.sol         # Interface
├── test/
│   ├── unit/                    # Unit tests
│   ├── integration/             # Integration tests
│   └── fuzz/                    # Fuzz tests (invariants)
├── script/
│   ├── deployment/              # Deployment scripts
│   └── utils/                   # Utility scripts
├── lib/
│   ├── forge-std/               # Foundry testing library
│   ├── openzeppelin-contracts/  # OpenZeppelin v5.x
│   └── prb-math/                # PRBMath for exp, ln, pow
└── foundry.toml                 # Foundry config
```

## Setup

```bash
# 1. Install dependencies (required after cloning)
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts PaulRBerg/prb-math

# 2. Copy environment file
cp .env.example .env
# Edit .env with your private keys and RPC URLs

# 3. Build
forge build

# 4. Run tests
forge test

# 5. Run tests with gas report
forge test --gas-report

# 6. Run fuzz tests
forge test --match-contract Fuzz

# 7. Coverage
forge coverage
```

## Dependencies

- **Solidity**: ^0.8.20
- **OpenZeppelin Contracts**: v5.x (ReentrancyGuard, Ownable, IERC20)
- **PRBMath**: v4.x (UD60x18 for fixed-point math)
- **Forge-Std**: Testing utilities

## Deployment

```bash
# Deploy to Mantle Testnet
forge script script/deployment/Deploy.s.sol --rpc-url mantle_testnet --broadcast --verify

# Deploy to Mantle Mainnet
forge script script/deployment/Deploy.s.sol --rpc-url mantle_mainnet --broadcast --verify
```

## Testing Strategy

### Unit Tests
- Test each math function independently
- Verify invariant: `K·x^α + y^α = C`
- Verify par redemption: at t=0, p=1

### Integration Tests
- Multi-maturity lending scenarios
- Full lifecycle: lend → redeem
- Full lifecycle: borrow → repay
- Solvency rejection tests

### Fuzz Tests
- Property-based testing with Foundry
- Invariant testing for `C` preservation
- Boundary condition testing
- Oracle failure scenarios

## Gas Targets

- Initialize: ~200k
- Lend: ~150k
- Borrow: ~180k
- Repay/Redeem: ~100k
- Oracle update: ~50k

## Network Configuration

### Mantle Testnet
- Chain ID: 5001
- RPC: https://rpc.testnet.mantle.xyz
- Explorer: https://explorer.testnet.mantle.xyz

### Mantle Mainnet
- Chain ID: 5000
- RPC: https://rpc.mantle.xyz
- Explorer: https://explorer.mantle.xyz

## Development Commands

```bash
# Compile contracts
forge build

# Run all tests
forge test -vvv

# Run specific test
forge test --match-test testLending -vvv

# Gas snapshot
forge snapshot

# Format code
forge fmt

# Check code style
forge fmt --check
```

## Math Library (PRBMath)

We use PRBMath for:
- `exp(x)` - Exponential function for e^x
- `ln(x)` - Natural logarithm
- `pow(x, y)` - Power function for fractional exponents (α calculations)

All values use 18-decimal fixed-point arithmetic (1e18 scale).

## Security

- Solidity 0.8.20+ (overflow/underflow protection)
- OpenZeppelin security patterns
- ReentrancyGuard on all state-changing functions
- Comprehensive test coverage
- Fuzz testing for edge cases
- Oracle staleness checks
- Solvency enforcement

## Reference

See `/CLAUDE.md` in project root for complete mathematical specification and implementation details.
