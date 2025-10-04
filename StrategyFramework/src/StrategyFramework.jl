module StrategyFramework

using Core: kwfunc
using Planar
using .Planar.Pkg

# Core framework constants
const DESCRIPTION = "StrategyFramework"
const MARGIN = Isolated
const EXC = :phemex
const TF = tf"1m"
const THREADSAFE = Ref(true)

@strategyenv!
@contractsenv!

# Core modules - will be implemented in subsequent tasks
include("core/types.jl")
include("core/environment.jl") 
include("core/initialization.jl")
include("core/parameters.jl")
include("core/configuration.jl")

# Trading modules - will be implemented in subsequent tasks
include("trading/position_management.jl")
include("trading/order_management.jl")
include("trading/risk_management.jl")
include("trading/market_making.jl")

# Data modules - will be implemented in subsequent tasks
include("data/ohlcv_management.jl")
include("data/pnl_tracking.jl")
include("data/trend_detection.jl")

# Utility modules - will be implemented in subsequent tasks
include("utilities/async_utils.jl")
include("utilities/math_utils.jl")
include("utilities/logging_utils.jl")
include("utilities/profiling_utils.jl")

# Interface modules - will be implemented in subsequent tasks
include("interfaces/signal_interface.jl")
include("interfaces/strategy_callbacks.jl")

# Integration modules
include("integration/telegram_integration.jl")
include("integration/exchange_management.jl")

# Export core types and interfaces
export SignalGenerator
export generate_buy_signal, generate_sell_signal
export should_trade, get_signal_lifetime
export initialize_strategy!, reset_strategy!, poll_strategy!

# Export strategy lifecycle callbacks
export call!

# Export utility functions
export calculate_position_adjustment, get_target_position_size, trade_amount
export closeposition!, manage_cash_reserves, manage_collateral, peak_cash!, calculate_drawdown, check_risk_limits
export track_pnl!, track_trends!, initialize_ohlcv!
export liveasync, livelock, livesleep
export with_profiling, enable_profiling!, is_profiling_enabled, configure_profiling
export profile_strategy_operation, profile_if_slow

# Export order management functions
export trade!, handle_order_error, cancelorders!, check_posside
export validate_trade_parameters, calculate_final_trade_amount, select_order_type
export calculate_order_price, calculate_leverage_adjustment, execute_order

# Export market making functions
export market_make, should_market_make, ensure_market_make
export get_make_amounts, calculate_optimal_spread, calculate_inventory_adjustment
export analyze_market_making_conditions, place_market_making_order

# Export configuration and environment functions
export apply_params!, convert_float_vector_to_params
export env_strategy_id, env_assets_flag, setassets!

# Export parameter management functions
export ParameterSpec, ParameterCache
export register_parameter!, convert_params_to_float_vector
export validate_parameter, set_parameter!, get_parameter
export clear_parameter_cache!, get_parameter_specs, get_optimization_bounds

# Export configuration management functions
export ConfigurationManager
export load_configuration!, get_config_value, set_config_value!
export validate_configuration, apply_configuration_to_strategy!
export load_environment_variables!, save_configuration!
export get_configuration_summary, reset_configuration!
export create_default_config_file, switch_environment!, merge_configurations!

# Export Telegram integration functions
export start_telegram, stop_telegram, send_telegram_notification
export send_trade_notification, send_error_notification, send_performance_update
export setup_telegram_alerts, is_telegram_available, get_telegram_status

# Export exchange and asset management functions
export ExchangeConfig, AssetUniverseConfig, MarketDataConfig
export configure_exchange!, get_exchange_config, setup_exchange!
export configure_asset_universe!, get_universe_config, create_asset_universe
export update_asset_universe!, configure_market_data!, get_market_data_config
export setup_market_data_sources!, get_available_assets, validate_asset_universe

end