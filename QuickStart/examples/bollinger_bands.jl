# Bollinger Bands Strategy
#
# This strategy uses Bollinger Bands to identify breakouts and mean reversion opportunities.
# Two approaches: breakout trading and mean reversion trading.

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define Bollinger Bands and supporting indicators
    sigdefs = attrs[:signals_def] = signals(
        :bb_upper => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_middle => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_lower => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_width => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        # Add RSI for additional confirmation
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        # Add volume for breakout confirmation
        :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

# Approach 1: Mean Reversion Strategy
function isbuy_mean_reversion(s::SC, ii, ats)
    # Get Bollinger Band values
    bb_upper = signal_value(s, ii, :bb_upper, ats)
    bb_middle = signal_value(s, ii, :bb_middle, ats)
    bb_lower = signal_value(s, ii, :bb_lower, ats)
    rsi = signal_value(s, ii, :rsi, ats)
    
    # Validate signals
    if any(isnothing, [bb_upper, bb_middle, bb_lower, rsi])
        return false
    end
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Mean reversion buy conditions:
    # 1. Price touches or goes below lower Bollinger Band
    # 2. RSI confirms oversold condition
    price_at_lower_band = current_price <= bb_lower
    rsi_oversold = rsi < 30
    
    return price_at_lower_band && rsi_oversold
end

function issell_mean_reversion(s::SC, ii, ats)
    # Get Bollinger Band values
    bb_upper = signal_value(s, ii, :bb_upper, ats)
    bb_middle = signal_value(s, ii, :bb_middle, ats)
    bb_lower = signal_value(s, ii, :bb_lower, ats)
    rsi = signal_value(s, ii, :rsi, ats)
    
    # Validate signals
    if any(isnothing, [bb_upper, bb_middle, bb_lower, rsi])
        return false
    end
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Mean reversion sell conditions:
    # 1. Price reaches middle band (take profit) OR
    # 2. Price touches upper band with overbought RSI
    price_at_middle = current_price >= bb_middle
    price_at_upper_band = current_price >= bb_upper
    rsi_overbought = rsi > 70
    
    return price_at_middle || (price_at_upper_band && rsi_overbought)
end

# Approach 2: Breakout Strategy
function isbuy_breakout(s::SC, ii, ats)
    # Get Bollinger Band values
    bb_upper = signal_value(s, ii, :bb_upper, ats)
    bb_lower = signal_value(s, ii, :bb_lower, ats)
    bb_width = signal_value(s, ii, :bb_width, ats)
    volume_ma = signal_value(s, ii, :volume_ma, ats)
    
    # Validate signals
    if any(isnothing, [bb_upper, bb_lower, bb_width, volume_ma])
        return false
    end
    
    # Get current price and volume
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    current_volume = data.volume[idx]
    
    # Breakout buy conditions:
    # 1. Price breaks above upper Bollinger Band
    # 2. Bollinger Bands are not too wide (avoid false breakouts in high volatility)
    # 3. Volume confirms the breakout
    price_breakout = current_price > bb_upper
    bands_not_too_wide = bb_width < (bb_upper - bb_lower) * 1.5  # Adjust threshold as needed
    volume_confirmation = current_volume > volume_ma * 1.2  # 20% above average volume
    
    return price_breakout && bands_not_too_wide && volume_confirmation
end

function issell_breakout(s::SC, ii, ats)
    # Get Bollinger Band values
    bb_upper = signal_value(s, ii, :bb_upper, ats)
    bb_lower = signal_value(s, ii, :bb_lower, ats)
    bb_middle = signal_value(s, ii, :bb_middle, ats)
    
    # Validate signals
    if any(isnothing, [bb_upper, bb_lower, bb_middle])
        return false
    end
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Breakout sell conditions:
    # 1. Price falls back below upper band (failed breakout) OR
    # 2. Price reaches a significant extension above upper band (take profit)
    failed_breakout = current_price < bb_upper
    extended_profit = current_price > bb_upper * 1.02  # 2% above upper band
    
    return failed_breakout || extended_profit
end

# Approach 3: Squeeze Strategy (Low Volatility Breakout)
function isbuy_squeeze(s::SC, ii, ats)
    # Get Bollinger Band values
    bb_upper = signal_value(s, ii, :bb_upper, ats)
    bb_lower = signal_value(s, ii, :bb_lower, ats)
    bb_middle = signal_value(s, ii, :bb_middle, ats)
    
    # Validate signals
    if any(isnothing, [bb_upper, bb_lower, bb_middle])
        return false
    end
    
    # Calculate band width as percentage of middle band
    band_width_pct = ((bb_upper - bb_lower) / bb_middle) * 100
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Look for historical band width to identify squeeze
    if idx < 20
        return false
    end
    
    # Calculate average band width over last 20 periods
    avg_band_width = 0.0
    valid_periods = 0
    
    for i in (idx-19):idx
        prev_ats = data.timestamp[i]
        prev_upper = signal_value(s, ii, :bb_upper, prev_ats)
        prev_lower = signal_value(s, ii, :bb_lower, prev_ats)
        prev_middle = signal_value(s, ii, :bb_middle, prev_ats)
        
        if !any(isnothing, [prev_upper, prev_lower, prev_middle])
            avg_band_width += ((prev_upper - prev_lower) / prev_middle) * 100
            valid_periods += 1
        end
    end
    
    if valid_periods < 10
        return false
    end
    
    avg_band_width /= valid_periods
    
    # Squeeze conditions:
    # 1. Current band width is significantly below average (squeeze)
    # 2. Price breaks above middle band (direction confirmation)
    squeeze_detected = band_width_pct < avg_band_width * 0.7  # 30% below average
    bullish_breakout = current_price > bb_middle
    
    return squeeze_detected && bullish_breakout
end

function issell_squeeze(s::SC, ii, ats)
    # Get Bollinger Band values
    bb_upper = signal_value(s, ii, :bb_upper, ats)
    bb_lower = signal_value(s, ii, :bb_lower, ats)
    bb_middle = signal_value(s, ii, :bb_middle, ats)
    
    # Validate signals
    if any(isnothing, [bb_upper, bb_lower, bb_middle])
        return false
    end
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Squeeze sell conditions:
    # 1. Price falls back below middle band OR
    # 2. Price reaches upper band (take profit)
    below_middle = current_price < bb_middle
    at_upper_band = current_price >= bb_upper
    
    return below_middle || at_upper_band
end

# Default implementation - choose your preferred approach
function isbuy(s::SC, ii, ats)
    # Use mean reversion approach by default
    return isbuy_mean_reversion(s, ii, ats)
    
    # Alternative: Use breakout approach
    # return isbuy_breakout(s, ii, ats)
    
    # Alternative: Use squeeze approach
    # return isbuy_squeeze(s, ii, ats)
end

function issell(s::SC, ii, ats)
    # Use mean reversion approach by default
    return issell_mean_reversion(s, ii, ats)
    
    # Alternative: Use breakout approach
    # return issell_breakout(s, ii, ats)
    
    # Alternative: Use squeeze approach
    # return issell_squeeze(s, ii, ats)
end

# Customization Options:
#
# 1. Adjust Bollinger Band parameters:
#    params=(; period=10, std=1.5)  # Shorter period, tighter bands
#    params=(; period=50, std=2.5)  # Longer period, wider bands
#
# 2. Add multiple Bollinger Band timeframes:
#    :bb_1m => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
#    :bb_5m => (; type=oti.BollingerBands{DFT}, tf=tf"5m", params=(; period=20, std=2.0)),
#
# 3. Combine with other indicators:
#    :keltner_upper => (; type=oti.KeltnerChannels{DFT}, tf=tf"1m", params=(; period=20, atr_mult=2.0)),
#
# 4. Add trend filters:
#    Only trade breakouts in the direction of the overall trend
#
# 5. Implement dynamic thresholds:
#    Adjust overbought/oversold levels based on market volatility