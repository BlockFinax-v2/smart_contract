# LiquidityPoolFacet Testing Documentation

## Overview

This document describes the comprehensive testing strategy for the `LiquidityPoolFacet` contract, which implements a sophisticated staking mechanism with dynamic APR, voting power calculation, and reward distribution.

## Test Structure

### 1. Unit Tests (`LiquidityPoolFacet.test.js`)

**Purpose**: Test individual functions and their basic functionality

**Coverage**:

- ✅ Contract initialization and configuration
- ✅ Staking functionality (basic scenarios)
- ✅ Unstaking with lock period validation
- ✅ Emergency withdrawal with penalty calculation
- ✅ Reward calculation and claiming
- ✅ Voting power calculation
- ✅ Pause/unpause functionality
- ✅ Owner-only functions and access control
- ✅ Configuration updates

**Key Test Scenarios**:

```javascript
// Example: Testing basic staking
it("Should allow users to stake USDC", async function () {
  const stakeAmount = ethers.utils.parseUnits("1000", 6);
  await liquidityPool.connect(user1).stake(stakeAmount);

  const stake = await liquidityPool.getStake(user1.address);
  expect(stake.amount).to.equal(stakeAmount);
  expect(stake.active).to.be.true;
});
```

### 2. Fuzz Tests (`LiquidityPoolFacet.fuzz.test.js`)

**Purpose**: Test contract behavior with random inputs and edge cases

**Coverage**:

- ✅ Random stake amounts (100 to 100,000 USDC)
- ✅ Random time manipulations (1 second to 10 years)
- ✅ Multiple concurrent user operations
- ✅ Edge cases and extreme values
- ✅ Invariant testing (voting power sum, total staked accuracy)

**Key Fuzz Scenarios**:

```javascript
// Example: Random stake amounts
for (let i = 0; i < 50; i++) {
  const randomAmount = Math.floor(Math.random() * 100000) + 100;
  const stakeAmount = ethers.utils.parseUnits(randomAmount.toString(), 6);

  await liquidityPool.connect(user).stake(stakeAmount);
  // Verify invariants hold
}
```

### 3. Integration Tests (`LiquidityPoolFacet.integration.test.js`)

**Purpose**: Test contract interaction with Diamond architecture and complex multi-user scenarios

**Coverage**:

- ✅ Diamond pattern integration
- ✅ Cross-facet storage sharing
- ✅ Multi-user complex scenarios
- ✅ Reward system over extended periods
- ✅ Dynamic APR changes
- ✅ Gas optimization verification
- ✅ Performance under load

**Key Integration Scenarios**:

```javascript
// Example: Multi-user staking scenario
it("Should handle complex multi-user staking scenario", async function () {
  // User1: Large early staker
  await liquidityPool.connect(user1).stake(ethers.utils.parseUnits("10000", 6));

  // User2: Medium staker (later)
  await liquidityPool.connect(user2).stake(ethers.utils.parseUnits("5000", 6));

  // Verify proportional rewards and voting power
});
```

## Test Features

### Mathematical Precision Testing

- **Voting Power Calculation**: Ensures sum always equals 1.0 (within tolerance)
- **Reward Calculation**: Validates APR-based reward distribution
- **Time-based Calculations**: Tests accuracy across various time periods

### Security Testing

- **Access Control**: Verifies owner-only functions
- **Reentrancy Protection**: Tests with ReentrancyGuard
- **Input Validation**: Tests with zero amounts, invalid parameters
- **Lock Period Enforcement**: Ensures premature unstaking fails

### Economic Model Testing

- **Dynamic APR**: Tests rate reduction based on total staked
- **Emergency Penalties**: Validates penalty calculation (15%)
- **Reward Distribution**: Ensures fair distribution over time
- **Minimum Stake Enforcement**: Tests minimum stake requirements

## Running Tests

### Prerequisites

```bash
npm install
npx hardhat compile
```

### Individual Test Suites

```bash
# Unit tests only
./run-tests.sh unit

# Fuzz tests only
./run-tests.sh fuzz

# Integration tests only
./run-tests.sh integration

# All tests
./run-tests.sh all
```

### Coverage and Gas Reports

```bash
# Coverage report
./run-tests.sh coverage

# Gas usage report
./run-tests.sh gas
```

### Manual Testing

```bash
# Individual test files
npx hardhat test test/LiquidityPoolFacet.test.js
npx hardhat test test/LiquidityPoolFacet.fuzz.test.js
npx hardhat test test/LiquidityPoolFacet.integration.test.js
```

## Test Data and Scenarios

### Stake Amounts Tested

- Minimum: 100 USDC (below minimum threshold)
- Small: 500-1,000 USDC
- Medium: 5,000-10,000 USDC
- Large: 50,000-100,000 USDC
- Maximum: 999,999 USDC (edge case)

### Time Periods Tested

- **Short Term**: 1 second to 1 hour
- **Medium Term**: 1 day to 1 week
- **Long Term**: 1 month to 1 year
- **Extreme**: Up to 10 years (overflow testing)

### APR Scenarios

- **Initial**: 10% (1000 basis points)
- **Reduced**: Based on total staked amount
- **Updated**: Dynamic changes by owner
- **Minimum**: 1% floor protection

## Expected Test Results

### Unit Tests

- ✅ All basic functionality working
- ✅ Proper error handling with custom errors
- ✅ Event emissions with correct parameters
- ✅ State changes reflected accurately

### Fuzz Tests

- ✅ No arithmetic overflows/underflows
- ✅ Invariants maintained under stress
- ✅ Graceful handling of edge cases
- ✅ Performance remains acceptable

### Integration Tests

- ✅ Diamond storage consistency
- ✅ Multi-user scenarios work correctly
- ✅ Gas usage within reasonable limits
- ✅ Complex workflows complete successfully

## Key Metrics and Benchmarks

### Gas Usage Targets

- **Stake**: < 500,000 gas
- **Unstake**: < 400,000 gas
- **Claim Rewards**: < 200,000 gas
- **Emergency Withdraw**: < 300,000 gas

### Performance Targets

- **Response Time**: < 2 seconds per operation
- **Scalability**: Support 100+ concurrent stakers
- **Precision**: Mathematical accuracy to 18 decimals

### Security Assertions

- **No Reentrancy**: All state-changing functions protected
- **Access Control**: Owner functions properly restricted
- **Input Validation**: All edge cases handled with custom errors
- **Lock Period**: Enforced without bypass possibilities

## Continuous Integration

The test suite is designed to be run in CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run Contract Tests
  run: |
    npm install
    npx hardhat compile
    ./run-tests.sh all
    ./run-tests.sh coverage
```

## Troubleshooting

### Common Issues

1. **Node.js Version**: Use Node.js 16-20 for best compatibility
2. **Gas Limit**: Increase gas limit in hardhat.config.js if needed
3. **Time Manipulation**: Reset blockchain state between tests
4. **Precision Errors**: Use `closeTo` matcher for decimal comparisons

### Debug Commands

```bash
# Verbose test output
npx hardhat test --verbose

# Single test case
npx hardhat test --grep "Should allow users to stake"

# Network debugging
npx hardhat node --verbose
```

## Maintenance

### Regular Updates

- Run full test suite before any contract changes
- Update test scenarios when adding new features
- Maintain fuzz test scenarios for edge cases
- Review gas usage benchmarks quarterly

### Test Coverage Goals

- **Line Coverage**: > 95%
- **Function Coverage**: 100%
- **Branch Coverage**: > 90%
- **Statement Coverage**: > 95%

This comprehensive testing strategy ensures the `LiquidityPoolFacet` contract is robust, secure, and performs optimally under all conditions.
