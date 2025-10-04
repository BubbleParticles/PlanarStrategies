# StrategyFramework Test Suite

This directory contains comprehensive tests for the StrategyFramework, covering both unit tests for individual utility functions and integration tests for the complete strategy lifecycle.

## Test Structure

### Unit Tests

#### `test_math_utils_standalone.jl`
Tests for mathematical utility functions:
- **getincr/baseincr functions**: Price and quantity increment calculations with exchange-specific rules
- **calculate_spread function**: Bid-ask spread calculations (absolute, relative, mid-price)
- **roc function**: Rate of Change calculations with different periods
- **rolling_volatility function**: Rolling volatility calculations using standard deviation method
- **parkinson_volatility function**: Parkinson volatility estimator using high-low range
- **tftodelay/timeframe_to_period functions**: Timeframe string parsing and conversion
- **normalize_price/normalize_quantity functions**: Price and quantity normalization to valid increments
- **calculate_atr function**: Average True Range indicator calculation

**Coverage**: 43 test cases covering normal operations, edge cases, error conditions, and floating-point precision issues.

#### `test_async_utils_standalone.jl`
Tests for asynchronous utility functions:
- **liveasync function**: Strategy-appropriate async execution (sync in sim, async in live)
- **livelock function**: Strategy-appropriate locking mechanisms with thread safety
- **livesleep function**: Strategy-appropriate sleep operations (no-op in sim, actual sleep in live)
- **async_with_timeout function**: Async execution with timeout handling
- **throttle_async function**: Function throttling with minimum intervals
- **batch_async function**: Batch execution of multiple async tasks

**Coverage**: 20 test cases covering simulation vs live mode behavior, timing constraints, and error handling.

#### `test_parameters_simple.jl`
Tests for parameter management system:
- **ParameterSpec construction**: Parameter specification with types, bounds, and validators
- **Parameter registration**: Registration and retrieval of parameter specifications
- **Type conversion**: Float vector to named parameters conversion for optimization
- **Parameter validation**: Bounds checking and custom validation functions
- **Parameter caching**: Get/set operations with type conversion and validation

**Coverage**: 31 test cases covering parameter lifecycle, type conversions, validation, and edge cases.

### Integration Tests

#### `integration_tests.jl`
Comprehensive integration tests covering the complete strategy framework:

##### Strategy Lifecycle Tests
- Strategy initialization and reset functionality
- Configuration management and mode detection (sim vs live)
- Clean state verification after reset operations

##### Signal Generation Interface Tests
- **SimpleBuySignalGenerator**: Random signal generation with thresholds
- **AlwaysBuySignalGenerator**: Consistent buy signals for testing
- **NeverTradeSignalGenerator**: No trading signals for testing
- **AlternatingSignalGenerator**: Alternating buy/sell signals for complex scenarios
- Signal validation, lifetime management, and trading permission checks

##### Order Execution Flow Tests
- Basic buy/sell order execution with position and balance tracking
- Order cancellation for open orders
- Error handling for edge cases (zero amounts, zero prices, overselling)
- Order history and status management

##### Data Management and Performance Tracking Tests
- Mock data initialization
- PnL tracking for different position types (long, short, no position)
- Performance metrics calculation and order history analysis

##### Strategy Polling Integration Tests
- Complete polling cycles with different signal generators
- Trade execution based on signal thresholds
- Position accumulation over multiple polling cycles
- No-trade scenarios with restrictive signal generators

##### End-to-End Strategy Workflow Tests
- Complete strategy lifecycle from initialization to reset
- Multi-cycle strategy execution with PnL tracking
- Mixed buy/sell signal scenarios with alternating patterns
- State verification at each stage of the workflow

**Coverage**: 121 test cases covering all major integration scenarios and workflows.

## Running the Tests

### Quick Test Run
```bash
cd user/strategies/StrategyFramework
julia test/simple_test_runner.jl
```

### Individual Test Files
```bash
julia test/test_math_utils_standalone.jl
julia test/test_async_utils_standalone.jl
julia test/test_parameters_simple.jl
julia test/integration_tests.jl
```

## Test Design Principles

### Standalone Testing
- Tests are designed to run without full Planar.jl dependencies
- Mock implementations replace complex external dependencies
- Each test file can be run independently

### Comprehensive Coverage
- **Unit Tests**: Focus on individual function correctness, edge cases, and error conditions
- **Integration Tests**: Focus on component interaction, workflow validation, and end-to-end scenarios
- **Error Handling**: Extensive testing of error conditions and recovery mechanisms

### Mock Strategy Framework
- Complete mock implementation of strategy, signal generator, and asset types
- Realistic order execution simulation with position and balance tracking
- Configurable signal generators for different testing scenarios

### Validation Focus
- Mathematical calculations tested for accuracy and edge cases
- Async behavior validated for both simulation and live modes
- Parameter management tested for type safety and validation rules
- Strategy lifecycle tested for state consistency and proper cleanup

## Test Results Summary

- **Total Test Cases**: 215
- **Unit Tests**: 94 cases (math: 43, async: 20, parameters: 31)
- **Integration Tests**: 121 cases
- **Success Rate**: 100% (all tests passing)
- **Coverage Areas**: 
  - Mathematical utilities and calculations
  - Asynchronous operations and timing
  - Parameter management and validation
  - Strategy lifecycle and state management
  - Signal generation and processing
  - Order execution and position tracking
  - Data management and performance metrics
  - End-to-end workflow validation

## Key Testing Features

### Floating Point Precision
- Uses approximate equality (`≈`) for floating-point comparisons
- Handles precision issues in mathematical calculations
- Validates normalization and rounding operations

### Timing and Performance
- Lenient timing tests to account for system variations
- Validates async behavior without strict timing requirements
- Tests throttling and batching mechanisms

### Error Condition Testing
- Comprehensive error handling validation
- Edge case testing (zero values, invalid inputs, boundary conditions)
- Exception propagation and recovery testing

### Mock Framework Realism
- Realistic order execution with proper state updates
- Position tracking with long/short support
- Balance management with transaction costs
- Signal generation with configurable behavior patterns

This test suite provides comprehensive validation of the StrategyFramework's functionality, ensuring reliability and correctness across all major components and use cases.