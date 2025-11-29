# PnL tracking system for StrategyFramework

using Dates
using Statistics
using Planar
# CircularBuffer is available via @strategyenv!() through Data.DataStructures

"""
    trackpnl!(s::SC, ai::AssetInstance, ats::DateTime; interval::Period = Hour(1))

Track PnL for a specific asset over a given interval.
This function calculates and stores PnL metrics for performance monitoring.
"""
function trackpnl!(s::SC, ai::AssetInstance, ats::DateTime; interval::Period = Hour(1))
    @debug "Tracking PnL" asset=ai timestamp=ats interval=interval
    
    try
        # Initialize PnL tracking structures if needed
        init_pnl_tracking!(s, ai)
        
        # Calculate current PnL
        current_pnl = calculate_current_pnl(s, ai, ats)
        
        # Update PnL history
        update_pnl_history!(s, ai, ats, current_pnl, interval)
        
        # Update performance metrics
        update_performance_metrics!(s, ai, current_pnl, ats)
        
        # Update peak cash tracking
        peak_cash!(s, ai, ats)
        
        # Calculate and update drawdown metrics
        update_drawdown_metrics!(s, ai, ats)
        
        @debug "PnL tracking completed" asset=ai pnl=current_pnl
        
    catch e
        @error "Failed to track PnL" asset=ai error=e
    end
    
    nothing
end

"""
    trackpnl!(s::SC, ats::DateTime; interval::Period = Hour(1))

Track PnL for all assets in the strategy.
"""
function trackpnl!(s::SC, ats::DateTime; interval::Period = Hour(1))
    @debug "Tracking PnL for all assets" timestamp=ats interval=interval
    
    # Get all assets from current configuration
    assets = get_current_assets()
    exchange = WATCHER_EXC[]
    
    for asset_str in assets
        try
            ai = AssetInstance(asset_str, exchange)
            trackpnl!(s, ai, ats; interval=interval)
        catch e
            @error "Failed to track PnL for asset" asset=asset_str error=e
        end
    end
    
    # Update overall strategy PnL
    update_strategy_pnl!(s, ats)
    
    nothing
end

"""
    init_pnl_tracking!(s::SC, ai::AssetInstance)

Initialize PnL tracking structures for an asset.
"""
function init_pnl_tracking!(s::SC, ai::AssetInstance)
    # Initialize PnL history
    if !haskey(s.attrs, :pnl_history)
        s[:pnl_history] = Dict{AssetInstance, CircularBuffer}()
    end
    
    if !haskey(s[:pnl_history], ai)
        # Store last 1000 PnL data points
        s[:pnl_history][ai] = CircularBuffer{Tuple{DateTime, Float64}}(1000)
    end
    
    # Initialize trade history
    if !haskey(s.attrs, :trade_history)
        s[:trade_history] = Dict{AssetInstance, Vector{Dict{Symbol, Any}}}()
    end
    
    if !haskey(s[:trade_history], ai)
        s[:trade_history][ai] = Dict{Symbol, Any}[]
    end
    
    # Initialize performance metrics
    if !haskey(s.attrs, :performance_metrics)
        s[:performance_metrics] = Dict{AssetInstance, Dict{Symbol, Any}}()
    end
    
    if !haskey(s[:performance_metrics], ai)
        s[:performance_metrics][ai] = Dict{Symbol, Any}(
            :total_pnl => 0.0,
            :realized_pnl => 0.0,
            :unrealized_pnl => 0.0,
            :peak_pnl => 0.0,
            :max_drawdown => 0.0,
            :total_trades => 0,
            :winning_trades => 0,
            :losing_trades => 0,
            :win_rate => 0.0,
            :avg_win => 0.0,
            :avg_loss => 0.0,
            :profit_factor => 0.0,
            :sharpe_ratio => 0.0,
            :last_updated => ats
        )
    end
    
    nothing
end

"""
    calculate_current_pnl(s::SC, ai::AssetInstance, ats::DateTime)

Calculate the current PnL for an asset.
"""
function calculate_current_pnl(s::SC, ai::AssetInstance, ats::DateTime)
    try
        # Get current position
        position = get_position(s, ai)
        
        if isnothing(position) || iszero(position.size)
            return 0.0  # No position, no PnL
        end
        
        # Get current market price
        current_price = get_current_price(s, ai, ats)
        
        if isnothing(current_price)
            @warn "Cannot calculate PnL: no current price available" asset=ai
            return 0.0
        end
        
        # Calculate unrealized PnL
        entry_price = position.entry_price
        position_size = position.size
        
        # PnL calculation depends on position side
        if position_size > 0  # Long position
            unrealized_pnl = (current_price - entry_price) * position_size
        else  # Short position
            unrealized_pnl = (entry_price - current_price) * abs(position_size)
        end
        
        # Get realized PnL from trade history
        realized_pnl = get_realized_pnl(s, ai)
        
        # Total PnL = Realized + Unrealized
        total_pnl = realized_pnl + unrealized_pnl
        
        @debug "PnL calculated" asset=ai realized=realized_pnl unrealized=unrealized_pnl total=total_pnl
        
        return total_pnl
        
    catch e
        @error "Failed to calculate current PnL" asset=ai error=e
        return 0.0
    end
end

"""
    get_position(s::SC, ai::AssetInstance)

Get the current position for an asset.
"""
function get_position(s::SC, ai::AssetInstance)
    try
        # This would integrate with Planar's position tracking
        # For now, return a mock position structure
        positions = get(s.attrs, :positions, Dict())
        return get(positions, ai, nothing)
    catch
        return nothing
    end
end

"""
    get_current_price(s::SC, ai::AssetInstance, ats::DateTime)

Get the current market price for an asset.
"""
function get_current_price(s::SC, ai::AssetInstance, ats::DateTime)
    try
        # Get OHLCV data
        ohlcv_data = get(get(s.attrs, :ohlcv_data, Dict()), ai, nothing)
        
        if isnothing(ohlcv_data) || isempty(ohlcv_data)
            return nothing
        end
        
        # Return the close price of the latest candle
        # This is a simplified implementation
        return 50000.0  # Mock price - in practice would get from OHLCV data
        
    catch e
        @error "Failed to get current price" asset=ai error=e
        return nothing
    end
end

"""
    get_realized_pnl(s::SC, ai::AssetInstance)

Get the realized PnL from completed trades.
"""
function get_realized_pnl(s::SC, ai::AssetInstance)
    trade_history = get(get(s.attrs, :trade_history, Dict()), ai, [])
    
    realized_pnl = 0.0
    for trade in trade_history
        if get(trade, :status, :open) == :closed
            realized_pnl += get(trade, :pnl, 0.0)
        end
    end
    
    return realized_pnl
end

"""
    update_pnl_history!(s::SC, ai::AssetInstance, ats::DateTime, pnl::Float64, interval::Period)

Update the PnL history for an asset.
"""
function update_pnl_history!(s::SC, ai::AssetInstance, ats::DateTime, pnl::Float64, interval::Period)
    pnl_history = s[:pnl_history][ai]
    
    # Check if we should add a new data point based on interval
    should_update = if isempty(pnl_history)
        true
    else
        last_timestamp = last(pnl_history)[1]
        (ats - last_timestamp) >= interval
    end
    
    if should_update
        push!(pnl_history, (ats, pnl))
        @debug "PnL history updated" asset=ai timestamp=ats pnl=pnl
    end
    
    nothing
end

"""
    update_performance_metrics!(s::SC, ai::AssetInstance, current_pnl::Float64, ats::DateTime)

Update performance metrics for an asset.
"""
function update_performance_metrics!(s::SC, ai::AssetInstance, current_pnl::Float64, ats::DateTime)
    metrics = s[:performance_metrics][ai]
    
    # Update basic metrics
    metrics[:total_pnl] = current_pnl
    metrics[:last_updated] = ats
    
    # Update peak PnL
    if current_pnl > metrics[:peak_pnl]
        metrics[:peak_pnl] = current_pnl
        metrics[:peak_pnl_time] = ats
    end
    
    # Calculate trade statistics
    update_trade_statistics!(s, ai, metrics)
    
    # Calculate risk metrics
    update_risk_metrics!(s, ai, metrics)
    
    nothing
end

"""
    update_trade_statistics!(s::SC, ai::AssetInstance, metrics::Dict{Symbol, Any})

Update trade-related statistics.
"""
function update_trade_statistics!(s::SC, ai::AssetInstance, metrics::Dict{Symbol, Any})
    trade_history = get(get(s.attrs, :trade_history, Dict()), ai, [])
    
    # Count trades
    closed_trades = filter(t -> get(t, :status, :open) == :closed, trade_history)
    metrics[:total_trades] = length(closed_trades)
    
    if isempty(closed_trades)
        return nothing
    end
    
    # Separate winning and losing trades
    winning_trades = filter(t -> get(t, :pnl, 0.0) > 0, closed_trades)
    losing_trades = filter(t -> get(t, :pnl, 0.0) < 0, closed_trades)
    
    metrics[:winning_trades] = length(winning_trades)
    metrics[:losing_trades] = length(losing_trades)
    
    # Calculate win rate
    metrics[:win_rate] = metrics[:total_trades] > 0 ? metrics[:winning_trades] / metrics[:total_trades] : 0.0
    
    # Calculate average win/loss
    if !isempty(winning_trades)
        metrics[:avg_win] = mean(t -> get(t, :pnl, 0.0), winning_trades)
    else
        metrics[:avg_win] = 0.0
    end
    
    if !isempty(losing_trades)
        metrics[:avg_loss] = mean(t -> abs(get(t, :pnl, 0.0)), losing_trades)
    else
        metrics[:avg_loss] = 0.0
    end
    
    # Calculate profit factor
    total_wins = sum(t -> get(t, :pnl, 0.0), winning_trades)
    total_losses = sum(t -> abs(get(t, :pnl, 0.0)), losing_trades)
    
    metrics[:profit_factor] = total_losses > 0 ? total_wins / total_losses : 0.0
    
    nothing
end

"""
    update_risk_metrics!(s::SC, ai::AssetInstance, metrics::Dict{Symbol, Any})

Update risk-related metrics like Sharpe ratio.
"""
function update_risk_metrics!(s::SC, ai::AssetInstance, metrics::Dict{Symbol, Any})
    pnl_history = get(get(s.attrs, :pnl_history, Dict()), ai, nothing)
    
    if isnothing(pnl_history) || length(pnl_history) < 2
        metrics[:sharpe_ratio] = 0.0
        return nothing
    end
    
    # Calculate returns from PnL history
    pnl_values = [pnl for (_, pnl) in pnl_history]
    
    if length(pnl_values) < 2
        metrics[:sharpe_ratio] = 0.0
        return nothing
    end
    
    # Calculate period returns
    returns = diff(pnl_values)
    
    if isempty(returns)
        metrics[:sharpe_ratio] = 0.0
        return nothing
    end
    
    # Calculate Sharpe ratio (simplified)
    mean_return = mean(returns)
    std_return = std(returns)
    
    metrics[:sharpe_ratio] = std_return > 0 ? mean_return / std_return : 0.0
    
    nothing
end

"""
    peak_cash!(s::SC, ai::AssetInstance, ats::DateTime)

Update peak cash tracking for an asset.
"""
function peak_cash!(s::SC, ai::AssetInstance, ats::DateTime)
    @debug "Updating peak cash tracking" asset=ai timestamp=ats
    
    try
        # Get current cash/equity value
        current_equity = get_current_equity(s, ai)
        
        # Initialize peak cash tracking
        if !haskey(s.attrs, :peak_cash)
            s[:peak_cash] = Dict{AssetInstance, Dict{Symbol, Any}}()
        end
        
        if !haskey(s[:peak_cash], ai)
            s[:peak_cash][ai] = Dict{Symbol, Any}(
                :peak_value => current_equity,
                :peak_time => ats,
                :current_value => current_equity,
                :last_updated => ats
            )
        end
        
        peak_data = s[:peak_cash][ai]
        peak_data[:current_value] = current_equity
        peak_data[:last_updated] = ats
        
        # Update peak if current value is higher
        if current_equity > peak_data[:peak_value]
            peak_data[:peak_value] = current_equity
            peak_data[:peak_time] = ats
            @debug "New peak cash recorded" asset=ai peak_value=current_equity
        end
        
    catch e
        @error "Failed to update peak cash" asset=ai error=e
    end
    
    nothing
end

"""
    peak_cash!(s::SC, ats::DateTime)

Update peak cash tracking for the entire strategy.
"""
function peak_cash!(s::SC, ats::DateTime)
    @debug "Updating strategy peak cash tracking" timestamp=ats
    
    try
        # Calculate total strategy equity
        total_equity = calculate_total_strategy_equity(s, ats)
        
        # Initialize strategy-level peak cash tracking
        if !haskey(s.attrs, :strategy_peak_cash)
            s[:strategy_peak_cash] = Dict{Symbol, Any}(
                :peak_value => total_equity,
                :peak_time => ats,
                :current_value => total_equity,
                :last_updated => ats
            )
        end
        
        peak_data = s[:strategy_peak_cash]
        peak_data[:current_value] = total_equity
        peak_data[:last_updated] = ats
        
        # Update peak if current value is higher
        if total_equity > peak_data[:peak_value]
            peak_data[:peak_value] = total_equity
            peak_data[:peak_time] = ats
            @debug "New strategy peak cash recorded" peak_value=total_equity
        end
        
        # Update individual asset peak cash
        assets = get_current_assets()
        exchange = WATCHER_EXC[]
        
        for asset_str in assets
            try
                ai = AssetInstance(asset_str, exchange)
                peak_cash!(s, ai, ats)
            catch e
                @error "Failed to update peak cash for asset" asset=asset_str error=e
            end
        end
        
    catch e
        @error "Failed to update strategy peak cash" error=e
    end
    
    nothing
end

"""
    get_current_equity(s::SC, ai::AssetInstance)

Get the current equity value for an asset.
"""
function get_current_equity(s::SC, ai::AssetInstance)
    try
        # This would integrate with Planar's balance tracking
        # For now, return a mock value based on PnL
        current_pnl = get(get(s.attrs, :performance_metrics, Dict()), ai, Dict())[:total_pnl]
        base_equity = 10000.0  # Mock base equity
        return base_equity + current_pnl
    catch
        return 10000.0  # Fallback value
    end
end

"""
    calculate_total_strategy_equity(s::SC, ats::DateTime)

Calculate the total equity across all assets in the strategy.
"""
function calculate_total_strategy_equity(s::SC, ats::DateTime)
    total_equity = 0.0
    
    assets = get_current_assets()
    exchange = WATCHER_EXC[]
    
    for asset_str in assets
        try
            ai = AssetInstance(asset_str, exchange)
            asset_equity = get_current_equity(s, ai)
            total_equity += asset_equity
        catch e
            @error "Failed to get equity for asset" asset=asset_str error=e
        end
    end
    
    return total_equity
end

"""
    calculate_drawdown(s::SC, ai::AssetInstance)

Calculate the current drawdown for an asset.
"""
function calculate_drawdown(s::SC, ai::AssetInstance)
    peak_data = get(get(s.attrs, :peak_cash, Dict()), ai, nothing)
    
    if isnothing(peak_data)
        return 0.0
    end
    
    peak_value = peak_data[:peak_value]
    current_value = peak_data[:current_value]
    
    if peak_value <= 0
        return 0.0
    end
    
    drawdown = (peak_value - current_value) / peak_value
    return max(0.0, drawdown)  # Drawdown should be non-negative
end

"""
    update_drawdown_metrics!(s::SC, ai::AssetInstance, ats::DateTime)

Update drawdown metrics for an asset.
"""
function update_drawdown_metrics!(s::SC, ai::AssetInstance, ats::DateTime)
    current_drawdown = calculate_drawdown(s, ai)
    
    # Update performance metrics with current drawdown
    if haskey(s.attrs, :performance_metrics) && haskey(s[:performance_metrics], ai)
        metrics = s[:performance_metrics][ai]
        
        # Update max drawdown if current is larger
        if current_drawdown > get(metrics, :max_drawdown, 0.0)
            metrics[:max_drawdown] = current_drawdown
            metrics[:max_drawdown_time] = ats
        end
        
        metrics[:current_drawdown] = current_drawdown
    end
    
    nothing
end

"""
    update_strategy_pnl!(s::SC, ats::DateTime)

Update overall strategy PnL metrics.
"""
function update_strategy_pnl!(s::SC, ats::DateTime)
    @debug "Updating strategy PnL metrics" timestamp=ats
    
    try
        # Initialize strategy metrics if needed
        if !haskey(s.attrs, :strategy_metrics)
            s[:strategy_metrics] = Dict{Symbol, Any}(
                :total_pnl => 0.0,
                :total_trades => 0,
                :winning_trades => 0,
                :losing_trades => 0,
                :max_drawdown => 0.0,
                :last_updated => ats
            )
        end
        
        strategy_metrics = s[:strategy_metrics]
        
        # Aggregate metrics from all assets
        total_pnl = 0.0
        total_trades = 0
        winning_trades = 0
        losing_trades = 0
        max_drawdown = 0.0
        
        assets = get_current_assets()
        exchange = WATCHER_EXC[]
        
        for asset_str in assets
            try
                ai = AssetInstance(asset_str, exchange)
                asset_metrics = get(get(s.attrs, :performance_metrics, Dict()), ai, Dict())
                
                total_pnl += get(asset_metrics, :total_pnl, 0.0)
                total_trades += get(asset_metrics, :total_trades, 0)
                winning_trades += get(asset_metrics, :winning_trades, 0)
                losing_trades += get(asset_metrics, :losing_trades, 0)
                max_drawdown = max(max_drawdown, get(asset_metrics, :max_drawdown, 0.0))
                
            catch e
                @error "Failed to aggregate metrics for asset" asset=asset_str error=e
            end
        end
        
        # Update strategy metrics
        strategy_metrics[:total_pnl] = total_pnl
        strategy_metrics[:total_trades] = total_trades
        strategy_metrics[:winning_trades] = winning_trades
        strategy_metrics[:losing_trades] = losing_trades
        strategy_metrics[:max_drawdown] = max_drawdown
        strategy_metrics[:win_rate] = total_trades > 0 ? winning_trades / total_trades : 0.0
        strategy_metrics[:last_updated] = ats
        
        @debug "Strategy PnL metrics updated" total_pnl=total_pnl total_trades=total_trades win_rate=strategy_metrics[:win_rate]
        
    catch e
        @error "Failed to update strategy PnL metrics" error=e
    end
    
    nothing
end

"""
    get_pnl_summary(s::SC, ai::AssetInstance)

Get a summary of PnL metrics for an asset.
"""
function get_pnl_summary(s::SC, ai::AssetInstance)
    metrics = get(get(s.attrs, :performance_metrics, Dict()), ai, Dict())
    peak_data = get(get(s.attrs, :peak_cash, Dict()), ai, Dict())
    
    return Dict{Symbol, Any}(
        :asset => ai,
        :total_pnl => get(metrics, :total_pnl, 0.0),
        :realized_pnl => get(metrics, :realized_pnl, 0.0),
        :unrealized_pnl => get(metrics, :unrealized_pnl, 0.0),
        :peak_pnl => get(metrics, :peak_pnl, 0.0),
        :current_drawdown => get(metrics, :current_drawdown, 0.0),
        :max_drawdown => get(metrics, :max_drawdown, 0.0),
        :total_trades => get(metrics, :total_trades, 0),
        :win_rate => get(metrics, :win_rate, 0.0),
        :profit_factor => get(metrics, :profit_factor, 0.0),
        :sharpe_ratio => get(metrics, :sharpe_ratio, 0.0),
        :peak_cash => get(peak_data, :peak_value, 0.0),
        :current_cash => get(peak_data, :current_value, 0.0),
        :last_updated => get(metrics, :last_updated, DateTime(0))
    )
end

"""
    get_strategy_pnl_summary(s::SC)

Get a summary of PnL metrics for the entire strategy.
"""
function get_strategy_pnl_summary(s::SC)
    strategy_metrics = get(s.attrs, :strategy_metrics, Dict())
    strategy_peak = get(s.attrs, :strategy_peak_cash, Dict())
    
    # Get individual asset summaries
    asset_summaries = Dict{AssetInstance, Dict{Symbol, Any}}()
    
    assets = get_current_assets()
    exchange = WATCHER_EXC[]
    
    for asset_str in assets
        try
            ai = AssetInstance(asset_str, exchange)
            asset_summaries[ai] = get_pnl_summary(s, ai)
        catch e
            @error "Failed to get PnL summary for asset" asset=asset_str error=e
        end
    end
    
    return Dict{Symbol, Any}(
        :strategy_metrics => strategy_metrics,
        :strategy_peak_cash => strategy_peak,
        :asset_summaries => asset_summaries,
        :summary_time => now()
    )
end