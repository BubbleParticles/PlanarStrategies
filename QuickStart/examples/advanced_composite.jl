# Advanced Composite Strategy
#
# This strategy combines multiple indicators and techniques for robust signal generation.
# It demonstrates advanced concepts like signal weighting, confirmation systems, and
# adaptive parameters based on market conditions.

function setsignals!(s)
    attrs = s.attrs
    attrs[:signals_set] = false
    
    # Comprehensive indicator suite
    sigdefs = attrs[:signals_def] = signals(
        # Trend indicators
        :sma_fast => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=10)),
        :sma_slow => (; type=oti.SMA{DFT}, tf=tf"1m", params=(; period=20)),
        :ema_trend => (; type=oti.EMA{DFT}, tf=tf"5m", params=(; period=50)),
        
        # Momentum indicators
        :rsi => (; type=oti.RSI{DFT}, tf=tf"1m", params=(; period=14)),
        :macd_line => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_signal => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        :macd_histogram => (; type=oti.MACD{DFT}, tf=tf"1m", params=(; fast=12, slow=26, signal=9)),
        
        # Volatility indicators
        :bb_upper => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_middle => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :bb_lower => (; type=oti.BollingerBands{DFT}, tf=tf"1m", params=(; period=20, std=2.0)),
        :atr => (; type=oti.ATR{DFT}, tf=tf"1m", params=(; period=14)),
        
        # Volume indicators
        :volume_ma => (; type=oti.VolumeMA{DFT}, tf=tf"1m", params=(; period=20)),
        :obv => (; type=oti.OBV{DFT}, tf=tf"1m", params=()),
        
        # Higher timeframe context
        :trend_1h => (; type=oti.SMA{DFT}, tf=tf"1h", params=(; period=20)),
        :rsi_1h => (; type=oti.RSI{DFT}, tf=tf"1h", params=(; period=14)),
    )
    
    inittrends!(s, keys(sigdefs.defs))
end

# Signal scoring system
function calculate_signal_score(s::SC, ai, ats, signal_type::Symbol)
    score = 0.0
    max_score = 0.0
    
    # Get all indicator values
    sma_fast = signal_value(s, ai, :sma_fast, ats)
    sma_slow = signal_value(s, ai, :sma_slow, ats)
    ema_trend = signal_value(s, ai, :ema_trend, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    macd_histogram = signal_value(s, ai, :macd_histogram, ats)
    bb_upper = signal_value(s, ai, :bb_upper, ats)
    bb_middle = signal_value(s, ai, :bb_middle, ats)
    bb_lower = signal_value(s, ai, :bb_lower, ats)
    atr = signal_value(s, ai, :atr, ats)
    volume_ma = signal_value(s, ai, :volume_ma, ats)
    obv = signal_value(s, ai, :obv, ats)
    trend_1h = signal_value(s, ai, :trend_1h, ats)
    rsi_1h = signal_value(s, ai, :rsi_1h, ats)
    
    # Get current price and volume
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    current_volume = data.volume[idx]
    
    if signal_type == :buy
        # Trend signals (weight: 30%)
        if !isnothing(sma_fast) && !isnothing(sma_slow)
            max_score += 10.0
            if sma_fast > sma_slow
                score += 10.0  # Strong bullish trend
            elseif sma_fast > sma_slow * 0.999
                score += 5.0   # Weak bullish trend
            end
        end
        
        if !isnothing(ema_trend)
            max_score += 10.0
            if current_price > ema_trend
                score += 10.0  # Price above trend
            elseif current_price > ema_trend * 0.995
                score += 5.0   # Price near trend
            end
        end
        
        if !isnothing(trend_1h)
            max_score += 10.0
            if current_price > trend_1h
                score += 10.0  # Higher timeframe bullish
            end
        end
        
        # Momentum signals (weight: 25%)
        if !isnothing(rsi)
            max_score += 10.0
            if rsi < 30
                score += 10.0  # Oversold
            elseif rsi < 50
                score += 5.0   # Below midline
            end
        end
        
        if !isnothing(macd_line) && !isnothing(macd_signal)
            max_score += 10.0
            if macd_line > macd_signal && macd_line > 0
                score += 10.0  # Strong bullish momentum
            elseif macd_line > macd_signal
                score += 5.0   # Weak bullish momentum
            end
        end
        
        if !isnothing(rsi_1h)
            max_score += 5.0
            if rsi_1h < 70
                score += 5.0   # Higher timeframe not overbought
            end
        end
        
        # Volatility signals (weight: 20%)
        if !isnothing(bb_lower) && !isnothing(bb_middle)
            max_score += 10.0
            if current_price <= bb_lower
                score += 10.0  # At lower band (mean reversion)
            elseif current_price < bb_middle
                score += 5.0   # Below middle
            end
        end
        
        if !isnothing(atr)
            max_score += 10.0
            # Higher volatility can be good for breakouts
            # This is a simplified volatility score
            score += min(10.0, atr * 1000)  # Adjust multiplier based on asset
        end
        
        # Volume signals (weight: 15%)
        if !isnothing(volume_ma)
            max_score += 10.0
            if current_volume > volume_ma * 1.2
                score += 10.0  # High volume confirmation
            elseif current_volume > volume_ma
                score += 5.0   # Above average volume
            end
        end
        
        if !isnothing(obv) && idx > 1
            max_score += 5.0
            prev_obv = signal_value(s, ai, :obv, data.timestamp[idx-1])
            if !isnothing(prev_obv) && obv > prev_obv
                score += 5.0   # OBV increasing
            end
        end
        
        # Market structure (weight: 10%)
        if idx >= 3
            max_score += 5.0
            # Check for higher lows (bullish structure)
            recent_low = minimum(data.low[(idx-2):idx])
            prev_low = minimum(data.low[max(1, idx-5):(idx-3)])
            if recent_low > prev_low
                score += 5.0
            end
        end
        
    elseif signal_type == :sell
        # Similar logic but inverted for sell signals
        # Trend signals (weight: 30%)
        if !isnothing(sma_fast) && !isnothing(sma_slow)
            max_score += 10.0
            if sma_fast < sma_slow
                score += 10.0  # Strong bearish trend
            elseif sma_fast < sma_slow * 1.001
                score += 5.0   # Weak bearish trend
            end
        end
        
        if !isnothing(ema_trend)
            max_score += 10.0
            if current_price < ema_trend
                score += 10.0  # Price below trend
            elseif current_price < ema_trend * 1.005
                score += 5.0   # Price near trend
            end
        end
        
        if !isnothing(trend_1h)
            max_score += 10.0
            if current_price < trend_1h
                score += 10.0  # Higher timeframe bearish
            end
        end
        
        # Momentum signals (weight: 25%)
        if !isnothing(rsi)
            max_score += 10.0
            if rsi > 70
                score += 10.0  # Overbought
            elseif rsi > 50
                score += 5.0   # Above midline
            end
        end
        
        if !isnothing(macd_line) && !isnothing(macd_signal)
            max_score += 10.0
            if macd_line < macd_signal && macd_line < 0
                score += 10.0  # Strong bearish momentum
            elseif macd_line < macd_signal
                score += 5.0   # Weak bearish momentum
            end
        end
        
        if !isnothing(rsi_1h)
            max_score += 5.0
            if rsi_1h > 30
                score += 5.0   # Higher timeframe not oversold
            end
        end
        
        # Volatility signals (weight: 20%)
        if !isnothing(bb_upper) && !isnothing(bb_middle)
            max_score += 10.0
            if current_price >= bb_upper
                score += 10.0  # At upper band (mean reversion)
            elseif current_price > bb_middle
                score += 5.0   # Above middle
            end
        end
        
        if !isnothing(atr)
            max_score += 10.0
            score += min(10.0, atr * 1000)  # Volatility score
        end
        
        # Volume signals (weight: 15%)
        if !isnothing(volume_ma)
            max_score += 10.0
            if current_volume > volume_ma * 1.2
                score += 10.0  # High volume confirmation
            elseif current_volume > volume_ma
                score += 5.0   # Above average volume
            end
        end
        
        if !isnothing(obv) && idx > 1
            max_score += 5.0
            prev_obv = signal_value(s, ai, :obv, data.timestamp[idx-1])
            if !isnothing(prev_obv) && obv < prev_obv
                score += 5.0   # OBV decreasing
            end
        end
        
        # Market structure (weight: 10%)
        if idx >= 3
            max_score += 5.0
            # Check for lower highs (bearish structure)
            recent_high = maximum(data.high[(idx-2):idx])
            prev_high = maximum(data.high[max(1, idx-5):(idx-3)])
            if recent_high < prev_high
                score += 5.0
            end
        end
    end
    
    # Return normalized score (0-100)
    return max_score > 0 ? (score / max_score) * 100 : 0.0
end

function isbuy(s::SC, ai, ats)
    # Calculate composite buy signal score
    buy_score = calculate_signal_score(s, ai, ats, :buy)
    
    # Adaptive threshold based on market conditions
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    
    # Get volatility for adaptive threshold
    atr = signal_value(s, ai, :atr, ats)
    base_threshold = 60.0  # Base threshold (60% of max score)
    
    if !isnothing(atr)
        # In high volatility, require higher confidence
        volatility_factor = min(2.0, atr * 10000)  # Adjust multiplier
        threshold = base_threshold + (volatility_factor * 5)
    else
        threshold = base_threshold
    end
    
    # Additional filters
    rsi = signal_value(s, ai, :rsi, ats)
    if !isnothing(rsi) && rsi > 80
        # Don't buy when extremely overbought
        return false
    end
    
    return buy_score >= threshold
end

function issell(s::SC, ai, ats)
    # Calculate composite sell signal score
    sell_score = calculate_signal_score(s, ai, ats, :sell)
    
    # Adaptive threshold based on market conditions
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    
    # Get volatility for adaptive threshold
    atr = signal_value(s, ai, :atr, ats)
    base_threshold = 60.0  # Base threshold (60% of max score)
    
    if !isnothing(atr)
        # In high volatility, require higher confidence
        volatility_factor = min(2.0, atr * 10000)  # Adjust multiplier
        threshold = base_threshold + (volatility_factor * 5)
    else
        threshold = base_threshold
    end
    
    # Additional filters
    rsi = signal_value(s, ai, :rsi, ats)
    if !isnothing(rsi) && rsi < 20
        # Don't sell when extremely oversold
        return false
    end
    
    return sell_score >= threshold
end

# Alternative: Machine Learning-inspired approach
function isbuy_ml_inspired(s::SC, ai, ats)
    # Feature extraction
    features = extract_features(s, ai, ats)
    
    if isempty(features)
        return false
    end
    
    # Simple linear combination (in real ML, this would be learned weights)
    weights = [
        0.25,  # trend_strength
        0.20,  # momentum_score
        0.15,  # volatility_score
        0.15,  # volume_score
        0.10,  # market_structure
        0.10,  # higher_timeframe
        0.05,  # sentiment_proxy
    ]
    
    # Calculate weighted score
    score = sum(features .* weights)
    
    # Apply sigmoid-like transformation
    probability = 1 / (1 + exp(-5 * (score - 0.5)))
    
    # Buy if probability > 70%
    return probability > 0.7
end

function extract_features(s::SC, ai, ats)
    features = Float64[]
    
    # Get indicators
    sma_fast = signal_value(s, ai, :sma_fast, ats)
    sma_slow = signal_value(s, ai, :sma_slow, ats)
    rsi = signal_value(s, ai, :rsi, ats)
    macd_line = signal_value(s, ai, :macd_line, ats)
    macd_signal = signal_value(s, ai, :macd_signal, ats)
    bb_upper = signal_value(s, ai, :bb_upper, ats)
    bb_lower = signal_value(s, ai, :bb_lower, ats)
    volume_ma = signal_value(s, ai, :volume_ma, ats)
    trend_1h = signal_value(s, ai, :trend_1h, ats)
    
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    current_price = data.close[idx]
    current_volume = data.volume[idx]
    
    # Feature 1: Trend strength (0-1)
    if !isnothing(sma_fast) && !isnothing(sma_slow)
        trend_strength = max(0, min(1, (sma_fast - sma_slow) / sma_slow + 0.5))
        push!(features, trend_strength)
    else
        return Float64[]  # Missing critical data
    end
    
    # Feature 2: Momentum score (0-1)
    if !isnothing(rsi)
        momentum_score = (100 - rsi) / 100  # Inverted RSI for buy signals
        push!(features, momentum_score)
    else
        return Float64[]
    end
    
    # Feature 3: Volatility score (0-1)
    if !isnothing(bb_upper) && !isnothing(bb_lower)
        band_position = (current_price - bb_lower) / (bb_upper - bb_lower)
        volatility_score = 1 - band_position  # Lower in band = higher score for buy
        push!(features, max(0, min(1, volatility_score)))
    else
        return Float64[]
    end
    
    # Feature 4: Volume score (0-1)
    if !isnothing(volume_ma)
        volume_score = min(1, current_volume / volume_ma / 2)  # Normalize to 0-1
        push!(features, volume_score)
    else
        push!(features, 0.5)  # Neutral if no volume data
    end
    
    # Feature 5: Market structure (0-1)
    if idx >= 5
        recent_highs = data.high[(idx-4):idx]
        structure_score = (recent_highs[end] - recent_highs[1]) / recent_highs[1]
        structure_score = max(0, min(1, structure_score * 10 + 0.5))  # Normalize
        push!(features, structure_score)
    else
        push!(features, 0.5)
    end
    
    # Feature 6: Higher timeframe (0-1)
    if !isnothing(trend_1h)
        htf_score = current_price > trend_1h ? 1.0 : 0.0
        push!(features, htf_score)
    else
        push!(features, 0.5)
    end
    
    # Feature 7: Sentiment proxy (0-1) - using MACD as proxy
    if !isnothing(macd_line) && !isnothing(macd_signal)
        sentiment = macd_line > macd_signal ? 1.0 : 0.0
        push!(features, sentiment)
    else
        push!(features, 0.5)
    end
    
    return features
end

# Customization Options:
#
# 1. Adjust scoring weights:
#    Modify the weights in calculate_signal_score() based on your preferences
#
# 2. Add more indicators:
#    Include additional technical indicators in setsignals!()
#
# 3. Implement machine learning:
#    Train actual ML models on historical data for feature weights
#
# 4. Add market regime detection:
#    Adjust strategy behavior based on detected market conditions
#
# 5. Implement dynamic thresholds:
#    Adjust signal thresholds based on recent performance