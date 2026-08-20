# Simple Moving Average Crossover Strategy
#
# This is the most basic trend-following strategy using two moving averages.
# Buy when fast MA crosses above slow MA, sell when fast MA crosses below slow MA.

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define two simple moving averages
    sigdefs = attrs[:signals_def] = signals(
        :sma_fast => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_slow => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    # Initialize trend tracking for the signals
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ii, ats)
    # Get the moving average values
    fast_ma = signal_value(s, ii, :sma_fast, ats)
    slow_ma = signal_value(s, ii, :sma_slow, ats)
    
    # Validate signals - return false if any are missing
    if isnothing(fast_ma) || isnothing(slow_ma)
        return false
    end
    
    # Buy when fast MA is above slow MA (uptrend)
    return fast_ma > slow_ma
end

function issell(s::SC, ii, ats)
    # Get the moving average values
    fast_ma = signal_value(s, ii, :sma_fast, ats)
    slow_ma = signal_value(s, ii, :sma_slow, ats)
    
    # Validate signals - return false if any are missing
    if isnothing(fast_ma) || isnothing(slow_ma)
        return false
    end
    
    # Sell when fast MA is below slow MA (downtrend)
    return fast_ma < slow_ma
end

# Optional: Add crossover detection for more precise entry/exit
function isbuy_with_crossover(s::SC, ii, ats)
    # Get current values
    fast_ma = signal_value(s, ii, :sma_fast, ats)
    slow_ma = signal_value(s, ii, :sma_slow, ats)
    
    if isnothing(fast_ma) || isnothing(slow_ma)
        return false
    end
    
    # Get previous values for crossover detection
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    
    if idx < 2  # Need at least 2 periods for crossover
        return false
    end
    
    prev_ats = data.timestamp[idx-1]
    prev_fast = signal_value(s, ii, :sma_fast, prev_ats)
    prev_slow = signal_value(s, ii, :sma_slow, prev_ats)
    
    if isnothing(prev_fast) || isnothing(prev_slow)
        return false
    end
    
    # Buy on bullish crossover (fast MA crosses above slow MA)
    return (prev_fast <= prev_slow) && (fast_ma > slow_ma)
end

function issell_with_crossover(s::SC, ii, ats)
    # Get current values
    fast_ma = signal_value(s, ii, :sma_fast, ats)
    slow_ma = signal_value(s, ii, :sma_slow, ats)
    
    if isnothing(fast_ma) || isnothing(slow_ma)
        return false
    end
    
    # Get previous values for crossover detection
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    
    if idx < 2  # Need at least 2 periods for crossover
        return false
    end
    
    prev_ats = data.timestamp[idx-1]
    prev_fast = signal_value(s, ii, :sma_fast, prev_ats)
    prev_slow = signal_value(s, ii, :sma_slow, prev_ats)
    
    if isnothing(prev_fast) || isnothing(prev_slow)
        return false
    end
    
    # Sell on bearish crossover (fast MA crosses below slow MA)
    return (prev_fast >= prev_slow) && (fast_ma < slow_ma)
end

# Customization Options:
# 
# 1. Adjust periods:
#    :sma_fast => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=5)),   # Faster
#    :sma_slow => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=50)),  # Slower
#
# 2. Use different timeframes:
#    :sma_fast => (; type=oti.SMA{DFT}, tf=tf"5m", params=(; period=10)),
#    :sma_slow => (; type=oti.SMA{DFT}, tf=tf"15m", params=(; period=20)),
#
# 3. Use exponential moving averages:
#    :ema_fast => (; type=oti.EMA{DFT}, tf=tf"1m", params=(; period=10)),
#    :ema_slow => (; type=oti.EMA{DFT}, tf=tf"1m", params=(; period=20)),
#
# 4. Add volume confirmation:
#    Include volume indicators to confirm signals
#
# 5. Add trend strength filter:
#    Only trade when trend strength is above a threshold