# Signal Generation Best Practices

This document provides comprehensive best practices for implementing custom signal generation functions in QuickStart. These guidelines will help you create robust, efficient, and profitable trading strategies.

## Table of Contents

1. [Signal Function Architecture](#signal-function-architecture)
2. [Indicator Setup Best Practices](#indicator-setup-best-practices)
3. [Signal Validation and Error Handling](#signal-validation-and-error-handling)
4. [Performance Optimization](#performance-optimization)
5. [Testing and Debugging](#testing-and-debugging)
6. [Risk Management Integration](#risk-management-integration)
7. [Common Patterns and Anti-Patterns](#common-patterns-and-anti-patterns)
8. [Advanced Techniques](#advanced-techniques)

## Signal Function Architecture

### Core Principles

1. **Separation of Concerns**: Keep signal logic separate from execution logic
2. **Stateless Functions**: Signal functions should be pure and stateless
3. **Fail-Safe Design**: Always return `false` when in doubt
4. **Performance First**: Optimize for speed in hot paths

### The Three-Function Pattern

Every QuickStart strategy implements three core functions:

```julia
function setsignals!(s)
    # Initialize indicators - called once during strategy startup
    # Define all indicators your strategy needs
    # Set up any persistent state
end

function isbuy(s::SC, ai, ats)
    # Buy signal logic - called every polling cycle
    # Return true when buy conditions are met
    # Return false otherwise
end

function issell(s::SC, ai, ats)
    # Sell signal logic - called every polling cycle  
    # Return true when sell conditions are met
    # Return false otherwise
end
```

### Function Responsibilities

#### `setsignals!(s)` - Indicator Initialization
- **Purpose**: Set up all indicators and persistent state
- **Called**: Once during strategy initialization
- **Should**: Define indicators, initialize state, set up trends
- **Should Not**: Perform calculations, access market data, make trading decisions

#### `isbuy(s, ai, ats)` - Buy Signal Generation
- **Purpose**: Determine when to enter long positions or exit short positions
- **Called**: Every polling cycle for each asset
- **Should**: Evaluate indicators, return boolean decision
- **Should Not**: Execute trades, modify state, perform heavy calculations

#### `issell(s, ai, ats)` - Sell Signal Generation
- **Purpose**: Determine when to exit long positions or enter short positions
- **Called**: Every polling cycle for each asset
- **Should**: Evaluate indicators, return boolean decision
- **Should Not**: Execute trades, modify state, perform heavy calculations

## Indicator Setup Best Practices

### Comprehensive Indicator Definition

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define indicators with clear naming and appropriate parameters
    sigdefs = attrs[:signals_def] = signals(
        # Trend indicators
        :sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_long => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
        :ema_trend => (; type=oti.EMA{DFT}, tf=tf"5m", params=(; period=50)),
        
        # Momentum indicators
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :macd_line => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_signal => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        
        # Volatility indicators
        :atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14)),
        :bb_upper => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_lower => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        
        # Volume indicators
        :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
        :obv => (; type=oti.OBV{DFT}, tf=tf"1m", params=()),
    )
    
    # Always call inittrends! with the indicator keys
    inittrends!(s, keys(sigdefs.defs))
    
    # Store any custom parameters for use in signal functions
    attrs[:rsi_oversold] = 30.0
    attrs[:rsi_overbought] = 70.0
    attrs[:signal_lifetime] = 0.2
end
```

### Naming Conventions

- **Use descriptive names**: `:sma_short`, `:rsi_daily`, `:bb_upper`
- **Include timeframe in name**: `:trend_1h`, `:momentum_5m`
- **Group related indicators**: `:macd_line`, `:macd_signal`, `:macd_histogram`
- **Avoid generic names**: Prefer `:sma_trend` over `:sma`

### Parameter Selection Guidelines

#### Moving Averages
```julia
# Short-term trend (5-20 periods)
:sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),

# Medium-term trend (20-50 periods)  
:sma_medium => (; type=oti.SMA{DFT}, tf=tf"5m", params=(; period=20)),

# Long-term trend (50-200 periods)
:sma_long => (; type=oti.EMA{DFT}, tf=tf"1h", params=(; period=50)),
```

#### Oscillators
```julia
# RSI - Standard 14 period, adjust for timeframe
:rsi_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
:rsi_5m => (; type=oti.RSI{DFT}, tf=tf"5m", params=(; period=14)),

# MACD - Standard parameters work well across timeframes
:macd => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
```

#### Volatility Indicators
```julia
# ATR - 14 period is standard
:atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14)),

# Bollinger Bands - 20 period, 2 standard deviations
:bb => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
```

## Signal Validation and Error Handling

### The Golden Rule: Always Validate

**Never use indicator values without validation**. This is the most common source of strategy failures.

```julia
function isbuy(s::SC, ai, ats)
    # ✅ CORRECT: Always validate signals
    rsi = signal_value(s, ai, :rsi, ats)
    sma = signal_value(s, ai, :sma_short, ats)
    
    # Check for missing values
    if isnothing(rsi) || isnothing(sma)
        return false
    end
    
    # Check for invalid values
    if isnan(rsi) || isinf(rsi) || isnan(sma) || isinf(sma)
        return false
    end
    
    # Now safe to use the values
    return rsi < 30 && sma > 0
end
```

### Validation Patterns

#### Single Indicator Validation
```julia
function validate_signal(value)
    return !isnothing(value) && !isnan(value) && !isinf(value)
end

function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    if !validate_signal(rsi)
        return false
    end
    
    return rsi < 30
end
```

#### Multiple Indicator Validation
```julia
function isbuy(s::SC, ai, ats)
    # Get all required signals
    rsi = signal_value(s, ai, :rsi, ats)
    macd = signal_value(s, ai, :macd_line, ats)
    sma = signal_value(s, ai, :sma_short, ats)
    
    # Validate all at once
    if any(x -> !validate_signal(x), [rsi, macd, sma])
        return false
    end
    
    # All signals are valid, proceed with logic
    return rsi < 30 && macd > 0 && sma > 0
end
```

#### Graceful Degradation
```julia
function isbuy(s::SC, ai, ats)
    # Primary signal
    rsi = signal_value(s, ai, :rsi, ats)
    
    if validate_signal(rsi)
        # Use primary logic
        return rsi < 30
    end
    
    # Fallback to secondary signal
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    if validate_signal(sma_short) && validate_signal(sma_long)
        # Use fallback logic
        return sma_short > sma_long
    end
    
    # No valid signals available
    return false
end
```

### Error Logging

Add logging to understand validation failures:

```julia
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    if !validate_signal(rsi)
        @ldebug 1 "RSI validation failed" ai ats rsi
        return false
    end
    
    buy_signal = rsi < 30
    @ldebug 2 "Buy signal evaluation" ai ats rsi buy_signal
    
    return buy_signal
end
```

## Performance Optimization

### Hot Path Optimization

Signal functions are called frequently and must be fast:

```julia
# ✅ FAST: Use pre-calculated indicators
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)  # Pre-calculated, fast
    return validate_signal(rsi) && rsi < 30
end

# ❌ SLOW: Calculate indicators in signal functions
function isbuy(s::SC, ai, ats)
    data = ohlcv(ai)
    # This recalculates RSI every time - very slow!
    rsi = calculate_rsi(data.close, 14)
    return rsi < 30
end
```

### Memory Efficiency

Avoid unnecessary allocations:

```julia
# ✅ EFFICIENT: Minimal allocations
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    threshold = 30.0  # Constant, no allocation
    return validate_signal(rsi) && rsi < threshold
end

# ❌ INEFFICIENT: Unnecessary allocations
function isbuy(s::SC, ai, ats)
    signals = [signal_value(s, ai, :rsi, ats)]  # Unnecessary array
    thresholds = [30.0]  # Unnecessary array
    return validate_signal(signals[1]) && signals[1] < thresholds[1]
end
```

### Caching Expensive Calculations

For complex calculations, cache results:

```julia
function setsignals!(s)
    # ... indicator setup ...
    
    # Initialize cache for expensive calculations
    attrs[:calculation_cache] = Dict{Tuple{Symbol, DateTime}, Float64}()
end

function expensive_calculation(s::SC, ai, ats)
    cache = s.attrs[:calculation_cache]
    key = (ai.symbol, ats)
    
    if haskey(cache, key)
        return cache[key]
    end
    
    # Perform expensive calculation
    result = complex_calculation(s, ai, ats)
    cache[key] = result
    
    # Limit cache size to prevent memory leaks
    if length(cache) > 1000
        # Remove oldest entries
        oldest_keys = sort(collect(keys(cache)))[1:500]
        for k in oldest_keys
            delete!(cache, k)
        end
    end
    
    return result
end
```

## Testing and Debugging

### Comprehensive Testing Strategy

#### Phase 1: Unit Testing Signal Logic
```julia
# Test signal functions in isolation
function test_buy_signal()
    # Mock strategy and data
    s = create_mock_strategy()
    ai = create_mock_asset()
    ats = DateTime("2023-01-01T12:00:00")
    
    # Set up test indicators
    s.attrs[:signals_def] = test_signals()
    
    # Test various scenarios
    @test isbuy(s, ai, ats) == false  # Default case
    
    # Test with specific indicator values
    set_mock_signal_value(s, ai, :rsi, ats, 25.0)  # Oversold
    @test isbuy(s, ai, ats) == true
    
    set_mock_signal_value(s, ai, :rsi, ats, 75.0)  # Overbought
    @test isbuy(s, ai, ats) == false
end
```

#### Phase 2: Integration Testing
```julia
# Test with real historical data
function test_with_historical_data()
    # Load historical data
    data = load_test_data("BTC/USDT", "2023-01-01", "2023-01-31")
    
    # Initialize strategy
    s = initialize_test_strategy()
    ai = create_asset_instance("BTC/USDT")
    
    # Test signal generation across time series
    buy_signals = []
    sell_signals = []
    
    for timestamp in data.timestamps
        buy_sig = isbuy(s, ai, timestamp)
        sell_sig = issell(s, ai, timestamp)
        
        push!(buy_signals, buy_sig)
        push!(sell_signals, sell_sig)
    end
    
    # Validate signal characteristics
    @test sum(buy_signals) > 0  # Should generate some buy signals
    @test sum(sell_signals) > 0  # Should generate some sell signals
    @test sum(buy_signals .& sell_signals) == 0  # No simultaneous signals
end
```

### Debugging Techniques

#### Signal State Logging
```julia
function isbuy(s::SC, ai, ats)
    # Log all indicator values for debugging
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    @ldebug 1 "Signal state" ai ats rsi sma_short sma_long
    
    # Validate signals
    if !validate_signal(rsi) || !validate_signal(sma_short) || !validate_signal(sma_long)
        @ldebug 1 "Signal validation failed" ai ats
        return false
    end
    
    # Evaluate conditions
    rsi_oversold = rsi < 30
    trend_bullish = sma_short > sma_long
    
    buy_signal = rsi_oversold && trend_bullish
    
    @ldebug 1 "Buy signal decision" ai ats rsi_oversold trend_bullish buy_signal
    
    return buy_signal
end
```

#### Performance Profiling
```julia
# Enable profiling for signal functions
function isbuy(s::SC, ai, ats)
    @profile begin
        # Your signal logic here
        rsi = signal_value(s, ai, :rsi, ats)
        return validate_signal(rsi) && rsi < 30
    end
end

# Or use timing macros for specific sections
function isbuy(s::SC, ai, ats)
    @time begin
        rsi = signal_value(s, ai, :rsi, ats)
    end
    
    return validate_signal(rsi) && rsi < 30
end
```

#### Signal History Tracking
```julia
function setsignals!(s)
    # ... indicator setup ...
    
    # Initialize signal history for debugging
    attrs[:signal_history] = Dict{Symbol, CircularBuffer{Bool}}()
    attrs[:signal_history][:buy] = CircularBuffer{Bool}(100)
    attrs[:signal_history][:sell] = CircularBuffer{Bool}(100)
end

function isbuy(s::SC, ai, ats)
    # Your signal logic
    buy_signal = your_buy_logic(s, ai, ats)
    
    # Track signal history
    push!(s.attrs[:signal_history][:buy], buy_signal)
    
    return buy_signal
end
```

## Risk Management Integration

### Working with QuickStart's Risk System

QuickStart handles position sizing and risk management automatically, but you can influence it:

#### Position Size Awareness
```julia
function isbuy(s::SC, ai, ats)
    # Check current position
    current_pos = position(ai)
    
    # Don't add to large positions
    if abs(current_pos) > 1000.0  # Adjust threshold as needed
        return false
    end
    
    # Your normal signal logic
    rsi = signal_value(s, ai, :rsi, ats)
    return validate_signal(rsi) && rsi < 30
end
```

#### Cash Management Awareness
```julia
function isbuy(s::SC, ai, ats)
    # Check available cash
    available_cash = cash(s.universe)
    
    # Don't trade if cash is too low
    if available_cash < 100.0  # Minimum cash threshold
        return false
    end
    
    # Your signal logic
    return your_buy_condition(s, ai, ats)
end
```

#### Volatility-Aware Signals
```julia
function isbuy(s::SC, ai, ats)
    # Get volatility measure
    atr = signal_value(s, ai, :atr, ats)
    
    if !validate_signal(atr)
        return false
    end
    
    # Adjust signal sensitivity based on volatility
    if atr > 0.05  # High volatility
        # Require stronger signals
        rsi = signal_value(s, ai, :rsi, ats)
        return validate_signal(rsi) && rsi < 20  # More extreme threshold
    else
        # Normal volatility, normal thresholds
        rsi = signal_value(s, ai, :rsi, ats)
        return validate_signal(rsi) && rsi < 30
    end
end
```

### Custom Risk Filters

#### Drawdown Protection
```julia
function isbuy(s::SC, ai, ats)
    # Check if in drawdown
    peak_cash = get(s.attrs, :peak_cash, 0.0)
    current_value = value(s.universe)
    
    if peak_cash > 0
        drawdown = (peak_cash - current_value) / peak_cash
        
        # Reduce trading during significant drawdown
        if drawdown > 0.10  # 10% drawdown
            return false
        end
    end
    
    # Normal signal logic
    return your_buy_condition(s, ai, ats)
end
```

#### Time-Based Filters
```julia
function isbuy(s::SC, ai, ats)
    # Avoid trading during low liquidity periods
    hour_of_day = hour(ats)
    
    # Avoid trading during typical low-liquidity hours (adjust for your market)
    if hour_of_day < 6 || hour_of_day > 22
        return false
    end
    
    # Your signal logic
    return your_buy_condition(s, ai, ats)
end
```

## Common Patterns and Anti-Patterns

### ✅ Good Patterns

#### 1. Multi-Confirmation Signals
```julia
function isbuy(s::SC, ai, ats)
    # Get multiple confirmations
    rsi = signal_value(s, ai, :rsi, ats)
    macd = signal_value(s, ai, :macd_line, ats)
    trend = signal_value(s, ai, :sma_trend, ats)
    
    # Validate all signals
    if !all(validate_signal, [rsi, macd, trend])
        return false
    end
    
    # Require multiple confirmations
    return rsi < 30 &&          # Oversold
           macd > 0 &&          # Bullish momentum
           trend > 0            # Uptrend
end
```

#### 2. Adaptive Thresholds
```julia
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    atr = signal_value(s, ai, :atr, ats)
    
    if !validate_signal(rsi) || !validate_signal(atr)
        return false
    end
    
    # Adapt threshold based on volatility
    base_threshold = 30.0
    volatility_adjustment = atr * 100  # Scale ATR to percentage
    adaptive_threshold = base_threshold - volatility_adjustment
    
    # Clamp to reasonable bounds
    threshold = clamp(adaptive_threshold, 15.0, 35.0)
    
    return rsi < threshold
end
```

#### 3. Signal Strength Scoring
```julia
function calculate_buy_strength(s::SC, ai, ats)
    score = 0.0
    max_score = 0.0
    
    # RSI component
    rsi = signal_value(s, ai, :rsi, ats)
    if validate_signal(rsi)
        max_score += 1.0
        if rsi < 20
            score += 1.0  # Strong oversold
        elseif rsi < 30
            score += 0.5  # Weak oversold
        end
    end
    
    # MACD component
    macd = signal_value(s, ai, :macd_line, ats)
    if validate_signal(macd)
        max_score += 1.0
        if macd > 0
            score += 1.0  # Bullish
        end
    end
    
    # Return normalized score (0-1)
    return max_score > 0 ? score / max_score : 0.0
end

function isbuy(s::SC, ai, ats)
    strength = calculate_buy_strength(s, ai, ats)
    return strength > 0.7  # Require 70% signal strength
end
```

### ❌ Anti-Patterns to Avoid

#### 1. No Signal Validation
```julia
# ❌ DANGEROUS: No validation
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    return rsi < 30  # Will crash if rsi is nothing!
end
```

#### 2. Complex Calculations in Signal Functions
```julia
# ❌ SLOW: Heavy calculations in hot path
function isbuy(s::SC, ai, ats)
    data = ohlcv(ai)
    
    # Don't do complex calculations here!
    correlation = calculate_correlation(data.close, data.volume, 50)
    regression_slope = linear_regression(data.close[end-20:end])
    
    return correlation > 0.5 && regression_slope > 0
end
```

#### 3. State Modification in Signal Functions
```julia
# ❌ WRONG: Modifying state in signal functions
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    # Don't modify strategy state here!
    s.attrs[:last_rsi] = rsi  # This can cause race conditions
    
    return validate_signal(rsi) && rsi < 30
end
```

#### 4. Direct Trading in Signal Functions
```julia
# ❌ WRONG: Trading directly in signal functions
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    if validate_signal(rsi) && rsi < 30
        # Don't trade directly here!
        trade!(s, ai, ats, now(); side=:buy, amount=100.0)  # Wrong!
        return false
    end
    
    return false
end
```

#### 5. Ignoring Framework Capabilities
```julia
# ❌ INEFFICIENT: Reimplementing framework features
function isbuy(s::SC, ai, ats)
    # Don't reimplement position sizing
    current_pos = position(ai)
    cash_available = cash(s.universe)
    
    # Complex position sizing logic that duplicates framework...
    if current_pos > 0
        return false  # Already long
    end
    
    if cash_available < 1000
        return false  # Not enough cash
    end
    
    # The framework handles all this automatically!
    rsi = signal_value(s, ai, :rsi, ats)
    return validate_signal(rsi) && rsi < 30
end
```

## Advanced Techniques

### Multi-Timeframe Analysis

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define indicators across multiple timeframes
    sigdefs = attrs[:signals_def] = signals(
        # Short-term signals (1m)
        :rsi_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :macd_1m => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        
        # Medium-term signals (5m)
        :trend_5m => (; type=oti.SMA{DFT}, tf=tf"5m", params=(; period=20)),
        :rsi_5m => (; type=oti.RSI{DFT}, tf=tf"5m", params=(; period=14)),
        
        # Long-term signals (1h)
        :trend_1h => (; type=oti.SMA{DFT}, tf=tf"1h", params=(; period=50)),
        :rsi_1h => (; type=oti.RSI{DFT}, tf=tf"1h", params=(; period=14)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ai, ats)
    # Get signals from different timeframes
    rsi_1m = signal_value(s, ai, :rsi_1m, ats)
    rsi_5m = signal_value(s, ai, :rsi_5m, ats)
    rsi_1h = signal_value(s, ai, :rsi_1h, ats)
    
    trend_5m = signal_value(s, ai, :trend_5m, ats)
    trend_1h = signal_value(s, ai, :trend_1h, ats)
    
    # Validate all signals
    signals = [rsi_1m, rsi_5m, rsi_1h, trend_5m, trend_1h]
    if !all(validate_signal, signals)
        return false
    end
    
    # Get current price for trend comparison
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Multi-timeframe buy conditions:
    # 1. Long-term trend is bullish (1h)
    # 2. Medium-term trend is bullish (5m)
    # 3. Short-term entry signal (1m RSI oversold)
    # 4. Medium-term not overbought (5m RSI)
    
    long_term_bullish = current_price > trend_1h
    medium_term_bullish = current_price > trend_5m
    short_term_entry = rsi_1m < 30
    medium_term_ok = rsi_5m < 70
    
    return long_term_bullish && medium_term_bullish && short_term_entry && medium_term_ok
end
```

### Machine Learning-Inspired Approaches

```julia
function setsignals!(s)
    # ... standard indicator setup ...
    
    # Initialize feature weights (could be learned from data)
    attrs[:feature_weights] = [
        0.3,  # Trend strength
        0.25, # Momentum
        0.2,  # Volatility
        0.15, # Volume
        0.1,  # Market structure
    ]
end

function extract_features(s::SC, ai, ats)
    # Feature 1: Trend strength
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    if !validate_signal(sma_short) || !validate_signal(sma_long)
        return nothing
    end
    
    trend_strength = (sma_short - sma_long) / sma_long
    trend_feature = tanh(trend_strength * 10)  # Normalize to [-1, 1]
    
    # Feature 2: Momentum
    rsi = signal_value(s, ai, :rsi, ats)
    if !validate_signal(rsi)
        return nothing
    end
    
    momentum_feature = (rsi - 50) / 50  # Normalize to [-1, 1]
    
    # Feature 3: Volatility
    atr = signal_value(s, ai, :atr, ats)
    if !validate_signal(atr)
        return nothing
    end
    
    # Get current price for volatility normalization
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    volatility_pct = atr / current_price
    volatility_feature = tanh(volatility_pct * 100)  # Normalize
    
    # Feature 4: Volume
    volume_ma = signal_value(s, ai, :volume_ma, ats)
    if !validate_signal(volume_ma)
        return nothing
    end
    
    current_volume = data.volume[idx]
    volume_ratio = current_volume / volume_ma
    volume_feature = tanh(log(volume_ratio))  # Log-normalize
    
    # Feature 5: Market structure (simplified)
    if idx < 5
        structure_feature = 0.0
    else
        recent_high = maximum(data.high[(idx-4):idx])
        recent_low = minimum(data.low[(idx-4):idx])
        price_position = (current_price - recent_low) / (recent_high - recent_low)
        structure_feature = (price_position - 0.5) * 2  # Normalize to [-1, 1]
    end
    
    return [trend_feature, momentum_feature, volatility_feature, volume_feature, structure_feature]
end

function isbuy(s::SC, ai, ats)
    features = extract_features(s, ai, ats)
    
    if isnothing(features)
        return false
    end
    
    weights = s.attrs[:feature_weights]
    
    # Calculate weighted score
    score = sum(features .* weights)
    
    # Apply sigmoid transformation
    probability = 1 / (1 + exp(-score * 5))
    
    # Buy if probability > threshold
    return probability > 0.7
end
```

### Dynamic Parameter Adaptation

```julia
function setsignals!(s)
    # ... indicator setup ...
    
    # Initialize adaptive parameters
    attrs[:adaptive_params] = Dict(
        :rsi_oversold => 30.0,
        :rsi_overbought => 70.0,
        :adaptation_rate => 0.01,
        :performance_window => 50,
    )
    
    # Track recent performance for adaptation
    attrs[:recent_trades] = CircularBuffer{Bool}(50)  # Track win/loss
end

function adapt_parameters!(s::SC, ai, ats)
    params = s.attrs[:adaptive_params]
    recent_trades = s.attrs[:recent_trades]
    
    if length(recent_trades) < params[:performance_window]
        return  # Not enough data yet
    end
    
    # Calculate recent win rate
    win_rate = sum(recent_trades) / length(recent_trades)
    
    # Adapt RSI thresholds based on performance
    if win_rate < 0.4  # Poor performance
        # Make signals more conservative
        params[:rsi_oversold] = max(20.0, params[:rsi_oversold] - params[:adaptation_rate] * 10)
        params[:rsi_overbought] = min(80.0, params[:rsi_overbought] + params[:adaptation_rate] * 10)
    elseif win_rate > 0.6  # Good performance
        # Make signals more aggressive
        params[:rsi_oversold] = min(35.0, params[:rsi_oversold] + params[:adaptation_rate] * 10)
        params[:rsi_overbought] = max(65.0, params[:rsi_overbought] - params[:adaptation_rate] * 10)
    end
end

function isbuy(s::SC, ai, ats)
    # Adapt parameters based on recent performance
    adapt_parameters!(s, ai, ats)
    
    # Use adaptive thresholds
    rsi = signal_value(s, ai, :rsi, ats)
    if !validate_signal(rsi)
        return false
    end
    
    threshold = s.attrs[:adaptive_params][:rsi_oversold]
    return rsi < threshold
end
```

### Market Regime Detection

```julia
function setsignals!(s)
    # ... standard indicators ...
    
    # Add regime detection indicators
    sigdefs = attrs[:signals_def] = signals(
        # ... existing indicators ...
        
        # Regime detection indicators
        :volatility_regime => (; type=oti.ATR{DFT}, tf=tf"1h", params=(; period=20)),
        :trend_regime => (; type=oti.ADX{DFT}, tf=tf"1h", params=(; period=14)),
        :volume_regime => (; type=oti.VolumeMA{DFT}, tf=tf"1h", params=(; period=20)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
    
    # Initialize regime state
    attrs[:current_regime] = :unknown
    attrs[:regime_confidence] = 0.0
end

function detect_market_regime(s::SC, ai, ats)
    # Get regime indicators
    atr = signal_value(s, ai, :volatility_regime, ats)
    adx = signal_value(s, ai, :trend_regime, ats)
    volume_ma = signal_value(s, ai, :volume_regime, ats)
    
    if !all(validate_signal, [atr, adx, volume_ma])
        return :unknown, 0.0
    end
    
    # Get current market data
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    current_volume = data.volume[idx]
    
    # Calculate regime scores
    volatility_score = atr / current_price * 100  # Volatility as percentage
    trend_score = adx  # ADX directly measures trend strength
    volume_score = current_volume / volume_ma  # Volume relative to average
    
    # Classify regimes
    if trend_score > 25 && volatility_score < 2.0
        regime = :trending_low_vol
        confidence = min(trend_score / 50, 1.0)
    elseif trend_score > 25 && volatility_score > 3.0
        regime = :trending_high_vol
        confidence = min(trend_score / 50, 1.0)
    elseif trend_score < 20 && volatility_score < 2.0
        regime = :ranging_low_vol
        confidence = min((25 - trend_score) / 25, 1.0)
    elseif trend_score < 20 && volatility_score > 3.0
        regime = :ranging_high_vol
        confidence = min((25 - trend_score) / 25, 1.0)
    else
        regime = :transitional
        confidence = 0.5
    end
    
    return regime, confidence
end

function isbuy(s::SC, ai, ats)
    # Detect current market regime
    regime, confidence = detect_market_regime(s, ai, ats)
    
    # Update strategy state
    s.attrs[:current_regime] = regime
    s.attrs[:regime_confidence] = confidence
    
    # Only trade with high regime confidence
    if confidence < 0.6
        return false
    end
    
    # Get base signals
    rsi = signal_value(s, ai, :rsi, ats)
    macd = signal_value(s, ai, :macd_line, ats)
    
    if !validate_signal(rsi) || !validate_signal(macd)
        return false
    end
    
    # Adapt strategy based on regime
    if regime == :trending_low_vol
        # Trend following in low volatility
        return macd > 0 && rsi < 60  # Less strict RSI
    elseif regime == :trending_high_vol
        # Conservative trend following in high volatility
        return macd > 0 && rsi < 40  # More strict RSI
    elseif regime == :ranging_low_vol
        # Mean reversion in ranging market
        return rsi < 25  # Very oversold
    elseif regime == :ranging_high_vol
        # Avoid trading in choppy, volatile markets
        return false
    else
        # Default behavior for transitional periods
        return rsi < 30 && macd > 0
    end
end
```

## Conclusion

These best practices provide a comprehensive foundation for developing robust, efficient, and profitable signal generation functions in QuickStart. Remember:

1. **Always validate signals** - This prevents most runtime errors
2. **Keep functions fast** - Signal functions are called frequently
3. **Test thoroughly** - Use simulation, paper trading, then live trading
4. **Start simple** - Begin with basic signals and add complexity gradually
5. **Monitor performance** - Track what works and what doesn't
6. **Respect the framework** - Let QuickStart handle risk management and execution

The examples in this directory demonstrate these principles in action. Study them, adapt them to your needs, and always test thoroughly before risking real capital.

Happy trading! 🚀