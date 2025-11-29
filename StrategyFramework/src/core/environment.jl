# Environment management for StrategyFramework

using Planar

# Environment variable reading functions
"""
    env_strategy_id()

Get the strategy ID from environment variables.
Returns the strategy identifier used for configuration and logging.
"""
function env_strategy_id()
    get(ENV, "STRATEGY_ID", "StrategyFramework")
end

"""
    env_assets_flag()

Get the assets flag from environment variables.
This determines which asset configuration to use.
"""
function env_assets_flag()
    flag_str = get(ENV, "ASSETS_FLAG", "default")
    Symbol(flag_str)
end

"""
    env_watcher_exchange()

Get the watcher exchange from environment variables.
"""
function env_watcher_exchange()
    exc_str = get(ENV, "WATCHER_EXC", "binance")
    Symbol(exc_str)
end

"""
    env_ohlcv_method()

Get the OHLCV method from environment variables.
"""
function env_ohlcv_method()
    method_str = get(ENV, "OHLCV_METHOD", "candles")
    Symbol(method_str)
end

"""
    env_profiling_enabled()

Check if profiling is enabled via environment variables.
"""
function env_profiling_enabled()
    profiling_str = get(ENV, "PROFILING", "false")
    lowercase(profiling_str) in ("true", "1", "yes", "on")
end

# Asset configuration functions
"""
    setassets!(flag::Symbol, exchange::Symbol, assets::Vector{String})

Set the asset configuration for a specific flag and exchange combination.
This allows different asset sets to be used in different environments.

# Arguments
- `flag::Symbol`: The asset flag identifier (e.g., :default, :test, :production)
- `exchange::Symbol`: The exchange identifier (e.g., :phemex, :binance)
- `assets::Vector{String}`: List of asset pairs (e.g., ["BTC/USDT:USDT", "ETH/USDT:USDT"])
"""
function setassets!(flag::Symbol, exchange::Symbol, assets::Vector{String})
    ASSETS_CT[(flag, exchange)] = copy(assets)
    nothing
end

"""
    get_exchange_assets(flag::Symbol, exchange::Symbol)

Get the asset list for a specific flag and exchange combination.
Returns an empty vector if no assets are configured for the combination.
"""
function get_exchange_assets(flag::Symbol, exchange::Symbol)
    get(ASSETS_CT, (flag, exchange), String[])
end

"""
    get_custom_assets(flag::Symbol)

Get custom assets for a specific flag across all exchanges.
Returns a dictionary mapping exchanges to their asset lists.
"""
function get_custom_assets(flag::Symbol)
    result = Dict{Symbol, Vector{String}}()
    for ((f, exc), assets) in ASSETS_CT
        if f == flag
            result[exc] = assets
        end
    end
    result
end

"""
    get_current_assets()

Get the assets for the currently configured flag and exchange.
"""
function get_current_assets()
    flag = ASSETS_FLAG[]
    exchange = WATCHER_EXC[]
    assets = get_exchange_assets(flag, exchange)
    if isempty(assets)
        return String[
            "BTC/USDT:USDT",
            "ETH/USDT:USDT",
            "SOL/USDT:USDT",
        ]
    end
    assets
end

# Module initialization function
"""
    __init__()

Initialize the StrategyFramework environment.
This function is called automatically when the module is loaded.
"""
function __init__()
    # Initialize environment references from environment variables
    ASSETS_FLAG[] = env_assets_flag()
    WATCHER_EXC[] = env_watcher_exchange()
    OHLCV_METHOD[] = env_ohlcv_method()
    PROFILING[] = env_profiling_enabled()
    
    # Set default asset configurations if none exist
    if isempty(ASSETS_CT)
        # Default configuration for common exchanges
        default_assets = String[
            "BTC/USDT:USDT",
            "ETH/USDT:USDT",
            "SOL/USDT:USDT",
        ]
        primary_asset = String["BTC/USDT:USDT"]
        setassets!(:default, :phemex, default_assets)
        setassets!(:default, :binance, default_assets)
        setassets!(:test, :phemex, primary_asset)
        setassets!(:test, :binance, primary_asset)
    end
    
    @debug "StrategyFramework environment initialized" ASSETS_FLAG=ASSETS_FLAG[] WATCHER_EXC=WATCHER_EXC[] OHLCV_METHOD=OHLCV_METHOD[] PROFILING=PROFILING[]
end