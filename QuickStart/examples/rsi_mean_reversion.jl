# RSI Mean Reversion Strategy
#
# This strategy uses RSI (Relative Strength Index) to identify overbought and oversold conditions.
# Buy when RSI is oversold (< 30), sell when RSI is overbought (> 70).

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define RSI indicator
    sigdefs = attrs[:signals_def] = signals(
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        # Optional: Add a trend filter to avoid counter-trend trades
        :trend_ma => (; type=oti.SMA{DFT}, tf=tf"5m", params=(; period=50)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ii, ats)
    # Get RSI value
    rsi = signal_value(s, ii, :rsi, ats)
    
    # Validate signal
    if isnothing(rsi)
        return false
    end
    
    # Buy when RSI indicates oversold condition
    return rsi < 30
end

function issell(s::SC, ii, ats)
    # Get RSI value
    rsi = signal_value(s, ii, :rsi, ats)
    
    # Validate signal
    if isnothing(rsi)
        return false
    end
    
    # Sell when RSI indicates overbought condition
    return rsi > 70
end

# Enhanced version with trend filter
function isbuy_with_trend_filter(s::SC, ii, ats)
    # Get RSI and trend values
    rsi = signal_value(s, ii, :rsi, ats)
    trend_ma = signal_value(s, ii, :trend_ma, ats)
    
    if isnothing(rsi) || isnothing(trend_ma)
        return false
    end
    
    # Get current price for trend comparison
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Only buy when oversold AND price is above trend MA (uptrend)
    return rsi < 30 && current_price > trend_ma
end

function issell_with_trend_filter(s::SC, ii, ats)
    # Get RSI and trend values
    rsi = signal_value(s, ii, :rsi, ats)
    trend_ma = signal_value(s, ii, :trend_ma, ats)
    
    if isnothing(rsi) || isnothing(trend_ma)
        return false
    end
    
    # Get current price for trend comparison
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Only sell when overbought AND price is below trend MA (downtrend)
    return rsi > 70 && current_price < trend_ma
end

# Advanced version with RSI divergence detection
function isbuy_with_divergence(s::SC, ii, ats)
    rsi = signal_value(s, ii, :rsi, ats)
    
    if isnothing(rsi)
        return false
    end
    
    # Basic oversold condition
    if rsi >= 30
        return false
    end
    
    # Check for bullish divergence (price makes lower low, RSI makes higher low)
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    
    if idx < 20  # Need sufficient history
        return rsi < 25  # More aggressive threshold without divergence
    end
    
    # Look back for previous low
    lookback = 10
    start_idx = max(1, idx - lookback)
    
    # Find recent price low and corresponding RSI
    price_low_idx = argmin(data.low[start_idx:idx]) + start_idx - 1
    price_low = data.low[price_low_idx]
    rsi_at_price_low = signal_value(s, ii, :rsi, data.timestamp[price_low_idx])
    
    if isnothing(rsi_at_price_low)
        return rsi < 25
    end
    
    current_price = data.close[idx]
    
    # Bullish divergence: price lower but RSI higher
    bullish_divergence = (current_price < price_low) && (rsi > rsi_at_price_low)
    
    return rsi < 30 && (rsi < 25 || bullish_divergence)
end

function issell_with_divergence(s::SC, ii, ats)
    rsi = signal_value(s, ii, :rsi, ats)
    
    if isnothing(rsi)
        return false
    end
    
    # Basic overbought condition
    if rsi <= 70
        return false
    end
    
    # Check for bearish divergence (price makes higher high, RSI makes lower high)
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    
    if idx < 20  # Need sufficient history
        return rsi > 75  # More aggressive threshold without divergence
    end
    
    # Look back for previous high
    lookback = 10
    start_idx = max(1, idx - lookback)
    
    # Find recent price high and corresponding RSI
    price_high_idx = argmax(data.high[start_idx:idx]) + start_idx - 1
    price_high = data.high[price_high_idx]
    rsi_at_price_high = signal_value(s, ii, :rsi, data.timestamp[price_high_idx])
    
    if isnothing(rsi_at_price_high)
        return rsi > 75
    end
    
    current_price = data.close[idx]
    
    # Bearish divergence: price higher but RSI lower
    bearish_divergence = (current_price > price_high) && (rsi < rsi_at_price_high)
    
    return rsi > 70 && (rsi > 75 || bearish_divergence)
end

# Customization Options:
#
# 1. Adjust RSI parameters:
#    :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=21)),  # Longer period
#
# 2. Modify overbought/oversold levels:
#    return rsi < 20  # More extreme oversold
#    return rsi > 80  # More extreme overbought
#
# 3. Add multiple RSI timeframes:
#    :rsi_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
#    :rsi_5m => (; type=oti.RSI{DFT}, tf=tf"5m", params=(; period=14)),
#
# 4. Combine with other mean reversion indicators:
#    :stoch => (; type=oti.Stochastic{DFT}, tf=tf"1m", params=(; k_period=14, d_period=3)),
#    :williams_r => (; type=oti.WilliamsR{DFT}, tf=tf"1m", params=(; period=14)),
#
# 5. Add volume confirmation:
#    Only trade when volume is above average