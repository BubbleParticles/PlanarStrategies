# MACD Momentum Strategy
#
# This strategy uses MACD (Moving Average Convergence Divergence) to identify momentum changes.
# MACD is excellent for trend following and momentum trading.

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define MACD and supporting indicators
    sigdefs = attrs[:signals_def] = signals(
        :macd_line => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_signal => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_histogram => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        # Add trend filter
        :trend_ma => (; type=oti.SMA{DFT}, tf=tf"5m", params=(; period=50)),
        # Add RSI for additional confirmation
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

# Basic MACD Strategy
function isbuy(s::SC, ai, ats)
    # Get MACD values
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    
    # Validate signals
    if any(isnothing, [macd_line, macd_signal, macd_histogram])
        return false
    end
    
    # Basic MACD buy conditions:
    # 1. MACD line crosses above signal line (bullish crossover)
    # 2. MACD histogram is positive (momentum increasing)
    bullish_crossover = macd_line > macd_signal
    positive_momentum = macd_histogram > 0
    
    return bullish_crossover && positive_momentum
end

function issell(s::SC, ai, ats)
    # Get MACD values
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    
    # Validate signals
    if any(isnothing, [macd_line, macd_signal, macd_histogram])
        return false
    end
    
    # Basic MACD sell conditions:
    # 1. MACD line crosses below signal line (bearish crossover)
    # 2. MACD histogram is negative (momentum decreasing)
    bearish_crossover = macd_line < macd_signal
    negative_momentum = macd_histogram < 0
    
    return bearish_crossover && negative_momentum
end

# Enhanced MACD with Trend Filter
function isbuy_with_trend(s::SC, ai, ats)
    # Get MACD and trend values
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    trend_ma = signal_value(s, ai, :trend_ma, ats)
    
    # Validate signals
    if any(isnothing, [macd_line, macd_signal, macd_histogram, trend_ma])
        return false
    end
    
    # Get current price
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Enhanced buy conditions:
    # 1. MACD bullish crossover
    # 2. Price above trend MA (uptrend)
    # 3. MACD line above zero line (strong momentum)
    bullish_crossover = macd_line > macd_signal
    uptrend = current_price > trend_ma
    strong_momentum = macd_line > 0
    
    return bullish_crossover && uptrend && strong_momentum
end

function issell_with_trend(s::SC, ai, ats)
    # Get MACD and trend values
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    trend_ma = signal_value(s, ai, :trend_ma, ats)
    
    # Validate signals
    if any(isnothing, [macd_line, macd_signal, macd_histogram, trend_ma])
        return false
    end
    
    # Get current price
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Enhanced sell conditions:
    # 1. MACD bearish crossover OR
    # 2. Price below trend MA (downtrend) OR
    # 3. MACD line below zero with weakening momentum
    bearish_crossover = macd_line < macd_signal
    downtrend = current_price < trend_ma
    weak_momentum = (macd_line < 0) && (macd_histogram < 0)
    
    return bearish_crossover || downtrend || weak_momentum
end

# MACD Divergence Strategy
function isbuy_with_divergence(s::SC, ai, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    
    if isnothing(macd_line) || isnothing(macd_signal)
        return false
    end
    
    # Basic bullish crossover
    if macd_line <= macd_signal
        return false
    end
    
    # Check for bullish divergence
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    
    if idx < 20  # Need sufficient history
        return true  # Just use basic crossover
    end
    
    # Look for divergence over last 10-20 periods
    lookback = 15
    start_idx = max(1, idx - lookback)
    
    # Find recent price low and corresponding MACD low
    price_low_idx = argmin(data.low[start_idx:idx]) + start_idx - 1
    price_low = data.low[price_low_idx]
    macd_at_price_low = signal_value(s, ai, :macd_line, data.timestamp[price_low_idx])
    
    if isnothing(macd_at_price_low)
        return true  # Just use basic crossover
    end
    
    current_price = data.close[idx]
    
    # Bullish divergence: price makes lower low, MACD makes higher low
    bullish_divergence = (current_price < price_low) && (macd_line > macd_at_price_low)
    
    # Strong buy signal if divergence is present
    return true  # Basic crossover is already confirmed, divergence is bonus
end

function issell_with_divergence(s::SC, ai, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    
    if isnothing(macd_line) || isnothing(macd_signal)
        return false
    end
    
    # Basic bearish crossover
    if macd_line >= macd_signal
        return false
    end
    
    # Check for bearish divergence
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    
    if idx < 20  # Need sufficient history
        return true  # Just use basic crossover
    end
    
    # Look for divergence over last 10-20 periods
    lookback = 15
    start_idx = max(1, idx - lookback)
    
    # Find recent price high and corresponding MACD high
    price_high_idx = argmax(data.high[start_idx:idx]) + start_idx - 1
    price_high = data.high[price_high_idx]
    macd_at_price_high = signal_value(s, ai, :macd_line, data.timestamp[price_high_idx])
    
    if isnothing(macd_at_price_high)
        return true  # Just use basic crossover
    end
    
    current_price = data.close[idx]
    
    # Bearish divergence: price makes higher high, MACD makes lower high
    bearish_divergence = (current_price > price_high) && (macd_line < macd_at_price_high)
    
    # Strong sell signal if divergence is present
    return true  # Basic crossover is already confirmed, divergence is bonus
end

# Zero Line Cross Strategy
function isbuy_zero_cross(s::SC, ai, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    
    if isnothing(macd_line) || isnothing(macd_histogram)
        return false
    end
    
    # Get previous MACD value for crossover detection
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    
    if idx < 2
        return false
    end
    
    prev_ats = data.timestamp[idx-1]
    prev_macd = signal_value(s, ai, :macd_line, prev_ats)
    
    if isnothing(prev_macd)
        return false
    end
    
    # Buy when MACD crosses above zero line
    zero_cross_bullish = (prev_macd <= 0) && (macd_line > 0)
    positive_momentum = macd_histogram > 0
    
    return zero_cross_bullish && positive_momentum
end

function issell_zero_cross(s::SC, ai, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    
    if isnothing(macd_line) || isnothing(macd_histogram)
        return false
    end
    
    # Get previous MACD value for crossover detection
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    
    if idx < 2
        return false
    end
    
    prev_ats = data.timestamp[idx-1]
    prev_macd = signal_value(s, ai, :macd_line, prev_ats)
    
    if isnothing(prev_macd)
        return false
    end
    
    # Sell when MACD crosses below zero line
    zero_cross_bearish = (prev_macd >= 0) && (macd_line < 0)
    negative_momentum = macd_histogram < 0
    
    return zero_cross_bearish && negative_momentum
end

# Customization Options:
#
# 1. Adjust MACD parameters:
#    params=(; fast=8, slow=21, signal=5)   # Faster, more sensitive
#    params=(; fast=19, slow=39, signal=9)  # Slower, less sensitive
#
# 2. Add multiple timeframes:
#    :macd_1m => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
#    :macd_5m => (; type=oti.MACD{DFT}, tf=tf"5m", params=(; fast=12, slow=26, signal=9)),
#
# 3. Combine with other momentum indicators:
#    :momentum => (; type=oti.Momentum{DFT}, tf=tf"1m", params=(; period=10)),
#    :roc => (; type=oti.ROC{DFT}, tf=tf"1m", params=(; period=12)),
#
# 4. Add volume confirmation:
#    :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
#
# 5. Implement histogram analysis:
#    Look for histogram peaks and troughs for early signals