# Market making system for StrategyFramework
# Handles automated market making, spread calculations, and liquidity provision

using Dates
using Statistics
using Planar

"""
    market_make(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime; 
                target_spread_pct::Float64 = 0.002, max_position_pct::Float64 = 0.1)

Execute market making strategy for an asset by placing buy and sell orders around current price.
Provides liquidity while managing inventory risk and maintaining target spreads.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance to market make
- `ats::DateTime`: Analysis timestamp
- `ts::DateTime`: Current timestamp
- `target_spread_pct::Float64`: Target spread as percentage of mid price (default: 0.2%)
- `max_position_pct::Float64`: Maximum position as percentage of available capital (default: 10%)

# Returns
- NamedTuple with market making results and order information
"""
function market_make(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime; 
                     target_spread_pct::Float64 = 0.002, max_position_pct::Float64 = 0.1)
    try
        @debug "Starting market making" ai=ai target_spread_pct=target_spread_pct
        
        # Check if market making is appropriate
        if !should_market_make(s, ai, ats)
            @debug "Market making conditions not met" ai=ai
            return (
                success = false,
                reason = "conditions_not_met",
                buy_order = nothing,
                sell_order = nothing
            )
        end
        
        # Get current market data
        current_price = last(s.universe[ai].close)
        market_conditions = analyze_market_making_conditions(s, ai)
        
        # Calculate optimal spread based on market conditions
        optimal_spread = calculate_optimal_spread(s, ai, target_spread_pct, market_conditions)
        
        # Calculate order amounts
        make_amounts = get_make_amounts(s, ai, max_position_pct)
        
        if make_amounts.buy_amount <= 0 && make_amounts.sell_amount <= 0
            @debug "No valid make amounts calculated" ai=ai
            return (
                success = false,
                reason = "no_valid_amounts",
                buy_order = nothing,
                sell_order = nothing
            )
        end
        
        # Calculate bid and ask prices
        half_spread = current_price * optimal_spread / 2
        bid_price = current_price - half_spread
        ask_price = current_price + half_spread
        
        # Normalize prices to exchange requirements
        bid_price = normalize_price(bid_price, get_tick_size(s, ai))
        ask_price = normalize_price(ask_price, get_tick_size(s, ai))
        
        # Place market making orders
        buy_result = nothing
        sell_result = nothing
        
        # Place buy order (bid)
        if make_amounts.buy_amount > 0
            buy_result = place_market_making_order(s, ai, Long(), make_amounts.buy_amount, 
                                                 bid_price, "market_make_buy")
        end
        
        # Place sell order (ask)
        if make_amounts.sell_amount > 0
            sell_result = place_market_making_order(s, ai, Short(), make_amounts.sell_amount, 
                                                  ask_price, "market_make_sell")
        end
        
        # Update market making tracking
        update_market_making_tracking(s, ai, ts, optimal_spread, make_amounts, buy_result, sell_result)
        
        success = (buy_result !== nothing && buy_result.success) || 
                 (sell_result !== nothing && sell_result.success)
        
        @info "Market making execution completed" ai=ai success=success spread=optimal_spread
        
        return (
            success = success,
            reason = success ? "orders_placed" : "order_placement_failed",
            buy_order = buy_result,
            sell_order = sell_result,
            spread_used = optimal_spread,
            market_conditions = market_conditions
        )
        
    catch e
        @error "Error in market making" ai=ai error=e
        return (
            success = false,
            reason = "error",
            buy_order = nothing,
            sell_order = nothing,
            error = e
        )
    end
end

"""
    should_market_make(s::SC, ai::AssetInstance, ats::DateTime)

Determine if market making should be performed based on current conditions.
Checks market volatility, position limits, and strategy state.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `ats::DateTime`: Analysis timestamp

# Returns
- Bool: true if market making should proceed
"""
function should_market_make(s::SC, ai::AssetInstance, ats::DateTime)
    try
        # Check if market making is enabled
        if !get(s.config, :enable_market_making, true)
            @debug "Market making disabled in configuration" ai=ai
            return false
        end
        
        # Check market hours
        if !is_market_open(s, ai, ats)
            @debug "Market is closed" ai=ai
            return false
        end
        
        # Check if sufficient data is available
        if length(s.universe[ai].close) < 20
            @debug "Insufficient market data for market making" ai=ai
            return false
        end
        
        # Check volatility conditions
        market_conditions = analyze_market_making_conditions(s, ai)
        max_volatility = get(s.config, :max_mm_volatility, 0.05)  # 5% max volatility
        
        if market_conditions.volatility > max_volatility
            @debug "Volatility too high for market making" ai=ai volatility=market_conditions.volatility
            return false
        end
        
        # Check position limits
        current_position_value = 0.0
        if haspositions(s, ai)
            current_position = position(s, ai)
            current_price = last(s.universe[ai].close)
            current_position_value = abs(current_position * current_price)
        end
        
        max_position_value = get_max_position_size(s, ai)
        position_utilization = current_position_value / max_position_value
        max_position_utilization = get(s.config, :max_mm_position_utilization, 0.8)  # 80% max
        
        if position_utilization > max_position_utilization
            @debug "Position utilization too high for market making" ai=ai utilization=position_utilization
            return false
        end
        
        # Check available cash
        available_cash = cash(s, ai)
        min_cash_for_mm = get(s.config, :min_cash_for_mm, 1000.0)  # $1000 minimum
        
        if available_cash < min_cash_for_mm
            @debug "Insufficient cash for market making" ai=ai available=available_cash
            return false
        end
        
        # Check recent market making activity (avoid over-trading)
        last_mm_time = get(s.config, :last_mm_time, Dict{AssetInstance, DateTime}())
        mm_cooldown = get(s.config, :mm_cooldown, Minute(5))
        
        if haskey(last_mm_time, ai)
            if ats - last_mm_time[ai] < mm_cooldown
                @debug "Market making cooldown active" ai=ai
                return false
            end
        end
        
        # Check spread conditions
        min_spread = get(s.config, :min_mm_spread, 0.001)  # 0.1% minimum spread
        if market_conditions.current_spread_pct < min_spread
            @debug "Current spread too tight for profitable market making" ai=ai spread=market_conditions.current_spread_pct
            return false
        end
        
        return true
        
    catch e
        @error "Error checking market making conditions" ai=ai error=e
        return false
    end
end

"""
    ensure_market_make(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime)

Ensure market making orders are active, placing new ones if needed.
Manages existing orders and replaces stale or unfavorable orders.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `ats::DateTime`: Analysis timestamp
- `ts::DateTime`: Current timestamp

# Returns
- Bool: true if market making orders are ensured to be active
"""
function ensure_market_make(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime)
    try
        @debug "Ensuring market making orders" ai=ai
        
        # Check existing market making orders
        existing_orders = get_active_market_making_orders(s, ai)
        
        # Determine if orders need to be refreshed
        needs_refresh = should_refresh_market_making_orders(s, ai, existing_orders, ats)
        
        if needs_refresh
            # Cancel existing market making orders
            cancel_market_making_orders(s, ai, existing_orders)
            
            # Place new market making orders
            result = market_make(s, ai, ats, ts)
            return result.success
        else
            @debug "Existing market making orders are still valid" ai=ai
            return true
        end
        
    catch e
        @error "Error ensuring market making" ai=ai error=e
        return false
    end
end

"""
    get_make_amounts(s::SC, ai::AssetInstance, max_position_pct::Float64)

Calculate optimal amounts for market making orders based on available capital and risk limits.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `max_position_pct::Float64`: Maximum position percentage

# Returns
- NamedTuple with buy_amount and sell_amount
"""
function get_make_amounts(s::SC, ai::AssetInstance, max_position_pct::Float64)
    try
        # Get available cash and current position
        available_cash = cash(s, ai)
        current_position = haspositions(s, ai) ? position(s, ai) : 0.0
        current_price = last(s.universe[ai].close)
        current_position_value = current_position * current_price
        
        # Calculate maximum position value
        max_position_value = available_cash * max_position_pct
        
        # Calculate base order size
        base_order_pct = get(s.config, :mm_base_order_pct, 0.02)  # 2% of available cash
        base_order_value = available_cash * base_order_pct
        
        # Adjust for current position (inventory management)
        inventory_adjustment = calculate_inventory_adjustment(current_position_value, max_position_value)
        
        # Calculate buy and sell amounts with inventory bias
        buy_amount = base_order_value * inventory_adjustment.buy_multiplier
        sell_amount = base_order_value * inventory_adjustment.sell_multiplier
        
        # Apply minimum and maximum order size limits
        min_order_value = get_min_position_size(s, ai)
        max_single_order_value = available_cash * get(s.config, :max_mm_single_order_pct, 0.05)  # 5% max
        
        buy_amount = clamp(buy_amount, min_order_value, max_single_order_value)
        sell_amount = clamp(sell_amount, min_order_value, max_single_order_value)
        
        # Check position limits
        if current_position_value + buy_amount > max_position_value
            buy_amount = max(0.0, max_position_value - current_position_value)
        end
        
        if abs(current_position_value - sell_amount) > max_position_value
            sell_amount = max(0.0, abs(current_position_value) - max_position_value)
        end
        
        # Normalize to exchange requirements
        buy_quantity = buy_amount / current_price
        sell_quantity = sell_amount / current_price
        
        lot_size = get_lot_size(s, ai)
        min_quantity = get_min_quantity(s, ai)
        
        buy_quantity = normalize_quantity(buy_quantity, lot_size, min_quantity)
        sell_quantity = normalize_quantity(sell_quantity, lot_size, min_quantity)
        
        # Convert back to amounts
        final_buy_amount = buy_quantity * current_price
        final_sell_amount = sell_quantity * current_price
        
        @debug "Market making amounts calculated" ai=ai buy_amount=final_buy_amount sell_amount=final_sell_amount inventory_adj=inventory_adjustment
        
        return (
            buy_amount = final_buy_amount,
            sell_amount = final_sell_amount,
            buy_quantity = buy_quantity,
            sell_quantity = sell_quantity,
            inventory_adjustment = inventory_adjustment
        )
        
    catch e
        @error "Error calculating make amounts" ai=ai error=e
        return (
            buy_amount = 0.0,
            sell_amount = 0.0,
            buy_quantity = 0.0,
            sell_quantity = 0.0,
            inventory_adjustment = nothing
        )
    end
end

"""
    calculate_optimal_spread(s::SC, ai::AssetInstance, target_spread_pct::Float64, market_conditions)

Calculate optimal spread for market making based on market conditions and volatility.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `target_spread_pct::Float64`: Target spread percentage
- `market_conditions`: Market condition analysis results

# Returns
- Float64: Optimal spread as percentage of mid price
"""
function calculate_optimal_spread(s::SC, ai::AssetInstance, target_spread_pct::Float64, market_conditions)
    try
        # Start with target spread
        optimal_spread = target_spread_pct
        
        # Adjust for volatility
        volatility_multiplier = calculate_volatility_spread_multiplier(market_conditions.volatility)
        optimal_spread *= volatility_multiplier
        
        # Adjust for volume
        volume_multiplier = calculate_volume_spread_multiplier(market_conditions.volume_ratio)
        optimal_spread *= volume_multiplier
        
        # Adjust for current market spread
        if market_conditions.current_spread_pct > 0
            # Don't make spread tighter than 80% of current market spread
            min_spread = market_conditions.current_spread_pct * 0.8
            optimal_spread = max(optimal_spread, min_spread)
        end
        
        # Apply configured limits
        min_spread = get(s.config, :min_mm_spread, 0.0005)  # 0.05% minimum
        max_spread = get(s.config, :max_mm_spread, 0.01)    # 1% maximum
        
        optimal_spread = clamp(optimal_spread, min_spread, max_spread)
        
        @debug "Optimal spread calculated" ai=ai target=target_spread_pct optimal=optimal_spread vol_mult=volatility_multiplier vol_mult=volume_multiplier
        
        return optimal_spread
        
    catch e
        @error "Error calculating optimal spread" ai=ai error=e
        return target_spread_pct  # Fallback to target
    end
end

"""
    calculate_inventory_adjustment(current_position_value::Float64, max_position_value::Float64)

Calculate inventory adjustment multipliers to manage position risk.
Reduces buy orders when long, reduces sell orders when short.

# Arguments
- `current_position_value::Float64`: Current position value (positive for long, negative for short)
- `max_position_value::Float64`: Maximum allowed position value

# Returns
- NamedTuple with buy_multiplier and sell_multiplier
"""
function calculate_inventory_adjustment(current_position_value::Float64, max_position_value::Float64)
    try
        if max_position_value <= 0
            return (buy_multiplier = 1.0, sell_multiplier = 1.0)
        end
        
        # Calculate position ratio (-1 to 1, where 1 is max long, -1 is max short)
        position_ratio = current_position_value / max_position_value
        position_ratio = clamp(position_ratio, -1.0, 1.0)
        
        # Calculate adjustment multipliers
        # When long (positive ratio): reduce buy orders, increase sell orders
        # When short (negative ratio): increase buy orders, reduce sell orders
        
        # Base multipliers
        buy_multiplier = 1.0
        sell_multiplier = 1.0
        
        # Inventory adjustment strength (how much to adjust based on position)
        adjustment_strength = get(s.config, :inventory_adjustment_strength, 0.5)  # 50% adjustment
        
        if position_ratio > 0  # Long position
            # Reduce buy orders, increase sell orders
            buy_multiplier = 1.0 - (position_ratio * adjustment_strength)
            sell_multiplier = 1.0 + (position_ratio * adjustment_strength * 0.5)  # Less aggressive on sell side
        elseif position_ratio < 0  # Short position
            # Increase buy orders, reduce sell orders
            buy_multiplier = 1.0 + (abs(position_ratio) * adjustment_strength * 0.5)  # Less aggressive on buy side
            sell_multiplier = 1.0 - (abs(position_ratio) * adjustment_strength)
        end
        
        # Ensure multipliers are within reasonable bounds
        buy_multiplier = clamp(buy_multiplier, 0.1, 2.0)
        sell_multiplier = clamp(sell_multiplier, 0.1, 2.0)
        
        return (
            buy_multiplier = buy_multiplier,
            sell_multiplier = sell_multiplier,
            position_ratio = position_ratio
        )
        
    catch e
        @error "Error calculating inventory adjustment" current_position=current_position_value max_position=max_position_value error=e
        return (buy_multiplier = 1.0, sell_multiplier = 1.0, position_ratio = 0.0)
    end
end

"""
    analyze_market_making_conditions(s::SC, ai::AssetInstance)

Analyze current market conditions relevant for market making decisions.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance

# Returns
- NamedTuple with market condition metrics
"""
function analyze_market_making_conditions(s::SC, ai::AssetInstance)
    try
        ohlcv = s.universe[ai]
        
        if length(ohlcv.close) < 20
            return (
                volatility = 0.02,
                volume_ratio = 1.0,
                current_spread_pct = 0.001,
                trend_strength = 0.0,
                price_stability = 0.5
            )
        end
        
        # Calculate volatility
        recent_closes = ohlcv.close[max(1, end-19):end]
        returns = diff(log.(recent_closes))
        volatility = std(returns)
        
        # Calculate volume ratio (recent vs historical)
        recent_volumes = ohlcv.volume[max(1, end-19):end]
        historical_volumes = ohlcv.volume[max(1, end-99):max(1, end-20)]
        
        avg_recent_volume = mean(recent_volumes)
        avg_historical_volume = length(historical_volumes) > 0 ? mean(historical_volumes) : avg_recent_volume
        volume_ratio = avg_historical_volume > 0 ? avg_recent_volume / avg_historical_volume : 1.0
        
        # Estimate current spread (simplified)
        current_price = last(ohlcv.close)
        estimated_spread_pct = max(0.001, volatility * 2)  # Rough estimate based on volatility
        
        # Calculate trend strength
        if length(recent_closes) >= 10
            trend_slope = (recent_closes[end] - recent_closes[end-9]) / recent_closes[end-9]
            trend_strength = abs(trend_slope)
        else
            trend_strength = 0.0
        end
        
        # Calculate price stability (inverse of volatility)
        price_stability = 1.0 / (1.0 + volatility * 10)
        
        return (
            volatility = volatility,
            volume_ratio = volume_ratio,
            current_spread_pct = estimated_spread_pct,
            trend_strength = trend_strength,
            price_stability = price_stability
        )
        
    catch e
        @error "Error analyzing market making conditions" ai=ai error=e
        return (
            volatility = 0.02,
            volume_ratio = 1.0,
            current_spread_pct = 0.001,
            trend_strength = 0.0,
            price_stability = 0.5
        )
    end
end

"""
    place_market_making_order(s::SC, ai::AssetInstance, side::PositionSide, amount::Float64, 
                             price::Float64, reason::String)

Place a market making order with appropriate parameters and tracking.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance
- `side::PositionSide`: Order side (Long for buy, Short for sell)
- `amount::Float64`: Order amount
- `price::Float64`: Order price
- `reason::String`: Reason for order (for tracking)

# Returns
- NamedTuple with order result information
"""
function place_market_making_order(s::SC, ai::AssetInstance, side::PositionSide, amount::Float64, 
                                  price::Float64, reason::String)
    try
        # Create order parameters for market making
        order_params = Dict{Symbol, Any}(
            :asset => ai,
            :side => side,
            :amount => amount,
            :price => price,
            :type => :gtc,  # Good Till Cancelled for market making
            :time_in_force => "GTC",
            :is_market_making => true,
            :reason => reason,
            :timestamp => now()
        )
        
        # Add market making specific parameters
        order_params[:post_only] = get(s.config, :mm_post_only, true)  # Ensure maker orders
        order_params[:reduce_only] = false  # Market making orders are not reduce-only
        
        # Generate order ID
        order_id = generate_order_id()
        order_params[:order_id] = order_id
        
        @info "Placing market making order" ai=ai side=side amount=amount price=price reason=reason order_id=order_id
        
        # Execute the order (this would integrate with Planar's order system)
        # For now, simulate the execution
        success_probability = 0.9  # Market making orders generally have high success rate
        
        if rand() < success_probability
            # Successful order placement
            result = (
                success = true,
                order_id = order_id,
                side = side,
                amount = amount,
                price = price,
                timestamp = now(),
                reason = reason,
                error = nothing
            )
            
            # Track the order
            track_market_making_order(s, ai, result)
            
            return result
        else
            # Failed order placement
            error_msg = "Order rejected by exchange"
            @warn "Market making order failed" ai=ai order_id=order_id error=error_msg
            
            return (
                success = false,
                order_id = order_id,
                side = side,
                amount = amount,
                price = price,
                timestamp = now(),
                reason = reason,
                error = error_msg
            )
        end
        
    catch e
        @error "Error placing market making order" ai=ai side=side amount=amount error=e
        return (
            success = false,
            order_id = "error",
            side = side,
            amount = amount,
            price = price,
            timestamp = now(),
            reason = reason,
            error = string(e)
        )
    end
end

"""
    update_market_making_tracking(s::SC, ai::AssetInstance, ts::DateTime, spread::Float64, 
                                 amounts, buy_result, sell_result)

Update tracking information for market making activity.
"""
function update_market_making_tracking(s::SC, ai::AssetInstance, ts::DateTime, spread::Float64, 
                                     amounts, buy_result, sell_result)
    try
        # Update last market making time
        if !haskey(s.config, :last_mm_time)
            s.config[:last_mm_time] = Dict{AssetInstance, DateTime}()
        end
        s.config[:last_mm_time][ai] = ts
        
        # Update market making statistics
        if !haskey(s.config, :mm_stats)
            s.config[:mm_stats] = Dict{AssetInstance, Dict{Symbol, Any}}()
        end
        
        if !haskey(s.config[:mm_stats], ai)
            s.config[:mm_stats][ai] = Dict{Symbol, Any}(
                :total_attempts => 0,
                :successful_orders => 0,
                :total_volume => 0.0,
                :avg_spread => 0.0,
                :last_update => ts
            )
        end
        
        stats = s.config[:mm_stats][ai]
        stats[:total_attempts] += 1
        stats[:last_update] = ts
        
        # Update successful orders count
        if (buy_result !== nothing && buy_result.success) || (sell_result !== nothing && sell_result.success)
            stats[:successful_orders] += 1
        end
        
        # Update volume and spread tracking
        total_volume = 0.0
        if buy_result !== nothing && buy_result.success
            total_volume += buy_result.amount
        end
        if sell_result !== nothing && sell_result.success
            total_volume += sell_result.amount
        end
        
        stats[:total_volume] += total_volume
        
        # Update average spread (exponential moving average)
        alpha = 0.1  # Smoothing factor
        stats[:avg_spread] = stats[:avg_spread] * (1 - alpha) + spread * alpha
        
        @debug "Market making tracking updated" ai=ai total_attempts=stats[:total_attempts] successful=stats[:successful_orders] volume=total_volume
        
    catch e
        @error "Error updating market making tracking" ai=ai error=e
    end
end

# Helper functions

"""
    calculate_volatility_spread_multiplier(volatility::Float64)

Calculate spread multiplier based on market volatility.
Higher volatility requires wider spreads.
"""
function calculate_volatility_spread_multiplier(volatility::Float64)
    # Base multiplier of 1.0 for normal volatility (around 2%)
    base_volatility = 0.02
    
    if volatility <= base_volatility
        return 1.0
    else
        # Increase spread linearly with volatility
        # 4% volatility -> 2x spread, 6% volatility -> 3x spread, etc.
        return 1.0 + (volatility - base_volatility) / base_volatility
    end
end

"""
    calculate_volume_spread_multiplier(volume_ratio::Float64)

Calculate spread multiplier based on volume conditions.
Lower volume requires wider spreads for safety.
"""
function calculate_volume_spread_multiplier(volume_ratio::Float64)
    if volume_ratio >= 1.0
        return 1.0  # Normal or high volume
    elseif volume_ratio >= 0.5
        return 1.0 + (1.0 - volume_ratio) * 0.5  # Slight increase for medium-low volume
    else
        return 1.5 + (0.5 - volume_ratio) * 1.0  # Significant increase for very low volume
    end
end

"""
    get_active_market_making_orders(s::SC, ai::AssetInstance)

Get currently active market making orders for an asset.
"""
function get_active_market_making_orders(s::SC, ai::AssetInstance)
    # This would integrate with Planar's order tracking system
    # For now, return empty list as placeholder
    return []
end

"""
    should_refresh_market_making_orders(s::SC, ai::AssetInstance, existing_orders, ats::DateTime)

Determine if existing market making orders should be refreshed.
"""
function should_refresh_market_making_orders(s::SC, ai::AssetInstance, existing_orders, ats::DateTime)
    # If no existing orders, need to place new ones
    if isempty(existing_orders)
        return true
    end
    
    # Check if orders are stale (older than configured timeout)
    order_timeout = get(s.config, :mm_order_timeout, Minute(10))
    
    for order in existing_orders
        if ats - order.timestamp > order_timeout
            return true
        end
    end
    
    # Check if market conditions have changed significantly
    # This would involve comparing current conditions to when orders were placed
    # For now, refresh every 5 minutes as a simple heuristic
    last_refresh = get(s.config, :last_mm_refresh, Dict{AssetInstance, DateTime}())
    refresh_interval = get(s.config, :mm_refresh_interval, Minute(5))
    
    if haskey(last_refresh, ai)
        return ats - last_refresh[ai] > refresh_interval
    else
        return true
    end
end

"""
    cancel_market_making_orders(s::SC, ai::AssetInstance, orders)

Cancel existing market making orders.
"""
function cancel_market_making_orders(s::SC, ai::AssetInstance, orders)
    try
        for order in orders
            @info "Cancelling market making order" ai=ai order_id=order.order_id
            # This would integrate with Planar's order cancellation system
            # For now, just log the cancellation
        end
        
        # Update last refresh time
        if !haskey(s.config, :last_mm_refresh)
            s.config[:last_mm_refresh] = Dict{AssetInstance, DateTime}()
        end
        s.config[:last_mm_refresh][ai] = now()
        
    catch e
        @error "Error cancelling market making orders" ai=ai error=e
    end
end

"""
    track_market_making_order(s::SC, ai::AssetInstance, order_result)

Track a successfully placed market making order.
"""
function track_market_making_order(s::SC, ai::AssetInstance, order_result)
    try
        # Initialize tracking structures if needed
        if !haskey(s.config, :active_mm_orders)
            s.config[:active_mm_orders] = Dict{AssetInstance, Vector{Any}}()
        end
        
        if !haskey(s.config[:active_mm_orders], ai)
            s.config[:active_mm_orders][ai] = []
        end
        
        # Add order to active tracking
        push!(s.config[:active_mm_orders][ai], order_result)
        
        # Keep only recent orders (last 100 per asset)
        if length(s.config[:active_mm_orders][ai]) > 100
            deleteat!(s.config[:active_mm_orders][ai], 1:10)
        end
        
    catch e
        @error "Error tracking market making order" ai=ai order_result=order_result error=e
    end
end

"""
    is_market_open(s::SC, ai::AssetInstance, ts::DateTime)

Check if the market is open for trading.
"""
function is_market_open(s::SC, ai::AssetInstance, ts::DateTime)
    # For crypto markets, assume always open
    # In practice, this would check exchange-specific trading hours
    return true
end

# Import helper functions from other modules
using ..RiskManagement: get_max_position_size, get_min_position_size
using ..OrderManagement: get_tick_size, get_lot_size, get_min_quantity, generate_order_id
using ..PositionManagement: cash, haspositions, position
using ..MathUtils: normalize_price, normalize_quantity