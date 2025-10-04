# Strategy initialization system for StrategyFramework

using Dates
using Planar

# Import strategy lifecycle types and functions
using Planar.Strategies: LoadStrategy, ResetStrategy, StartStrategy, StopStrategy, WarmupPeriod, StrategyMarkets, default_load
using Planar.Executors: WatchOHLCV

"""
    initialize_strategy!(s::SC, sg::SignalGenerator)

Initialize the StrategyFramework with all necessary components.
This function sets up the framework infrastructure including:
- Position tracking
- Performance metrics
- Risk management
- Data management
- Signal generation integration

# Arguments
- `s::SC`: The strategy instance
- `sg::SignalGenerator`: The signal generator implementation
"""
function initialize_strategy!(s::SC, sg::SignalGenerator)
    @debug "Initializing StrategyFramework" strategy_id=id(s)
    
    # Initialize core tracking systems (simplified versions)
    # Note: These are basic implementations - full StrategyTools versions will be added later
    if !haskey(s.attrs, :pnl)
        s[:pnl] = Dict()
    end
    
    if !haskey(s.attrs, :def_lev)
        s[:def_lev] = 1.0
    end
    
    # Initialize trend tracking if signal generator requires it
    if hasmethod(requires_trends, (typeof(sg),))
        trends = requires_trends(sg)
        if !haskey(s.attrs, :trends)
            s[:trends] = Dict()
        end
    end
    
    # Initialize position tracker
    if !haskey(s.attrs, :position_tracker)
        s[:position_tracker] = PositionTracker()
    end
    
    # Initialize performance metrics
    if !haskey(s.attrs, :performance_metrics)
        s[:performance_metrics] = PerformanceMetrics()
    end
    
    # Initialize strategy configuration
    if !haskey(s.attrs, :strategy_config)
        s[:strategy_config] = StrategyConfig()
    end
    
    # Initialize signal generator state
    if hasmethod(initialize!, (typeof(sg), typeof(s)))
        initialize!(sg, s)
    end
    
    @debug "StrategyFramework initialization complete"
    nothing
end

"""
    reset_strategy!(s::SC, sg::SignalGenerator)

Reset the strategy state with all SurgeV4 initialization logic.
This function performs a complete reset of the strategy including:
- Clearing position tracking
- Resetting performance metrics
- Reinitializing data systems
- Applying current parameters

# Arguments
- `s::SC`: The strategy instance
- `sg::SignalGenerator`: The signal generator implementation
"""
function reset_strategy!(s::SC, sg::SignalGenerator)
    @debug "Resetting StrategyFramework" strategy_id=id(s)
    
    # Reset core tracking systems (simplified versions)
    # Note: These are basic implementations - full StrategyTools versions will be added later
    if haskey(s.attrs, :pnl)
        empty!(s[:pnl])
    else
        s[:pnl] = Dict()
    end
    
    if !haskey(s.attrs, :def_lev)
        s[:def_lev] = 1.0
    end
    
    # Reset trend tracking if needed
    if haskey(s.attrs, :trends)
        empty!(s[:trends])
    end
    
    # Reset position tracker
    position_tracker = get(s.attrs, :position_tracker, PositionTracker())
    empty!(position_tracker.extremas)
    empty!(position_tracker.hl_trackers)
    empty!(position_tracker.backoff)
    position_tracker.uni_iter = (AssetInstance[], Ref(DateTime(0)))
    s[:position_tracker] = position_tracker
    
    # Reset performance metrics but preserve configuration
    perf_metrics = get(s.attrs, :performance_metrics, PerformanceMetrics())
    empty!(perf_metrics.pnl_history)
    empty!(perf_metrics.trade_history)
    perf_metrics.peak_cash = 0.0
    perf_metrics.max_drawdown = 0.0
    perf_metrics.total_trades = 0
    perf_metrics.winning_trades = 0
    s[:performance_metrics] = perf_metrics
    
    # Apply current parameters
    apply_params!(s)
    
    # Reset signal generator state
    if hasmethod(reset!, (typeof(sg), typeof(s)))
        reset!(sg, s)
    end
    
    @debug "StrategyFramework reset complete"
    nothing
end

"""
    apply_params!(s::SC)

Apply parameters from strategy configuration to the strategy instance.
This function updates strategy attributes based on the current configuration,
including leverage, order types, timeouts, and risk parameters.

# Arguments
- `s::SC`: The strategy instance
"""
function apply_params!(s::SC)
    # Apply configuration to strategy if available
    apply_configuration_to_strategy!(s)
    
    config = get(s.attrs, :strategy_config, StrategyConfig())
    
    # Apply trading parameters
    s.attrs[:signal_lifetime] = config.signal_lifetime
    s.attrs[:trade_cooldown] = config.trade_cooldown
    s.attrs[:order_timeout] = config.order_timeout
    s.attrs[:def_lev] = config.def_lev
    
    # Apply risk management parameters
    s.attrs[:reserve_cash_pct] = config.reserve_cash_pct
    s.attrs[:peak_cash] = config.peak_cash
    
    # Apply execution settings
    s.attrs[:ordertype] = config.ordertype
    s.attrs[:ismake] = config.ismake
    
    # Apply environment settings
    s.attrs[:throttle] = config.throttle
    s.attrs[:sync_history_limit] = config.sync_history_limit
    s.attrs[:watch_idle_timeout] = config.watch_idle_timeout
    
    @debug "Parameters applied" config
    nothing
end

"""
    convert_float_vector_to_params(s::SC, params::Vector{Float64})

Convert a float vector to strategy parameters for optimization.
This function maps optimization parameters to strategy configuration values.

# Arguments
- `s::SC`: The strategy instance
- `params::Vector{Float64}`: Parameter vector from optimizer

# Returns
- Updated strategy configuration
"""
function convert_float_vector_to_params(s::SC, params::Vector{Float64})
    # Get parameter names from strategy attributes or use defaults
    param_names = get(s.attrs, :optimization_params, [:signal_lifetime, :def_lev, :reserve_cash_pct])
    
    # Use the parameter conversion utility
    param_dict = convert_float_vector_to_params(params, param_names)
    
    # Update strategy configuration
    config = get(s.attrs, :strategy_config, StrategyConfig())
    
    for (name, value) in param_dict
        if hasfield(typeof(config), name)
            setfield!(config, name, value)
        end
    end
    
    s[:strategy_config] = config
    apply_params!(s)
    
    config
end

# Strategy lifecycle callback implementations
"""
    call!(t::Type{<:SC}, config, ::LoadStrategy)

Load strategy callback - called during strategy construction.
Sets up the strategy configuration and performs initial setup.
"""
function call!(t::Type{<:SC}, config, ::LoadStrategy)
    @debug "Loading StrategyFramework" strategy_type=t
    
    # Set minimum timeframe and available timeframes
    config.min_timeframe = TF
    config.timeframes = [TF]
    
    # Set default configuration values if not already set
    if !hasfield(typeof(config), :signal_lifetime) || !isdefined(config, :signal_lifetime)
        config.signal_lifetime = 0.2
    end
    
    if !hasfield(typeof(config), :def_lev) || !isdefined(config, :def_lev)
        config.def_lev = 1.0
    end
    
    # Use default loading mechanism from Planar
    default_load(@__MODULE__, t, config)
end

"""
    call!(s::SC, ::ResetStrategy)

Reset strategy callback - called when strategy is reset.
Initializes OHLCV watching and resets strategy state.
"""
function call!(s::SC, ::ResetStrategy)
    @debug "Resetting StrategyFramework" strategy_id=id(s)
    
    # Initialize OHLCV watching for data updates
    call!(s, WatchOHLCV())
    
    # Get signal generator from strategy attributes
    sg = get(s.attrs, :signal_generator, nothing)
    if sg !== nothing
        reset_strategy!(s, sg)
    else
        @warn "No signal generator found during reset" strategy_id=id(s)
        # Perform basic reset without signal generator
        basic_strategy_reset!(s)
    end
    
    @debug "StrategyFramework reset complete" strategy_id=id(s)
    nothing
end

"""
    call!(s::SC, ::StartStrategy)

Start strategy callback - called before strategy execution begins.
Performs final initialization and setup before trading starts.
"""
function call!(s::SC, ::StartStrategy)
    @debug "Starting StrategyFramework" strategy_id=id(s)
    
    # Get signal generator from strategy attributes
    sg = get(s.attrs, :signal_generator, nothing)
    if sg !== nothing
        initialize_strategy!(s, sg)
    else
        @warn "No signal generator found during start" strategy_id=id(s)
        # Perform basic initialization without signal generator
        basic_strategy_initialization!(s)
    end
    
    # Initialize warmup period if needed
    warmup_period = call!(s, WarmupPeriod())
    if warmup_period > Second(0)
        @debug "Strategy warmup period configured" period=warmup_period strategy_id=id(s)
        
        # Initialize data sources during warmup
        initialize_warmup_data!(s, warmup_period)
    end
    
    # Initialize OHLCV data management
    initialize_ohlcv!(s)
    
    @debug "StrategyFramework start complete" strategy_id=id(s)
    nothing
end

"""
    call!(s::SC, ::StopStrategy)

Stop strategy callback - called after strategy execution ends.
Performs cleanup and final logging.
"""
function call!(s::SC, ::StopStrategy)
    @debug "Stopping StrategyFramework" strategy_id=id(s)
    
    # Get signal generator from strategy attributes
    sg = get(s.attrs, :signal_generator, nothing)
    if sg !== nothing && hasmethod(cleanup!, (typeof(sg), typeof(s)))
        cleanup!(sg, s)
    end
    
    # Finalize performance metrics
    finalize_performance_metrics!(s)
    
    # Log final strategy statistics
    log_final_statistics!(s)
    
    @debug "StrategyFramework stopped" strategy_id=id(s)
    nothing
end

"""
    call!(s::SC, ::WarmupPeriod)

Warmup period callback - returns the required warmup period for the strategy.
Default implementation returns 1 day, but can be overridden by signal generators.
"""
function call!(s::SC, ::WarmupPeriod)
    # Get signal generator from strategy attributes
    sg = get(s.attrs, :signal_generator, nothing)
    if sg !== nothing && hasmethod(get_warmup_period, (typeof(sg),))
        warmup = get_warmup_period(sg)
        @debug "Signal generator warmup period" period=warmup strategy_id=id(s)
        return warmup
    end
    
    # Check strategy configuration for warmup period
    config = get(s.attrs, :strategy_config, nothing)
    if config !== nothing && hasfield(typeof(config), :warmup_period)
        warmup = config.warmup_period
        @debug "Configuration warmup period" period=warmup strategy_id=id(s)
        return warmup
    end
    
    # Default warmup period
    default_warmup = Day(1)
    @debug "Default warmup period" period=default_warmup strategy_id=id(s)
    default_warmup
end

"""
    call!(::Union{<:SC,Type{<:SC}}, ::StrategyMarkets)

Strategy markets callback - returns the list of market symbols for the strategy.
Uses the current asset configuration from environment settings.
"""
function call!(::Union{<:SC,Type{<:SC}}, ::StrategyMarkets)
    markets = get_current_assets()
    @debug "Strategy markets configured" markets=markets
    markets
end

"""
    poll_strategy!(s::SC, sg::SignalGenerator, ts::DateTime)

Main strategy polling loop - called at each time step during execution.
This function coordinates signal generation with trading actions.

# Arguments
- `s::SC`: The strategy instance
- `sg::SignalGenerator`: The signal generator implementation
- `ts::DateTime`: Current timestamp
"""
function poll_strategy!(s::SC, sg::SignalGenerator, ts::DateTime)
    ats = available(s.timeframe, ts)
    
    # Update performance tracking
    track_pnl!(s, ats)
    
    # Process each asset in the universe
    foreach(s.universe) do ai
        try
            # Check if we should trade this asset
            if should_trade(sg, s, ai, ats)
                # Generate buy signal
                buy_signal = generate_buy_signal(sg, s, ai, ats)
                if buy_signal
                    handle_buy_signal!(s, ai, ats, ts)
                end
                
                # Generate sell signal
                sell_signal = generate_sell_signal(sg, s, ai, ats)
                if sell_signal
                    handle_sell_signal!(s, ai, ats, ts)
                end
            end
            
            # Update tracking for this asset
            update_asset_tracking!(s, ai, ats)
            
        catch e
            @error "Error processing asset in strategy poll" asset=ai exception=e
        end
    end
    
    nothing
end

"""
    call!(s::SC, ts::DateTime, ctx)

Main strategy execution callback - called at each time step.
This is the entry point for strategy execution that delegates to the polling system.
"""
function call!(s::SC, ts::DateTime, ctx)
    # Get signal generator from strategy attributes
    sg = get(s.attrs, :signal_generator, nothing)
    if sg === nothing
        @warn "No signal generator configured for strategy" strategy_id=id(s) timestamp=ts
        return nothing
    end
    
    try
        poll_strategy!(s, sg, ts)
    catch e
        @error "Error in strategy execution" strategy_id=id(s) timestamp=ts exception=e
        # Don't rethrow to avoid stopping the strategy
    end
    
    nothing
end

# Helper functions for signal handling
"""
    handle_buy_signal!(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime)

Handle a buy signal by executing appropriate trading logic.
"""
function handle_buy_signal!(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime)
    # This will be implemented in the trading modules
    @debug "Buy signal received" asset=ai timestamp=ts
    # TODO: Implement in trading/order_management.jl
end

"""
    handle_sell_signal!(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime)

Handle a sell signal by executing appropriate trading logic.
"""
function handle_sell_signal!(s::SC, ai::AssetInstance, ats::DateTime, ts::DateTime)
    # This will be implemented in the trading modules
    @debug "Sell signal received" asset=ai timestamp=ts
    # TODO: Implement in trading/order_management.jl
end

"""
    update_asset_tracking!(s::SC, ai::AssetInstance, ats::DateTime)

Update tracking information for an asset.
"""
function update_asset_tracking!(s::SC, ai::AssetInstance, ats::DateTime)
    # This will be implemented in the data modules
    # TODO: Implement in data/trend_detection.jl
end

# Optional interface methods for signal generators
"""
    requires_trends(sg::SignalGenerator)

Return the trend types required by the signal generator.
Signal generators can implement this method to specify which trends they need.
"""
function requires_trends(sg::SignalGenerator)
    Symbol[]  # Default: no trends required
end

"""
    initialize!(sg::SignalGenerator, s::SC)

Initialize the signal generator with strategy context.
Signal generators can implement this method for custom initialization.
"""
function initialize!(sg::SignalGenerator, s::SC)
    nothing  # Default: no initialization needed
end

"""
    reset!(sg::SignalGenerator, s::SC)

Reset the signal generator state.
Signal generators can implement this method for custom reset logic.
"""
function reset!(sg::SignalGenerator, s::SC)
    nothing  # Default: no reset needed
end

"""
    cleanup!(sg::SignalGenerator, s::SC)

Cleanup the signal generator state when strategy stops.
Signal generators can implement this method for custom cleanup logic.
"""
function cleanup!(sg::SignalGenerator, s::SC)
    nothing  # Default: no cleanup needed
end

"""
    get_warmup_period(sg::SignalGenerator)

Get the warmup period required by the signal generator.
Signal generators can implement this method to specify their warmup requirements.
"""
function get_warmup_period(sg::SignalGenerator)
    Day(1)  # Default: 1 day warmup
end

# Helper functions for callback system

"""
    basic_strategy_reset!(s::SC)

Perform basic strategy reset when no signal generator is available.
"""
function basic_strategy_reset!(s::SC)
    @debug "Performing basic strategy reset" strategy_id=id(s)
    
    # Reset core tracking systems
    if haskey(s.attrs, :pnl)
        empty!(s[:pnl])
    else
        s[:pnl] = Dict()
    end
    
    # Reset basic configuration
    if !haskey(s.attrs, :def_lev)
        s[:def_lev] = 1.0
    end
    
    # Reset position tracker
    position_tracker = get(s.attrs, :position_tracker, PositionTracker())
    empty!(position_tracker.extremas)
    empty!(position_tracker.hl_trackers)
    empty!(position_tracker.backoff)
    position_tracker.uni_iter = (AssetInstance[], Ref(DateTime(0)))
    s[:position_tracker] = position_tracker
    
    # Reset performance metrics
    perf_metrics = get(s.attrs, :performance_metrics, PerformanceMetrics())
    empty!(perf_metrics.pnl_history)
    empty!(perf_metrics.trade_history)
    perf_metrics.peak_cash = 0.0
    perf_metrics.max_drawdown = 0.0
    perf_metrics.total_trades = 0
    perf_metrics.winning_trades = 0
    s[:performance_metrics] = perf_metrics
    
    # Apply basic parameters
    apply_params!(s)
    
    nothing
end

"""
    basic_strategy_initialization!(s::SC)

Perform basic strategy initialization when no signal generator is available.
"""
function basic_strategy_initialization!(s::SC)
    @debug "Performing basic strategy initialization" strategy_id=id(s)
    
    # Initialize core tracking systems
    if !haskey(s.attrs, :pnl)
        s[:pnl] = Dict()
    end
    
    if !haskey(s.attrs, :def_lev)
        s[:def_lev] = 1.0
    end
    
    # Initialize position tracker
    if !haskey(s.attrs, :position_tracker)
        s[:position_tracker] = PositionTracker()
    end
    
    # Initialize performance metrics
    if !haskey(s.attrs, :performance_metrics)
        s[:performance_metrics] = PerformanceMetrics()
    end
    
    # Initialize strategy configuration
    if !haskey(s.attrs, :strategy_config)
        s[:strategy_config] = StrategyConfig()
    end
    
    nothing
end

"""
    initialize_warmup_data!(s::SC, warmup_period::Period)

Initialize data sources during the warmup period.
"""
function initialize_warmup_data!(s::SC, warmup_period::Period)
    @debug "Initializing warmup data" strategy_id=id(s) warmup_period=warmup_period
    
    # Calculate warmup start time
    current_time = now()
    warmup_start = current_time - warmup_period
    
    # Store warmup information in strategy attributes
    s[:warmup_start] = warmup_start
    s[:warmup_end] = current_time
    s[:warmup_period] = warmup_period
    
    # Initialize data for warmup period
    foreach(s.universe) do ai
        try
            initialize_asset_warmup_data!(s, ai, warmup_start, current_time)
        catch e
            @warn "Failed to initialize warmup data for asset" asset=ai exception=e
        end
    end
    
    nothing
end

"""
    initialize_asset_warmup_data!(s::SC, ai::AssetInstance, start_time::DateTime, end_time::DateTime)

Initialize warmup data for a specific asset.
"""
function initialize_asset_warmup_data!(s::SC, ai::AssetInstance, start_time::DateTime, end_time::DateTime)
    @debug "Initializing asset warmup data" asset=ai start_time=start_time end_time=end_time
    
    # Store asset warmup information
    if !haskey(s.attrs, :asset_warmup_data)
        s[:asset_warmup_data] = Dict()
    end
    
    s[:asset_warmup_data][ai] = (start_time=start_time, end_time=end_time, initialized=true)
    
    nothing
end

"""
    finalize_performance_metrics!(s::SC)

Finalize performance metrics when strategy stops.
"""
function finalize_performance_metrics!(s::SC)
    @debug "Finalizing performance metrics" strategy_id=id(s)
    
    perf_metrics = get(s.attrs, :performance_metrics, nothing)
    if perf_metrics !== nothing
        # Calculate final metrics
        total_trades = perf_metrics.total_trades
        winning_trades = perf_metrics.winning_trades
        win_rate = total_trades > 0 ? winning_trades / total_trades : 0.0
        
        # Store final metrics
        s[:final_total_trades] = total_trades
        s[:final_winning_trades] = winning_trades
        s[:final_win_rate] = win_rate
        s[:final_max_drawdown] = perf_metrics.max_drawdown
        s[:final_peak_cash] = perf_metrics.peak_cash
        
        @debug "Performance metrics finalized" total_trades=total_trades win_rate=win_rate max_drawdown=perf_metrics.max_drawdown
    end
    
    nothing
end

"""
    log_final_statistics!(s::SC)

Log final strategy statistics when strategy stops.
"""
function log_final_statistics!(s::SC)
    strategy_id = id(s)
    
    # Log basic strategy information
    @info "Strategy execution completed" strategy_id=strategy_id
    
    # Log performance metrics if available
    if haskey(s.attrs, :final_total_trades)
        @info "Final performance metrics" strategy_id=strategy_id total_trades=s[:final_total_trades] win_rate=s[:final_win_rate] max_drawdown=s[:final_max_drawdown]
    end
    
    # Log configuration summary
    config = get(s.attrs, :strategy_config, nothing)
    if config !== nothing
        @info "Strategy configuration" strategy_id=strategy_id signal_lifetime=config.signal_lifetime def_lev=config.def_lev ordertype=config.ordertype
    end
    
    # Log signal generator information
    sg = get(s.attrs, :signal_generator, nothing)
    if sg !== nothing
        @info "Signal generator" strategy_id=strategy_id signal_generator_type=typeof(sg)
    end
    
    nothing
end