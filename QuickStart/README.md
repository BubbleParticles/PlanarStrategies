# QuickStart Trading Strategy

QuickStart is a comprehensive foundation for building trading strategies in the Planar ecosystem. It extracts all the essential trading infrastructure, utilities, and risk management from SurgeV4 while providing a clean, customizable interface for implementing your own signal generation logic.

## Overview

QuickStart is designed as a **strategy framework** rather than a complete trading strategy. It provides all the complex infrastructure needed for professional trading while allowing you to focus entirely on signal generation - the core intelligence of your strategy.

### How QuickStart Differs from SurgeV4

| Aspect | SurgeV4 | QuickStart |
|--------|---------|------------|
| **Purpose** | Complete SMA crossover strategy | Customizable strategy framework |
| **Signal Logic** | Built-in SMA crossover with OBV confirmation | Placeholder functions you implement |
| **Indicators** | Pre-defined: SMA, ROC, VTX, OBV, KAMA, ATR | User-defined via `setsignals!()` function |
| **Customization** | Requires modifying core strategy files | Clean interface via `signal_placeholders.jl` |
| **Use Case** | Specific momentum-based strategy | Foundation for any signal-based strategy |
| **Infrastructure** | Complete trading framework | **Same complete trading framework** |
| **Risk Management** | Advanced position sizing and controls | **Same advanced position sizing and controls** |
| **Market Making** | Built-in market making capabilities | **Same built-in market making capabilities** |
| **Multi-Mode Support** | Sim, paper, and live trading | **Same sim, paper, and live trading** |

**Key Insight**: QuickStart gives you 95% of SurgeV4's sophisticated infrastructure while letting you implement the 5% that matters most - your unique trading signals.

### Key Features

- **Complete Trading Infrastructure**: All utilities from SurgeV4 for order management, position sizing, and risk controls
- **Customizable Signal Generation**: Simple placeholder functions that you can replace with your own logic
- **Risk Management**: Advanced position sizing with volatility adjustments, leverage management, and drawdown protection
- **Market Making**: Built-in market making capabilities with spread calculations
- **Multi-Mode Support**: Works seamlessly across simulation, paper trading, and live trading
- **Performance Optimized**: Efficient execution with optional profiling support

## Quick Start

### 1. Basic Setup

The strategy is already configured and ready to use. The main files are:

```
user/strategies/QuickStart/
├── src/
│   ├── QuickStart.jl           # Main strategy module
│   ├── utils.jl                # Core utilities
│   ├── call_utils.jl           # Order and asset management
│   ├── trade_utils.jl          # Trading execution utilities
│   └── signal_placeholders.jl  # Your customization point
├── Project.toml                # Dependencies
└── README.md                   # This file
```

### 2. Implementing Your Signals

The core customization happens in `src/signal_placeholders.jl`. This file contains three key functions that define your strategy's intelligence:

#### `setsignals!(s)` - Initialize Your Indicators
```julia
function setsignals!(s)
    # Define your indicators here - this runs once during strategy initialization
    attrs = s.attrs
    attrs[:signals_set] = false
    sigdefs = attrs[:signals_def] = signals(
        # Define your indicators with their parameters
        :my_indicator => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
        # Add more indicators as needed
    )
    inittrends!(s, keys(sigdefs.defs))
end
```

#### `isbuy(s::SC, ai, ats)` - Buy Signal Logic
```julia
function isbuy(s::SC, ai, ats)
    # Your buy signal logic here
    # Parameters:
    #   s   = Strategy instance (access to all utilities and data)
    #   ai  = Asset instance (current trading pair)
    #   ats = Current timestamp
    
    # Get indicator values
    my_signal = signal_value(s, ai, :my_indicator, ats)
    
    # Always validate signals before using them
    if isnothing(my_signal)
        return false
    end
    
    # Your buy condition logic
    return my_signal > some_threshold
end
```

#### `issell(s::SC, ai, ats)` - Sell Signal Logic
```julia
function issell(s::SC, ai, ats)
    # Your sell signal logic here
    # Same parameters as isbuy()
    
    # Get indicator values
    my_signal = signal_value(s, ai, :my_indicator, ats)
    
    # Always validate signals
    if isnothing(my_signal)
        return false
    end
    
    # Your sell condition logic
    return my_signal < some_threshold
end
```

### Signal Function Parameters Explained

- **`s::SC`**: The strategy instance containing all utilities, configuration, and state
- **`ai`**: Asset instance representing the current trading pair (e.g., BTC/USDT)
- **`ats`**: Current timestamp for the signal evaluation

### Available Data in Signal Functions

Within your signal functions, you have access to:

```julia
# Get indicator values
signal_value(s, ai, :indicator_name, ats)

# Get OHLCV data
data = ohlcv(ai)
idx = dateindex(data, ats)
current_price = data.close[idx]
current_volume = data.volume[idx]

# Get current position information
pos = position(ai)
cash = cash(s.universe)

# Access strategy configuration
leverage = s.def_lev
```

### 3. Ready-to-Use Examples

QuickStart includes a comprehensive set of example implementations in the `examples/` directory. Each example demonstrates different trading approaches and complexity levels:

#### Available Examples

1. **`simple_ma_crossover.jl`** - Basic moving average crossover (great starting point)
2. **`rsi_mean_reversion.jl`** - RSI-based mean reversion strategy
3. **`bollinger_bands.jl`** - Bollinger Bands breakout strategy
4. **`macd_momentum.jl`** - MACD momentum strategy
5. **`multi_timeframe.jl`** - Multiple timeframe analysis
6. **`trend_following.jl`** - Trend following with multiple confirmations
7. **`advanced_composite.jl`** - Complex multi-indicator strategy

#### Quick Start with Examples

1. **Browse the examples**: Look at `examples/README.md` for detailed descriptions
2. **Choose an example** that matches your trading style
3. **Copy the code** from the example file
4. **Paste into** `src/signal_placeholders.jl`
5. **Customize parameters** to your preferences
6. **Test in simulation** before going live

#### Example: Simple Moving Average Strategy

Here's the complete `simple_ma_crossover.jl` example:

```julia
# Copy this into src/signal_placeholders.jl

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    sigdefs = attrs[:signals_def] = signals(
        :sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_long => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ai, ats)
    short_ma = signal_value(s, ai, :sma_short, ats)
    long_ma = signal_value(s, ai, :sma_long, ats)
    
    # Always validate signals
    if isnothing(short_ma) || isnothing(long_ma)
        return false
    end
    
    # Buy when short MA crosses above long MA
    return short_ma > long_ma
end

function issell(s::SC, ai, ats)
    short_ma = signal_value(s, ai, :sma_short, ats)
    long_ma = signal_value(s, ai, :sma_long, ats)
    
    if isnothing(short_ma) || isnothing(long_ma)
        return false
    end
    
    # Sell when short MA crosses below long MA
    return short_ma < long_ma
end
```

**That's it!** This complete example will give you a working moving average crossover strategy with all the sophisticated risk management and execution logic from SurgeV4.

## Complete Utility Reference

QuickStart provides an extensive library of utilities organized across several modules. These are the same battle-tested utilities from SurgeV4, giving you professional-grade trading infrastructure.

### Core Utilities (`utils.jl`)

#### Environment and Configuration Management
```julia
# Environment configuration
env_strategy_id()           # Get current strategy ID from environment
env_assets_flag()           # Get asset configuration flag  
setassets!(kind)           # Set asset configuration type (e.g., "default", "custom")

# Strategy configuration
apply_params!(s, params)    # Apply parameter set to strategy
get_params_tuple(s)        # Get current parameters as tuple for optimization
```

#### Position and Order Management
```julia
# Position control
closeposition!(s, ai, ts; pside=nothing)  # Safely close position with retry logic
cancelorders!(s, ai; side=nothing)        # Cancel orders with automatic retry
handle_fail(s, ai, ats, ts; kwargs...)    # Handle failed orders with fallback strategies

# Order utilities
simfees(s, t)              # Calculate simulation fees based on order type
```

#### Async Operations and Locking
```julia
# Live trading utilities
liveasync(f, s)            # Execute function asynchronously in live mode only
livelock(l, s)             # Strategy-appropriate locking (no-op in simulation)

# Performance and monitoring
with_profiling(f, s, ts)   # Execute function with optional profiling
start_telegram(s)          # Initialize Telegram bot for remote monitoring
```

### Trading Utilities (`trade_utils.jl`)

#### Core Trading Functions
```julia
# Primary trading function - handles everything automatically
trade!(s, ai, ats, ts; 
       pos=nothing,        # Position side (Long/Short) - auto-detected if nil
       side=nothing,       # Order side (Buy/Sell) - auto-detected if nil  
       amount=nothing,     # Trade amount - auto-calculated if nil
       ordertype=nothing,  # Order type - uses strategy default if nil
       kwargs...)          # Additional order parameters

# Price calculation utilities
baseincr(s, ai; modifier=1.0)              # Calculate base price increment
getincr(s, ai, ats; side, base=nothing)    # Get buy/sell price increments with spread
```

#### Market Making System
```julia
# Market making functions (automatic liquidity provision)
market_make(s, ai, ts; ats, pos)                    # Execute market making logic
should_market_make(s, ai, ats; pos)                 # Check if market making is appropriate
ensure_market_make(s, ai, ats, ts; pos)             # Ensure market making orders are active
get_make_amount(s, ai, pos)                         # Calculate optimal market making amount
```

#### Position Sizing and Risk Management
```julia
# Advanced position sizing (considers volatility, trend, drawdown)
calculate_position_adjustment(s, ai, ats)           # Calculate volatility-based adjustment
get_target_position_size(s, ai, ps, ats)           # Get target position size with adjustments
trade_amount(s, ai, ats, ps)                       # Calculate trade amount with risk controls
calculate_trade_amount(s, ai, ats, ps, target_pos) # Calculate specific trade amount needed
```

### Asset and Order Management (`call_utils.jl`)

#### Asset Configuration
```julia
# Asset management
get_exchange_assets(exc, flag)    # Get assets for specific exchange and configuration
get_custom_assets(flag)           # Get custom asset configurations from environment

# Order error handling (automatic)
# - Handles OrderError exceptions with fallback strategies
# - Automatically retries failed orders with different parameters
# - Provides graceful degradation for order execution issues
```

### Data Access Functions

#### Market Data
```julia
# OHLCV data access
data = ohlcv(ai)                  # Get OHLCV data for asset
idx = dateindex(data, ats)        # Get index for specific timestamp
current_price = data.close[idx]   # Get current close price
current_volume = data.volume[idx] # Get current volume

# Signal data access  
signal_value(s, ai, :signal_name, ats)  # Get indicator value at timestamp
```

#### Position and Balance Information
```julia
# Position information
pos = position(ai)                # Get current position
cash_available = cash(s.universe) # Get available cash
total_value = value(s.universe)   # Get total portfolio value

# Risk metrics
peak_cash = s.attrs[:peak_cash]   # Track peak cash for drawdown calculation
```

### Indicator Library

QuickStart supports all indicators from the Planar ecosystem:

#### Technical Indicators
```julia
# Moving averages
:sma => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20))
:ema => (; type=oti.EMA{DFT}, tf=tf"1m", params=(; period=20))
:kama => (; type=oti.KAMA{DFT}, tf=tf"1m", params=(; period=20))

# Oscillators  
:rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14))
:macd => (; type=oti.MACD{DFT}, tf=tf"5m", params=(; fast=12, slow=26, signal=9))
:stoch => (; type=oti.Stochastic{DFT}, tf=tf"1m", params=(; k_period=14, d_period=3))

# Volatility indicators
:atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14))
:bb => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0))

# Volume indicators
:obv => (; type=oti.OBV{DFT}, tf=tf"1m", params=NamedTuple())
:vwap => (; type=oti.VWAP{DFT}, tf=tf"1m", params=NamedTuple())

# Trend indicators
:vtx => (; type=oti.VTX{DFT}, tf=tf"1m", params=(; period=14))
:adx => (; type=oti.ADX{DFT}, tf=tf"1m", params=(; period=14))
```

### Utility Functions for Signal Development

#### Common Patterns
```julia
# Check if position exists
has_position = !iszero(position(ai))

# Check position side
is_long = position(ai) > 0
is_short = position(ai) < 0

# Get position size
position_size = abs(position(ai))

# Calculate percentage change
pct_change = (current_price - previous_price) / previous_price * 100

# Time-based conditions
is_market_hours = hour(ats) >= 9 && hour(ats) <= 16  # Example market hours
```

### Position and Risk Management

#### Dynamic Position Sizing
QuickStart includes sophisticated position sizing that considers:
- **Volatility Adjustment**: Uses ATR (Average True Range) to adjust position size based on market volatility
- **Trend Strength**: Uses KAMA (Kaufman Adaptive Moving Average) for trend-based adjustments
- **Market Conditions**: Uses VTX (Vortex Indicator) for additional market state analysis

#### Risk Controls
- **Leverage Management**: Automatic leverage adjustment based on market conditions (0.1x to 5x range)
- **Drawdown Protection**: Position sizing reduces during drawdown periods
- **Cash Management**: Reserves cash for risk management and ensures sufficient margin

#### Example: Understanding Position Sizing
```julia
# The strategy automatically calculates position adjustments
adjustment_mult = calculate_position_adjustment(s, ai, ats)
this_lev = s.def_lev * adjustment_mult

# Leverage is clamped to safe bounds
this_lev = clamp(this_lev, 0.1, 5.0)
```

## Configuration

### Strategy Parameters

QuickStart inherits comprehensive parameter sets from SurgeV4:

- `base_params` - Basic configuration parameters
- `best_params` - Optimized parameter set
- `high_profit_params` - High-risk, high-reward parameters

### Environment Variables

Key environment variables for configuration:

- `STRATEGY_ID` - Unique identifier for your strategy instance
- `{STRATEGY_ID}_ASSETS_FLAG` - Asset configuration (e.g., "default", "custom")
- `{STRATEGY_ID}_WATCHER_EXC` - Exchange for data watching (default: "bybit")
- `{STRATEGY_ID}_OHLCV_METHOD` - OHLCV data method (default: "candles")
- `STRATEGY_PROFILING` - Enable profiling (set to "1")

### Asset Configuration

Configure assets in your `user/planar.toml`:

```toml
[strategies.QuickStart]
assets = ["BTC/USDT:USDT", "ETH/USDT:USDT"]
exchange = "phemex"
margin = "Isolated"
```

## Advanced Usage

### Custom Indicators

You can use any indicator from the Planar ecosystem:

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :macd => (; type=oti.MACD{DFT}, tf=tf"5m", params=(; fast=12, slow=26, signal=9)),
        :bb => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
    )
    inittrends!(s, keys(sigdefs.defs))
end
```

### Multiple Timeframes

Work with different timeframes for different signals:

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    sigdefs = attrs[:signals_def] = signals(
        :trend_1h => (; type=oti.SMA{DFT}, tf=tf"1h", params=(; period=20)),
        :entry_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
    )
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ai, ats)
    # Long-term trend from 1h
    trend = signal_value(s, ai, :trend_1h, ats)
    # Short-term entry from 1m
    rsi = signal_value(s, ai, :entry_1m, ats)
    
    if isnothing(trend) || isnothing(rsi)
        return false
    end
    
    # Buy when in uptrend and RSI is oversold
    return trend > 0 && rsi < 30
end
```

### Complex Signal Logic

Implement sophisticated signal combinations:

```julia
function isbuy(s::SC, ai, ats)
    # Get multiple signals
    rsi = signal_value(s, ai, :rsi, ats)
    macd = signal_value(s, ai, :macd, ats)
    bb_upper = signal_value(s, ai, :bb_upper, ats)
    bb_lower = signal_value(s, ai, :bb_lower, ats)
    
    # Get current price
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Complex buy condition
    return !isnothing(rsi) && !isnothing(macd) && 
           !isnothing(bb_lower) &&
           rsi < 30 &&                    # Oversold
           macd > 0 &&                    # MACD bullish
           current_price < bb_lower       # Price below lower Bollinger Band
end
```

## Understanding the Framework Architecture

### What QuickStart Provides (The 95%)

QuickStart gives you all the complex, battle-tested infrastructure from SurgeV4:

#### 1. **Advanced Risk Management**
- **Dynamic Position Sizing**: Automatically adjusts position size based on market volatility (ATR)
- **Trend-Aware Leverage**: Uses KAMA and VTX indicators to adjust leverage (0.1x to 5x range)
- **Drawdown Protection**: Reduces position sizes during drawdown periods
- **Cash Management**: Maintains cash reserves and ensures sufficient margin

#### 2. **Sophisticated Order Management**
- **Smart Order Types**: Automatically selects optimal order types (limit, market, reduce)
- **Error Handling**: Automatic fallback strategies for failed orders
- **Stale Order Management**: Automatically cancels and replaces stale orders
- **Market Making**: Built-in liquidity provision with spread calculations

#### 3. **Multi-Mode Execution**
- **Simulation Mode**: Fast backtesting with accurate fee calculations
- **Paper Trading**: Real-time trading with simulated orders
- **Live Trading**: Full production trading with all safety features

#### 4. **Professional Infrastructure**
- **Data Management**: Robust OHLCV data handling with validation
- **Performance Tracking**: PnL calculation, drawdown tracking, trade statistics
- **Remote Monitoring**: Telegram bot integration for live monitoring
- **Optimization Support**: Parameter optimization integration

### What You Implement (The 5%)

You focus on the core intelligence - the signal generation:

```julia
function setsignals!(s)
    # Define your indicators
end

function isbuy(s::SC, ai, ats)
    # Your buy logic
    return true_or_false
end

function issell(s::SC, ai, ats)  
    # Your sell logic
    return true_or_false
end
```

### The Power of This Approach

This separation means:
- **You don't reinvent the wheel** - All the complex trading infrastructure is provided
- **You focus on alpha generation** - Spend time on what makes money, not plumbing
- **Professional-grade execution** - Your signals get executed with institutional-quality risk management
- **Rapid iteration** - Test new signal ideas without rebuilding infrastructure

## Best Practices for Signal Development

### 1. Always Validate Signals
Never assume indicator values are valid:

```julia
function isbuy(s::SC, ai, ats)
    signal = signal_value(s, ai, :my_signal, ats)
    
    # Always validate before using
    if isnothing(signal) || isnan(signal) || isinf(signal)
        return false
    end
    
    # Now safe to use signal
    return signal > threshold
end
```

### 2. Use Multiple Confirmation Signals
Combine multiple indicators for more robust signals:

```julia
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    macd = signal_value(s, ai, :macd, ats)
    trend = signal_value(s, ai, :trend, ats)
    
    # Validate all signals
    if any(isnothing, [rsi, macd, trend])
        return false
    end
    
    # Multiple confirmations
    return rsi < 30 &&          # Oversold
           macd > 0 &&          # Bullish momentum  
           trend > 0            # Uptrend
end
```

### 3. Respect the Framework's Risk Management
Don't fight the built-in risk controls:

```julia
# ✅ DO: Let the framework handle position sizing
function isbuy(s::SC, ai, ats)
    # Just return true/false for your signal
    return my_buy_condition
end

# ❌ DON'T: Try to override position sizing in signal functions
function isbuy(s::SC, ai, ats)
    if my_buy_condition
        # Don't do this - let the framework handle sizing
        trade!(s, ai, ats, now(); amount=1000.0)  # ❌ Wrong!
    end
    return false
end
```

### 4. Performance Optimization
Keep signal functions fast and efficient:

```julia
# ✅ DO: Use pre-calculated indicators
function isbuy(s::SC, ai, ats)
    sma = signal_value(s, ai, :sma, ats)  # Pre-calculated
    return !isnothing(sma) && sma > threshold
end

# ❌ DON'T: Calculate indicators in signal functions
function isbuy(s::SC, ai, ats)
    data = ohlcv(ai)
    # Don't calculate SMA here every time - too slow!
    sma = mean(data.close[end-19:end])  # ❌ Inefficient!
    return sma > threshold
end
```

### 5. Comprehensive Testing Strategy

#### Phase 1: Simulation Testing
```julia
# Test with historical data first
# - Verify signal logic works correctly
# - Check for edge cases and errors
# - Validate performance metrics
```

#### Phase 2: Paper Trading
```julia
# Test with real-time data but simulated orders
# - Verify signals work with live data
# - Check timing and latency issues
# - Validate order execution logic
```

#### Phase 3: Live Trading (Small Size)
```julia
# Start with minimal position sizes
# - Monitor performance closely
# - Gradually increase size as confidence builds
# - Keep detailed logs for analysis
```

### 6. Signal Debugging and Monitoring

Add logging to understand your signals:

```julia
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    if isnothing(rsi)
        @ldebug 1 "RSI signal missing" ai ats
        return false
    end
    
    buy_signal = rsi < 30
    @ldebug 1 "Buy signal check" ai rsi buy_signal
    
    return buy_signal
end
```

### 7. Parameter Management

Use environment variables for easy parameter tuning:

```julia
function setsignals!(s)
    # Get parameters from environment with defaults
    rsi_period = parse(Int, get(ENV, "RSI_PERIOD", "14"))
    rsi_oversold = parse(Float64, get(ENV, "RSI_OVERSOLD", "30"))
    
    attrs = s.attrs
    attrs[:signals_set] = false
    attrs[:rsi_oversold] = rsi_oversold  # Store for use in signals
    
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=rsi_period)),
    )
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    threshold = s.attrs[:rsi_oversold]  # Use stored parameter
    
    return !isnothing(rsi) && rsi < threshold
end
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. No Trades Executing

**Symptoms**: Strategy runs but no trades are placed

**Diagnosis**:
```julia
# Add debug logging to your signal functions
function isbuy(s::SC, ai, ats)
    signal = signal_value(s, ai, :my_signal, ats)
    @ldebug 1 "Buy signal debug" ai signal ats
    
    result = !isnothing(signal) && signal > threshold
    @ldebug 1 "Buy decision" ai result signal threshold
    return result
end
```

**Common Causes**:
- Signal functions always return `false`
- Indicators not properly initialized in `setsignals!()`
- Insufficient cash or margin
- Position limits reached
- Signal validation failing (indicators returning `nothing`)

**Solutions**:
- Verify `isbuy()` and `issell()` logic with debug logging
- Check indicator definitions in `setsignals!()`
- Verify sufficient balance: `cash(s.universe)`
- Check position limits in strategy configuration

#### 2. Signal Values are `nothing`

**Symptoms**: `signal_value()` returns `nothing`

**Diagnosis**:
```julia
function setsignals!(s)
    @ldebug 1 "Setting up signals"
    attrs = s.attrs
    attrs[:signals_set] = false
    sigdefs = attrs[:signals_def] = signals(
        :my_signal => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    @ldebug 1 "Signal definitions" sigdefs
    inittrends!(s, keys(sigdefs.defs))
end
```

**Common Causes**:
- Indicator not defined in `setsignals!()`
- Insufficient historical data for indicator calculation
- Timeframe mismatch between indicator and strategy
- Indicator name mismatch between definition and usage

**Solutions**:
- Verify indicator names match exactly
- Ensure sufficient historical data (at least indicator period + buffer)
- Check timeframe compatibility
- Verify `inittrends!()` is called with correct keys

#### 3. Leverage and Position Sizing Issues

**Symptoms**: Unexpected position sizes or leverage values

**Understanding**: QuickStart automatically manages leverage based on:
- Base leverage setting (`s.def_lev`)
- Market volatility (ATR-based adjustment)
- Trend strength (KAMA and VTX adjustments)
- Drawdown protection

**Diagnosis**:
```julia
# Check current leverage calculation
adjustment = calculate_position_adjustment(s, ai, ats)
current_lev = s.def_lev * adjustment
final_lev = clamp(current_lev, 0.1, 5.0)
@ldebug 1 "Leverage calculation" s.def_lev adjustment current_lev final_lev
```

**Solutions**:
- Adjust base leverage (`s.def_lev`) in strategy parameters
- Check exchange-specific leverage limits
- Verify margin mode configuration (Isolated vs Cross)
- Monitor volatility adjustments in volatile markets

#### 4. Performance Issues

**Symptoms**: Strategy runs slowly or uses excessive memory

**Common Causes**:
- Complex calculations in signal functions
- Inefficient data access patterns
- Memory leaks in custom code

**Solutions**:
```julia
# ✅ Efficient signal function
function isbuy(s::SC, ai, ats)
    # Use pre-calculated indicators
    signal = signal_value(s, ai, :sma, ats)
    return !isnothing(signal) && signal > threshold
end

# ❌ Inefficient signal function  
function isbuy(s::SC, ai, ats)
    # Don't calculate indicators here
    data = ohlcv(ai)
    sma = mean(data.close[end-19:end])  # Slow!
    return sma > threshold
end
```

#### 5. Data and Timing Issues

**Symptoms**: Inconsistent signals or timing problems

**Common Causes**:
- Lookahead bias in signal calculations
- Timezone issues
- Data gaps or missing candles

**Solutions**:
- Always use `ats` parameter for time-based calculations
- Validate data availability before using
- Handle missing data gracefully

### Advanced Debugging Techniques

#### Enable Comprehensive Logging
```julia
# Set environment variable for debug logging
ENV["JULIA_DEBUG"] = "all"

# Or specific modules
ENV["JULIA_DEBUG"] = "QuickStart"
```

#### Monitor Strategy State
```julia
function isbuy(s::SC, ai, ats)
    # Log strategy state
    @ldebug 1 "Strategy state" ai ats position(ai) cash(s.universe)
    
    # Your signal logic
    signal = signal_value(s, ai, :my_signal, ats)
    @ldebug 1 "Signal state" ai signal
    
    return !isnothing(signal) && signal > threshold
end
```

#### Performance Profiling
```julia
# Enable profiling in environment
ENV["STRATEGY_PROFILING"] = "1"

# The framework will automatically profile your signal functions
```

### Getting Help

If you're still having issues:

1. **Check the examples** - Look at working implementations in `examples/`
2. **Review SurgeV4** - See how the original strategy implements similar logic
3. **Enable debug logging** - Use `@ldebug` statements to trace execution
4. **Test incrementally** - Start with simple signals and add complexity gradually
5. **Use simulation mode** - Test thoroughly before paper or live trading

## Migration from SurgeV4

If you're familiar with SurgeV4 and want to understand the differences:

### What's the Same
- **All utilities and infrastructure** - Every function from `utils.jl`, `trade_utils.jl`, and `call_utils.jl`
- **Risk management system** - Same position sizing, leverage adjustment, and drawdown protection
- **Order execution** - Same sophisticated order management and error handling
- **Market making** - Same liquidity provision capabilities
- **Multi-mode support** - Same simulation, paper, and live trading modes
- **Performance tracking** - Same PnL calculation and metrics
- **Configuration system** - Same parameter sets and environment variable support

### What's Different
- **Signal generation** - SurgeV4's specific SMA+OBV logic is replaced with customizable placeholders
- **Indicator setup** - Instead of hardcoded indicators, you define them in `setsignals!()`
- **Customization approach** - Clean interface via `signal_placeholders.jl` instead of modifying core files

### Migration Steps
1. **Copy your SurgeV4 configuration** - Same parameter sets work
2. **Extract your signal logic** - Move your custom signals to QuickStart's placeholder functions
3. **Define your indicators** - Use `setsignals!()` to set up the indicators you need
4. **Test thoroughly** - Verify behavior matches your expectations

## Advanced Customization

### Custom Risk Management
While QuickStart handles most risk management automatically, you can add custom rules:

```julia
function isbuy(s::SC, ai, ats)
    # Standard signal logic
    signal = signal_value(s, ai, :my_signal, ats)
    if isnothing(signal) || signal <= threshold
        return false
    end
    
    # Custom risk checks
    current_pos = position(ai)
    max_position = 1000.0  # Your custom limit
    
    if abs(current_pos) >= max_position
        @ldebug 1 "Position limit reached" ai current_pos max_position
        return false
    end
    
    # Check portfolio heat
    total_risk = sum(abs(position(ai)) for ai in s.universe.assets)
    max_total_risk = 5000.0
    
    if total_risk >= max_total_risk
        @ldebug 1 "Portfolio risk limit reached" total_risk max_total_risk
        return false
    end
    
    return true
end
```

### Custom Order Types
You can specify custom order parameters:

```julia
function isbuy(s::SC, ai, ats)
    if my_signal_condition
        # The framework will handle the trade with custom parameters
        # You can influence order type through strategy configuration
        return true
    end
    return false
end
```

### Integration with External Systems
QuickStart supports integration with external data sources and systems:

```julia
function setsignals!(s)
    # You can add custom data sources or external API calls here
    # Just ensure they're properly cached and don't slow down execution
    
    attrs = s.attrs
    attrs[:signals_set] = false
    attrs[:external_data] = fetch_external_data()  # Your custom function
    
    # Standard indicator setup
    sigdefs = attrs[:signals_def] = signals(
        :my_signal => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    inittrends!(s, keys(sigdefs.defs))
end
```

## Summary

QuickStart is **SurgeV4 without the specific signal logic**. It gives you:

- ✅ **All the infrastructure** - Risk management, order execution, market making
- ✅ **All the utilities** - Position management, data handling, monitoring
- ✅ **All the robustness** - Error handling, fallbacks, safety features
- ✅ **Clean customization** - Simple interface for your signal logic
- ✅ **Professional execution** - Institutional-quality trading infrastructure

**Your job**: Implement `setsignals!()`, `isbuy()`, and `issell()` functions.
**Framework's job**: Everything else.

This separation lets you focus on what generates alpha (your signals) while leveraging battle-tested infrastructure for everything else.

---

**Ready to start?** 
1. Choose an example from `examples/` that matches your trading style
2. Copy it to `src/signal_placeholders.jl`
3. Customize the parameters and logic
4. Test in simulation mode
5. Graduate to paper trading, then live trading

**Remember**: You're building on a foundation that already handles the hard parts. Focus on your signal generation logic and let QuickStart handle the rest.