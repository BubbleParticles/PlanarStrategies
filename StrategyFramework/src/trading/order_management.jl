# Order management system for StrategyFramework
# Handles comprehensive order execution, type selection, and leverage adjustment

using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Statistics
using Planar

"""
    trade!(s::SC, ii::InstrumentInstance, ats::DateTime, ts::DateTime; 
           pos::PositionSide, side::PositionSide, amount::Float64, kwargs...)

Execute trade with comprehensive order handling, error management, and leverage adjustment.
This is the main entry point for all trading operations in the framework.

# Arguments
- `s::SC`: Strategy instance
- `ii::InstrumentInstance`: Instrument instance to trade
- `ats::DateTime`: Analysis timestamp
- `ts::DateTime`: Current timestamp
- `pos::PositionSide`: Target position side
- `side::PositionSide`: Order side (Long/Short)
- `amount::Float64`: Trade amount in base currency
- `kwargs...`: Additional order parameters

# Returns
- Bool: true if trade was successfully placed, false otherwise
"""
function trade!(s::SC, ii::InstrumentInstance, ats::DateTime, ts::DateTime; 
                pos::PositionSide, side::PositionSide, amount::Float64, kwargs...)
    try
        @debug "Initiating trade" ii=ii pos=pos side=side amount=amount
        
        # Validate trade parameters
        if !validate_trade_parameters(s, ii, pos, side, amount)
            @warn "Trade validation failed" ii=ii pos=pos side=side amount=amount
            return false
        end
        
        # Check trade cooldown
        if !check_trade_cooldown(s, ii, ts)
            @debug "Trade blocked by cooldown" ii=ii
            return false
        end
        
        # Calculate final trade amount with adjustments
        final_amount = calculate_final_trade_amount(s, ii, ats, side, amount)
        
        if final_amount <= 0
            @debug "Final trade amount is zero or negative" ii=ii original_amount=amount final_amount=final_amount
            return false
        end
        
        # Select optimal order type
        order_type = select_order_type(s, ii, side, final_amount, kwargs)
        
        # Calculate order price
        order_price = calculate_order_price(s, ii, side, order_type)
        
        # Apply leverage adjustments
        leverage_info = calculate_leverage_adjustment(s, ii, side, final_amount)
        
        # Normalize order parameters
        normalized_amount = normalize_order_amount(s, ii, final_amount)
        normalized_price = normalize_order_price(s, ii, order_price)
        
        # Create order parameters
        order_params = create_order_parameters(s, ii, side, normalized_amount, normalized_price, 
                                             order_type, leverage_info, kwargs)
        
        # Execute the order
        order_result = execute_order(s, ii, order_params)
        
        if order_result.success
            # Update tracking and state
            update_trade_tracking(s, ii, ts, order_result)
            @info "Trade executed successfully" ii=ii order_id=order_result.order_id amount=normalized_amount price=normalized_price
            return true
        else
            # Handle order failure
            handle_order_failure(s, ii, order_params, order_result.error)
            return false
        end
        
    catch e
        @error "Error in trade execution" ii=ii pos=pos side=side amount=amount error=e
        return false
    end
end

"""
    validate_trade_parameters(s::SC, ii::InstrumentInstance, pos::PositionSide, side::PositionSide, amount::Float64)

Validate trade parameters before execution.
"""
function validate_trade_parameters(s::SC, ii::InstrumentInstance, pos::PositionSide, side::PositionSide, amount::Float64)
    try
        # Check amount is positive
        if amount <= 0
            @warn "Invalid trade amount" ii=ii amount=amount
            return false
        end
        
        # Check minimum trade amount
        min_amount = get_min_position_size(s, ii)
        if amount < min_amount
            @debug "Trade amount below minimum" ii=ii amount=amount min_amount=min_amount
            return false
        end
        
        # Check maximum position limits
        current_position_value = 0.0
        if haspositions(s, ii)
            current_position = position(s, ii)
            current_price = last(s.universe[ii].close)
            current_position_value = abs(current_position * current_price)
        end
        
        max_position = get_max_position_size(s, ii)
        if side isa Long && current_position_value + amount > max_position
            @warn "Trade would exceed maximum position size" ii=ii current=current_position_value amount=amount max=max_position
            return false
        end
        
        # Check available cash for increasing positions
        if is_increasing_position(s, ii, side)
            available_cash = cash(s, ii)
            reserve_amount = manage_cash_reserves(s)
            usable_cash = available_cash - reserve_amount
            
            if amount > usable_cash
                @warn "Insufficient cash for trade" ii=ii amount=amount available=usable_cash
                return false
            end
        end
        
        # Check market hours and trading status
        if !is_market_open(s, ii, now())
            @debug "Market is closed" ii=ii
            return false
        end
        
        return true
        
    catch e
        @error "Error validating trade parameters" ii=ii error=e
        return false
    end
end

"""
    check_trade_cooldown(s::SC, ii::InstrumentInstance, ts::DateTime)

Check if sufficient time has passed since last trade.
"""
function check_trade_cooldown(s::SC, ii::InstrumentInstance, ts::DateTime)
    try
        cooldown_period = get(s.config, :trade_cooldown, Minute(1))
        
        if !haskey(s.config, :last_trade_time)
            s.config[:last_trade_time] = Dict{InstrumentInstance, DateTime}()
        end
        
        last_trade_times = s.config[:last_trade_time]
        
        if haskey(last_trade_times, ii)
            time_since_last = ts - last_trade_times[ii]
            if time_since_last < cooldown_period
                @debug "Trade cooldown active" ii=ii time_remaining=(cooldown_period - time_since_last)
                return false
            end
        end
        
        return true
        
    catch e
        @error "Error checking trade cooldown" ii=ii error=e
        return false
    end
end

"""
    calculate_final_trade_amount(s::SC, ii::InstrumentInstance, ats::DateTime, side::PositionSide, amount::Float64)

Calculate final trade amount with all adjustments applied.
"""
function calculate_final_trade_amount(s::SC, ii::InstrumentInstance, ats::DateTime, side::PositionSide, amount::Float64)
    try
        # Start with base amount
        final_amount = amount
        
        # Apply position adjustment multipliers
        adjustment_multiplier = calculate_position_adjustment(s, ii, ats)
        final_amount *= adjustment_multiplier
        
        # Apply risk-based adjustments
        risk_multiplier = calculate_risk_multiplier(s, ii, ats)
        final_amount *= risk_multiplier
        
        # Apply drawdown adjustments
        drawdown_multiplier = calculate_drawdown_multiplier(s)
        final_amount *= drawdown_multiplier
        
        # Apply volatility-based adjustments
        volatility_multiplier = calculate_volatility_adjustment(s, ii)
        final_amount *= volatility_multiplier
        
        # Ensure final amount is within bounds
        min_amount = get_min_position_size(s, ii)
        max_amount = get_max_single_trade_amount(s, ii)
        
        final_amount = clamp(final_amount, min_amount, max_amount)
        
        @debug "Trade amount calculation" ii=ii original=amount final=final_amount adjustment=adjustment_multiplier risk=risk_multiplier drawdown=drawdown_multiplier volatility=volatility_multiplier
        
        return final_amount
        
    catch e
        @error "Error calculating final trade amount" ii=ii amount=amount error=e
        return 0.0
    end
end

"""
    select_order_type(s::SC, ii::InstrumentInstance, side::PositionSide, amount::Float64, kwargs)

Select optimal order type based on market conditions and strategy configuration.
"""
function select_order_type(s::SC, ii::InstrumentInstance, side::PositionSide, amount::Float64, kwargs)
    try
        # Check if order type is explicitly specified
        if haskey(kwargs, :ordertype)
            return kwargs[:ordertype]
        end
        
        # Get default order type from configuration
        default_type = get(s.config, :ordertype, :gtc)
        
        # Check market conditions for order type optimization
        market_conditions = analyze_market_conditions(s, ii)
        
        # Select order type based on conditions
        if market_conditions.volatility > 0.05  # High volatility
            if market_conditions.spread_pct > 0.002  # Wide spread
                return :market  # Use market orders in volatile, wide-spread conditions
            else
                return :ioc  # Use IOC in volatile, tight-spread conditions
            end
        elseif market_conditions.volume_ratio < 0.5  # Low volume
            return :gtc  # Use GTC in low volume conditions
        else
            return default_type
        end
        
    catch e
        @error "Error selecting order type" ii=ii error=e
        return :gtc  # Safe fallback
    end
end

"""
    calculate_order_price(s::SC, ii::InstrumentInstance, side::PositionSide, order_type::Symbol)

Calculate optimal order price based on order type and market conditions.
"""
function calculate_order_price(s::SC, ii::InstrumentInstance, side::PositionSide, order_type::Symbol)
    try
        current_price = last(s.universe[ii].close)
        
        if order_type == :market
            return current_price  # Market orders use current price
        end
        
        # Get bid-ask spread information
        spread_info = get_spread_info(s, ii)
        
        # Calculate price adjustment based on order type and side
        if order_type == :gtc
            # GTC orders: use slightly favorable pricing for better fill probability
            adjustment_pct = get(s.config, :gtc_price_adjustment, 0.001)  # 0.1% default
            
            if side isa Long
                # Buy orders: bid slightly higher
                return current_price * (1.0 + adjustment_pct)
            else
                # Sell orders: offer slightly lower
                return current_price * (1.0 - adjustment_pct)
            end
            
        elseif order_type == :ioc
            # IOC orders: use tighter pricing for immediate execution
            adjustment_pct = get(s.config, :ioc_price_adjustment, 0.0005)  # 0.05% default
            
            if side isa Long
                return current_price * (1.0 + adjustment_pct)
            else
                return current_price * (1.0 - adjustment_pct)
            end
            
        else
            # Other order types: use current price
            return current_price
        end
        
    catch e
        @error "Error calculating order price" ii=ii side=side order_type=order_type error=e
        return last(s.universe[ii].close)  # Fallback to current price
    end
end

"""
    calculate_leverage_adjustment(s::SC, ii::InstrumentInstance, side::PositionSide, amount::Float64)

Calculate leverage adjustments for new and existing positions.
"""
function calculate_leverage_adjustment(s::SC, ii::InstrumentInstance, side::PositionSide, amount::Float64)
    try
        # Get current leverage settings
        default_leverage = get(s.config, :def_lev, 1.0)
        max_leverage = get(s.config, :max_leverage, 5.0)
        
        # Check if position exists
        has_existing_position = haspositions(s, ii)
        current_position = has_existing_position ? position(s, ii) : 0.0
        
        # Calculate position direction
        is_same_direction = if has_existing_position
            (current_position > 0 && side isa Long) || (current_position < 0 && side isa Short)
        else
            true  # New position
        end
        
        # Adjust leverage based on market conditions
        market_conditions = analyze_market_conditions(s, ii)
        volatility_adjustment = calculate_volatility_leverage_adjustment(market_conditions.volatility)
        
        # Calculate risk-adjusted leverage
        risk_adjustment = calculate_risk_leverage_adjustment(s, ii)
        
        # Combine adjustments
        adjusted_leverage = default_leverage * volatility_adjustment * risk_adjustment
        adjusted_leverage = clamp(adjusted_leverage, 1.0, max_leverage)
        
        # Calculate margin requirements
        current_price = last(s.universe[ii].close)
        position_value = amount
        required_margin = position_value / adjusted_leverage
        
        return (
            leverage = adjusted_leverage,
            required_margin = required_margin,
            is_increasing = is_same_direction,
            volatility_adj = volatility_adjustment,
            risk_adj = risk_adjustment
        )
        
    catch e
        @error "Error calculating leverage adjustment" ii=ii side=side amount=amount error=e
        return (
            leverage = 1.0,
            required_margin = amount,
            is_increasing = true,
            volatility_adj = 1.0,
            risk_adj = 1.0
        )
    end
end

"""
    normalize_order_amount(s::SC, ii::InstrumentInstance, amount::Float64)

Normalize order amount to exchange requirements.
"""
function normalize_order_amount(s::SC, ii::InstrumentInstance, amount::Float64)
    try
        current_price = last(s.universe[ii].close)
        quantity = amount / current_price
        
        # Get exchange parameters
        lot_size = get_lot_size(s, ii)
        min_quantity = get_min_quantity(s, ii)
        
        # Normalize to lot size
        normalized_quantity = round(quantity / lot_size) * lot_size
        
        # Ensure minimum quantity
        if normalized_quantity > 0 && normalized_quantity < min_quantity
            normalized_quantity = min_quantity
        end
        
        # Convert back to amount
        return normalized_quantity * current_price
        
    catch e
        @error "Error normalizing order amount" ii=ii amount=amount error=e
        return 0.0
    end
end

"""
    normalize_order_price(s::SC, ii::InstrumentInstance, price::Float64)

Normalize order price to exchange tick size requirements.
"""
function normalize_order_price(s::SC, ii::InstrumentInstance, price::Float64)
    try
        tick_size = get_tick_size(s, ii)
        return round(price / tick_size) * tick_size
    catch e
        @error "Error normalizing order price" ii=ii price=price error=e
        return price
    end
end

"""
    create_order_parameters(s::SC, ii::InstrumentInstance, side::PositionSide, amount::Float64, 
                           price::Float64, order_type::Symbol, leverage_info, kwargs)

Create comprehensive order parameters for execution.
"""
function create_order_parameters(s::SC, ii::InstrumentInstance, side::PositionSide, amount::Float64, 
                                price::Float64, order_type::Symbol, leverage_info, kwargs)
    try
        # Base order parameters
        params = Dict{Symbol, Any}(
            :asset => ii,
            :side => side,
            :amount => amount,
            :price => price,
            :type => order_type,
            :leverage => leverage_info.leverage,
            :timestamp => now()
        )
        
        # Add order-type specific parameters
        if order_type == :gtc
            params[:time_in_force] = "GTC"
            params[:timeout] = get(s.config, :order_timeout, Minute(2))
        elseif order_type == :ioc
            params[:time_in_force] = "IOC"
        elseif order_type == :market
            params[:time_in_force] = "IOC"
            params[:price] = nothing  # Market orders don't need price
        end
        
        # Add leverage-specific parameters
        if leverage_info.leverage > 1.0
            params[:margin_mode] = get(s.config, :margin_mode, "isolated")
            params[:required_margin] = leverage_info.required_margin
        end
        
        # Add strategy-specific parameters
        params[:strategy_id] = get(s.config, :strategy_id, "StrategyFramework")
        params[:is_make] = get(s.config, :ismake, true)
        
        # Merge additional kwargs
        for (key, value) in kwargs
            if key ∉ [:asset, :side, :amount, :price, :type]  # Don't override core parameters
                params[key] = value
            end
        end
        
        return params
        
    catch e
        @error "Error creating order parameters" ii=ii side=side amount=amount error=e
        return Dict{Symbol, Any}()
    end
end

"""
    execute_order(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any})

Execute order with proper error handling and result tracking.
"""
function execute_order(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any})
    try
        # Generate unique order ID
        order_id = generate_order_id()
        order_params[:order_id] = order_id
        
        @info "Executing order" ii=ii order_id=order_id type=order_params[:type] amount=order_params[:amount] price=order_params[:price]
        
        # In a real implementation, this would call Planar's order execution system
        # For now, we'll simulate the order execution
        
        # Simulate order validation
        if !validate_order_params(order_params)
            return (success = false, order_id = order_id, error = "Invalid order parameters")
        end
        
        # Simulate exchange communication
        # In practice, this would be something like:
        # result = place_order_on_exchange(s, order_params)
        
        # For simulation, assume success with some probability based on order type
        success_probability = if order_params[:type] == :market
            0.95  # Market orders have high success rate
        elseif order_params[:type] == :ioc
            0.85  # IOC orders have good success rate
        else
            0.90  # GTC orders have good success rate
        end
        
        # Simulate execution
        if rand() < success_probability
            # Successful execution
            execution_price = order_params[:price]
            if order_params[:type] == :market
                # Market orders may have slippage
                slippage = (rand() - 0.5) * 0.002  # ±0.1% slippage
                execution_price = last(s.universe[ii].close) * (1.0 + slippage)
            end
            
            return (
                success = true,
                order_id = order_id,
                execution_price = execution_price,
                executed_amount = order_params[:amount],
                timestamp = now(),
                error = nothing
            )
        else
            # Failed execution
            error_messages = [
                "Insufficient margin",
                "Order rejected by exchange",
                "Market closed",
                "Price out of range",
                "Network timeout"
            ]
            error = rand(error_messages)
            
            return (
                success = false,
                order_id = order_id,
                error = error,
                timestamp = now()
            )
        end
        
    catch e
        @error "Error executing order" ii=ii order_params=order_params error=e
        return (
            success = false,
            order_id = get(order_params, :order_id, "unknown"),
            error = string(e),
            timestamp = now()
        )
    end
end

"""
    update_trade_tracking(s::SC, ii::InstrumentInstance, ts::DateTime, order_result)

Update trade tracking and strategy state after successful order execution.
"""
function update_trade_tracking(s::SC, ii::InstrumentInstance, ts::DateTime, order_result)
    try
        # Update last trade time
        if !haskey(s.config, :last_trade_time)
            s.config[:last_trade_time] = Dict{InstrumentInstance, DateTime}()
        end
        s.config[:last_trade_time][ii] = ts
        
        # Update trade count
        s.config[:total_trades] = get(s.config, :total_trades, 0) + 1
        
        # Update trade history
        if !haskey(s.config, :trade_history)
            s.config[:trade_history] = Dict{InstrumentInstance, Vector{NamedTuple}}()
        end
        
        if !haskey(s.config[:trade_history], ii)
            s.config[:trade_history][ii] = NamedTuple[]
        end
        
        trade_record = (
            timestamp = ts,
            order_id = order_result.order_id,
            execution_price = order_result.execution_price,
            executed_amount = order_result.executed_amount,
            success = order_result.success
        )
        
        push!(s.config[:trade_history][ii], trade_record)
        
        # Keep only recent trade history (last 1000 trades per asset)
        if length(s.config[:trade_history][ii]) > 1000
            deleteat!(s.config[:trade_history][ii], 1:100)
        end
        
        @debug "Trade tracking updated" ii=ii order_id=order_result.order_id total_trades=s.config[:total_trades]
        
    catch e
        @error "Error updating trade tracking" ii=ii order_result=order_result error=e
    end
end

# Helper functions

"""
    is_increasing_position(s::SC, ii::InstrumentInstance, side::PositionSide)

Check if the trade would increase the current position size.
"""
function is_increasing_position(s::SC, ii::InstrumentInstance, side::PositionSide)
    if !haspositions(s, ii)
        return true  # New position is always increasing
    end
    
    current_position = position(s, ii)
    return (current_position > 0 && side isa Long) || (current_position < 0 && side isa Short)
end


"""
    analyze_market_conditions(s::SC, ii::InstrumentInstance)

Analyze current market conditions for order optimization.
"""
function analyze_market_conditions(s::SC, ii::InstrumentInstance)
    try
        ohlcv = s.universe[ii]
        if length(ohlcv.close) < 20
            return (volatility = 0.02, spread_pct = 0.001, volume_ratio = 1.0)
        end
        
        # Calculate volatility
        recent_closes = ohlcv.close[max(1, end-19):end]
        returns = diff(log.(recent_closes))
        volatility = std(returns)
        
        # Calculate spread (simplified)
        current_price = last(ohlcv.close)
        spread_pct = 0.001  # Default 0.1% spread
        
        # Calculate volume ratio
        recent_volumes = ohlcv.volume[max(1, end-19):end]
        avg_recent_volume = mean(recent_volumes)
        avg_historical_volume = mean(ohlcv.volume[max(1, end-99):max(1, end-20)])
        volume_ratio = avg_historical_volume > 0 ? avg_recent_volume / avg_historical_volume : 1.0
        
        return (
            volatility = volatility,
            spread_pct = spread_pct,
            volume_ratio = volume_ratio
        )
        
    catch e
        @error "Error analyzing market conditions" ii=ii error=e
        return (volatility = 0.02, spread_pct = 0.001, volume_ratio = 1.0)
    end
end

"""
    calculate_volatility_adjustment(s::SC, ii::InstrumentInstance)

Calculate position size adjustment based on current volatility.
"""
function calculate_volatility_adjustment(s::SC, ii::InstrumentInstance)
    try
        market_conditions = analyze_market_conditions(s, ii)
        volatility = market_conditions.volatility
        
        # Reduce position size in high volatility
        if volatility < 0.01  # Low volatility
            return 1.2
        elseif volatility < 0.03  # Medium volatility
            return 1.0
        elseif volatility < 0.05  # High volatility
            return 0.8
        else  # Very high volatility
            return 0.6
        end
        
    catch e
        @error "Error calculating volatility adjustment" ii=ii error=e
        return 1.0
    end
end

"""
    get_max_single_trade_amount(s::SC, ii::InstrumentInstance)

Get maximum amount for a single trade.
"""
function get_max_single_trade_amount(s::SC, ii::InstrumentInstance)
    available_cash = cash(s, ii)
    max_pct = get(s.config, :max_single_trade_pct, 0.1)  # 10% of available cash
    return available_cash * max_pct
end

"""
    get_spread_info(s::SC, ii::InstrumentInstance)

Get bid-ask spread information for an asset.
"""
function get_spread_info(s::SC, ii::InstrumentInstance)
    # Simplified spread calculation
    # In practice, this would get real bid-ask data
    current_price = last(s.universe[ii].close)
    spread_pct = 0.001  # 0.1% default spread
    
    return (
        bid = current_price * (1.0 - spread_pct / 2),
        ask = current_price * (1.0 + spread_pct / 2),
        spread = current_price * spread_pct,
        spread_pct = spread_pct
    )
end

"""
    calculate_volatility_leverage_adjustment(volatility::Float64)

Adjust leverage based on market volatility.
"""
function calculate_volatility_leverage_adjustment(volatility::Float64)
    if volatility < 0.01
        return 1.0  # Normal leverage in low volatility
    elseif volatility < 0.03
        return 0.9  # Slightly reduce leverage
    elseif volatility < 0.05
        return 0.7  # Significantly reduce leverage
    else
        return 0.5  # Minimal leverage in high volatility
    end
end

"""
    calculate_risk_leverage_adjustment(s::SC, ii::InstrumentInstance)

Adjust leverage based on current risk exposure.
"""
function calculate_risk_leverage_adjustment(s::SC, ii::InstrumentInstance)
    try
        # Calculate current portfolio risk
        total_exposure = 0.0
        available_cash = cash(s, ii)
        
        for (asset, _) in s.universe
            if haspositions(s, asset)
                pos_value = abs(position(s, asset) * last(s.universe[asset].close))
                total_exposure += pos_value
            end
        end
        
        if available_cash <= 0
            return 0.5  # Conservative if no cash
        end
        
        risk_ratio = total_exposure / (total_exposure + available_cash)
        
        # Reduce leverage as risk increases
        if risk_ratio < 0.3
            return 1.0
        elseif risk_ratio < 0.5
            return 0.8
        elseif risk_ratio < 0.7
            return 0.6
        else
            return 0.4
        end
        
    catch e
        @error "Error calculating risk leverage adjustment" ii=ii error=e
        return 0.7  # Conservative fallback
    end
end

"""
    validate_order_params(order_params::Dict{Symbol, Any})

Validate order parameters before execution.
"""
function validate_order_params(order_params::Dict{Symbol, Any})
    try
        # Check required parameters
        required_params = [:asset, :side, :amount, :type]
        for param in required_params
            if !haskey(order_params, param)
                @error "Missing required order parameter" param=param
                return false
            end
        end
        
        # Validate amount
        if order_params[:amount] <= 0
            @error "Invalid order amount" amount=order_params[:amount]
            return false
        end
        
        # Validate price for limit orders
        if order_params[:type] != :market && haskey(order_params, :price)
            if order_params[:price] <= 0
                @error "Invalid order price" price=order_params[:price]
                return false
            end
        end
        
        return true
        
    catch e
        @error "Error validating order parameters" error=e
        return false
    end
end
# Order Error Handling and Validation Functions

"""
    handle_order_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle order errors with fallback mechanisms and recovery strategies.
Implements comprehensive error handling for different types of order failures.

# Arguments
- `s::SC`: Strategy instance
- `ii::InstrumentInstance`: Instrument instance
- `order_params::Dict{Symbol, Any}`: Original order parameters
- `error::String`: Error message from failed order

# Returns
- Bool: true if error was handled successfully (possibly with fallback), false otherwise
"""
function handle_order_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @warn "Handling order error" ii=ii order_id=get(order_params, :order_id, "unknown") error=error
        
        # Categorize error type
        error_category = categorize_order_error(error)
        
        # Update error tracking
        update_error_tracking(s, ii, error_category, error)
        
        # Handle based on error category
        success = if error_category == :insufficient_margin
            handle_margin_error(s, ii, order_params, error)
        elseif error_category == :price_out_of_range
            handle_price_error(s, ii, order_params, error)
        elseif error_category == :market_closed
            handle_market_closed_error(s, ii, order_params, error)
        elseif error_category == :network_timeout
            handle_network_error(s, ii, order_params, error)
        elseif error_category == :order_rejected
            handle_rejection_error(s, ii, order_params, error)
        elseif error_category == :insufficient_balance
            handle_balance_error(s, ii, order_params, error)
        elseif error_category == :position_limit
            handle_position_limit_error(s, ii, order_params, error)
        elseif error_category == :invalid_parameters
            handle_parameter_error(s, ii, order_params, error)
        else
            handle_unknown_error(s, ii, order_params, error)
        end
        
        if success
            @info "Order error handled successfully" ii=ii error_category=error_category
        else
            @error "Failed to handle order error" ii=ii error_category=error_category
            
            # Send notification for unhandled errors
            send_error_notification(s, ii, error, order_params)
        end
        
        return success
        
    catch e
        @error "Error in order error handling" ii=ii error=e original_error=error
        return false
    end
end

"""
    categorize_order_error(error::String)

Categorize order error based on error message content.
"""
function categorize_order_error(error::String)
    error_lower = lowercase(error)
    
    if contains(error_lower, "margin") || contains(error_lower, "leverage")
        return :insufficient_margin
    elseif contains(error_lower, "price") || contains(error_lower, "range") || contains(error_lower, "limit")
        return :price_out_of_range
    elseif contains(error_lower, "market") && contains(error_lower, "closed")
        return :market_closed
    elseif contains(error_lower, "timeout") || contains(error_lower, "network") || contains(error_lower, "connection")
        return :network_timeout
    elseif contains(error_lower, "rejected") || contains(error_lower, "denied")
        return :order_rejected
    elseif contains(error_lower, "balance") || contains(error_lower, "insufficient")
        return :insufficient_balance
    elseif contains(error_lower, "position") && contains(error_lower, "limit")
        return :position_limit
    elseif contains(error_lower, "parameter") || contains(error_lower, "invalid")
        return :invalid_parameters
    else
        return :unknown
    end
end

"""
    handle_margin_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle insufficient margin errors by reducing leverage or position size.
"""
function handle_margin_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Handling margin error with leverage reduction" ii=ii
        
        # Reduce leverage and try again
        current_leverage = get(order_params, :leverage, 1.0)
        new_leverage = max(1.0, current_leverage * 0.7)  # Reduce by 30%
        
        # Adjust order amount based on new leverage
        original_amount = order_params[:amount]
        new_amount = original_amount * (new_leverage / current_leverage)
        
        # Create fallback order with reduced leverage
        fallback_params = copy(order_params)
        fallback_params[:leverage] = new_leverage
        fallback_params[:amount] = new_amount
        fallback_params[:fallback_reason] = "margin_error_recovery"
        
        @info "Retrying order with reduced leverage" ii=ii original_leverage=current_leverage new_leverage=new_leverage
        
        # Execute fallback order
        result = execute_order(s, ii, fallback_params)
        
        if result.success
            @info "Margin error resolved with leverage reduction" ii=ii order_id=result.order_id
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            @warn "Fallback order also failed" ii=ii error=result.error
            return false
        end
        
    catch e
        @error "Error handling margin error" ii=ii error=e
        return false
    end
end

"""
    handle_price_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle price out of range errors by adjusting price or switching to market order.
"""
function handle_price_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Handling price error with market order fallback" ii=ii
        
        # Switch to market order for immediate execution
        fallback_params = copy(order_params)
        fallback_params[:type] = :market
        fallback_params[:price] = nothing  # Market orders don't need price
        fallback_params[:fallback_reason] = "price_error_recovery"
        
        @info "Switching to market order" ii=ii original_type=order_params[:type]
        
        # Execute market order
        result = execute_order(s, ii, fallback_params)
        
        if result.success
            @info "Price error resolved with market order" ii=ii order_id=result.order_id
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            @warn "Market order fallback also failed" ii=ii error=result.error
            return false
        end
        
    catch e
        @error "Error handling price error" ii=ii error=e
        return false
    end
end

"""
    handle_market_closed_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle market closed errors by scheduling order for later execution.
"""
function handle_market_closed_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Market closed, scheduling order for later" ii=ii
        
        # Add to pending orders queue
        if !haskey(s.config, :pending_orders)
            s.config[:pending_orders] = Dict{InstrumentInstance, Vector{Dict{Symbol, Any}}}()
        end
        
        if !haskey(s.config[:pending_orders], ii)
            s.config[:pending_orders][ii] = Dict{Symbol, Any}[]
        end
        
        # Add timestamp and retry info
        pending_order = copy(order_params)
        pending_order[:scheduled_time] = now()
        pending_order[:retry_reason] = "market_closed"
        pending_order[:max_retries] = 5
        pending_order[:retry_count] = 0
        
        push!(s.config[:pending_orders][ii], pending_order)
        
        @info "Order scheduled for retry when market opens" ii=ii order_id=get(order_params, :order_id, "unknown")
        
        return true  # Successfully scheduled
        
    catch e
        @error "Error handling market closed error" ii=ii error=e
        return false
    end
end

"""
    handle_network_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle network timeout errors with exponential backoff retry.
"""
function handle_network_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        retry_count = get(order_params, :retry_count, 0)
        max_retries = get(s.config, :max_network_retries, 3)
        
        if retry_count >= max_retries
            @error "Maximum network retries exceeded" ii=ii retry_count=retry_count
            return false
        end
        
        # Calculate exponential backoff delay
        base_delay = get(s.config, :network_retry_delay, 2.0)  # 2 seconds base
        delay = base_delay * (2 ^ retry_count)  # Exponential backoff
        
        @info "Network error, retrying with backoff" ii=ii retry_count=retry_count delay=delay
        
        # Sleep for backoff period
        sleep(delay)
        
        # Retry order with updated retry count
        retry_params = copy(order_params)
        retry_params[:retry_count] = retry_count + 1
        retry_params[:retry_reason] = "network_error"
        
        result = execute_order(s, ii, retry_params)
        
        if result.success
            @info "Network error resolved on retry" ii=ii order_id=result.order_id retry_count=retry_count + 1
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            # Recursive retry if still failing
            return handle_network_error(s, ii, retry_params, result.error)
        end
        
    catch e
        @error "Error handling network error" ii=ii error=e
        return false
    end
end

"""
    handle_rejection_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle order rejection errors by analyzing and adjusting parameters.
"""
function handle_rejection_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Handling order rejection" ii=ii error=error
        
        # Analyze rejection reason and adjust accordingly
        if contains(lowercase(error), "size") || contains(lowercase(error), "amount")
            # Adjust order size
            new_amount = order_params[:amount] * 0.8  # Reduce by 20%
            min_amount = get_min_position_size(s, ii)
            
            if new_amount < min_amount
                @warn "Adjusted amount below minimum, canceling order" ii=ii new_amount=new_amount min_amount=min_amount
                return false
            end
            
            fallback_params = copy(order_params)
            fallback_params[:amount] = new_amount
            fallback_params[:fallback_reason] = "size_adjustment"
            
            result = execute_order(s, ii, fallback_params)
            
            if result.success
                @info "Rejection resolved with size adjustment" ii=ii order_id=result.order_id
                update_trade_tracking(s, ii, now(), result)
                return true
            end
        end
        
        # If size adjustment didn't work or wasn't applicable, try market order
        return handle_price_error(s, ii, order_params, error)
        
    catch e
        @error "Error handling rejection error" ii=ii error=e
        return false
    end
end

"""
    handle_balance_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle insufficient balance errors by adjusting order size to available funds.
"""
function handle_balance_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Handling balance error" ii=ii
        
        # Get available cash and adjust order size
        available_cash = cash(s, ii)
        reserve_amount = manage_cash_reserves(s)
        usable_cash = available_cash - reserve_amount
        
        if usable_cash <= 0
            @warn "No usable cash available" ii=ii available_cash=available_cash reserve_amount=reserve_amount
            return false
        end
        
        # Adjust order amount to available cash (with safety margin)
        safety_margin = 0.95  # Use 95% of available cash
        adjusted_amount = usable_cash * safety_margin
        
        min_amount = get_min_position_size(s, ii)
        if adjusted_amount < min_amount
            @warn "Adjusted amount below minimum after balance check" ii=ii adjusted_amount=adjusted_amount min_amount=min_amount
            return false
        end
        
        fallback_params = copy(order_params)
        fallback_params[:amount] = adjusted_amount
        fallback_params[:fallback_reason] = "balance_adjustment"
        
        @info "Retrying with adjusted amount" ii=ii original_amount=order_params[:amount] adjusted_amount=adjusted_amount
        
        result = execute_order(s, ii, fallback_params)
        
        if result.success
            @info "Balance error resolved with amount adjustment" ii=ii order_id=result.order_id
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            @warn "Adjusted order also failed" ii=ii error=result.error
            return false
        end
        
    catch e
        @error "Error handling balance error" ii=ii error=e
        return false
    end
end

"""
    handle_position_limit_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle position limit errors by closing existing positions or reducing order size.
"""
function handle_position_limit_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Handling position limit error" ii=ii
        
        # Check if we can reduce existing position to make room
        if haspositions(s, ii)
            current_position = position(s, ii)
            order_side = order_params[:side]
            
            # If trying to increase position in same direction, try to close some first
            if (current_position > 0 && order_side isa Long) || (current_position < 0 && order_side isa Short)
                @info "Attempting partial position close to make room" ii=ii current_position=current_position
                
                # Close 30% of current position
                close_amount = abs(current_position) * 0.3
                close_side = current_position > 0 ? Short() : Long()
                
                # Create close order
                close_params = Dict{Symbol, Any}(
                    :asset => ii,
                    :side => close_side,
                    :amount => close_amount * last(s.universe[ii].close),  # Convert to base currency
                    :type => :market,  # Use market order for quick execution
                    :reason => "position_limit_management"
                )
                
                close_result = execute_order(s, ii, close_params)
                
                if close_result.success
                    @info "Partial position closed, retrying original order" ii=ii
                    
                    # Wait a moment for position update
                    sleep(1.0)
                    
                    # Retry original order
                    result = execute_order(s, ii, order_params)
                    
                    if result.success
                        @info "Position limit resolved with partial close" ii=ii order_id=result.order_id
                        update_trade_tracking(s, ii, now(), result)
                        return true
                    end
                end
            end
        end
        
        # If partial close didn't work, reduce order size
        reduced_amount = order_params[:amount] * 0.5  # Reduce by 50%
        min_amount = get_min_position_size(s, ii)
        
        if reduced_amount < min_amount
            @warn "Cannot reduce order size further" ii=ii reduced_amount=reduced_amount min_amount=min_amount
            return false
        end
        
        fallback_params = copy(order_params)
        fallback_params[:amount] = reduced_amount
        fallback_params[:fallback_reason] = "position_limit_reduction"
        
        result = execute_order(s, ii, fallback_params)
        
        if result.success
            @info "Position limit resolved with size reduction" ii=ii order_id=result.order_id
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            return false
        end
        
    catch e
        @error "Error handling position limit error" ii=ii error=e
        return false
    end
end

"""
    handle_parameter_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle invalid parameter errors by correcting parameters and retrying.
"""
function handle_parameter_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @info "Handling parameter error" ii=ii error=error
        
        # Create corrected parameters
        corrected_params = copy(order_params)
        
        # Normalize all parameters
        if haskey(corrected_params, :amount)
            corrected_params[:amount] = normalize_order_amount(s, ii, corrected_params[:amount])
        end
        
        if haskey(corrected_params, :price) && corrected_params[:price] !== nothing
            corrected_params[:price] = normalize_order_price(s, ii, corrected_params[:price])
        end
        
        # Ensure leverage is within bounds
        if haskey(corrected_params, :leverage)
            max_leverage = get(s.config, :max_leverage, 5.0)
            corrected_params[:leverage] = clamp(corrected_params[:leverage], 1.0, max_leverage)
        end
        
        # Add fallback reason
        corrected_params[:fallback_reason] = "parameter_correction"
        
        @info "Retrying with corrected parameters" ii=ii
        
        result = execute_order(s, ii, corrected_params)
        
        if result.success
            @info "Parameter error resolved with corrections" ii=ii order_id=result.order_id
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            @warn "Corrected order also failed" ii=ii error=result.error
            return false
        end
        
    catch e
        @error "Error handling parameter error" ii=ii error=e
        return false
    end
end

"""
    handle_unknown_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)

Handle unknown errors with generic fallback strategies.
"""
function handle_unknown_error(s::SC, ii::InstrumentInstance, order_params::Dict{Symbol, Any}, error::String)
    try
        @warn "Handling unknown error with market order fallback" ii=ii error=error
        
        # Try market order as last resort
        fallback_params = copy(order_params)
        fallback_params[:type] = :market
        fallback_params[:price] = nothing
        fallback_params[:fallback_reason] = "unknown_error_recovery"
        
        result = execute_order(s, ii, fallback_params)
        
        if result.success
            @info "Unknown error resolved with market order" ii=ii order_id=result.order_id
            update_trade_tracking(s, ii, now(), result)
            return true
        else
            @error "All fallback strategies failed" ii=ii final_error=result.error
            return false
        end
        
    catch e
        @error "Error handling unknown error" ii=ii error=e
        return false
    end
end

"""
    update_error_tracking(s::SC, ii::InstrumentInstance, error_category::Symbol, error::String)

Update error tracking statistics for monitoring and analysis.
"""
function update_error_tracking(s::SC, ii::InstrumentInstance, error_category::Symbol, error::String)
    try
        # Initialize error tracking if not exists
        if !haskey(s.config, :error_stats)
            s.config[:error_stats] = Dict{Symbol, Int}()
        end
        
        if !haskey(s.config, :error_history)
            s.config[:error_history] = Tuple{DateTime, InstrumentInstance, Symbol, String}[]
        end
        
        # Update error count by category
        s.config[:error_stats][error_category] = get(s.config[:error_stats], error_category, 0) + 1
        
        # Add to error history
        push!(s.config[:error_history], (now(), ii, error_category, error))
        
        # Keep only recent error history (last 1000 errors)
        if length(s.config[:error_history]) > 1000
            deleteat!(s.config[:error_history], 1:100)
        end
        
        @debug "Error tracking updated" ii=ii error_category=error_category total_errors=sum(values(s.config[:error_stats]))
        
    catch e
        @error "Error updating error tracking" ii=ii error=e
    end
end

"""
    cancelorders!(s::SC, ii::InstrumentInstance; timeout::Period = Minute(2), reason::String = "timeout")

Cancel stale or unwanted orders for an asset.
Provides comprehensive order cancellation with proper error handling.

# Arguments
- `s::SC`: Strategy instance
- `ii::InstrumentInstance`: Instrument instance to cancel orders for
- `timeout::Period`: Cancel orders older than this timeout
- `reason::String`: Reason for cancellation (for logging)

# Returns
- Int: Number of orders successfully canceled
"""
function cancelorders!(s::SC, ii::InstrumentInstance; timeout::Period = Minute(2), reason::String = "timeout")
    try
        @info "Canceling orders" ii=ii timeout=timeout reason=reason
        
        # Get list of open orders (in practice, this would query the exchange)
        open_orders = get_open_orders(s, ii)
        
        if isempty(open_orders)
            @debug "No open orders to cancel" ii=ii
            return 0
        end
        
        canceled_count = 0
        current_time = now()
        
        for order in open_orders
            try
                # Check if order should be canceled
                should_cancel = false
                cancel_reason = reason
                
                # Check timeout
                if haskey(order, :timestamp)
                    order_age = current_time - order[:timestamp]
                    if order_age > timeout
                        should_cancel = true
                        cancel_reason = "timeout_exceeded"
                    end
                end
                
                # Check for specific cancellation conditions
                if reason == "risk_management"
                    should_cancel = true
                    cancel_reason = "risk_management"
                elseif reason == "strategy_reset"
                    should_cancel = true
                    cancel_reason = "strategy_reset"
                elseif reason == "emergency"
                    should_cancel = true
                    cancel_reason = "emergency_stop"
                end
                
                if should_cancel
                    success = cancel_single_order(s, ii, order, cancel_reason)
                    if success
                        canceled_count += 1
                        @info "Order canceled" ii=ii order_id=order[:order_id] reason=cancel_reason
                    else
                        @warn "Failed to cancel order" ii=ii order_id=order[:order_id]
                    end
                end
                
            catch e
                @error "Error processing order for cancellation" ii=ii order=order error=e
            end
        end
        
        # Update cancellation tracking
        update_cancellation_tracking(s, ii, canceled_count, reason)
        
        @info "Order cancellation completed" ii=ii canceled_count=canceled_count total_orders=length(open_orders)
        
        return canceled_count
        
    catch e
        @error "Error in order cancellation" ii=ii error=e
        return 0
    end
end

"""
    get_open_orders(s::SC, ii::InstrumentInstance)

Get list of open orders for an asset.
In practice, this would query the exchange API.
"""
function get_open_orders(s::SC, ii::InstrumentInstance)
    try
        # In a real implementation, this would query the exchange
        # For now, we'll simulate with stored pending orders
        
        pending_orders = get(s.config, :pending_orders, Dict{InstrumentInstance, Vector{Dict{Symbol, Any}}}())
        
        if haskey(pending_orders, ii)
            return pending_orders[ii]
        else
            return Dict{Symbol, Any}[]
        end
        
    catch e
        @error "Error getting open orders" ii=ii error=e
        return Dict{Symbol, Any}[]
    end
end

"""
    cancel_single_order(s::SC, ii::InstrumentInstance, order::Dict{Symbol, Any}, reason::String)

Cancel a single order with proper error handling.
"""
function cancel_single_order(s::SC, ii::InstrumentInstance, order::Dict{Symbol, Any}, reason::String)
    try
        order_id = get(order, :order_id, "unknown")
        
        @debug "Canceling single order" ii=ii order_id=order_id reason=reason
        
        # In practice, this would call the exchange API to cancel the order
        # For simulation, we'll assume success with high probability
        
        success_probability = 0.95  # 95% success rate for cancellations
        
        if rand() < success_probability
            # Remove from pending orders if it exists there
            if haskey(s.config, :pending_orders) && haskey(s.config[:pending_orders], ii)
                filter!(o -> get(o, :order_id, "") != order_id, s.config[:pending_orders][ii])
            end
            
            return true
        else
            @warn "Order cancellation failed" ii=ii order_id=order_id
            return false
        end
        
    catch e
        @error "Error canceling single order" ii=ii order=order error=e
        return false
    end
end

"""
    update_cancellation_tracking(s::SC, ii::InstrumentInstance, canceled_count::Int, reason::String)

Update cancellation tracking statistics.
"""
function update_cancellation_tracking(s::SC, ii::InstrumentInstance, canceled_count::Int, reason::String)
    try
        # Initialize tracking if not exists
        if !haskey(s.config, :cancellation_stats)
            s.config[:cancellation_stats] = Dict{String, Int}()
        end
        
        if !haskey(s.config, :total_cancellations)
            s.config[:total_cancellations] = 0
        end
        
        # Update statistics
        s.config[:cancellation_stats][reason] = get(s.config[:cancellation_stats], reason, 0) + canceled_count
        s.config[:total_cancellations] += canceled_count
        
        @debug "Cancellation tracking updated" ii=ii canceled_count=canceled_count reason=reason total=s.config[:total_cancellations]
        
    catch e
        @error "Error updating cancellation tracking" ii=ii error=e
    end
end

"""
    check_posside(s::SC, ii::InstrumentInstance, intended_side::PositionSide)

Validate position side consistency and detect potential issues.
Ensures that the intended position side is consistent with strategy logic.

# Arguments
- `s::SC`: Strategy instance
- `ii::InstrumentInstance`: Instrument instance
- `intended_side::PositionSide`: Intended position side for validation

# Returns
- NamedTuple with validation results and recommendations
"""
function check_posside(s::SC, ii::InstrumentInstance, intended_side::PositionSide)
    try
        @debug "Checking position side consistency" ii=ii intended_side=intended_side
        
        # Get current position information
        has_position = haspositions(s, ii)
        current_position = has_position ? position(s, ii) : 0.0
        current_side = if current_position > 0
            Long()
        elseif current_position < 0
            Short()
        else
            nothing
        end
        
        # Analyze position side consistency
        validation_results = analyze_position_side_consistency(s, ii, current_side, intended_side)
        
        # Check for potential issues
        issues = check_position_side_issues(s, ii, current_side, intended_side)
        
        # Generate recommendations
        recommendations = generate_position_side_recommendations(s, ii, current_side, intended_side, issues)
        
        # Determine overall validation status
        status = if isempty(issues)
            :valid
        elseif any(issue -> issue.severity == :high, issues)
            :invalid
        else
            :warning
        end
        
        result = (
            status = status,
            current_side = current_side,
            intended_side = intended_side,
            current_position = current_position,
            is_consistent = validation_results.is_consistent,
            is_reversal = validation_results.is_reversal,
            is_increase = validation_results.is_increase,
            is_decrease = validation_results.is_decrease,
            issues = issues,
            recommendations = recommendations,
            action_required = status == :invalid
        )
        
        if status == :invalid
            @warn "Position side validation failed" ii=ii result=result
        elseif status == :warning
            @info "Position side validation warnings" ii=ii issues=length(issues)
        else
            @debug "Position side validation passed" ii=ii
        end
        
        return result
        
    catch e
        @error "Error checking position side" ii=ii intended_side=intended_side error=e
        return (
            status = :error,
            current_side = nothing,
            intended_side = intended_side,
            current_position = 0.0,
            is_consistent = false,
            is_reversal = false,
            is_increase = false,
            is_decrease = false,
            issues = [(severity = :high, type = :validation_error, message = string(e))],
            recommendations = ["Review position side validation logic"],
            action_required = true
        )
    end
end

"""
    analyze_position_side_consistency(s::SC, ii::InstrumentInstance, current_side, intended_side::PositionSide)

Analyze the consistency between current and intended position sides.
"""
function analyze_position_side_consistency(s::SC, ii::InstrumentInstance, current_side, intended_side::PositionSide)
    try
        # Determine relationship between current and intended sides
        is_consistent = if current_side === nothing
            true  # No current position, any intended side is consistent
        elseif typeof(current_side) == typeof(intended_side)
            true  # Same direction
        else
            false  # Different directions
        end
        
        is_reversal = if current_side === nothing
            false  # No position to reverse
        else
            typeof(current_side) != typeof(intended_side)
        end
        
        is_increase = if current_side === nothing
            true  # New position is always an increase
        else
            typeof(current_side) == typeof(intended_side)
        end
        
        is_decrease = !is_increase && !is_reversal
        
        return (
            is_consistent = is_consistent,
            is_reversal = is_reversal,
            is_increase = is_increase,
            is_decrease = is_decrease
        )
        
    catch e
        @error "Error analyzing position side consistency" ii=ii error=e
        return (
            is_consistent = false,
            is_reversal = false,
            is_increase = false,
            is_decrease = false
        )
    end
end

"""
    check_position_side_issues(s::SC, ii::InstrumentInstance, current_side, intended_side::PositionSide)

Check for potential issues with the intended position side.
"""
function check_position_side_issues(s::SC, ii::InstrumentInstance, current_side, intended_side::PositionSide)
    issues = []
    
    try
        # Check for rapid position reversals
        if current_side !== nothing && typeof(current_side) != typeof(intended_side)
            last_reversal_time = get(s.config, :last_reversal_time, Dict{InstrumentInstance, DateTime}())
            
            if haskey(last_reversal_time, ii)
                time_since_reversal = now() - last_reversal_time[ii]
                min_reversal_interval = get(s.config, :min_reversal_interval, Minute(5))
                
                if time_since_reversal < min_reversal_interval
                    push!(issues, (
                        severity = :high,
                        type = :rapid_reversal,
                        message = "Position reversal too soon after previous reversal"
                    ))
                end
            end
        end
        
        # Check for excessive position changes
        position_changes = get(s.config, :position_changes, Dict{InstrumentInstance, Int}())
        changes_today = get(position_changes, ii, 0)
        max_changes_per_day = get(s.config, :max_position_changes_per_day, 10)
        
        if changes_today >= max_changes_per_day
            push!(issues, (
                severity = :medium,
                type = :excessive_changes,
                message = "Too many position changes today"
            ))
        end
        
        # Check for conflicting signals
        if haskey(s.config, :recent_signals)
            recent_signals = s.config[:recent_signals]
            if haskey(recent_signals, ii)
                last_signal = recent_signals[ii]
                if haskey(last_signal, :side) && typeof(last_signal[:side]) != typeof(intended_side)
                    signal_age = now() - last_signal[:timestamp]
                    if signal_age < Minute(1)  # Very recent conflicting signal
                        push!(issues, (
                            severity = :medium,
                            type = :conflicting_signal,
                            message = "Conflicting signal detected recently"
                        ))
                    end
                end
            end
        end
        
        # Check risk limits for the intended side
        if intended_side isa Long
            # Check long position limits
            total_long_exposure = calculate_total_long_exposure(s)
            max_long_exposure = get(s.config, :max_long_exposure_pct, 0.8) * sum(cash(s, ai_other) for (ai_other, _) in s.universe)
            
            if total_long_exposure > max_long_exposure
                push!(issues, (
                    severity = :high,
                    type = :exposure_limit,
                    message = "Long exposure limit would be exceeded"
                ))
            end
        else
            # Check short position limits
            total_short_exposure = calculate_total_short_exposure(s)
            max_short_exposure = get(s.config, :max_short_exposure_pct, 0.5) * sum(cash(s, ai_other) for (ai_other, _) in s.universe)
            
            if total_short_exposure > max_short_exposure
                push!(issues, (
                    severity = :high,
                    type = :exposure_limit,
                    message = "Short exposure limit would be exceeded"
                ))
            end
        end
        
        return issues
        
    catch e
        @error "Error checking position side issues" ii=ii error=e
        push!(issues, (
            severity = :high,
            type = :check_error,
            message = "Error during position side validation"
        ))
        return issues
    end
end

"""
    generate_position_side_recommendations(s::SC, ii::InstrumentInstance, current_side, intended_side::PositionSide, issues)

Generate recommendations based on position side analysis.
"""
function generate_position_side_recommendations(s::SC, ii::InstrumentInstance, current_side, intended_side::PositionSide, issues)
    recommendations = String[]
    
    try
        # Recommendations based on issues
        for issue in issues
            if issue.type == :rapid_reversal
                push!(recommendations, "Wait for minimum reversal interval before changing position direction")
            elseif issue.type == :excessive_changes
                push!(recommendations, "Reduce position change frequency or review signal generation logic")
            elseif issue.type == :conflicting_signal
                push!(recommendations, "Review signal generation for consistency")
            elseif issue.type == :exposure_limit
                push!(recommendations, "Reduce position size or close other positions to manage exposure")
            end
        end
        
        # General recommendations
        if current_side !== nothing && typeof(current_side) != typeof(intended_side)
            push!(recommendations, "Consider gradual position transition instead of immediate reversal")
        end
        
        if isempty(issues)
            push!(recommendations, "Position side validation passed - proceed with intended action")
        end
        
        return recommendations
        
    catch e
        @error "Error generating position side recommendations" ii=ii error=e
        return ["Review position side validation logic due to error"]
    end
end

# Helper functions for position side validation

"""
    calculate_total_long_exposure(s::SC)

Calculate total long exposure across all positions.
"""
function calculate_total_long_exposure(s::SC)
    try
        total_exposure = 0.0
        
        for (ii, ohlcv) in s.universe
            if haspositions(s, ii)
                pos = position(s, ii)
                if pos > 0  # Long position
                    current_price = last(ohlcv.close)
                    exposure = pos * current_price
                    total_exposure += exposure
                end
            end
        end
        
        return total_exposure
        
    catch e
        @error "Error calculating total long exposure" error=e
        return 0.0
    end
end

"""
    calculate_total_short_exposure(s::SC)

Calculate total short exposure across all positions.
"""
function calculate_total_short_exposure(s::SC)
    try
        total_exposure = 0.0
        
        for (ii, ohlcv) in s.universe
            if haspositions(s, ii)
                pos = position(s, ii)
                if pos < 0  # Short position
                    current_price = last(ohlcv.close)
                    exposure = abs(pos) * current_price
                    total_exposure += exposure
                end
            end
        end
        
        return total_exposure
        
    catch e
        @error "Error calculating total short exposure" error=e
        return 0.0
    end
end

"""
    send_error_notification(s::SC, ii::InstrumentInstance, error::String, order_params::Dict{Symbol, Any})

Send error notification through configured channels (e.g., Telegram).
"""
function send_error_notification(s::SC, ii::InstrumentInstance, error::String, order_params::Dict{Symbol, Any})
    try
        if is_telegram_available(s)
            message = """
            🚨 Order Error Alert
            
            Instrument: $(ii)
            Error: $(error)
            Order ID: $(get(order_params, :order_id, "unknown"))
            Amount: $(get(order_params, :amount, "unknown"))
            Type: $(get(order_params, :type, "unknown"))
            
            Time: $(now())
            """
            
            send_error_notification(s, message)
        end
        
    catch e
        @error "Error sending error notification" ii=ii error=e
    end
end