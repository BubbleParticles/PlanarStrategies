# Trend Following Strategy
#
# This strategy focuses on identifying and following strong trends using multiple
# trend confirmation indicators. It aims to capture large moves while avoiding
# whipsaws in sideways markets.

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Comprehensive trend detection suite
    sigdefs = attrs[:signals_def] = signals(
        # Multiple moving averages for trend hierarchy
        :sma_fast => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=8)),
        :sma_medium => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=21)),
        :sma_slow => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=55)),
        :ema_trend => (; type=oti.EMA{DFT}, tf=tf"5m", params=(; period=34)),
        
        # Trend strength indicators
        :adx => (; type=oti.ADX{DFT}, tf=tf"1m", params=(; period=14)),
        :di_plus => (; type=oti.DI{DFT}, tf=tf"1m", params=(; period=14)),
        :di_minus => (; type=oti.DI{DFT}, tf=tf"1m", params=(; period=14)),
        
        # Momentum for trend confirmation
        :macd_line => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_signal => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :roc => (; type=oti.ROC{DFT}, tf=tf"1m", params=(; period=12)),
        
        # Volatility for trend filtering
        :atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14)),
        
        # Higher timeframe trend context
        :trend_15m => (; type=oti.SMA{DFT}, tf=tf"15m", params=(; period=20)),
        :trend_1h => (; type=oti.SMA{DFT}, tf=tf"1h", params=(; period=20)),
        
        # Volume for trend confirmation
        :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

function is_strong_uptrend(s::SC, ii, ats)
    # Get all trend indicators
    sma_fast = signal_value(s, ii, :sma_fast, ats)
    sma_medium = signal_value(s, ii, :sma_medium, ats)
    sma_slow = signal_value(s, ii, :sma_slow, ats)
    ema_trend = signal_value(s, ii, :ema_trend, ats)
    adx = signal_value(s, ii, :adx, ats)
    di_plus = signal_value(s, ii, :di_plus, ats)
    di_minus = signal_value(s, ii, :di_minus, ats)
    trend_15m = signal_value(s, ii, :trend_15m, ats)
    trend_1h = signal_value(s, ii, :trend_1h, ats)
    
    # Validate critical indicators
    if any(isnothing, [sma_fast, sma_medium, sma_slow, adx])
        return false
    end
    
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Multiple trend confirmations required
    confirmations = 0
    total_checks = 0
    
    # 1. Moving average hierarchy (strongest signal)
    total_checks += 1
    if sma_fast > sma_medium > sma_slow && current_price > sma_fast
        confirmations += 1
    end
    
    # 2. ADX trend strength
    total_checks += 1
    if adx > 25  # Strong trend threshold
        confirmations += 1
        
        # 3. Directional movement confirmation
        if !isnothing(di_plus) && !isnothing(di_minus)
            total_checks += 1
            if di_plus > di_minus
                confirmations += 1
            end
        end
    end
    
    # 4. Higher timeframe alignment
    if !isnothing(trend_15m)
        total_checks += 1
        if current_price > trend_15m
            confirmations += 1
        end
    end
    
    if !isnothing(trend_1h)
        total_checks += 1
        if current_price > trend_1h
            confirmations += 1
        end
    end
    
    # 5. EMA trend confirmation
    if !isnothing(ema_trend)
        total_checks += 1
        if current_price > ema_trend
            confirmations += 1
        end
    end
    
    # Require at least 70% of checks to pass
    return total_checks > 0 && (confirmations / total_checks) >= 0.7
end

function is_strong_downtrend(s::SC, ii, ats)
    # Get all trend indicators
    sma_fast = signal_value(s, ii, :sma_fast, ats)
    sma_medium = signal_value(s, ii, :sma_medium, ats)
    sma_slow = signal_value(s, ii, :sma_slow, ats)
    ema_trend = signal_value(s, ii, :ema_trend, ats)
    adx = signal_value(s, ii, :adx, ats)
    di_plus = signal_value(s, ii, :di_plus, ats)
    di_minus = signal_value(s, ii, :di_minus, ats)
    trend_15m = signal_value(s, ii, :trend_15m, ats)
    trend_1h = signal_value(s, ii, :trend_1h, ats)
    
    # Validate critical indicators
    if any(isnothing, [sma_fast, sma_medium, sma_slow, adx])
        return false
    end
    
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    
    # Multiple trend confirmations required
    confirmations = 0
    total_checks = 0
    
    # 1. Moving average hierarchy (strongest signal)
    total_checks += 1
    if sma_fast < sma_medium < sma_slow && current_price < sma_fast
        confirmations += 1
    end
    
    # 2. ADX trend strength
    total_checks += 1
    if adx > 25  # Strong trend threshold
        confirmations += 1
        
        # 3. Directional movement confirmation
        if !isnothing(di_plus) && !isnothing(di_minus)
            total_checks += 1
            if di_minus > di_plus
                confirmations += 1
            end
        end
    end
    
    # 4. Higher timeframe alignment
    if !isnothing(trend_15m)
        total_checks += 1
        if current_price < trend_15m
            confirmations += 1
        end
    end
    
    if !isnothing(trend_1h)
        total_checks += 1
        if current_price < trend_1h
            confirmations += 1
        end
    end
    
    # 5. EMA trend confirmation
    if !isnothing(ema_trend)
        total_checks += 1
        if current_price < ema_trend
            confirmations += 1
        end
    end
    
    # Require at least 70% of checks to pass
    return total_checks > 0 && (confirmations / total_checks) >= 0.7
end

function isbuy(s::SC, ii, ats)
    # Only buy in strong uptrends
    if !is_strong_uptrend(s, ii, ats)
        return false
    end
    
    # Get momentum and entry timing indicators
    macd_line = signal_value(s, ii, :macd_line, ats)
    macd_signal = signal_value(s, ii, :macd_signal, ats)
    roc = signal_value(s, ii, :roc, ats)
    volume_ma = signal_value(s, ii, :volume_ma, ats)
    atr = signal_value(s, ii, :atr, ats)
    
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    current_volume = data.volume[idx]
    
    # Entry conditions within strong uptrend
    entry_signals = 0
    total_entry_checks = 0
    
    # 1. MACD momentum confirmation
    if !isnothing(macd_line) && !isnothing(macd_signal)
        total_entry_checks += 1
        if macd_line > macd_signal && macd_line > 0
            entry_signals += 1
        end
    end
    
    # 2. Rate of change momentum
    if !isnothing(roc)
        total_entry_checks += 1
        if roc > 0
            entry_signals += 1
        end
    end
    
    # 3. Volume confirmation
    if !isnothing(volume_ma)
        total_entry_checks += 1
        if current_volume > volume_ma
            entry_signals += 1
        end
    end
    
    # 4. Pullback entry (buy on minor pullbacks in strong trends)
    sma_fast = signal_value(s, ii, :sma_fast, ats)
    if !isnothing(sma_fast) && idx >= 3
        total_entry_checks += 1
        current_price = data.close[idx]
        prev_price = data.close[idx-1]
        
        # Look for price pulling back to fast MA (good entry point)
        if current_price <= sma_fast * 1.005 && prev_price > sma_fast * 1.005
            entry_signals += 1
        end
    end
    
    # Require at least 50% of entry signals
    return total_entry_checks > 0 && (entry_signals / total_entry_checks) >= 0.5
end

function issell(s::SC, ii, ats)
    # Sell if strong downtrend develops
    if is_strong_downtrend(s, ii, ats)
        return true
    end
    
    # Or sell if uptrend weakens significantly
    if !is_strong_uptrend(s, ii, ats)
        # Check if trend is just consolidating or actually reversing
        adx = signal_value(s, ii, :adx, ats)
        sma_fast = signal_value(s, ii, :sma_fast, ats)
        sma_medium = signal_value(s, ii, :sma_medium, ats)
        
        if !isnothing(adx) && !isnothing(sma_fast) && !isnothing(sma_medium)
            # If ADX is falling and fast MA crosses below medium MA, exit
            if adx < 20 && sma_fast < sma_medium
                return true
            end
        end
    end
    
    # Additional exit conditions
    macd_line = signal_value(s, ii, :macd_line, ats)
    macd_signal = signal_value(s, ii, :macd_signal, ats)
    roc = signal_value(s, ii, :roc, ats)
    
    # Exit on momentum divergence
    if !isnothing(macd_line) && !isnothing(macd_signal)
        if macd_line < macd_signal && macd_line < 0
            return true
        end
    end
    
    # Exit on negative rate of change
    if !isnothing(roc) && roc < -2  # Significant negative momentum
        return true
    end
    
    return false
end

# Alternative: Breakout trend following
function isbuy_breakout(s::SC, ii, ats)
    # Look for breakouts from consolidation periods
    adx = signal_value(s, ii, :adx, ats)
    atr = signal_value(s, ii, :atr, ats)
    volume_ma = signal_value(s, ii, :volume_ma, ats)
    
    if any(isnothing, [adx, atr, volume_ma])
        return false
    end
    
    data = ohlcv(ii)
    idx = dateindex(data, ats)
    
    if idx < 20
        return false
    end
    
    current_price = data.close[idx]
    current_volume = data.volume[idx]
    
    # Look for consolidation followed by breakout
    # 1. Recent low ADX (consolidation)
    recent_adx_low = minimum([signal_value(s, ii, :adx, data.timestamp[i]) 
                             for i in (idx-10):idx 
                             if !isnothing(signal_value(s, ii, :adx, data.timestamp[i]))])
    
    # 2. Current ADX rising (trend starting)
    if recent_adx_low > 15 || adx < recent_adx_low * 1.2
        return false
    end
    
    # 3. Price breakout above recent high
    recent_high = maximum(data.high[(idx-10):idx])
    if current_price <= recent_high
        return false
    end
    
    # 4. Volume confirmation
    if current_volume <= volume_ma * 1.1
        return false
    end
    
    # 5. Volatility expansion
    recent_atr = [signal_value(s, ii, :atr, data.timestamp[i]) 
                  for i in (idx-5):idx 
                  if !isnothing(signal_value(s, ii, :atr, data.timestamp[i]))]
    
    if length(recent_atr) < 3
        return false
    end
    
    avg_recent_atr = sum(recent_atr) / length(recent_atr)
    if atr <= avg_recent_atr * 1.1  # ATR should be expanding
        return false
    end
    
    return true
end

# Trend strength measurement
function get_trend_strength(s::SC, ii, ats)
    adx = signal_value(s, ii, :adx, ats)
    di_plus = signal_value(s, ii, :di_plus, ats)
    di_minus = signal_value(s, ii, :di_minus, ats)
    
    if any(isnothing, [adx, di_plus, di_minus])
        return 0.0
    end
    
    # Normalize ADX to 0-100 scale
    strength = min(100, adx)
    
    # Adjust for direction
    if di_plus > di_minus
        return strength  # Positive for uptrend
    else
        return -strength  # Negative for downtrend
    end
end

# Customization Options:
#
# 1. Adjust trend strength thresholds:
#    Change ADX threshold from 25 to 20 (more sensitive) or 30 (less sensitive)
#
# 2. Modify moving average periods:
#    Use different combinations like 5/13/34 or 10/20/50
#
# 3. Add more trend filters:
#    :parabolic_sar => (; type=oti.ParabolicSAR{DFT}, tf=tf"1m", params=(; af_start=0.02, af_increment=0.02, af_max=0.2)),
#
# 4. Implement trend strength weighting:
#    Adjust position size based on trend strength
#
# 5. Add market structure analysis:
#    Look for higher highs/higher lows pattern confirmation