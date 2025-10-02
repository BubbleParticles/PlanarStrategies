# Signal Customization Tutorial

This tutorial provides a step-by-step guide to implementing custom signal generation functions in QuickStart. We'll build a complete strategy from scratch, demonstrating all key concepts and best practices.

## Table of Contents

1. [Understanding the Signal Interface](#understanding-the-signal-interface)
2. [Building Your First Signal](#building-your-first-signal)
3. [Adding Multiple Indicators](#adding-multiple-indicators)
4. [Implementing Signal Validation](#implementing-signal-validation)
5. [Advanced Signal Logic](#advanced-signal-logic)
6. [Testing and Debugging](#testing-and-debugging)
7. [Performance Optimization](#performance-optimization)
8. [Real-World Example](#real-world-example)

## Understanding the Signal Interface

QuickStart uses a three-function interface for signal generation:

```julia
function setsignals!(s)
    # Initialize indicators - called once at startup
end

function isbuy(s::SC, ai, ats)
    # Buy signal logic - called every polling cycle
    # Return true when buy conditions are met
end

function issell(s::SC, ai, ats)
    # Sell signal logic - called every polling cycle
    # Return true when sell conditions are met
end
```

### Function Parameters

- **`s::SC`**: Strategy instance containing all utilities and state
- **`ai`**: Asset instance (e.g., BTC/USDT trading pair)
- **`ats`**: Available timestamp for signal evaluation

### Key Concepts

1. **Indicators are pre-calculated** - Define them in `setsignals!()`, use them in signal functions
2. **Signal functions are stateless** - They should not modify strategy state
3. **Always validate signals** - Check for `nothing`, `NaN`, and `Inf` values
4. **Return boolean decisions** - `true` for signal present, `false` otherwise

## Building Your First Signal

Let's build a simple RSI-based strategy step by step.

### Step 1: Basic Structure

Start with the basic three-function structure:

```julia
function setsignals!(s)
    # We'll add indicators here
end

function isbuy(s::SC, ai, ats)
    # We'll add buy logic here
    return false  # Default: no buy signals
end

function issell(s::SC, ai, ats)
    # We'll add sell logic here
    return false  # Default: no sell signals
end
```

### Step 2: Add RSI Indicator

Define the RSI indicator in `setsignals!()`:

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define RSI indicator
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
    )
    
    # Initialize trend tracking (required)
    inittrends!(s, keys(sigdefs.defs))
end
```

**Key Points**:
- `attrs[:signals_set] = false` - Required initialization
- `:rsi` - Indicator name (you'll use this to access the indicator)
- `type=oti.RSI{DFT}` - RSI indicator type
- `tf=tf"1m"` - 1-minute timeframe
- `params=(; period=14)` - 14-period RSI
- `inittrends!(s, keys(sigdefs.defs))` - Required to initialize indicators

### Step 3: Implement Buy Signal

Add RSI-based buy logic:

```julia
function isbuy(s::SC, ai, ats)
    # Get RSI value
    rsi = signal_value(s, ai, :rsi, ats)
    
    # Validate signal (CRITICAL!)
    if isnothing(rsi)
        return false
    end
    
    # Buy when RSI indicates oversold condition
    return rsi < 30
end
```

**Key Points**:
- `signal_value(s, ai, :rsi, ats)` - Gets the RSI value at timestamp `ats`
- Always check `isnothing(rsi)` before using the value
- `rsi < 30` - Buy when RSI is below 30 (oversold)

### Step 4: Implement Sell Signal

Add RSI-based sell logic:

```julia
function issell(s::SC, ai, ats)
    # Get RSI value
    rsi = signal_value(s, ai, :rsi, ats)
    
    # Validate signal
    if isnothing(rsi)
        return false
    end
    
    # Sell when RSI indicates overbought condition
    return rsi > 70
end
```

### Step 5: Complete Basic Strategy

Here's your complete basic RSI strategy:

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    if isnothing(rsi)
        return false
    end
    
    return rsi < 30
end

function issell(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    
    if isnothing(rsi)
        return false
    end
    
    return rsi > 70
end
```

**Congratulations!** You've built your first QuickStart signal strategy.

## Adding Multiple Indicators

Let's enhance the strategy by adding a trend filter using moving averages.

### Step 1: Add Moving Average Indicators

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_long => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end
```

### Step 2: Implement Trend-Filtered Buy Signal

```julia
function isbuy(s::SC, ai, ats)
    # Get all indicator values
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Validate all signals
    if isnothing(rsi) || isnothing(sma_short) || isnothing(sma_long)
        return false
    end
    
    # Buy conditions:
    # 1. RSI oversold (mean reversion signal)
    # 2. Short MA above long MA (uptrend filter)
    rsi_oversold = rsi < 30
    uptrend = sma_short > sma_long
    
    return rsi_oversold && uptrend
end
```

### Step 3: Implement Trend-Filtered Sell Signal

```julia
function issell(s::SC, ai, ats)
    # Get all indicator values
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Validate all signals
    if isnothing(rsi) || isnothing(sma_short) || isnothing(sma_long)
        return false
    end
    
    # Sell conditions:
    # 1. RSI overbought OR
    # 2. Trend reversal (short MA below long MA)
    rsi_overbought = rsi > 70
    downtrend = sma_short < sma_long
    
    return rsi_overbought || downtrend
end
```

## Implementing Signal Validation

Proper signal validation is crucial for robust strategies. Let's implement comprehensive validation.

### Step 1: Create Validation Helper

```julia
function validate_signal(value)
    return !isnothing(value) && !isnan(value) && !isinf(value)
end

function validate_all_signals(signals)
    return all(validate_signal, signals)
end
```

### Step 2: Enhanced Signal Functions

```julia
function isbuy(s::SC, ai, ats)
    # Get all indicator values
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Comprehensive validation
    signals = [rsi, sma_short, sma_long]
    if !validate_all_signals(signals)
        @ldebug 1 "Signal validation failed" ai ats rsi sma_short sma_long
        return false
    end
    
    # Signal logic with logging
    rsi_oversold = rsi < 30
    uptrend = sma_short > sma_long
    buy_signal = rsi_oversold && uptrend
    
    @ldebug 2 "Buy signal evaluation" ai ats rsi rsi_oversold uptrend buy_signal
    
    return buy_signal
end
```

### Step 3: Graceful Degradation

Implement fallback logic when some indicators are missing:

```julia
function isbuy(s::SC, ai, ats)
    # Primary signals
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Try primary strategy (RSI + trend filter)
    if validate_all_signals([rsi, sma_short, sma_long])
        rsi_oversold = rsi < 30
        uptrend = sma_short > sma_long
        return rsi_oversold && uptrend
    end
    
    # Fallback to RSI only
    if validate_signal(rsi)
        @ldebug 1 "Using RSI fallback strategy" ai ats
        return rsi < 25  # More conservative threshold
    end
    
    # Fallback to trend only
    if validate_all_signals([sma_short, sma_long])
        @ldebug 1 "Using trend fallback strategy" ai ats
        return sma_short > sma_long * 1.01  # Require 1% difference
    end
    
    # No valid signals
    @ldebug 1 "No valid signals available" ai ats
    return false
end
```

## Advanced Signal Logic

Let's implement more sophisticated signal logic with multiple confirmations and adaptive thresholds.

### Step 1: Add More Indicators

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    sigdefs = attrs[:signals_def] = signals(
        # Momentum indicators
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :macd_line => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_signal => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        
        # Trend indicators
        :sma_short => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_long => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
        
        # Volatility indicators
        :atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14)),
        :bb_upper => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_lower => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        
        # Volume indicators
        :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
    
    # Store adaptive parameters
    attrs[:rsi_oversold_base] = 30.0
    attrs[:rsi_overbought_base] = 70.0
end
```

### Step 2: Implement Signal Scoring System

```julia
function calculate_buy_score(s::SC, ai, ats)
    score = 0.0
    max_score = 0.0
    
    # RSI momentum score (weight: 25%)
    rsi = signal_value(s, ai, :rsi, ats)
    if validate_signal(rsi)
        max_score += 25.0
        if rsi < 20
            score += 25.0  # Very oversold
        elseif rsi < 30
            score += 15.0  # Oversold
        elseif rsi < 40
            score += 5.0   # Slightly oversold
        end
    end
    
    # MACD momentum score (weight: 25%)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    if validate_all_signals([macd_line, macd_signal])
        max_score += 25.0
        if macd_line > macd_signal && macd_line > 0
            score += 25.0  # Strong bullish momentum
        elseif macd_line > macd_signal
            score += 15.0  # Weak bullish momentum
        end
    end
    
    # Trend score (weight: 30%)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    if validate_all_signals([sma_short, sma_long])
        max_score += 30.0
        trend_strength = (sma_short - sma_long) / sma_long
        if trend_strength > 0.02  # Strong uptrend (2%+)
            score += 30.0
        elseif trend_strength > 0.005  # Weak uptrend (0.5%+)
            score += 15.0
        end
    end
    
    # Volatility score (weight: 10%)
    bb_lower = signal_value(s, ai, :bb_lower, ats)
    if validate_signal(bb_lower)
        max_score += 10.0
        data = ohlcv(ai)
        idx = dateindex(data, ats)
        current_price = data.close[idx]
        
        if current_price <= bb_lower
            score += 10.0  # Price at lower Bollinger Band
        elseif current_price <= bb_lower * 1.01
            score += 5.0   # Price near lower band
        end
    end
    
    # Volume confirmation (weight: 10%)
    volume_ma = signal_value(s, ai, :volume_ma, ats)
    if validate_signal(volume_ma)
        max_score += 10.0
        data = ohlcv(ai)
        idx = dateindex(data, ats)
        current_volume = data.volume[idx]
        
        if current_volume > volume_ma * 1.5
            score += 10.0  # High volume
        elseif current_volume > volume_ma
            score += 5.0   # Above average volume
        end
    end
    
    # Return percentage score
    return max_score > 0 ? (score / max_score) * 100 : 0.0
end
```

### Step 3: Implement Adaptive Thresholds

```julia
function get_adaptive_threshold(s::SC, ai, ats)
    # Base threshold
    base_threshold = 60.0  # Require 60% signal strength
    
    # Adjust based on volatility
    atr = signal_value(s, ai, :atr, ats)
    if validate_signal(atr)
        data = ohlcv(ai)
        idx = dateindex(data, ats)
        current_price = data.close[idx]
        
        volatility_pct = (atr / current_price) * 100
        
        # In high volatility, require higher confidence
        if volatility_pct > 3.0  # High volatility
            base_threshold += 10.0
        elseif volatility_pct < 1.0  # Low volatility
            base_threshold -= 5.0
        end
    end
    
    return clamp(base_threshold, 50.0, 80.0)
end

function isbuy(s::SC, ai, ats)
    # Calculate signal strength
    buy_score = calculate_buy_score(s, ai, ats)
    
    # Get adaptive threshold
    threshold = get_adaptive_threshold(s, ai, ats)
    
    # Additional filters
    rsi = signal_value(s, ai, :rsi, ats)
    if validate_signal(rsi) && rsi > 80
        # Don't buy when extremely overbought
        return false
    end
    
    buy_signal = buy_score >= threshold
    
    @ldebug 1 "Buy signal analysis" ai ats buy_score threshold buy_signal
    
    return buy_signal
end
```

## Testing and Debugging

### Step 1: Add Comprehensive Logging

```julia
function isbuy(s::SC, ai, ats)
    @ldebug 1 "=== Buy Signal Analysis ===" ai ats
    
    # Get all indicators with logging
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    
    @ldebug 1 "Indicator values" ai ats rsi sma_short sma_long macd_line
    
    # Validation with detailed logging
    if !validate_signal(rsi)
        @ldebug 1 "RSI validation failed" ai ats rsi
        return false
    end
    
    if !validate_all_signals([sma_short, sma_long])
        @ldebug 1 "SMA validation failed" ai ats sma_short sma_long
        return false
    end
    
    # Signal logic with step-by-step logging
    rsi_oversold = rsi < 30
    uptrend = sma_short > sma_long
    macd_bullish = validate_signal(macd_line) && macd_line > 0
    
    @ldebug 1 "Signal conditions" ai ats rsi_oversold uptrend macd_bullish
    
    buy_signal = rsi_oversold && uptrend && macd_bullish
    
    @ldebug 1 "Final buy decision" ai ats buy_signal
    
    return buy_signal
end
```

### Step 2: Create Test Functions

```julia
function test_signal_validation()
    # Test with various invalid values
    @test !validate_signal(nothing)
    @test !validate_signal(NaN)
    @test !validate_signal(Inf)
    @test !validate_signal(-Inf)
    @test validate_signal(50.0)
    @test validate_signal(0.0)
    @test validate_signal(-10.0)
    
    println("✅ Signal validation tests passed")
end

function test_buy_signal_logic()
    # Mock strategy setup
    s = create_mock_strategy()
    ai = create_mock_asset()
    ats = DateTime("2023-01-01T12:00:00")
    
    # Test case 1: All signals valid, conditions met
    set_mock_signal(s, ai, :rsi, ats, 25.0)  # Oversold
    set_mock_signal(s, ai, :sma_short, ats, 105.0)
    set_mock_signal(s, ai, :sma_long, ats, 100.0)  # Uptrend
    
    @test isbuy(s, ai, ats) == true
    
    # Test case 2: RSI not oversold
    set_mock_signal(s, ai, :rsi, ats, 50.0)  # Not oversold
    @test isbuy(s, ai, ats) == false
    
    # Test case 3: Downtrend
    set_mock_signal(s, ai, :rsi, ats, 25.0)  # Oversold
    set_mock_signal(s, ai, :sma_short, ats, 95.0)
    set_mock_signal(s, ai, :sma_long, ats, 100.0)  # Downtrend
    
    @test isbuy(s, ai, ats) == false
    
    println("✅ Buy signal logic tests passed")
end
```

### Step 3: Performance Testing

```julia
function benchmark_signal_functions()
    s = create_test_strategy()
    ai = create_test_asset()
    ats = DateTime("2023-01-01T12:00:00")
    
    # Benchmark buy signal function
    @time begin
        for i in 1:1000
            isbuy(s, ai, ats)
        end
    end
    
    # Benchmark sell signal function
    @time begin
        for i in 1:1000
            issell(s, ai, ats)
        end
    end
    
    println("✅ Performance benchmarks completed")
end
```

## Performance Optimization

### Step 1: Optimize Signal Access

```julia
# ✅ FAST: Cache frequently accessed signals
function isbuy(s::SC, ai, ats)
    # Get all signals once
    signals = (
        rsi = signal_value(s, ai, :rsi, ats),
        sma_short = signal_value(s, ai, :sma_short, ats),
        sma_long = signal_value(s, ai, :sma_long, ats),
        macd = signal_value(s, ai, :macd_line, ats)
    )
    
    # Validate all at once
    if !all(validate_signal, [signals.rsi, signals.sma_short, signals.sma_long])
        return false
    end
    
    # Use cached values
    return signals.rsi < 30 && signals.sma_short > signals.sma_long
end
```

### Step 2: Minimize Allocations

```julia
# ✅ EFFICIENT: Avoid unnecessary allocations
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    sma_short = signal_value(s, ai, :sma_short, ats)
    sma_long = signal_value(s, ai, :sma_long, ats)
    
    # Direct comparisons without intermediate arrays
    return validate_signal(rsi) && validate_signal(sma_short) && 
           validate_signal(sma_long) && rsi < 30.0 && sma_short > sma_long
end

# ❌ SLOW: Creates unnecessary arrays
function isbuy_slow(s::SC, ai, ats)
    signals = [signal_value(s, ai, :rsi, ats), 
               signal_value(s, ai, :sma_short, ats),
               signal_value(s, ai, :sma_long, ats)]
    
    thresholds = [30.0, 0.0, 0.0]  # Unnecessary array
    
    return all(validate_signal, signals) && signals[1] < thresholds[1]
end
```

### Step 3: Efficient Validation Patterns

```julia
# ✅ FAST: Early return on first invalid signal
function isbuy(s::SC, ai, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    if !validate_signal(rsi)
        return false
    end
    
    sma_short = signal_value(s, ai, :sma_short, ats)
    if !validate_signal(sma_short)
        return false
    end
    
    sma_long = signal_value(s, ai, :sma_long, ats)
    if !validate_signal(sma_long)
        return false
    end
    
    # All signals valid, proceed with logic
    return rsi < 30 && sma_short > sma_long
end
```

## Real-World Example

Let's build a complete, production-ready strategy that combines multiple concepts:

```julia
function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Comprehensive indicator suite
    sigdefs = attrs[:signals_def] = signals(
        # Multi-timeframe trend analysis
        :trend_1m => (; type=oti.EMA{DFT}, tf=tf"1m", params=(; period=20)),
        :trend_5m => (; type=oti.EMA{DFT}, tf=tf"5m", params=(; period=20)),
        :trend_15m => (; type=oti.EMA{DFT}, tf=tf"15m", params=(; period=20)),
        
        # Momentum indicators
        :rsi_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :rsi_5m => (; type=oti.RSI{DFT}, tf=tf"5m", params=(; period=14)),
        :macd_line => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_signal => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        
        # Volatility and support/resistance
        :atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14)),
        :bb_upper => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_middle => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_lower => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        
        # Volume confirmation
        :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
        :obv => (; type=oti.OBV{DFT}, tf=tf"1m", params=()),
    )
    
    inittrends!(s, keys(sigdefs.defs))
    
    # Strategy parameters
    attrs[:signal_params] = (
        rsi_oversold = 30.0,
        rsi_overbought = 70.0,
        min_trend_alignment = 2,  # Require at least 2 timeframes aligned
        volume_threshold = 1.2,   # 20% above average volume
        volatility_filter = 0.05, # 5% max volatility
        signal_strength_threshold = 70.0,
    )
    
    # Performance tracking
    attrs[:signal_history] = Dict(
        :buy_signals => CircularBuffer{Bool}(100),
        :sell_signals => CircularBuffer{Bool}(100),
        :signal_strength => CircularBuffer{Float64}(100),
    )
end

function analyze_trend_alignment(s::SC, ai, ats)
    # Get current price
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Get trend indicators
    trend_1m = signal_value(s, ai, :trend_1m, ats)
    trend_5m = signal_value(s, ai, :trend_5m, ats)
    trend_15m = signal_value(s, ai, :trend_15m, ats)
    
    # Count aligned timeframes
    aligned_bullish = 0
    aligned_bearish = 0
    
    for trend in [trend_1m, trend_5m, trend_15m]
        if validate_signal(trend)
            if current_price > trend
                aligned_bullish += 1
            else
                aligned_bearish += 1
            end
        end
    end
    
    return (bullish = aligned_bullish, bearish = aligned_bearish)
end

function calculate_signal_strength(s::SC, ai, ats)
    strength = 0.0
    max_strength = 0.0
    
    # Trend alignment (40% weight)
    alignment = analyze_trend_alignment(s, ai, ats)
    max_strength += 40.0
    if alignment.bullish >= 2
        strength += 40.0 * (alignment.bullish / 3.0)
    end
    
    # Momentum indicators (30% weight)
    rsi_1m = signal_value(s, ai, :rsi_1m, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    
    if validate_signal(rsi_1m)
        max_strength += 15.0
        if rsi_1m < 30
            strength += 15.0
        elseif rsi_1m < 40
            strength += 10.0
        elseif rsi_1m < 50
            strength += 5.0
        end
    end
    
    if validate_all_signals([macd_line, macd_signal])
        max_strength += 15.0
        if macd_line > macd_signal
            strength += 15.0
        end
    end
    
    # Volatility and position (20% weight)
    bb_lower = signal_value(s, ai, :bb_lower, ats)
    bb_middle = signal_value(s, ai, :bb_middle, ats)
    
    if validate_all_signals([bb_lower, bb_middle])
        max_strength += 20.0
        data = ohlcv(ai)
        idx = dateindex(data, ats)
        current_price = data.close[idx]
        
        bb_position = (current_price - bb_lower) / (bb_middle - bb_lower)
        if bb_position < 0.2  # Near lower band
            strength += 20.0
        elseif bb_position < 0.4
            strength += 15.0
        elseif bb_position < 0.6
            strength += 10.0
        end
    end
    
    # Volume confirmation (10% weight)
    volume_ma = signal_value(s, ai, :volume_ma, ats)
    if validate_signal(volume_ma)
        max_strength += 10.0
        data = ohlcv(ai)
        idx = dateindex(data, ats)
        current_volume = data.volume[idx]
        
        if current_volume > volume_ma * 1.5
            strength += 10.0
        elseif current_volume > volume_ma
            strength += 5.0
        end
    end
    
    return max_strength > 0 ? (strength / max_strength) * 100 : 0.0
end

function isbuy(s::SC, ai, ats)
    params = s.attrs[:signal_params]
    
    # Calculate signal strength
    signal_strength = calculate_signal_strength(s, ai, ats)
    
    # Store signal strength for analysis
    push!(s.attrs[:signal_history][:signal_strength], signal_strength)
    
    # Volatility filter
    atr = signal_value(s, ai, :atr, ats)
    if validate_signal(atr)
        data = ohlcv(ai)
        idx = dateindex(data, ats)
        current_price = data.close[idx]
        volatility_pct = atr / current_price
        
        if volatility_pct > params.volatility_filter
            @ldebug 1 "Volatility filter triggered" ai ats volatility_pct
            return false
        end
    end
    
    # Trend alignment requirement
    alignment = analyze_trend_alignment(s, ai, ats)
    if alignment.bullish < params.min_trend_alignment
        @ldebug 1 "Insufficient trend alignment" ai ats alignment
        return false
    end
    
    # Signal strength threshold
    buy_signal = signal_strength >= params.signal_strength_threshold
    
    # Store signal for analysis
    push!(s.attrs[:signal_history][:buy_signals], buy_signal)
    
    @ldebug 1 "Buy signal analysis" ai ats signal_strength alignment buy_signal
    
    return buy_signal
end

function issell(s::SC, ai, ats)
    params = s.attrs[:signal_params]
    
    # Quick exit conditions
    rsi_1m = signal_value(s, ai, :rsi_1m, ats)
    if validate_signal(rsi_1m) && rsi_1m > params.rsi_overbought
        @ldebug 1 "RSI overbought exit" ai ats rsi_1m
        return true
    end
    
    # Trend reversal detection
    alignment = analyze_trend_alignment(s, ai, ats)
    if alignment.bearish >= 2
        @ldebug 1 "Trend reversal exit" ai ats alignment
        return true
    end
    
    # MACD bearish crossover
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    
    if validate_all_signals([macd_line, macd_signal])
        if macd_line < macd_signal && macd_line < 0
            @ldebug 1 "MACD bearish crossover exit" ai ats macd_line macd_signal
            return true
        end
    end
    
    return false
end
```

This real-world example demonstrates:

1. **Multi-timeframe analysis** for trend confirmation
2. **Signal strength calculation** with weighted components
3. **Volatility filtering** to avoid choppy markets
4. **Performance tracking** for strategy analysis
5. **Comprehensive logging** for debugging
6. **Multiple exit conditions** for risk management

## Next Steps

Now that you understand signal customization:

1. **Start simple** - Begin with basic examples
2. **Test thoroughly** - Use simulation mode extensively
3. **Add complexity gradually** - Build up your strategy step by step
4. **Monitor performance** - Track what works and what doesn't
5. **Study the examples** - Learn from the provided implementations

Remember: The best strategy is one you understand completely and have tested thoroughly. Start simple, test extensively, and iterate based on results.

Happy trading! 🚀