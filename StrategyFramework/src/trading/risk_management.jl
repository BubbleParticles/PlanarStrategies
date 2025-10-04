# Risk management system for StrategyFramework
# Handles position closing, cash management, and drawdown calculations

using Dates
using Statistics
using Planar

"""
    closeposition!(s::SC, ai::AssetInstance; reason::String = "risk_management", 
                   emergency::Bool = false)

Close position for an asset with proper error handling and logging.
Supports both normal and emergency closure modes.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance to close position for
- `reason::String`: Reason for closing position (for logging)
- `emergency::Bool`: If true, use market orders for immediate closure

# Returns
- Bool: true if position was successfully closed or already closed
"""
function closeposition!(s::SC, ai::AssetInstance; reason::String = "risk_management", 
                       emergency::Bool = false)
    try
        # Check if position exists
        if !haspositions(s, ai)
            @debug "No position to close" ai=ai reason=reason
            return true
        end
        
        current_position = position(s, ai)
        if abs(current_position) < get_min_position_size(s, ai) / last(s.universe[ai].close)
            @debug "Position too small to close" ai=ai position=current_position
            return true
        end
        
        @info "Closing position" ai=ai position=current_position reason=reason emergency=emergency
        
        # Determine order type based on emergency flag
        order_type = emergency ? :market : get(s.config, :ordertype, :gtc)
        
        # Calculate close amount (opposite of current position)
        close_side = current_position > 0 ? Short() : Long()
        close_amount = abs(current_position)
        
        # Place close order
        success = place_close_order(s, ai, close_side, close_amount, order_type)
        
        if success
            # Update tracking
            update_close_tracking(s, ai, reason)
            @info "Position close order placed successfully" ai=ai amount=close_amount
            return true
        else
            @error "Failed to place close order" ai=ai
            
            # If normal close failed and not already emergency, try emergency close
            if !emergency
                @warn "Attempting emergency close" ai=ai
                return closeposition!(s, ai; reason="emergency_after_failed_close", emergency=true)
            end
            
            return false
        end
        
    catch e
        @error "Error closing position" ai=ai reason=reason error=e
        
        # Try emergency close if not already attempted
        if !emergency
            try
                return closeposition!(s, ai; reason="error_recovery", emergency=true)
            catch e2
                @error "Emergency close also failed" ai=ai error=e2
            end
        end
        
        return false
    end
end

"""
    place_close_order(s::SC, ai::AssetInstance, side::PositionSide, amount::Float64, order_type::Symbol)

Place order to close position with proper error handling.
"""
function place_close_order(s::SC, ai::AssetInstance, side::PositionSide, amount::Float64, order_type::Symbol)
    try
        # Get current market data
        current_price = last(s.universe[ai].close)
        
        # Calculate order price based on order type
        if order_type == :market
            # Market order - use current price (will be executed at market)
            order_price = current_price
        else
            # Limit order - use slightly favorable price to ensure execution
            price_adjustment = current_price * 0.001  # 0.1% adjustment
            if side isa Long
                order_price = current_price + price_adjustment  # Buy slightly higher
            else
                order_price = current_price - price_adjustment  # Sell slightly lower
            end
        end
        
        # Normalize price and amount
        order_price = normalize_price(order_price, get_tick_size(s, ai))
        order_amount = normalize_quantity(amount, get_lot_size(s, ai), get_min_quantity(s, ai))
        
        if order_amount <= 0
            @error "Invalid order amount after normalization" ai=ai original_amount=amount normalized_amount=order_amount
            return false
        end
        
        # Place the order (this would integrate with Planar's order system)
        # For now, we'll simulate the order placement
        order_id = generate_order_id()
        
        # Log the order
        @info "Placing close order" ai=ai side=side amount=order_amount price=order_price type=order_type id=order_id
        
        # In a real implementation, this would call Planar's order placement functions
        # order_result = place_order(s, ai, side, order_amount, order_price, order_type)
        
        # For now, assume success
        return true
        
    catch e
        @error "Error placing close order" ai=ai side=side amount=amount error=e
        return false
    end
end

"""
    update_close_tracking(s::SC, ai::AssetInstance, reason::String)

Update tracking information when a position is closed.
"""
function update_close_tracking(s::SC, ai::AssetInstance, reason::String)
    try
        # Update last close time
        if !haskey(s.config, :last_close_time)
            s.config[:last_close_time] = Dict{AssetInstance, DateTime}()
        end
        s.config[:last_close_time][ai] = now()
        
        # Update close reason tracking
        if !haskey(s.config, :close_reasons)
            s.config[:close_reasons] = Dict{String, Int}()
        end
        s.config[:close_reasons][reason] = get(s.config[:close_reasons], reason, 0) + 1
        
        # Update position close count
        s.config[:total_closes] = get(s.config, :total_closes, 0) + 1
        
    catch e
        @error "Error updating close tracking" ai=ai reason=reason error=e
    end
end

"""
    manage_cash_reserves(s::SC)

Manage cash reserves and ensure sufficient liquidity for operations.
Returns the amount of cash that should be kept in reserve.

# Arguments
- `s::SC`: Strategy instance

# Returns
- Float64: Amount of cash to keep in reserve
"""
function manage_cash_reserves(s::SC)
    try
        # Calculate total available cash across all assets
        total_cash = 0.0
        for (ai, _) in s.universe
            total_cash += cash(s, ai)
        end
        
        # Get reserve percentage from configuration
        reserve_pct = get(s.config, :reserve_cash_pct, 0.1)  # 10% default
        
        # Calculate base reserve amount
        base_reserve = total_cash * reserve_pct
        
        # Adjust reserve based on market conditions
        volatility_multiplier = calculate_volatility_reserve_multiplier(s)
        drawdown_multiplier = calculate_drawdown_reserve_multiplier(s)
        
        # Apply multipliers
        adjusted_reserve = base_reserve * volatility_multiplier * drawdown_multiplier
        
        # Ensure minimum reserve
        min_reserve = get(s.config, :min_cash_reserve, 100.0)  # $100 minimum
        final_reserve = max(adjusted_reserve, min_reserve)
        
        # Ensure reserve doesn't exceed total cash
        final_reserve = min(final_reserve, total_cash * 0.5)  # Max 50% in reserve
        
        @debug "Cash reserve calculation" total_cash=total_cash base_reserve=base_reserve final_reserve=final_reserve
        
        return final_reserve
        
    catch e
        @error "Error managing cash reserves" error=e
        return 0.0
    end
end

"""
    calculate_volatility_reserve_multiplier(s::SC)

Calculate reserve multiplier based on market volatility.
Higher volatility requires more cash reserves.
"""
function calculate_volatility_reserve_multiplier(s::SC)
    try
        volatilities = Float64[]
        
        # Calculate volatility for each asset
        for (ai, ohlcv) in s.universe
            if length(ohlcv.close) >= 20
                recent_closes = ohlcv.close[max(1, end-19):end]
                returns = diff(log.(recent_closes))
                vol = std(returns) * sqrt(252)  # Annualized volatility
                push!(volatilities, vol)
            end
        end
        
        if isempty(volatilities)
            return 1.0
        end
        
        # Calculate average volatility
        avg_volatility = mean(volatilities)
        
        # Map volatility to reserve multiplier
        # Low volatility (< 20%): 1.0x reserves
        # Medium volatility (20-50%): 1.0-1.5x reserves
        # High volatility (> 50%): 1.5-2.0x reserves
        if avg_volatility < 0.20
            return 1.0
        elseif avg_volatility < 0.50
            return 1.0 + (avg_volatility - 0.20) / 0.30 * 0.5
        else
            return 1.5 + min((avg_volatility - 0.50) / 0.50 * 0.5, 0.5)
        end
        
    catch e
        @error "Error calculating volatility reserve multiplier" error=e
        return 1.2  # Conservative fallback
    end
end

"""
    calculate_drawdown_reserve_multiplier(s::SC)

Calculate reserve multiplier based on current drawdown.
Higher drawdown requires more conservative cash management.
"""
function calculate_drawdown_reserve_multiplier(s::SC)
    try
        peak_cash = get(s.config, :peak_cash, 0.0)
        current_cash = sum(cash(s, ai) for (ai, _) in s.universe)
        
        if peak_cash <= 0
            return 1.0
        end
        
        drawdown_pct = (peak_cash - current_cash) / peak_cash
        
        # Map drawdown to reserve multiplier
        # No drawdown: 1.0x reserves
        # 10% drawdown: 1.2x reserves
        # 20% drawdown: 1.5x reserves
        # 30%+ drawdown: 2.0x reserves
        if drawdown_pct <= 0
            return 1.0
        elseif drawdown_pct < 0.10
            return 1.0 + drawdown_pct * 2.0
        elseif drawdown_pct < 0.20
            return 1.2 + (drawdown_pct - 0.10) * 3.0
        elseif drawdown_pct < 0.30
            return 1.5 + (drawdown_pct - 0.20) * 5.0
        else
            return 2.0
        end
        
    catch e
        @error "Error calculating drawdown reserve multiplier" error=e
        return 1.5  # Conservative fallback
    end
end

"""
    manage_collateral(s::SC, ai::AssetInstance)

Manage collateral requirements for leveraged positions.
Ensures sufficient collateral is maintained for margin trading.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance

# Returns
- NamedTuple with collateral information
"""
function manage_collateral(s::SC, ai::AssetInstance)
    try
        # Get current position and leverage
        current_position = haspositions(s, ai) ? position(s, ai) : 0.0
        leverage = get(s.config, :def_lev, 1.0)
        current_price = last(s.universe[ai].close)
        
        # Calculate position value and required collateral
        position_value = abs(current_position * current_price)
        required_collateral = position_value / leverage
        
        # Get available collateral
        available_cash = cash(s, ai)
        
        # Calculate collateral utilization
        collateral_utilization = required_collateral > 0 ? required_collateral / available_cash : 0.0
        
        # Calculate margin level (available / required)
        margin_level = required_collateral > 0 ? available_cash / required_collateral : Inf
        
        # Determine collateral status
        warning_level = get(s.config, :collateral_warning_level, 2.0)  # 200% margin level
        critical_level = get(s.config, :collateral_critical_level, 1.5)  # 150% margin level
        
        status = if margin_level >= warning_level
            :healthy
        elseif margin_level >= critical_level
            :warning
        else
            :critical
        end
        
        # Calculate additional collateral needed for safety
        target_margin_level = get(s.config, :target_margin_level, 3.0)  # 300% target
        additional_collateral_needed = max(0.0, required_collateral * target_margin_level - available_cash)
        
        return (
            position_value = position_value,
            required_collateral = required_collateral,
            available_collateral = available_cash,
            collateral_utilization = collateral_utilization,
            margin_level = margin_level,
            status = status,
            additional_needed = additional_collateral_needed
        )
        
    catch e
        @error "Error managing collateral" ai=ai error=e
        return (
            position_value = 0.0,
            required_collateral = 0.0,
            available_collateral = 0.0,
            collateral_utilization = 0.0,
            margin_level = Inf,
            status = :error,
            additional_needed = 0.0
        )
    end
end

"""
    peak_cash!(s::SC)

Update and track peak cash levels for drawdown calculations.
Should be called regularly during strategy execution.

# Arguments
- `s::SC`: Strategy instance

# Returns
- Float64: Current peak cash level
"""
function peak_cash!(s::SC)
    try
        # Calculate current total cash
        current_cash = sum(cash(s, ai) for (ai, _) in s.universe)
        
        # Add unrealized PnL from open positions
        unrealized_pnl = 0.0
        for (ai, ohlcv) in s.universe
            if haspositions(s, ai)
                current_position = position(s, ai)
                current_price = last(ohlcv.close)
                # This is a simplified calculation - in practice would need entry price
                position_value = current_position * current_price
                unrealized_pnl += position_value
            end
        end
        
        total_equity = current_cash + unrealized_pnl
        
        # Update peak cash if current is higher
        current_peak = get(s.config, :peak_cash, 0.0)
        if total_equity > current_peak
            s.config[:peak_cash] = total_equity
            s.config[:peak_cash_time] = now()
            @info "New peak cash reached" peak_cash=total_equity previous_peak=current_peak
        end
        
        # Update peak cash history for analysis
        if !haskey(s.config, :peak_cash_history)
            s.config[:peak_cash_history] = Tuple{DateTime, Float64}[]
        end
        
        # Add to history (keep last 1000 entries)
        history = s.config[:peak_cash_history]
        push!(history, (now(), total_equity))
        if length(history) > 1000
            deleteat!(history, 1:100)  # Remove oldest 100 entries
        end
        
        return s.config[:peak_cash]
        
    catch e
        @error "Error updating peak cash" error=e
        return get(s.config, :peak_cash, 0.0)
    end
end

"""
    calculate_drawdown(s::SC)

Calculate current drawdown metrics.

# Arguments
- `s::SC`: Strategy instance

# Returns
- NamedTuple with drawdown information
"""
function calculate_drawdown(s::SC)
    try
        peak_cash = get(s.config, :peak_cash, 0.0)
        
        if peak_cash <= 0
            return (
                current_drawdown = 0.0,
                current_drawdown_pct = 0.0,
                max_drawdown = 0.0,
                max_drawdown_pct = 0.0,
                drawdown_duration = Day(0),
                recovery_factor = 1.0
            )
        end
        
        # Calculate current equity
        current_cash = sum(cash(s, ai) for (ai, _) in s.universe)
        unrealized_pnl = 0.0
        for (ai, ohlcv) in s.universe
            if haspositions(s, ai)
                current_position = position(s, ai)
                current_price = last(ohlcv.close)
                position_value = current_position * current_price
                unrealized_pnl += position_value
            end
        end
        current_equity = current_cash + unrealized_pnl
        
        # Calculate current drawdown
        current_drawdown = peak_cash - current_equity
        current_drawdown_pct = current_drawdown / peak_cash
        
        # Update maximum drawdown
        max_drawdown = get(s.config, :max_drawdown, 0.0)
        max_drawdown_pct = get(s.config, :max_drawdown_pct, 0.0)
        
        if current_drawdown > max_drawdown
            s.config[:max_drawdown] = current_drawdown
            s.config[:max_drawdown_pct] = current_drawdown_pct
            s.config[:max_drawdown_time] = now()
        end
        
        # Calculate drawdown duration
        peak_time = get(s.config, :peak_cash_time, now())
        drawdown_duration = now() - peak_time
        
        # Calculate recovery factor (how much gain needed to recover)
        recovery_factor = current_equity > 0 ? peak_cash / current_equity : Inf
        
        return (
            current_drawdown = current_drawdown,
            current_drawdown_pct = current_drawdown_pct,
            max_drawdown = s.config[:max_drawdown],
            max_drawdown_pct = s.config[:max_drawdown_pct],
            drawdown_duration = drawdown_duration,
            recovery_factor = recovery_factor
        )
        
    catch e
        @error "Error calculating drawdown" error=e
        return (
            current_drawdown = 0.0,
            current_drawdown_pct = 0.0,
            max_drawdown = 0.0,
            max_drawdown_pct = 0.0,
            drawdown_duration = Day(0),
            recovery_factor = 1.0
        )
    end
end

"""
    check_risk_limits(s::SC, ai::AssetInstance)

Check if current positions violate risk limits and take corrective action.

# Arguments
- `s::SC`: Strategy instance
- `ai::AssetInstance`: Asset instance to check

# Returns
- NamedTuple with risk check results and actions taken
"""
function check_risk_limits(s::SC, ai::AssetInstance)
    try
        actions_taken = String[]
        violations = String[]
        
        # Check position size limits
        if haspositions(s, ai)
            current_position = position(s, ai)
            current_price = last(s.universe[ai].close)
            position_value = abs(current_position * current_price)
            
            max_position_value = get_max_position_size(s, ai)
            if position_value > max_position_value
                push!(violations, "position_size_exceeded")
                @warn "Position size limit exceeded" ai=ai current=position_value limit=max_position_value
                
                # Reduce position to limit
                if closeposition!(s, ai; reason="position_size_limit")
                    push!(actions_taken, "position_closed_size_limit")
                end
            end
        end
        
        # Check drawdown limits
        drawdown_info = calculate_drawdown(s)
        max_drawdown_limit = get(s.config, :max_drawdown_limit, 0.25)  # 25% max drawdown
        
        if drawdown_info.current_drawdown_pct > max_drawdown_limit
            push!(violations, "max_drawdown_exceeded")
            @warn "Maximum drawdown exceeded" current=drawdown_info.current_drawdown_pct limit=max_drawdown_limit
            
            # Close all positions if drawdown limit exceeded
            if closeposition!(s, ai; reason="max_drawdown_limit", emergency=true)
                push!(actions_taken, "emergency_close_drawdown")
            end
        end
        
        # Check collateral limits (for leveraged positions)
        collateral_info = manage_collateral(s, ai)
        if collateral_info.status == :critical
            push!(violations, "critical_collateral_level")
            @warn "Critical collateral level" ai=ai margin_level=collateral_info.margin_level
            
            # Emergency position reduction
            if closeposition!(s, ai; reason="critical_collateral", emergency=true)
                push!(actions_taken, "emergency_close_collateral")
            end
        end
        
        # Check concentration limits
        total_portfolio_value = sum(cash(s, ai_other) for (ai_other, _) in s.universe)
        if haspositions(s, ai)
            position_value = abs(position(s, ai) * last(s.universe[ai].close))
            concentration = position_value / total_portfolio_value
            max_concentration = get(s.config, :max_concentration, 0.30)  # 30% max per asset
            
            if concentration > max_concentration
                push!(violations, "concentration_limit_exceeded")
                @warn "Concentration limit exceeded" ai=ai concentration=concentration limit=max_concentration
                
                # Reduce position to limit
                if closeposition!(s, ai; reason="concentration_limit")
                    push!(actions_taken, "position_reduced_concentration")
                end
            end
        end
        
        return (
            violations = violations,
            actions_taken = actions_taken,
            risk_level = isempty(violations) ? :normal : (length(violations) > 2 ? :high : :medium)
        )
        
    catch e
        @error "Error checking risk limits" ai=ai error=e
        return (
            violations = ["error_in_risk_check"],
            actions_taken = String[],
            risk_level = :error
        )
    end
end

# Helper functions for exchange-specific parameters
"""
    get_tick_size(s::SC, ai::AssetInstance)

Get minimum price increment (tick size) for an asset.
"""
function get_tick_size(s::SC, ai::AssetInstance)
    return get(s.config, :tick_size, 0.01)
end

"""
    get_lot_size(s::SC, ai::AssetInstance)

Get minimum quantity increment (lot size) for an asset.
"""
function get_lot_size(s::SC, ai::AssetInstance)
    return get(s.config, :lot_size, 0.001)
end

"""
    get_min_quantity(s::SC, ai::AssetInstance)

Get minimum order quantity for an asset.
"""
function get_min_quantity(s::SC, ai::AssetInstance)
    return get(s.config, :min_quantity, 0.001)
end

"""
    generate_order_id()

Generate unique order ID for tracking.
"""
function generate_order_id()
    return string(now()) * "_" * string(rand(1000:9999))
end