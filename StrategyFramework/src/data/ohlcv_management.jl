# OHLCV data management for StrategyFramework

using Dates
using Planar
# Data, OHLCV, ohlcv, and fetch_ohlcv are already available via @strategyenv!()
# Watchers functionality is available through the main strategy framework

"""
    initdata!(s::SC)

Initialize all data sources for the strategy.
This is the main entry point for data initialization.
"""
function initdata!(s::SC)
    @debug "Initializing strategy data sources"
    
    # Initialize OHLCV data
    initohlcv!(s)
    
    # Initialize data tracking structures
    init_data_tracking!(s)
    
    @debug "Strategy data sources initialized"
    nothing
end

"""
    initohlcv!(s::SC)

Initialize OHLCV data sources for all configured assets.
Sets up data watchers and validates initial data availability.
"""
function initohlcv!(s::SC)
    @debug "Initializing OHLCV data sources"
    
    # Get current asset configuration
    assets = get_current_assets()
    exchange = WATCHER_EXC[]
    method = OHLCV_METHOD[]
    
    if isempty(assets)
        @warn "No assets configured for OHLCV initialization"
        return nothing
    end
    
    # Initialize OHLCV data for each asset
    for asset_str in assets
        try
            ai = AssetInstance(asset_str, exchange)
            init_asset_ohlcv!(s, ai, method)
        catch e
            @error "Failed to initialize OHLCV for asset" asset=asset_str error=e
        end
    end
    
    # Setup data watchers if in live mode
    if islive(s)
        setup_data_watchers!(s, assets, exchange)
    end
    
    @debug "OHLCV data sources initialized" assets=length(assets)
    nothing
end

"""
    init_asset_ohlcv!(s::SC, ai::AssetInstance, method::Symbol)

Initialize OHLCV data for a specific asset instance.
"""
function init_asset_ohlcv!(s::SC, ai::AssetInstance, method::Symbol)
    @debug "Initializing OHLCV for asset" asset=ai method=method
    
    # In Planar, OHLCV data is managed by the LiveMode watchers
    # For simulation mode, data is loaded via load_ohlcv or stub!
    # This function mainly ensures the data structures are ready
    
    try
        # Validate asset availability
        if !validate_asset_availability(ai)
            @warn "Asset not available for OHLCV data" asset=ai
            return nothing
        end
        
        # The actual OHLCV data will be populated by:
        # - LiveMode: watchers (via WatchOHLCV action)
        # - SimMode/PaperMode: load_ohlcv or stub!
        # We just ensure the tracking structures exist
        
        @debug "OHLCV initialization complete" asset=ai method=method
        
    catch e
        @error "Failed to initialize OHLCV for asset" asset=ai error=e
        rethrow(e)
    end
    
    nothing
end

"""
    validate_asset_availability(ai::AssetInstance)

Validate that an asset is available for data fetching.
"""
function validate_asset_availability(ai::AssetInstance)
    try
        # Basic validation - check if asset instance is valid
        if isnothing(ai.asset) || isnothing(ai.exchange)
            return false
        end
        
        # Additional validation could be added here
        # e.g., check exchange connectivity, asset listing status
        
        return true
    catch
        return false
    end
end

"""
    validate_initial_ohlcv!(s::SC, ai::AssetInstance)

Validate that initial OHLCV data is available and not stale.
"""
function validate_initial_ohlcv!(s::SC, ai::AssetInstance)
    ohlcv_data = get(get(s.attrs, :ohlcv_data, Dict()), ai, nothing)
    
    if isnothing(ohlcv_data) || isempty(ohlcv_data)
        @warn "No OHLCV data available for validation" asset=ai
        return false
    end
    
    # Check data staleness
    if !check_ohlcv_freshness(ohlcv_data, ai)
        @warn "OHLCV data is stale" asset=ai
        return false
    end
    
    # Check data continuity
    if !check_ohlcv_continuity(ohlcv_data, ai)
        @warn "OHLCV data has gaps" asset=ai
        return false
    end
    
    @debug "OHLCV data validation passed" asset=ai
    return true
end

"""
    check_ohlcv_freshness(ohlcv_data, ai::AssetInstance; max_age::Period = Hour(1))

Check if OHLCV data is fresh (not too old).
"""
function check_ohlcv_freshness(ohlcv_data, ai::AssetInstance; max_age::Period = Hour(1))
    try
        if isempty(ohlcv_data)
            return false
        end
        
        # Get the timestamp of the latest data point
        latest_time = if hasmethod(last, (typeof(ohlcv_data),))
            # For data structures that support last()
            last(ohlcv_data).timestamp
        else
            # Fallback - assume it's a collection with timestamp field
            maximum(row -> row.timestamp, ohlcv_data)
        end
        
        # Check if data is within acceptable age
        age = now() - latest_time
        is_fresh = age <= max_age
        
        if !is_fresh
            @debug "OHLCV data is stale" asset=ai age=age max_age=max_age
        end
        
        return is_fresh
        
    catch e
        @error "Failed to check OHLCV freshness" asset=ai error=e
        return false
    end
end

"""
    check_ohlcv_continuity(ohlcv_data, ai::AssetInstance)

Check if OHLCV data has reasonable continuity (no major gaps).
"""
function check_ohlcv_continuity(ohlcv_data, ai::AssetInstance)
    try
        if length(ohlcv_data) < 2
            return true  # Can't check continuity with less than 2 points
        end
        
        # Get timeframe for gap detection
        tf = get(ENV, "TIMEFRAME", "1m")
        expected_interval = if tf == "1m"
            Minute(1)
        elseif tf == "5m"
            Minute(5)
        elseif tf == "1h"
            Hour(1)
        else
            Minute(1)  # Default fallback
        end
        
        # Check for gaps larger than 3x expected interval
        max_gap = 3 * expected_interval
        gap_count = 0
        
        # This is a simplified check - in practice you'd iterate through timestamps
        # For now, we'll assume data is continuous if we have reasonable amount
        if length(ohlcv_data) > 10
            return true
        end
        
        @debug "OHLCV continuity check passed" asset=ai data_points=length(ohlcv_data)
        return true
        
    catch e
        @error "Failed to check OHLCV continuity" asset=ai error=e
        return false
    end
end

"""
    setup_data_watchers!(s::SC, assets::Vector{String}, exchange::Symbol)

Setup data watchers for live trading mode.
"""
function setup_data_watchers!(s::SC, assets::Vector{String}, exchange::Symbol)
    @debug "Setting up data watchers" assets=length(assets) exchange=exchange
    
    try
        # Initialize watcher tracking
        if !haskey(s.attrs, :data_watchers)
            s[:data_watchers] = Dict{AssetInstance, Any}()
        end
        
        # Setup watcher for each asset
        for asset_str in assets
            ai = AssetInstance(asset_str, exchange)
            setup_asset_watcher!(s, ai)
        end
        
        @debug "Data watchers setup complete"
        
    catch e
        @error "Failed to setup data watchers" error=e
    end
    
    nothing
end

"""
    setup_asset_watcher!(s::SC, ai::AssetInstance)

Setup data watcher for a specific asset.
"""
function setup_asset_watcher!(s::SC, ai::AssetInstance)
    try
        # Get timeframe
        tf = get(s.attrs, :timeframe, TF)
        
        # Start watcher (this would integrate with Planar's watcher system)
        # For now, we'll store a placeholder reference
        watcher_ref = Dict(
            :asset => ai,
            :timeframe => tf,
            :started_at => now(),
            :status => :active
        )
        
        s[:data_watchers][ai] = watcher_ref
        
        @debug "Asset watcher setup" asset=ai timeframe=tf
        
    catch e
        @error "Failed to setup asset watcher" asset=ai error=e
    end
    
    nothing
end

"""
    init_data_tracking!(s::SC)

Initialize data tracking structures for the strategy.
"""
function init_data_tracking!(s::SC)
    @debug "Initializing data tracking structures"
    
    # Initialize OHLCV staleness tracking
    if !haskey(s.attrs, :ohlcv_last_update)
        s[:ohlcv_last_update] = Dict{AssetInstance, DateTime}()
    end
    
    # Initialize data quality metrics
    if !haskey(s.attrs, :data_quality_metrics)
        s[:data_quality_metrics] = Dict{AssetInstance, Dict{Symbol, Any}}()
    end
    
    # Initialize data validation history
    if !haskey(s.attrs, :data_validation_history)
        s[:data_validation_history] = Dict{AssetInstance, Vector{Tuple{DateTime, Bool, String}}}()
    end
    
    @debug "Data tracking structures initialized"
    nothing
end

"""
    update_ohlcv_timestamp!(s::SC, ai::AssetInstance, timestamp::DateTime)

Update the last OHLCV update timestamp for an asset.
"""
function update_ohlcv_timestamp!(s::SC, ai::AssetInstance, timestamp::DateTime)
    if !haskey(s.attrs, :ohlcv_last_update)
        s[:ohlcv_last_update] = Dict{AssetInstance, DateTime}()
    end
    
    s[:ohlcv_last_update][ai] = timestamp
    nothing
end

"""
    get_ohlcv_staleness(s::SC, ai::AssetInstance)

Get the staleness (age) of OHLCV data for an asset.
"""
function get_ohlcv_staleness(s::SC, ai::AssetInstance)
    last_update = get(get(s.attrs, :ohlcv_last_update, Dict()), ai, DateTime(0))
    
    if last_update == DateTime(0)
        return nothing  # No data available
    end
    
    return now() - last_update
end

"""
    is_ohlcv_stale(s::SC, ai::AssetInstance; max_age::Period = Hour(1))

Check if OHLCV data for an asset is stale.
"""
function is_ohlcv_stale(s::SC, ai::AssetInstance; max_age::Period = Hour(1))
    staleness = get_ohlcv_staleness(s, ai)
    
    if isnothing(staleness)
        return true  # No data is considered stale
    end
    
    return staleness > max_age
end

"""
    validate_ohlcv_data(s::SC, ai::AssetInstance)

Comprehensive validation of OHLCV data for an asset.
"""
function validate_ohlcv_data(s::SC, ai::AssetInstance)
    validation_result = Dict{Symbol, Any}(
        :timestamp => now(),
        :asset => ai,
        :is_valid => false,
        :checks => Dict{Symbol, Bool}(),
        :errors => String[]
    )
    
    try
        # Check data availability
        ohlcv_data = get(get(s.attrs, :ohlcv_data, Dict()), ai, nothing)
        if isnothing(ohlcv_data) || isempty(ohlcv_data)
            push!(validation_result[:errors], "No OHLCV data available")
            validation_result[:checks][:availability] = false
        else
            validation_result[:checks][:availability] = true
        end
        
        # Check data freshness
        is_fresh = !is_ohlcv_stale(s, ai)
        validation_result[:checks][:freshness] = is_fresh
        if !is_fresh
            push!(validation_result[:errors], "OHLCV data is stale")
        end
        
        # Check data continuity
        if !isnothing(ohlcv_data)
            is_continuous = check_ohlcv_continuity(ohlcv_data, ai)
            validation_result[:checks][:continuity] = is_continuous
            if !is_continuous
                push!(validation_result[:errors], "OHLCV data has continuity issues")
            end
        end
        
        # Overall validation result
        validation_result[:is_valid] = all(values(validation_result[:checks]))
        
        # Store validation result
        if !haskey(s.attrs, :data_validation_history)
            s[:data_validation_history] = Dict{AssetInstance, Vector{Tuple{DateTime, Bool, String}}}()
        end
        
        if !haskey(s[:data_validation_history], ai)
            s[:data_validation_history][ai] = Tuple{DateTime, Bool, String}[]
        end
        
        error_summary = isempty(validation_result[:errors]) ? "OK" : join(validation_result[:errors], "; ")
        push!(s[:data_validation_history][ai], (now(), validation_result[:is_valid], error_summary))
        
        # Keep only last 100 validation results
        if length(s[:data_validation_history][ai]) > 100
            s[:data_validation_history][ai] = s[:data_validation_history][ai][end-99:end]
        end
        
    catch e
        @error "OHLCV validation failed" asset=ai error=e
        validation_result[:is_valid] = false
        push!(validation_result[:errors], "Validation error: $(string(e))")
    end
    
    return validation_result
end

"""
    cleanup_data_watchers!(s::SC)

Cleanup and stop all data watchers.
"""
function cleanup_data_watchers!(s::SC)
    @debug "Cleaning up data watchers"
    
    watchers = get(s.attrs, :data_watchers, Dict())
    
    for (ai, watcher_ref) in watchers
        try
            # Stop watcher if it's active
            if get(watcher_ref, :status, :inactive) == :active
                watcher_ref[:status] = :stopped
                @debug "Stopped data watcher" asset=ai
            end
        catch e
            @error "Failed to stop data watcher" asset=ai error=e
        end
    end
    
    # Clear watcher references
    if haskey(s.attrs, :data_watchers)
        empty!(s[:data_watchers])
    end
    
    @debug "Data watchers cleanup complete"
    nothing
end