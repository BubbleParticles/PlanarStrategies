# Position management system for StrategyFramework
# Handles position sizing, volatility adjustments, and risk-based calculations

using Statistics
using Dates
using Planar

"""
    calculate_position_adjustment(s::SC, ai::AssetInstance, ats::DateTime)

Calculate position size adjustment based on volatility indicators (ATR, KAMA, VTX).
Returns a multiplier that adjusts the base position size based on market conditions.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `ats::DateTime`: Current timestamp

# Returns
- Float64: Position adjustment multiplier (typically 0.5 to 2.0)
"""
function calculate_position_adjustment(s::SC, ai::AssetInstance, ats::DateTime)
    try
        # Get OHLCV data for calculations
        ohlcv = s.universe[ai]
        if isempty(ohlcv)
            @warn "No OHLCV data available for position adjustment calculation" ai=ai
            return 1.0
        end
        
        # Extract price data
        closes = ohlcv.close
        highs = ohlcv.high
        lows = ohlcv.low
        volumes = ohlcv.volume
        
        if length(closes) < 50  # Need sufficient data for indicators
            return 1.0
        end
        
        # Calculate ATR-based volatility adjustment
        atr_adjustment = calculate_atr_adjustment(highs, lows, closes)
        
        # Calculate KAMA-based trend adjustment
        kama_adjustment = calculate_kama_adjustment(closes)
        
        # Calculate VTX-based trend strength adjustment
        vtx_adjustment = calculate_vtx_adjustment(highs, lows, closes, volumes)
        
        # Combine adjustments with weights
        # ATR: 40% weight (volatility)
        # KAMA: 35% weight (trend direction)
        # VTX: 25% weight (trend strength)
        combined_adjustment = (
            0.40 * atr_adjustment +
            0.35 * kama_adjustment +
            0.25 * vtx_adjustment
        )
        
        # Clamp adjustment between 0.2 and 3.0 for safety
        return clamp(combined_adjustment, 0.2, 3.0)
        
    catch e
        @error "Error calculating position adjustment" ai=ai error=e
        return 1.0  # Safe fallback
    end
end

"""
    calculate_atr_adjustment(highs, lows, closes, period::Int = 14)

Calculate position adjustment based on Average True Range (ATR).
Higher volatility reduces position size, lower volatility increases it.
"""
function calculate_atr_adjustment(highs, lows, closes, period::Int = 14)
    if length(closes) < period + 1
        return 1.0
    end
    
    # Calculate ATR
    atr_values = calculate_atr(highs, lows, closes, period)
    current_atr = atr_values[end]
    
    if isnan(current_atr) || current_atr <= 0
        return 1.0
    end
    
    # Calculate ATR percentile over recent history
    recent_atr = atr_values[max(1, end-100):end]
    recent_atr = recent_atr[.!isnan.(recent_atr)]
    
    if length(recent_atr) < 10
        return 1.0
    end
    
    # Calculate percentile rank of current ATR
    atr_percentile = sum(recent_atr .<= current_atr) / length(recent_atr)
    
    # Inverse relationship: high volatility -> smaller position
    # Map percentile (0-1) to adjustment (1.5-0.5)
    return 1.5 - atr_percentile
end

"""
    calculate_kama_adjustment(closes, period::Int = 20)

Calculate position adjustment based on Kaufman Adaptive Moving Average (KAMA).
Strong trends increase position size, sideways markets decrease it.
"""
function calculate_kama_adjustment(closes, period::Int = 20)
    if length(closes) < period + 10
        return 1.0
    end
    
    # Calculate KAMA
    kama_values = calculate_kama(closes, period)
    
    if length(kama_values) < 5
        return 1.0
    end
    
    current_price = closes[end]
    current_kama = kama_values[end]
    
    if isnan(current_kama) || current_kama <= 0
        return 1.0
    end
    
    # Calculate trend strength based on price vs KAMA
    price_kama_ratio = current_price / current_kama
    
    # Calculate KAMA slope (trend direction strength)
    if length(kama_values) >= 5
        recent_kama = kama_values[end-4:end]
        kama_slope = (recent_kama[end] - recent_kama[1]) / recent_kama[1]
    else
        kama_slope = 0.0
    end
    
    # Strong uptrend: price > KAMA and positive slope
    # Strong downtrend: price < KAMA and negative slope
    # Sideways: price ≈ KAMA or conflicting signals
    
    trend_strength = abs(kama_slope) * 10  # Scale slope
    direction_alignment = abs(price_kama_ratio - 1.0) * 2  # Distance from KAMA
    
    # Combine trend strength and direction alignment
    adjustment = 1.0 + min(trend_strength + direction_alignment, 1.0)
    
    return clamp(adjustment, 0.5, 2.0)
end

"""
    calculate_kama(closes, period::Int = 20, fast_sc::Float64 = 2.0, slow_sc::Float64 = 30.0)

Calculate Kaufman Adaptive Moving Average (KAMA).
"""
function calculate_kama(closes, period::Int = 20, fast_sc::Float64 = 2.0, slow_sc::Float64 = 30.0)
    n = length(closes)
    if n < period + 1
        return Float64[]
    end
    
    kama = Vector{Float64}(undef, n)
    kama[1:period] .= NaN
    
    # Initialize KAMA with SMA
    kama[period + 1] = mean(closes[1:period + 1])
    
    fast_sc = 2.0 / (fast_sc + 1.0)
    slow_sc = 2.0 / (slow_sc + 1.0)
    
    for i in (period + 2):n
        # Calculate efficiency ratio
        change = abs(closes[i] - closes[i - period])
        volatility = sum(abs.(diff(closes[(i - period):i])))
        
        er = volatility > 0 ? change / volatility : 0.0
        
        # Calculate smoothing constant
        sc = (er * (fast_sc - slow_sc) + slow_sc)^2
        
        # Calculate KAMA
        kama[i] = kama[i - 1] + sc * (closes[i] - kama[i - 1])
    end
    
    return kama
end

"""
    calculate_vtx_adjustment(highs, lows, closes, volumes, period::Int = 14)

Calculate position adjustment based on Volume-Trend-X (VTX) indicator.
High volume with strong trends increases position size.
"""
function calculate_vtx_adjustment(highs, lows, closes, volumes, period::Int = 14)
    if length(closes) < period + 1
        return 1.0
    end
    
    # Calculate price momentum
    price_changes = diff(closes)
    
    # Calculate volume-weighted momentum
    if length(volumes) >= length(price_changes)
        vol_weighted_momentum = price_changes .* volumes[2:end]
    else
        vol_weighted_momentum = price_changes
    end
    
    # Calculate rolling average of volume-weighted momentum
    if length(vol_weighted_momentum) < period
        return 1.0
    end
    
    recent_momentum = vol_weighted_momentum[max(1, end-period+1):end]
    avg_momentum = mean(abs.(recent_momentum))
    
    # Calculate volume trend
    recent_volumes = volumes[max(1, end-period+1):end]
    volume_trend = mean(recent_volumes) / mean(volumes[max(1, end-2*period+1):max(1, end-period)])
    
    if isnan(volume_trend) || volume_trend <= 0
        volume_trend = 1.0
    end
    
    # Combine momentum and volume trend
    # High momentum + increasing volume = stronger signal
    momentum_strength = min(avg_momentum / (mean(abs.(closes)) * 0.01), 2.0)  # Normalize
    volume_strength = clamp(volume_trend, 0.5, 2.0)
    
    adjustment = 0.7 + 0.3 * momentum_strength * volume_strength
    
    return clamp(adjustment, 0.5, 2.0)
end

"""
    get_target_position_size(s::SC, ai::AssetInstance, ps::PositionSide, ats::DateTime)

Calculate target position size with dynamic adjustments based on market conditions.
Considers volatility, trend strength, and risk management parameters.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `ps::PositionSide`: Position side (Long/Short)
- `ats::DateTime`: Current timestamp

# Returns
- Float64: Target position size in base currency
"""
function get_target_position_size(s::SC, ai::AssetInstance, ps::PositionSide, ats::DateTime)
    try
        # Get base position size from strategy configuration
        base_size = get_base_position_size(s, ai)
        
        if base_size <= 0
            return 0.0
        end
        
        # Apply volatility and trend adjustments
        adjustment_multiplier = calculate_position_adjustment(s, ai, ats)
        
        # Apply risk management adjustments
        risk_multiplier = calculate_risk_multiplier(s, ai, ats)
        
        # Apply drawdown adjustments
        drawdown_multiplier = calculate_drawdown_multiplier(s)
        
        # Calculate final target size
        target_size = base_size * adjustment_multiplier * risk_multiplier * drawdown_multiplier
        
        # Apply position limits
        max_position = get_max_position_size(s, ai)
        target_size = min(target_size, max_position)
        
        # Ensure minimum position size if trading
        min_position = get_min_position_size(s, ai)
        if target_size > 0 && target_size < min_position
            target_size = min_position
        end
        
        return target_size
        
    catch e
        @error "Error calculating target position size" ai=ai ps=ps error=e
        return 0.0
    end
end

"""
    get_base_position_size(s::SC, ai::AssetInstance)

Get base position size from strategy configuration.
"""
function get_base_position_size(s::SC, ai::AssetInstance)
    # Default base size as percentage of available cash
    available_cash = cash(s, ai)
    base_pct = get(s.config, :base_position_pct, 0.1)  # 10% default
    
    return available_cash * base_pct
end

"""
    calculate_risk_multiplier(s::SC, ai::AssetInstance, ats::DateTime)

Calculate risk-based position size multiplier.
Reduces position size based on current risk exposure.
"""
function calculate_risk_multiplier(s::SC, ai::AssetInstance, ats::DateTime)
    try
        # Calculate current portfolio risk
        total_exposure = 0.0
        available_cash = cash(s, ai)
        
        # Sum up all position exposures
        for (asset, _) in s.universe
            if haspositions(s, asset)
                pos_value = abs(position(s, asset) * last(s.universe[asset].close))
                total_exposure += pos_value
            end
        end
        
        # Calculate risk ratio
        if available_cash > 0
            risk_ratio = total_exposure / (total_exposure + available_cash)
        else
            risk_ratio = 1.0
        end
        
        # Reduce position size as risk increases
        # At 50% risk ratio, reduce to 80% size
        # At 80% risk ratio, reduce to 50% size
        if risk_ratio < 0.3
            return 1.0
        elseif risk_ratio < 0.5
            return 1.0 - (risk_ratio - 0.3) * 1.0  # Linear reduction
        elseif risk_ratio < 0.8
            return 0.8 - (risk_ratio - 0.5) * 1.0  # Steeper reduction
        else
            return 0.2  # Minimum multiplier
        end
        
    catch e
        @error "Error calculating risk multiplier" ai=ai error=e
        return 0.5  # Conservative fallback
    end
end

"""
    calculate_drawdown_multiplier(s::SC)

Calculate position size multiplier based on current drawdown.
Reduces position size during drawdown periods.
"""
function calculate_drawdown_multiplier(s::SC)
    try
        # Get peak cash and current cash
        peak_cash = get(s.config, :peak_cash, 0.0)
        current_cash = sum(cash(s, ai) for (ai, _) in s.universe)
        
        if peak_cash <= 0
            return 1.0
        end
        
        # Calculate drawdown percentage
        drawdown_pct = (peak_cash - current_cash) / peak_cash
        
        # Reduce position size based on drawdown
        if drawdown_pct < 0.05  # Less than 5% drawdown
            return 1.0
        elseif drawdown_pct < 0.15  # 5-15% drawdown
            return 1.0 - drawdown_pct * 2.0  # Gradual reduction
        elseif drawdown_pct < 0.30  # 15-30% drawdown
            return 0.7 - (drawdown_pct - 0.15) * 2.0  # Steeper reduction
        else  # More than 30% drawdown
            return 0.3  # Minimum multiplier
        end
        
    catch e
        @error "Error calculating drawdown multiplier" error=e
        return 0.5  # Conservative fallback
    end
end

"""
    get_max_position_size(s::SC, ai::AssetInstance)

Get maximum allowed position size for an asset.
"""
function get_max_position_size(s::SC, ai::AssetInstance)
    available_cash = cash(s, ai)
    max_pct = get(s.config, :max_position_pct, 0.25)  # 25% default
    
    return available_cash * max_pct
end

"""
    get_min_position_size(s::SC, ai::AssetInstance)

Get minimum position size for an asset (exchange minimum).
"""
function get_min_position_size(s::SC, ai::AssetInstance)
    # This should be based on exchange minimum order size
    # For now, use a reasonable default
    return get(s.config, :min_position_size, 10.0)  # $10 minimum
end

"""
    trade_amount(s::SC, ai::AssetInstance, ats::DateTime, ps::PositionSide)

Calculate the actual trade amount considering drawdown, available cash, and position limits.
This is the final amount to be used for order placement.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `ats::DateTime`: Current timestamp
- `ps::PositionSide`: Position side (Long/Short)

# Returns
- Float64: Trade amount in base currency
"""
function trade_amount(s::SC, ai::AssetInstance, ats::DateTime, ps::PositionSide)
    try
        # Get target position size
        target_size = get_target_position_size(s, ai, ps, ats)
        
        if target_size <= 0
            return 0.0
        end
        
        # Get current position
        current_position = haspositions(s, ai) ? abs(position(s, ai)) : 0.0
        current_price = last(s.universe[ai].close)
        current_position_value = current_position * current_price
        
        # Calculate position difference
        position_diff = target_size - current_position_value
        
        # Only trade if difference is significant
        min_trade_amount = get_min_position_size(s, ai)
        if abs(position_diff) < min_trade_amount
            return 0.0
        end
        
        # Check available cash for increasing positions
        if position_diff > 0
            available_cash = cash(s, ai)
            reserve_pct = get(s.config, :reserve_cash_pct, 0.1)
            usable_cash = available_cash * (1.0 - reserve_pct)
            
            # Limit trade amount to available cash
            position_diff = min(position_diff, usable_cash)
        end
        
        # Apply leverage if configured
        leverage = get(s.config, :def_lev, 1.0)
        if leverage > 1.0 && position_diff > 0
            # Only apply leverage to increasing positions
            position_diff *= leverage
        end
        
        # Convert to quantity (shares/contracts)
        if current_price > 0
            trade_quantity = abs(position_diff) / current_price
        else
            @warn "Invalid price for trade amount calculation" ai=ai price=current_price
            return 0.0
        end
        
        # Apply exchange-specific minimums and increments
        trade_quantity = normalize_trade_quantity(s, ai, trade_quantity)
        
        # Convert back to base currency amount
        final_amount = trade_quantity * current_price
        
        return final_amount
        
    catch e
        @error "Error calculating trade amount" ai=ai ps=ps error=e
        return 0.0
    end
end

"""
    normalize_trade_quantity(s::SC, ai::AssetInstance, quantity::Float64)

Normalize trade quantity to exchange requirements.
"""
function normalize_trade_quantity(s::SC, ai::AssetInstance, quantity::Float64)
    try
        # Get exchange info (this would come from exchange configuration)
        # For now, use reasonable defaults
        lot_size = get(s.config, :lot_size, 0.001)
        min_quantity = get(s.config, :min_quantity, 0.001)
        
        # Normalize to lot size
        normalized = round(quantity / lot_size) * lot_size
        
        # Ensure minimum quantity
        if normalized > 0 && normalized < min_quantity
            normalized = min_quantity
        end
        
        return normalized
        
    catch e
        @error "Error normalizing trade quantity" ai=ai quantity=quantity error=e
        return 0.0
    end
end

"""
    should_adjust_position(s::SC, ai::AssetInstance, ats::DateTime)

Determine if position should be adjusted based on current market conditions.
"""
function should_adjust_position(s::SC, ai::AssetInstance, ats::DateTime)
    try
        # Check if enough time has passed since last adjustment
        last_trade_time = get(s.config, :last_trade_time, Dict{AssetInstance, DateTime}())
        cooldown = get(s.config, :trade_cooldown, Minute(5))
        
        if haskey(last_trade_time, ai)
            if ats - last_trade_time[ai] < cooldown
                return false
            end
        end
        
        # Check if market conditions warrant adjustment
        target_size = get_target_position_size(s, ai, Long(), ats)  # Use Long as default
        current_position = haspositions(s, ai) ? abs(position(s, ai)) : 0.0
        current_price = last(s.universe[ai].close)
        current_position_value = current_position * current_price
        
        # Calculate percentage difference
        if target_size > 0
            diff_pct = abs(target_size - current_position_value) / target_size
            min_adjustment_pct = get(s.config, :min_adjustment_pct, 0.1)  # 10% minimum
            
            return diff_pct >= min_adjustment_pct
        end
        
        return false
        
    catch e
        @error "Error checking if position should be adjusted" ai=ai error=e
        return false
    end
end