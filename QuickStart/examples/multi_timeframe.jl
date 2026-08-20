# Multi-Timeframe Strategy
#
# This strategy uses multiple timeframes to get a complete market picture:
# - Higher timeframe (1h) for overall trend direction
# - Medium timeframe (15m) for trend confirmation
# - Lower timeframe (1m) for precise entry/exit timing

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Define indicators across multiple timeframes
    sigdefs = attrs[:signals_def] = signals(
        # Higher timeframe - Overall trend
        :trend_1h => (; type=oti.SMA{DFT}, tf=tf"1h", params=(; period=20)),
        :rsi_1h => (; type=oti.RSI{DFT}, tf=tf"1h", params=(; period=14)),
        
        # Medium timeframe - Trend confirmation
        :sma_15m => (; type=oti.SMA{DFT}, tf=tf"15m", params=(; period=50)),
        :macd_15m => (; type=oti.MACD{DFT}, tf=tf"15m", params=(; fast=12, slow=26, signal=9)),
        
        # Lower timeframe - Entry timing
        :rsi_1m => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :bb_upper_1m => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_lower_1m => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

function isbuy(s::SC, ii, ats)
    # Get all required signals
    trend_1h = signal_value(s, ii, :trend_1h, ats)
    rsi_1h = signal_value(s, ii, :rsi_1h, ats)
    sma_15m = signal_value(s, ii, :sma_15m, ats)
    macd_15m = signal_value(s, ii, :macd_15m, ats)
    rsi_1m = signal_value(s, ii, :rsi_1m, ats)
    bb_lower_1m = signal_value(s, ii, :bb_lower_1m, ats)
    
    # Validate all signals
    if any(isnothing, [trend_1h, rsi_1h, sma_15m, macd_15m, rsi_1m, bb_lower_1m])
        return false
    end
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Multi-timeframe buy conditions:
    
    # 1. Higher timeframe: Bullish trend and not overbought
    higher_tf_bullish = (current_price > trend_1h) && (rsi_1h < 70)
    
    # 2. Medium timeframe: Price above SMA and MACD bullish
    medium_tf_bullish = (current_price > sma_15m) && (macd_15m > 0)
    
    # 3. Lower timeframe: Oversold condition near Bollinger Band lower
    lower_tf_entry = (rsi_1m < 40) && (current_price <= bb_lower_1m * 1.01)  # Within 1% of lower band
    
    # All conditions must be met
    return higher_tf_bullish && medium_tf_bullish && lower_tf_entry
end

function issell(s::SC, ii, ats)
    # Get all required signals
    trend_1h = signal_value(s, ii, :trend_1h, ats)
    rsi_1h = signal_value(s, ii, :rsi_1h, ats)
    sma_15m = signal_value(s, ii, :sma_15m, ats)
    macd_15m = signal_value(s, ii, :macd_15m, ats)
    rsi_1m = signal_value(s, ii, :rsi_1m, ats)
    bb_upper_1m = signal_value(s, ii, :bb_upper_1m, ats)
    
    # Validate all signals
    if any(isnothing, [trend_1h, rsi_1h, sma_15m, macd_15m, rsi_1m, bb_upper_1m])
        return false
    end
    
    # Get current price
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Multi-timeframe sell conditions:
    
    # 1. Higher timeframe: Bearish trend or overbought
    higher_tf_bearish = (current_price < trend_1h) || (rsi_1h > 70)
    
    # 2. Medium timeframe: Price below SMA or MACD bearish
    medium_tf_bearish = (current_price < sma_15m) || (macd_15m < 0)
    
    # 3. Lower timeframe: Overbought condition near Bollinger Band upper
    lower_tf_exit = (rsi_1m > 60) && (current_price >= bb_upper_1m * 0.99)  # Within 1% of upper band
    
    # Any major timeframe bearish signal triggers sell
    return higher_tf_bearish || medium_tf_bearish || lower_tf_exit
end

# Alternative: Trend-following version
function isbuy_trend_following(s::SC, ii, ats)
    # Get trend signals from multiple timeframes
    trend_1h = signal_value(s, ii, :trend_1h, ats)
    sma_15m = signal_value(s, ii, :sma_15m, ats)
    macd_15m = signal_value(s, ii, :macd_15m, ats)
    rsi_1m = signal_value(s, ii, :rsi_1m, ats)
    
    if any(isnothing, [trend_1h, sma_15m, macd_15m, rsi_1m])
        return false
    end
    
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # All timeframes must be bullish
    trend_1h_bullish = current_price > trend_1h
    trend_15m_bullish = (current_price > sma_15m) && (macd_15m > 0)
    trend_1m_pullback = rsi_1m < 50  # Wait for pullback on lower timeframe
    
    return trend_1h_bullish && trend_15m_bullish && trend_1m_pullback
end

function issell_trend_following(s::SC, ii, ats)
    # Get trend signals from multiple timeframes
    trend_1h = signal_value(s, ii, :trend_1h, ats)
    sma_15m = signal_value(s, ii, :sma_15m, ats)
    macd_15m = signal_value(s, ii, :macd_15m, ats)
    rsi_1m = signal_value(s, ii, :rsi_1m, ats)
    
    if any(isnothing, [trend_1h, sma_15m, macd_15m, rsi_1m])
        return false
    end
    
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Sell when any major timeframe turns bearish
    trend_1h_bearish = current_price < trend_1h
    trend_15m_bearish = (current_price < sma_15m) || (macd_15m < 0)
    trend_1m_overbought = rsi_1m > 70
    
    return trend_1h_bearish || trend_15m_bearish || trend_1m_overbought
end

# Customization Options:
#
# 1. Adjust timeframe hierarchy:
#    Use 4h/1h/5m or 1d/4h/15m combinations
#
# 2. Add more confirmation indicators:
#    :adx_1h => (; type=oti.ADX{DFT}, tf=tf"1h", params=(; period=14)),  # Trend strength
#    :volume_15m => (; type=oti.VolumeMA{DFT}, tf=tf"15m", params=(; period=20)),
#
# 3. Implement timeframe synchronization:
#    Wait for all timeframes to align before trading
#
# 4. Add momentum filters:
#    :momentum_1h => (; type=oti.Momentum{DFT}, tf=tf"1h", params=(; period=10)),
#
# 5. Use different entry/exit criteria:
#    More aggressive entries, more conservative exits