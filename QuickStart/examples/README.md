# QuickStart Signal Examples

This directory contains comprehensive example implementations of signal generation functions for the QuickStart strategy. Each example demonstrates different approaches to implementing trading signals, from simple to advanced, with complete documentation and best practices.

## Examples Overview

### Basic Examples (Great for Beginners)
1. **`simple_ma_crossover.jl`** - Basic moving average crossover strategy
   - **Approach**: Trend following using two moving averages
   - **Complexity**: ⭐ (Beginner)
   - **Best For**: Learning the basics, stable trending markets
   - **Key Concepts**: Signal validation, crossover detection, parameter customization

2. **`rsi_mean_reversion.jl`** - RSI-based mean reversion strategy
   - **Approach**: Mean reversion using RSI overbought/oversold levels
   - **Complexity**: ⭐⭐ (Beginner-Intermediate)
   - **Best For**: Ranging markets, counter-trend trading
   - **Key Concepts**: Oscillator signals, trend filters, divergence detection

### Intermediate Examples
3. **`bollinger_bands.jl`** - Bollinger Bands breakout and mean reversion
   - **Approach**: Multiple strategies using Bollinger Bands
   - **Complexity**: ⭐⭐⭐ (Intermediate)
   - **Best For**: Volatility-based trading, breakout detection
   - **Key Concepts**: Volatility analysis, multiple signal approaches, volume confirmation

4. **`macd_momentum.jl`** - MACD momentum strategy
   - **Approach**: Momentum trading using MACD indicator
   - **Complexity**: ⭐⭐⭐ (Intermediate)
   - **Best For**: Momentum markets, trend confirmation
   - **Key Concepts**: Momentum indicators, signal line crossovers, histogram analysis

5. **`multi_timeframe.jl`** - Multiple timeframe analysis
   - **Approach**: Combining signals from different timeframes
   - **Complexity**: ⭐⭐⭐⭐ (Intermediate-Advanced)
   - **Best For**: Comprehensive market analysis, reducing false signals
   - **Key Concepts**: Timeframe alignment, signal hierarchy, context filtering

### Advanced Examples
6. **`trend_following.jl`** - Comprehensive trend following system
   - **Approach**: Multi-indicator trend following with confirmations
   - **Complexity**: ⭐⭐⭐⭐ (Advanced)
   - **Best For**: Strong trending markets, systematic trading
   - **Key Concepts**: Multiple confirmations, adaptive thresholds, trend strength

7. **`advanced_composite.jl`** - Complex multi-indicator strategy
   - **Approach**: Machine learning-inspired signal scoring system
   - **Complexity**: ⭐⭐⭐⭐⭐ (Expert)
   - **Best For**: Sophisticated analysis, adaptive trading systems
   - **Key Concepts**: Signal scoring, feature extraction, adaptive parameters

## How to Use These Examples

### Quick Start Process
1. **Browse examples** - Read through the examples to understand different approaches
2. **Choose your style** - Pick an example that matches your trading philosophy
3. **Copy the code** - Copy the complete code from your chosen example
4. **Paste and customize** - Paste into `src/signal_placeholders.jl` and adjust parameters
5. **Test thoroughly** - Always test in simulation mode first

### Detailed Implementation Steps

#### Step 1: Choose Your Example
Consider your trading style and market conditions:
- **Trending markets**: `simple_ma_crossover.jl`, `trend_following.jl`
- **Ranging markets**: `rsi_mean_reversion.jl`, `bollinger_bands.jl`
- **High-frequency**: `macd_momentum.jl`
- **Comprehensive analysis**: `multi_timeframe.jl`, `advanced_composite.jl`

#### Step 2: Understand the Example
Each example includes:
- **Complete implementation** of all three required functions
- **Detailed comments** explaining the logic
- **Multiple variations** showing different approaches
- **Customization options** for parameter tuning
- **Best practices** demonstrated in code

#### Step 3: Copy and Implement
```bash
# Navigate to your QuickStart strategy
cd user/strategies/QuickStart

# Copy your chosen example to the signal placeholders file
cp examples/simple_ma_crossover.jl src/signal_placeholders.jl
```

#### Step 4: Customize Parameters
Each example includes customization sections like:
```julia
# Customization Options:
# 1. Adjust periods:
#    :sma_fast => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=5)),
# 2. Use different timeframes:
#    :sma_fast => (; type=oti.SMA{DFT}, tf=tf"5m", params=(; period=10)),
```

#### Step 5: Test and Validate
1. **Simulation testing** - Backtest with historical data
2. **Paper trading** - Test with real-time data, simulated orders
3. **Live trading** - Start with small positions

## Example Implementations Deep Dive

### 1. Simple Moving Average Crossover (`simple_ma_crossover.jl`)

**Core Concept**: Buy when fast MA crosses above slow MA, sell when it crosses below.

**Key Features**:
- Two implementation variants: continuous signals vs. crossover detection
- Parameter customization examples
- Clear signal validation patterns
- Performance optimization techniques

**Best For**:
- Learning QuickStart signal implementation
- Trending markets with clear directional moves
- Strategies requiring simple, reliable signals

**Sample Usage**:
```julia
# Basic implementation
function isbuy(s::SC, ai, ats)
    short_ma = signal_value(s, ai, :sma_short, ats)
    long_ma = signal_value(s, ai, :sma_long, ats)
    
    if isnothing(short_ma) || isnothing(long_ma)
        return false
    end
    
    return short_ma > long_ma
end
```

### 2. RSI Mean Reversion (`rsi_mean_reversion.jl`)

**Core Concept**: Buy when RSI indicates oversold conditions, sell when overbought.

**Key Features**:
- Basic RSI signals with trend filters
- Divergence detection for advanced entries
- Multiple threshold strategies
- Volume and trend confirmations

**Best For**:
- Ranging or sideways markets
- Counter-trend trading strategies
- Markets with clear support/resistance levels

**Advanced Features**:
- Bullish/bearish divergence detection
- Trend filter integration
- Adaptive threshold adjustment

### 3. Bollinger Bands (`bollinger_bands.jl`)

**Core Concept**: Three different strategies using Bollinger Bands.

**Key Features**:
- **Mean Reversion**: Trade bounces off bands
- **Breakout**: Trade band breakouts with volume confirmation
- **Squeeze**: Trade low volatility breakouts

**Best For**:
- Volatility-based trading
- Markets with clear volatility cycles
- Breakout and mean reversion opportunities

**Unique Aspects**:
- Multiple strategy approaches in one file
- Volume confirmation techniques
- Volatility regime detection

### 4. MACD Momentum (`macd_momentum.jl`)

**Core Concept**: Use MACD for momentum-based entries and exits.

**Key Features**:
- MACD line and signal line crossovers
- Histogram analysis for momentum strength
- Zero-line crossover strategies
- Divergence detection

**Best For**:
- Momentum trading
- Trend confirmation
- Markets with strong directional moves

### 5. Multi-Timeframe Analysis (`multi_timeframe.jl`)

**Core Concept**: Combine signals from multiple timeframes for better accuracy.

**Key Features**:
- Higher timeframe trend filtering
- Lower timeframe entry signals
- Timeframe alignment strategies
- Context-aware signal generation

**Best For**:
- Comprehensive market analysis
- Reducing false signals
- Professional trading approaches

**Implementation Pattern**:
```julia
# Long-term trend (1h) + short-term entry (1m)
long_term_bullish = current_price > trend_1h
short_term_entry = rsi_1m < 30
return long_term_bullish && short_term_entry
```

### 6. Trend Following (`trend_following.jl`)

**Core Concept**: Comprehensive trend following with multiple confirmations.

**Key Features**:
- Multiple trend indicators
- Strength-based filtering
- Adaptive position sizing awareness
- Risk-adjusted entries

**Best For**:
- Strong trending markets
- Systematic trend following
- Risk-conscious trading

### 7. Advanced Composite (`advanced_composite.jl`)

**Core Concept**: Machine learning-inspired signal scoring system.

**Key Features**:
- Multi-indicator scoring system
- Feature extraction and weighting
- Adaptive thresholds based on market conditions
- Comprehensive signal analysis

**Best For**:
- Sophisticated trading systems
- Adaptive market strategies
- Advanced practitioners

**Signal Scoring Example**:
```julia
# Calculate weighted score from multiple indicators
score = trend_weight * trend_signal + 
        momentum_weight * momentum_signal + 
        volatility_weight * volatility_signal

# Apply sigmoid transformation for probability
probability = 1 / (1 + exp(-score * 5))
return probability > 0.7
```

## Best Practices Demonstrated

### 1. Signal Validation
Every example shows proper signal validation:
```julia
if isnothing(signal) || isnan(signal) || isinf(signal)
    return false
end
```

### 2. Performance Optimization
- Use pre-calculated indicators via `signal_value()`
- Avoid heavy calculations in signal functions
- Minimize memory allocations

### 3. Error Handling
- Graceful handling of missing data
- Fallback strategies for failed indicators
- Comprehensive logging for debugging

### 4. Parameter Management
- Environment variable integration
- Clear customization sections
- Reasonable default values

### 5. Multi-Confirmation Signals
- Combine multiple indicators for robustness
- Use different timeframes for context
- Implement strength-based filtering

## Testing Your Implementation

### Phase 1: Code Validation
```julia
# Test signal functions with mock data
@test isbuy(mock_strategy, mock_asset, test_timestamp) isa Bool
@test issell(mock_strategy, mock_asset, test_timestamp) isa Bool
```

### Phase 2: Historical Backtesting
```julia
# Run simulation with historical data
# Verify signal generation patterns
# Check performance metrics
```

### Phase 3: Paper Trading
```julia
# Test with real-time data
# Validate timing and execution
# Monitor for edge cases
```

### Phase 4: Live Trading
```julia
# Start with minimal position sizes
# Monitor performance closely
# Scale up gradually
```

## Customization Guidelines

### Parameter Tuning
1. **Start with defaults** - Use example parameters as baseline
2. **Adjust gradually** - Make small incremental changes
3. **Test thoroughly** - Validate each change in simulation
4. **Document changes** - Keep track of what works

### Adding Custom Indicators
```julia
function setsignals!(s)
    # Add your custom indicators
    sigdefs = attrs[:signals_def] = signals(
        :custom_indicator => (; type=oti.YourIndicator{DFT}, tf=tf"1m", params=(; period=20)),
        # ... other indicators
    )
    inittrends!(s, keys(sigdefs.defs))
end
```

### Combining Examples
You can combine elements from different examples:
```julia
function isbuy(s::SC, ai, ats)
    # RSI from mean reversion example
    rsi = signal_value(s, ai, :rsi, ats)
    
    # MACD from momentum example
    macd = signal_value(s, ai, :macd_line, ats)
    
    # Bollinger Bands from volatility example
    bb_lower = signal_value(s, ai, :bb_lower, ats)
    
    # Combine all signals
    return validate_all([rsi, macd, bb_lower]) &&
           rsi < 30 && macd > 0 && current_price < bb_lower
end
```

## Performance Considerations

### Computational Efficiency
- **Pre-calculate indicators** in `setsignals!()`
- **Minimize allocations** in signal functions
- **Cache expensive calculations** when necessary
- **Use efficient data structures**

### Memory Management
- **Avoid memory leaks** in persistent state
- **Limit cache sizes** for long-running strategies
- **Clean up unused data** periodically

### Latency Optimization
- **Keep signal functions fast** (< 1ms typical)
- **Avoid I/O operations** in hot paths
- **Use efficient algorithms** for calculations

## Troubleshooting Common Issues

### No Trades Executing
1. Check signal functions return `true` when expected
2. Verify indicator setup in `setsignals!()`
3. Ensure sufficient cash and margin
4. Check position limits and risk controls

### Signal Values are `nothing`
1. Verify indicator names match exactly
2. Ensure sufficient historical data
3. Check timeframe compatibility
4. Validate `inittrends!()` call

### Performance Issues
1. Profile signal functions for bottlenecks
2. Check for memory leaks in custom code
3. Optimize data access patterns
4. Consider caching strategies

### Unexpected Behavior
1. Add debug logging to signal functions
2. Test with known data scenarios
3. Verify parameter values
4. Check for edge cases

## Advanced Topics

For more advanced signal generation techniques, see:
- **`BEST_PRACTICES.md`** - Comprehensive best practices guide
- **Multi-timeframe analysis** patterns
- **Machine learning integration** approaches
- **Market regime detection** techniques
- **Adaptive parameter systems**

## Getting Help

If you need assistance:
1. **Study the examples** - Each demonstrates key concepts
2. **Read the best practices** - `BEST_PRACTICES.md` has detailed guidance
3. **Check the main README** - Comprehensive framework documentation
4. **Test incrementally** - Start simple and add complexity gradually
5. **Use simulation mode** - Always test before live trading

---

**Remember**: These examples are educational implementations. Always test thoroughly and understand the risks before using any trading strategy with real money. Start with simulation, progress to paper trading, and only use live trading with capital you can afford to lose.

## Best Practices Demonstrated

- **Signal validation** - Always check for valid indicator values
- **Parameter management** - How to configure indicator parameters
- **Multiple timeframes** - Using different timeframes for different signals
- **Risk management integration** - Working with the framework's risk controls
- **Performance optimization** - Efficient signal calculations
- **Error handling** - Graceful handling of missing or invalid data

## Testing Your Signals

Before using any signal implementation:

1. **Backtest thoroughly** using simulation mode
2. **Paper trade** to validate real-time behavior
3. **Monitor performance** metrics and adjust parameters
4. **Start with small position sizes** when going live

## Customization Tips

- **Adjust periods** - Modify indicator periods to match your timeframe
- **Combine signals** - Use multiple indicators for confirmation
- **Add filters** - Include additional conditions to reduce false signals
- **Optimize parameters** - Use Planar's optimization tools to find best settings

---

**Warning**: These are example implementations for educational purposes. Always test thoroughly and understand the risks before using any trading strategy with real money.