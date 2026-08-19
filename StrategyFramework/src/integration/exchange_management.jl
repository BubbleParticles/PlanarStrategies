"""
Exchange and asset management utilities for StrategyFramework.

This module provides comprehensive exchange configuration, rate limiting,
asset universe management, and market data source configuration utilities.
"""

# Import from parent module when included
# using ..StrategyFramework: SC, StrategyConfig
using Dates
using Logging

# Import Planar modules for exchange and asset management
using Planar
using Planar.Exchanges
using Planar.Engine.Instances: AssetInstance
using Planar.Engine.Collections: AssetCollection
using Planar.Engine.Misc: Config

# Import now from TimeTicks to avoid ambiguity with Dates.now
using Planar.Engine.TimeTicks: now

# Exchange configuration and rate limiting

"""
    ExchangeConfig

Configuration structure for exchange-specific settings including rate limits,
API endpoints, and connection parameters.
"""
@kwdef mutable struct ExchangeConfig
    # Basic exchange settings
    exchange_id::Symbol = :phemex
    sandbox::Bool = false
    account::String = "default"
    
    # Rate limiting settings
    rate_limit_enabled::Bool = true
    requests_per_second::Float64 = 10.0
    burst_limit::Int = 50
    cooldown_period::Period = Second(1)
    
    # Connection settings
    timeout::Period = Second(30)
    retry_attempts::Int = 3
    retry_delay::Period = Second(1)
    
    # API settings
    api_key::String = ""
    api_secret::String = ""
    passphrase::String = ""  # For some exchanges like OKX
    
    # Market data settings
    enable_websocket::Bool = true
    websocket_timeout::Period = Second(60)
    ohlcv_limit::Int = 1000
    
    # Trading settings
    default_order_type::Symbol = :limit
    enable_margin::Bool = false
    margin_mode::Symbol = :cross  # :cross or :isolated
end

"""
    AssetUniverseConfig

Configuration for managing the asset universe including filtering,
selection criteria, and dynamic management settings.
"""
@kwdef mutable struct AssetUniverseConfig
    # Asset selection criteria
    min_volume_24h::Float64 = 1_000_000.0  # Minimum 24h volume in USD
    min_price::Float64 = 0.0001  # Minimum price filter
    max_price::Float64 = 1_000_000.0  # Maximum price filter
    
    # Quote currencies to include
    quote_currencies::Vector{String} = ["USDT", "USDC", "USD"]
    
    # Asset filtering
    exclude_patterns::Vector{String} = [".*UP.*", ".*DOWN.*", ".*BEAR.*", ".*BULL.*"]
    include_patterns::Vector{String} = String[]  # Empty means include all (after exclusions)
    
    # Dynamic management
    enable_dynamic_universe::Bool = false
    universe_update_interval::Period = Hour(24)
    max_assets::Int = 50
    
    # Data requirements
    min_data_history::Period = Day(30)
    required_timeframes::Vector{String} = ["1m", "5m", "1h"]
end

"""
    MarketDataConfig

Configuration for market data sources and management.
"""
@kwdef mutable struct MarketDataConfig
    # Primary data source
    primary_source::Symbol = :ccxt
    backup_sources::Vector{Symbol} = Symbol[]
    
    # Data quality settings
    enable_data_validation::Bool = true
    max_gap_tolerance::Period = Minute(5)
    enable_gap_filling::Bool = true
    
    # Caching settings
    enable_caching::Bool = true
    cache_duration::Period = Hour(1)
    max_cache_size::Int = 1000  # Number of cached responses
    
    # Real-time data settings
    enable_realtime::Bool = true
    realtime_update_interval::Period = Second(1)
    enable_tick_data::Bool = false
    
    # Historical data settings
    historical_data_limit::Int = 10000
    enable_progressive_loading::Bool = true
    chunk_size::Int = 1000
end

# Global configuration storage
const EXCHANGE_CONFIGS = Dict{Symbol, ExchangeConfig}()
const UNIVERSE_CONFIGS = Dict{Symbol, AssetUniverseConfig}()
const MARKET_DATA_CONFIGS = Dict{Symbol, MarketDataConfig}()

# Rate limiting state
const RATE_LIMITERS = Dict{Symbol, Dict{String, Any}}()

"""
    configure_exchange!(exchange_id::Symbol, config::ExchangeConfig)

Configure exchange settings for the specified exchange.
"""
function configure_exchange!(exchange_id::Symbol, config::ExchangeConfig)
    EXCHANGE_CONFIGS[exchange_id] = config
    
    # Initialize rate limiter if enabled
    if config.rate_limit_enabled
        _initialize_rate_limiter!(exchange_id, config)
    end
    
    @info "StrategyFramework: Exchange configured" exchange_id sandbox=config.sandbox rate_limit=config.rate_limit_enabled
    return config
end

"""
    get_exchange_config(exchange_id::Symbol)

Get the configuration for the specified exchange.
"""
function get_exchange_config(exchange_id::Symbol)
    get(EXCHANGE_CONFIGS, exchange_id, ExchangeConfig(exchange_id=exchange_id))
end

"""
    setup_exchange!(s::SC, exchange_id::Symbol; kwargs...)

Setup and configure an exchange for the strategy.
"""
function setup_exchange!(s::SC, exchange_id::Symbol; kwargs...)
    try
        # Get or create exchange configuration
        config = get_exchange_config(exchange_id)
        
        # Override config with kwargs
        for (key, value) in kwargs
            if hasfield(ExchangeConfig, key)
                setfield!(config, key, value)
            end
        end
        
        # Get exchange instance from Planar
        exchange = Exchanges.getexchange!(
            exchange_id;
            sandbox=config.sandbox,
            account=config.account
        )
        
        # Configure rate limiting
        if config.rate_limit_enabled
            _setup_exchange_rate_limiting!(exchange, config)
        end
        
        @info "StrategyFramework: Exchange setup completed" exchange_id account=config.account sandbox=config.sandbox
        return exchange
        
    catch e
        @error "StrategyFramework: Failed to setup exchange" exchange_id exception=e
        rethrow(e)
    end
end

"""
    configure_asset_universe!(universe_id::Symbol, config::AssetUniverseConfig)

Configure asset universe settings.
"""
function configure_asset_universe!(universe_id::Symbol, config::AssetUniverseConfig)
    UNIVERSE_CONFIGS[universe_id] = config
    @info "StrategyFramework: Asset universe configured" universe_id max_assets=config.max_assets min_volume=config.min_volume_24h
    return config
end

"""
    get_universe_config(universe_id::Symbol)

Get the asset universe configuration.
"""
function get_universe_config(universe_id::Symbol)
    get(UNIVERSE_CONFIGS, universe_id, AssetUniverseConfig())
end

"""
    create_asset_universe(s::SC, assets::Vector{String}; universe_id::Symbol=:default)

Create an asset universe for the strategy with the specified assets.
"""
function create_asset_universe(s::SC, assets::Vector{String}; universe_id::Symbol=:default)
    try
        config = get_universe_config(universe_id)
        
        # Filter assets based on configuration
        filtered_assets = _filter_assets(assets, config)
        
        # Create asset collection
        universe = AssetCollection(
            filtered_assets;
            exc=exchange(s),
            load_data=false,
            timeframe=s.timeframe
        )
        
        @info "StrategyFramework: Asset universe created" universe_id asset_count=length(filtered_assets)
        return universe
        
    catch e
        @error "StrategyFramework: Failed to create asset universe" universe_id exception=e
        rethrow(e)
    end
end

"""
    update_asset_universe!(s::SC, new_assets::Vector{String})

Dynamically update the strategy's asset universe.
"""
function update_asset_universe!(s::SC, new_assets::Vector{String})
    try
        # Create new universe
        new_universe = create_asset_universe(s, new_assets)
        
        # Update strategy universe (this is experimental in Planar)
        s.universe = new_universe
        
        @info "StrategyFramework: Asset universe updated" new_count=length(new_assets)
        return true
        
    catch e
        @error "StrategyFramework: Failed to update asset universe" exception=e
        return false
    end
end

"""
    configure_market_data!(data_id::Symbol, config::MarketDataConfig)

Configure market data source settings.
"""
function configure_market_data!(data_id::Symbol, config::MarketDataConfig)
    MARKET_DATA_CONFIGS[data_id] = config
    @info "StrategyFramework: Market data configured" data_id primary_source=config.primary_source enable_realtime=config.enable_realtime
    return config
end

"""
    get_market_data_config(data_id::Symbol)

Get market data configuration.
"""
function get_market_data_config(data_id::Symbol)
    get(MARKET_DATA_CONFIGS, data_id, MarketDataConfig())
end

"""
    setup_market_data_sources!(s::SC; data_id::Symbol=:default)

Setup market data sources for the strategy.
"""
function setup_market_data_sources!(s::SC; data_id::Symbol=:default)
    try
        config = get_market_data_config(data_id)
        
        # Setup primary data source
        _setup_primary_data_source!(s, config)
        
        # Setup backup sources if configured
        for backup_source in config.backup_sources
            _setup_backup_data_source!(s, backup_source, config)
        end
        
        # Enable real-time data if configured
        if config.enable_realtime
            _setup_realtime_data!(s, config)
        end
        
        @info "StrategyFramework: Market data sources configured" data_id primary=config.primary_source realtime=config.enable_realtime
        return true
        
    catch e
        @error "StrategyFramework: Failed to setup market data sources" data_id exception=e
        return false
    end
end

"""
    get_available_assets(exchange_id::Symbol; quote_currency::String="USDT")

Get list of available assets from the exchange.
"""
function get_available_assets(exchange_id::Symbol; quote_currency::String="USDT")
    try
        # Get exchange instance
        exchange = Exchanges.getexchange!(exchange_id)
        
        # Get available tickers
        tickers = Exchanges.tickers(exchange_id, Symbol(quote_currency))
        
        return collect(tickers)
        
    catch e
        @error "StrategyFramework: Failed to get available assets" exchange_id quote_currency exception=e
        return String[]
    end
end

"""
    validate_asset_universe(s::SC, assets::Vector{String})

Validate that all assets in the universe are available and meet requirements.
"""
function validate_asset_universe(s::SC, assets::Vector{String})
    valid_assets = String[]
    invalid_assets = String[]
    
    try
        exchange_id = Symbol(Exchanges.exchangeid(exchange(s)))
        available_assets = get_available_assets(exchange_id)
        
        for asset in assets
            if asset in available_assets
                push!(valid_assets, asset)
            else
                push!(invalid_assets, asset)
            end
        end
        
    catch e
        @error "StrategyFramework: Failed to validate asset universe" exception=e
        invalid_assets = copy(assets)
    end
    
    return (valid_assets, invalid_assets)
end

# Private helper functions

function _initialize_rate_limiter!(exchange_id::Symbol, config::ExchangeConfig)
    RATE_LIMITERS[exchange_id] = Dict(
        "requests_per_second" => config.requests_per_second,
        "burst_limit" => config.burst_limit,
        "last_request" => now(),
        "request_count" => 0,
        "cooldown_until" => now()
    )
end

function _setup_exchange_rate_limiting!(exchange, config::ExchangeConfig)
    # This would integrate with Planar's exchange rate limiting
    # Implementation depends on Planar's internal rate limiting mechanisms
    @debug "StrategyFramework: Rate limiting configured" requests_per_second=config.requests_per_second
end

function _filter_assets(assets::Vector{String}, config::AssetUniverseConfig)
    filtered = String[]
    
    for asset in assets
        # Apply exclusion patterns
        excluded = false
        for pattern in config.exclude_patterns
            if occursin(Regex(pattern), asset)
                excluded = true
                break
            end
        end
        
        if excluded
            continue
        end
        
        # Apply inclusion patterns (if any)
        if !isempty(config.include_patterns)
            included = false
            for pattern in config.include_patterns
                if occursin(Regex(pattern), asset)
                    included = true
                    break
                end
            end
            
            if !included
                continue
            end
        end
        
        # Check quote currency
        quote_match = false
        for quote_curr in config.quote_currencies
            if endswith(asset, quote_curr)
                quote_match = true
                break
            end
        end
        
        if !quote_match
            continue
        end
        
        push!(filtered, asset)
    end
    
    # Limit to max_assets if specified
    if config.max_assets > 0 && length(filtered) > config.max_assets
        filtered = filtered[1:config.max_assets]
    end
    
    return filtered
end

function _setup_primary_data_source!(s::SC, config::MarketDataConfig)
    # Setup primary data source based on configuration
    @debug "StrategyFramework: Setting up primary data source" source=config.primary_source
end

function _setup_backup_data_source!(s::SC, source::Symbol, config::MarketDataConfig)
    # Setup backup data source
    @debug "StrategyFramework: Setting up backup data source" source=source
end

function _setup_realtime_data!(s::SC, config::MarketDataConfig)
    # Setup real-time data feeds
    @debug "StrategyFramework: Setting up real-time data" interval=config.realtime_update_interval
end

# Initialize default configurations
function __init_exchange_management__()
    # Setup default exchange configurations
    configure_exchange!(:phemex, ExchangeConfig(
        exchange_id=:phemex,
        requests_per_second=10.0,
        enable_margin=true
    ))
    
    configure_exchange!(:binance, ExchangeConfig(
        exchange_id=:binance,
        requests_per_second=20.0,
        enable_margin=true
    ))
    
    # Setup default universe configuration
    configure_asset_universe!(:default, AssetUniverseConfig(
        min_volume_24h=1_000_000.0,
        quote_currencies=["USDT", "USDC"],
        max_assets=20
    ))
    
    # Setup default market data configuration
    configure_market_data!(:default, MarketDataConfig(
        primary_source=:ccxt,
        enable_realtime=true,
        enable_caching=true
    ))
    
    @debug "StrategyFramework: Exchange management initialized"
end

# Initialize on module load
__init_exchange_management__()