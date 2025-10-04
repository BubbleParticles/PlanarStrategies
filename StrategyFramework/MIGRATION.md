# Migration Guide: SurgeV4 to StrategyFramework

This guide provides step-by-step instructions for migrating from SurgeV4.jl to the new StrategyFramework architecture.

## Table of Contents

- [Overview](#overview)
- [Key Differences](#key-differences)
- [Migration Steps](#migration-steps)
- [Code Examples](#code-examples)
- [Configuration Changes](#configuration-changes)
- [Testing Your Migration](#testing-your-migration)
- [Compatibility Utilities](#compatibility-utilities)
- [Troubleshooting](#troubleshooting)

## Overview

StrategyFramework is a modular refactoring of SurgeV4 that separates signal generation logic from trading infrastructure. The main benefits of migrating include:

- **Cleaner Code**: Signal logic is separated from infrastructure
- **Better Testing**: Modular architecture enables better unit testing
- **Reusability**: Framework can be used for multiple strategies
- **Maintainability**: Clear separation of concerns
- **Extensibility**: Easy to add new features and utilities

## Key Differences

### Architecture Changes

| Aspect | SurgeV4 | StrategyFramework |
|--------|---------|-------------------|
| **Structure** | Monolithic strategy file | Modular framework with signal interface |
| **Signal Logic** | Embedded in strategy callbacks | Separate `SignalGenerator` implementation |
| **Configuration** | Direct parameter access | Structured configuration management |
| **Utilities** | Inline utility functions | Organized utility modules |
| **Testing** | Strategy-level testing only | Unit and integration testing |

### Code Organization

#### SurgeV4 Structure
```
SurgeV4.jl
├── All signal logic mixed with infrastructure
├── Utility functions scattered throughout
├── Configuration hardcoded
└── Single large file
```

#### StrategyFramework Structure
```
StrategyFramework/
├── src/
│   ├── interfaces/signal_interface.jl    # Your signal logic goes here
│   ├── core/                            # Framework infrastructure
│   ├── trading/                         # Trading utilities
│   ├── data/                           # Data management
│   └── utilities/                      # Helper functions
└── Your signal implementation
```

### Signal Generation Changes

#### SurgeV4 Approach
```julia
# Signal logic embedded in strategy callbacks
function call!(::ResetStrategy, s::SC, args...)
    # Signal logic mixed with initialization
    if some_condition
        # Buy logic here
    end
end
```

#### StrategyFramework Approach
```julia
# Clean signal interface
struct MySignalGenerator <: SignalGenerator
    # Signal parameters
end

function generate_buy_signal(sg::MySignalGenerator, s::SC, ai, ats)
    # Pure signal logic
    return signal_condition
end
```

## Migration Steps

### Step 1: Analyze Your SurgeV4 Strategy

Before migrating, identify the key components in your SurgeV4 strategy:

1. **Signal Logic**: Code that determines when to buy/sell
2. **Parameters**: Configuration values and optimization parameters
3. **Custom Utilities**: Any custom functions you've added
4. **Configuration**: Asset lists, exchange settings, etc.

#### Example Analysis
```julia
# In your SurgeV4 strategy, identify:

# 1. Signal Logic (extract this)
if rsi < 30 && macd_signal > 0
    # This becomes generate_buy_signal logic
end

# 2. Parameters (move to signal generator struct)
const RSI_PERIOD = 14
const MACD_FAST = 12
const MACD_SLOW = 26

# 3. Custom Utilities (move to utilities or keep in signal generator)
function calculate_custom_indicator(data)
    # Custom calculation
end
```

### Step 2: Create Your Signal Generator

Create a new signal generator that implements the `SignalGenerator` interface:

```julia
# Create: MyStrategy.jl
using StrategyFramework

struct MySignalGenerator <: SignalGenerator
    # Move your parameters here
    rsi_period::Int
    rsi_oversold::Float64
    rsi_overbought::Float64
    macd_fast::Int
    macd_slow::Int
    macd_signal::Int
    
    # Constructor with defaults
    MySignalGenerator(;
        rsi_period=14,
        rsi_oversold=30.0,
        rsi_overbought=70.0,
        macd_fast=12,
        macd_slow=26,
        macd_signal=9
    ) = new(rsi_period, rsi_oversold, rsi_overbought, macd_fast, macd_slow, macd_signal)
end

# Implement required methods
function generate_buy_signal(sg::MySignalGenerator, s::SC, ai, ats)
    # Move your buy signal logic here
    ohlcv = s.universe[ai].ohlcv
    
    # Calculate indicators using your existing logic
    rsi = calculate_rsi(ohlcv.close, sg.rsi_period)
    macd_line, macd_signal, macd_hist = calculate_macd(ohlcv.close, sg.macd_fast, sg.macd_slow, sg.macd_signal)
    
    # Your signal condition
    return rsi < sg.rsi_oversold && macd_hist[end] > 0
end

function generate_sell_signal(sg::MySignalGenerator, s::SC, ai, ats)
    # Move your sell signal logic here
    ohlcv = s.universe[ai].ohlcv
    
    rsi = calculate_rsi(ohlcv.close, sg.rsi_period)
    macd_line, macd_signal, macd_hist = calculate_macd(ohlcv.close, sg.macd_fast, sg.macd_slow, sg.macd_signal)
    
    return rsi > sg.rsi_overbought && macd_hist[end] < 0
end

# Optional: implement custom trading conditions
function should_trade(sg::MySignalGenerator, s::SC, ai, ats)
    # Move any trading condition logic here
    # For example, time-based restrictions, volatility checks, etc.
    return true  # Or your custom conditions
end
```

### Step 3: Migrate Utility Functions

Move any custom utility functions to appropriate locations:

#### Option 1: Keep in Signal Generator (Recommended for strategy-specific utilities)
```julia
# Add to your signal generator file
function calculate_rsi(prices::Vector{Float64}, period::Int)
    # Your RSI calculation logic
end

function calculate_macd(prices::Vector{Float64}, fast::Int, slow::Int, signal::Int)
    # Your MACD calculation logic
end
```

#### Option 2: Add to Framework Utilities (For reusable utilities)
```julia
# Add to src/utilities/math_utils.jl if it's generally useful
function calculate_rsi(prices::Vector{Float64}, period::Int)
    # Implementation
end
```

### Step 4: Update Configuration

#### SurgeV4 Configuration
```julia
# Hardcoded in strategy
const ASSETS = ["BTC/USDT", "ETH/USDT"]
const EXCHANGE = :phemex
```

#### StrategyFramework Configuration
```bash
# Environment variables
export STRATEGY_ID="my_migrated_strategy"
export ASSETS_FLAG="production"
export WATCHER_EXC="phemex"
```

```julia
# Asset configuration
setassets!(:production, :phemex, ["BTC/USDT", "ETH/USDT"])
setassets!(:test, :phemex, ["BTC/USDT"])
```

### Step 5: Update Strategy Registration

#### Update your `user/planar.toml`:
```toml
[strategies.my_migrated_strategy]
module = "StrategyFramework"
signal_generator = "MySignalGenerator"  # Your signal generator
assets_flag = "production"
exchange = "phemex"

[strategies.my_migrated_strategy.params]
rsi_period = 14
rsi_oversold = 30.0
rsi_overbought = 70.0
macd_fast = 12
macd_slow = 26
macd_signal = 9
```

## Code Examples

### Example 1: Simple Moving Average Strategy

#### SurgeV4 Version
```julia
# SurgeV4 - everything mixed together
module SurgeV4MA

const SHORT_MA = 10
const LONG_MA = 20

function call!(::ResetStrategy, s::SC, args...)
    # Initialization mixed with signal logic
    s.config[:short_ma] = SHORT_MA
    s.config[:long_ma] = LONG_MA
end

function call!(::StartStrategy, s::SC, args...)
    # Trading logic mixed with infrastructure
    for ai in s.universe
        ohlcv = s.universe[ai].ohlcv
        
        if length(ohlcv.close) >= LONG_MA
            short_ma = mean(ohlcv.close[end-SHORT_MA+1:end])
            long_ma = mean(ohlcv.close[end-LONG_MA+1:end])
            
            if short_ma > long_ma && !hasposition(s, ai)
                # Buy logic
                trade!(s, ai, ...)
            elseif short_ma < long_ma && hasposition(s, ai)
                # Sell logic
                trade!(s, ai, ...)
            end
        end
    end
end

end
```

#### StrategyFramework Version
```julia
# StrategyFramework - clean separation
using StrategyFramework
using Statistics

struct MASignalGenerator <: SignalGenerator
    short_period::Int
    long_period::Int
    
    MASignalGenerator(short=10, long=20) = new(short, long)
end

function generate_buy_signal(sg::MASignalGenerator, s::SC, ai, ats)
    ohlcv = s.universe[ai].ohlcv
    
    if length(ohlcv.close) < sg.long_period
        return false
    end
    
    short_ma = mean(ohlcv.close[end-sg.short_period+1:end])
    long_ma = mean(ohlcv.close[end-sg.long_period+1:end])
    
    return short_ma > long_ma
end

function generate_sell_signal(sg::MASignalGenerator, s::SC, ai, ats)
    ohlcv = s.universe[ai].ohlcv
    
    if length(ohlcv.close) < sg.long_period
        return false
    end
    
    short_ma = mean(ohlcv.close[end-sg.short_period+1:end])
    long_ma = mean(ohlcv.close[end-sg.long_period+1:end])
    
    return short_ma < long_ma
end
```

### Example 2: Complex Multi-Indicator Strategy

#### SurgeV4 Version (Simplified)
```julia
module SurgeV4Complex

# Parameters scattered throughout
const RSI_PERIOD = 14
const BB_PERIOD = 20
const BB_STD = 2.0

function complex_signal_logic(s, ai)
    # Complex logic mixed with infrastructure
    ohlcv = s.universe[ai].ohlcv
    
    # RSI calculation
    rsi = calculate_rsi(ohlcv.close, RSI_PERIOD)
    
    # Bollinger Bands calculation
    bb_upper, bb_lower = calculate_bb(ohlcv.close, BB_PERIOD, BB_STD)
    
    # Volume analysis
    volume_ma = mean(ohlcv.volume[end-10:end])
    
    # Complex signal logic
    buy_signal = rsi < 30 && ohlcv.close[end] < bb_lower && ohlcv.volume[end] > volume_ma * 1.5
    sell_signal = rsi > 70 && ohlcv.close[end] > bb_upper
    
    return buy_signal, sell_signal
end

function call!(::StartStrategy, s::SC, args...)
    for ai in s.universe
        buy_signal, sell_signal = complex_signal_logic(s, ai)
        
        if buy_signal && !hasposition(s, ai)
            # Buy logic with infrastructure mixed in
        elseif sell_signal && hasposition(s, ai)
            # Sell logic with infrastructure mixed in
        end
    end
end

end
```

#### StrategyFramework Version
```julia
using StrategyFramework
using Statistics

struct ComplexSignalGenerator <: SignalGenerator
    rsi_period::Int
    rsi_oversold::Float64
    rsi_overbought::Float64
    bb_period::Int
    bb_std::Float64
    volume_period::Int
    volume_multiplier::Float64
    
    ComplexSignalGenerator(;
        rsi_period=14,
        rsi_oversold=30.0,
        rsi_overbought=70.0,
        bb_period=20,
        bb_std=2.0,
        volume_period=10,
        volume_multiplier=1.5
    ) = new(rsi_period, rsi_oversold, rsi_overbought, bb_period, bb_std, volume_period, volume_multiplier)
end

# Helper functions (could be moved to utilities if reusable)
function calculate_rsi(prices::Vector{Float64}, period::Int)
    # RSI calculation implementation
end

function calculate_bollinger_bands(prices::Vector{Float64}, period::Int, std_dev::Float64)
    # Bollinger Bands calculation implementation
end

function generate_buy_signal(sg::ComplexSignalGenerator, s::SC, ai, ats)
    ohlcv = s.universe[ai].ohlcv
    
    # Check if we have enough data
    min_data = max(sg.rsi_period, sg.bb_period, sg.volume_period)
    if length(ohlcv.close) < min_data
        return false
    end
    
    # Calculate indicators
    rsi = calculate_rsi(ohlcv.close, sg.rsi_period)
    bb_upper, bb_lower = calculate_bollinger_bands(ohlcv.close, sg.bb_period, sg.bb_std)
    volume_ma = mean(ohlcv.volume[end-sg.volume_period+1:end])
    
    # Signal logic
    rsi_condition = rsi < sg.rsi_oversold
    bb_condition = ohlcv.close[end] < bb_lower
    volume_condition = ohlcv.volume[end] > volume_ma * sg.volume_multiplier
    
    return rsi_condition && bb_condition && volume_condition
end

function generate_sell_signal(sg::ComplexSignalGenerator, s::SC, ai, ats)
    ohlcv = s.universe[ai].ohlcv
    
    min_data = max(sg.rsi_period, sg.bb_period)
    if length(ohlcv.close) < min_data
        return false
    end
    
    rsi = calculate_rsi(ohlcv.close, sg.rsi_period)
    bb_upper, bb_lower = calculate_bollinger_bands(ohlcv.close, sg.bb_period, sg.bb_std)
    
    rsi_condition = rsi > sg.rsi_overbought
    bb_condition = ohlcv.close[end] > bb_upper
    
    return rsi_condition && bb_condition
end

function should_trade(sg::ComplexSignalGenerator, s::SC, ai, ats)
    # Add any additional trading conditions
    # For example, time-based restrictions, market conditions, etc.
    
    # Don't trade during low liquidity periods
    ohlcv = s.universe[ai].ohlcv
    if length(ohlcv.volume) >= sg.volume_period
        recent_volume = mean(ohlcv.volume[end-sg.volume_period+1:end])
        if recent_volume < 1000  # Minimum volume threshold
            return false
        end
    end
    
    return true
end
```

## Configuration Changes

### Environment Variables Migration

#### SurgeV4 Approach
```julia
# Hardcoded in strategy
const EXCHANGE = :phemex
const ASSETS = ["BTC/USDT", "ETH/USDT"]
const TIMEFRAME = tf"1m"
```

#### StrategyFramework Approach
```bash
# Set via environment variables
export STRATEGY_ID="my_strategy"
export ASSETS_FLAG="production"
export WATCHER_EXC="phemex"
export OHLCV_METHOD="ccxt"
```

### Parameter Management Migration

#### SurgeV4 Approach
```julia
# Parameters scattered throughout code
const RSI_PERIOD = 14
const MA_SHORT = 10
const MA_LONG = 20

# Or in config dict
s.config[:rsi_period] = 14
```

#### StrategyFramework Approach
```julia
# Structured in signal generator
struct MySignalGenerator <: SignalGenerator
    rsi_period::Int
    ma_short::Int
    ma_long::Int
end

# Or using parameter management system
register_parameter!(ParameterSpec("rsi_period", Int, 14, (5, 30)))
register_parameter!(ParameterSpec("ma_short", Int, 10, (5, 20)))
register_parameter!(ParameterSpec("ma_long", Int, 20, (15, 50)))
```

### Asset Configuration Migration

#### SurgeV4 Approach
```julia
# Hardcoded asset list
const ASSETS = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
```

#### StrategyFramework Approach
```julia
# Flexible asset configuration
setassets!(:production, :phemex, ["BTC/USDT", "ETH/USDT", "ADA/USDT"])
setassets!(:test, :phemex, ["BTC/USDT"])
setassets!(:development, :phemex, ["BTC/USDT", "ETH/USDT"])

# Use via environment
ENV["ASSETS_FLAG"] = "production"  # or "test" or "development"
```

## Testing Your Migration

### 1. Unit Testing Your Signal Generator

```julia
using Test
using StrategyFramework

@testset "Signal Generator Tests" begin
    sg = MySignalGenerator(rsi_period=14, rsi_oversold=30.0, rsi_overbought=70.0)
    
    # Test signal generation with mock data
    mock_ohlcv = create_mock_ohlcv_data()
    mock_strategy = create_mock_strategy(mock_ohlcv)
    mock_ai = create_mock_asset_instance()
    
    # Test buy signal
    buy_signal = generate_buy_signal(sg, mock_strategy, mock_ai, now())
    @test isa(buy_signal, Bool)
    
    # Test sell signal
    sell_signal = generate_sell_signal(sg, mock_strategy, mock_ai, now())
    @test isa(sell_signal, Bool)
    
    # Test should_trade
    should_trade_result = should_trade(sg, mock_strategy, mock_ai, now())
    @test isa(should_trade_result, Bool)
end
```

### 2. Integration Testing

```julia
@testset "Integration Tests" begin
    # Test with StrategyFramework
    sg = MySignalGenerator()
    
    # Test strategy initialization
    # Test signal integration
    # Test parameter management
end
```

### 3. Backtesting Comparison

```julia
# Compare results between SurgeV4 and StrategyFramework
# Run same backtest period with both implementations
# Verify similar performance metrics
```

## Compatibility Utilities

### SurgeV4 Compatibility Layer

If you need to maintain some SurgeV4 compatibility during migration, you can create compatibility utilities:

```julia
# compatibility.jl
module SurgeV4Compatibility

using StrategyFramework

# Wrapper to make SurgeV4-style functions work
function surge_style_signal(s::SC, ai, signal_func::Function)
    # Convert StrategyFramework context to SurgeV4-style
    return signal_func(s, ai)
end

# Parameter compatibility
function get_surge_param(s::SC, key::Symbol, default)
    return get(s.config, key, default)
end

# Asset compatibility
function get_surge_assets(s::SC)
    return get_current_assets()
end

end
```

### Gradual Migration Helper

```julia
# gradual_migration.jl
struct HybridSignalGenerator <: SignalGenerator
    surge_buy_func::Function
    surge_sell_func::Function
    
    HybridSignalGenerator(buy_func, sell_func) = new(buy_func, sell_func)
end

function generate_buy_signal(sg::HybridSignalGenerator, s::SC, ai, ats)
    # Call your existing SurgeV4 buy logic
    return sg.surge_buy_func(s, ai, ats)
end

function generate_sell_signal(sg::HybridSignalGenerator, s::SC, ai, ats)
    # Call your existing SurgeV4 sell logic
    return sg.surge_sell_func(s, ai, ats)
end
```

## Troubleshooting

### Common Migration Issues

#### 1. Signal Logic Not Triggering

**Problem**: Signals are not being generated as expected.

**Solution**:
- Check that your signal generator is properly registered
- Verify that `generate_buy_signal` and `generate_sell_signal` return boolean values
- Add debug logging to your signal methods
- Ensure you have sufficient data for your indicators

```julia
function generate_buy_signal(sg::MySignalGenerator, s::SC, ai, ats)
    @debug "Checking buy signal" ai=ai ats=ats
    
    ohlcv = s.universe[ai].ohlcv
    if length(ohlcv.close) < sg.required_data_points
        @debug "Insufficient data" available=length(ohlcv.close) required=sg.required_data_points
        return false
    end
    
    # Your signal logic
    result = your_signal_condition
    @debug "Buy signal result" result=result
    return result
end
```

#### 2. Configuration Not Loading

**Problem**: Environment variables or configuration not being applied.

**Solution**:
- Verify environment variables are set correctly
- Check that `__init__()` function is being called
- Ensure asset configuration is set before strategy starts

```julia
# Debug configuration
@info "Current configuration" ASSETS_FLAG=ASSETS_FLAG[] WATCHER_EXC=WATCHER_EXC[] current_assets=get_current_assets()
```

#### 3. Parameter Access Issues

**Problem**: Cannot access parameters that were available in SurgeV4.

**Solution**:
- Move parameters to signal generator struct
- Use parameter management system
- Access strategy configuration through `s.config`

```julia
# Instead of direct access
# old_value = RSI_PERIOD

# Use signal generator parameters
function generate_buy_signal(sg::MySignalGenerator, s::SC, ai, ats)
    rsi_period = sg.rsi_period  # From struct
    # or
    rsi_period = get_parameter("rsi_period", 14)  # From parameter system
end
```

#### 4. Performance Differences

**Problem**: Strategy performance differs between SurgeV4 and StrategyFramework.

**Solution**:
- Verify signal logic is identical
- Check timing differences in signal generation
- Ensure data access patterns are the same
- Compare indicator calculations

```julia
# Add performance comparison logging
@info "Signal comparison" surgev4_signal=old_signal framework_signal=new_signal
```

### Migration Checklist

- [ ] Identified all signal logic in SurgeV4
- [ ] Created signal generator struct with parameters
- [ ] Implemented `generate_buy_signal` method
- [ ] Implemented `generate_sell_signal` method
- [ ] Implemented `should_trade` method (if needed)
- [ ] Migrated utility functions
- [ ] Updated configuration (environment variables, assets)
- [ ] Updated strategy registration in `planar.toml`
- [ ] Created unit tests for signal generator
- [ ] Ran integration tests
- [ ] Compared backtest results
- [ ] Verified performance metrics
- [ ] Updated documentation

### Getting Help

If you encounter issues during migration:

1. **Check the Examples**: Review the code examples in this guide
2. **Run Tests**: Use the test suite to verify your implementation
3. **Debug Logging**: Add debug statements to understand execution flow
4. **Compare Outputs**: Compare signal generation between old and new implementations
5. **Consult Documentation**: Review the main README and API documentation

### Best Practices for Migration

1. **Migrate Incrementally**: Start with simple signal logic, then add complexity
2. **Test Thoroughly**: Create comprehensive tests for your signal generator
3. **Keep SurgeV4 Backup**: Maintain your original SurgeV4 implementation during migration
4. **Document Changes**: Keep notes on what you've changed and why
5. **Validate Results**: Compare performance metrics between implementations

## Conclusion

Migrating from SurgeV4 to StrategyFramework provides significant benefits in terms of code organization, testability, and maintainability. While the migration requires some effort, the structured approach outlined in this guide should make the process straightforward.

The key is to focus on extracting your signal logic into the clean `SignalGenerator` interface while leveraging the framework's infrastructure for everything else. This separation of concerns will make your strategies more robust and easier to maintain going forward.