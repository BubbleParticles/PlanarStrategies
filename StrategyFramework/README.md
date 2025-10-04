# StrategyFramework

A comprehensive, modular foundation for building trading strategies in the Planar ecosystem. StrategyFramework extracts all the reusable infrastructure, utilities, and trading logic from SurgeV4.jl while providing a clean abstract interface for implementing custom signal generation logic.

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Signal Generator Interface](#signal-generator-interface)
- [Configuration](#configuration)
- [Environment Variables](#environment-variables)
- [Examples](#examples)
- [Module Structure](#module-structure)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Migration from SurgeV4](#migration-from-surgev4)
- [Contributing](#contributing)

## Overview

StrategyFramework is implemented as a strategy under `user/strategies/StrategyFramework` and provides:

- **Modular Architecture**: Clean separation of concerns across core, trading, data, utilities, and interface modules
- **Signal Interface**: Abstract interface for implementing custom signal generation logic
- **Trading Infrastructure**: Comprehensive position management, order execution, and risk controls
- **Data Management**: OHLCV handling, PnL tracking, and trend analysis utilities
- **Utility Functions**: Mathematical calculations, async operations, logging, and profiling support
- **Environment Management**: Flexible configuration for different deployment environments
- **Risk Management**: Built-in position sizing, drawdown protection, and risk controls
- **Performance Tracking**: Comprehensive PnL tracking and performance metrics

## Key Features

### 🎯 Signal-Based Trading
- Clean abstract interface for signal generation
- Automatic signal lifetime management
- Signal validation and debugging utilities
- Support for complex multi-asset strategies

### 📊 Advanced Position Management
- Dynamic position sizing based on volatility (ATR, KAMA, VTX)
- Leverage adjustment based on market conditions
- Drawdown-aware position sizing
- Risk-based position limits

### 🔄 Comprehensive Order Management
- Automatic order type selection
- Error handling with fallback mechanisms
- Stale order cancellation
- Position side validation

### 📈 Data & Analytics
- OHLCV data initialization and validation
- Real-time PnL tracking and calculation
- Trend detection utilities
- Performance history management

### ⚙️ Configuration Management
- Environment-specific configurations
- Parameter optimization support
- Asset universe management
- Exchange configuration

## Installation

1. Ensure you have Planar.jl installed and configured
2. Navigate to your Planar user directory:
   ```bash
   cd user/strategies
   ```
3. The StrategyFramework should already be available if you're using the complete Planar installation

## Quick Start

### 1. Create a Simple Signal Generator

```julia
using StrategyFramework

# Define your signal generator
struct SimpleMASignal <: SignalGenerator
    short_period::Int
    long_period::Int
    
    SimpleMASignal(short=10, long=20) = new(short, long)
end

# Implement required methods
function generate_buy_signal(sg::SimpleMASignal, s::SC, ai, ats)
    # Get OHLCV data
    ohlcv = s.universe[ai].ohlcv
    
    # Calculate moving averages
    short_ma = mean(ohlcv.close[end-sg.short_period+1:end])
    long_ma = mean(ohlcv.close[end-sg.long_period+1:end])
    
    # Generate buy signal when short MA crosses above long MA
    return short_ma > long_ma
end

function generate_sell_signal(sg::SimpleMASignal, s::SC, ai, ats)
    # Get OHLCV data
    ohlcv = s.universe[ai].ohlcv
    
    # Calculate moving averages
    short_ma = mean(ohlcv.close[end-sg.short_period+1:end])
    long_ma = mean(ohlcv.close[end-sg.long_period+1:end])
    
    # Generate sell signal when short MA crosses below long MA
    return short_ma < long_ma
end

# Optional: customize trading conditions
function should_trade(sg::SimpleMASignal, s::SC, ai, ats)
    # Only trade during market hours, avoid weekends, etc.
    hour = Dates.hour(ats)
    return 9 <= hour <= 16  # Trade only during 9 AM to 4 PM
end
```

### 2. Configure Your Strategy

Create or update your `user/planar.toml`:

```toml
[strategies.my_ma_strategy]
module = "StrategyFramework"
assets_flag = "default"
exchange = "phemex"

[strategies.my_ma_strategy.params]
short_period = 10
long_period = 20
signal_lifetime = 0.5
```

### 3. Set Environment Variables

```bash
export STRATEGY_ID="my_ma_strategy"
export ASSETS_FLAG="default"
export WATCHER_EXC="phemex"
export OHLCV_METHOD="ccxt"
```

### 4. Run Your Strategy

```julia
using Planar
using StrategyFramework

# Initialize your signal generator
signal_gen = SimpleMASignal(10, 20)

# The framework handles the rest automatically through Planar's strategy system
```

## Signal Generator Interface

The core of StrategyFramework is the `SignalGenerator` interface. All custom strategies must implement this interface.

### Required Methods

```julia
abstract type SignalGenerator end

# Must implement these methods:
function generate_buy_signal(sg::SignalGenerator, s::SC, ai, ats)
    # Return true if a buy signal is generated, false otherwise
end

function generate_sell_signal(sg::SignalGenerator, s::SC, ai, ats)
    # Return true if a sell signal is generated, false otherwise
end
```

### Optional Methods

```julia
# Optional methods with default implementations:
function should_trade(sg::SignalGenerator, s::SC, ai, ats)
    true  # Default: always allow trading
end

function get_signal_lifetime(sg::SignalGenerator)
    0.2  # Default signal lifetime in seconds
end
```

### Method Parameters

- `sg::SignalGenerator`: Your signal generator instance
- `s::SC`: The strategy instance (provides access to data, configuration, etc.)
- `ai`: Asset instance (the specific asset being analyzed)
- `ats`: Available timestamp (current time for analysis)

### Accessing Data in Signal Methods

```julia
function generate_buy_signal(sg::MySignal, s::SC, ai, ats)
    # Access OHLCV data
    ohlcv = s.universe[ai].ohlcv
    
    # Access current position
    pos = position(s, ai)
    
    # Access strategy configuration
    config = s.config
    
    # Access cash and balance information
    cash = s.cash[]
    
    # Your signal logic here...
    return signal_condition
end
```

## Configuration

### Strategy Configuration

StrategyFramework supports flexible configuration through multiple methods:

#### 1. Environment Variables (Highest Priority)
```bash
export STRATEGY_ID="my_strategy"
export ASSETS_FLAG="production"
export WATCHER_EXC="binance"
export OHLCV_METHOD="ccxt"
export PROFILING="false"
```

#### 2. Configuration Files
```julia
# Load configuration from file
config_manager = ConfigurationManager()
load_configuration!(config_manager, "config/production.toml")
```

#### 3. Programmatic Configuration
```julia
# Set configuration programmatically
set_config_value!(config_manager, "trading.signal_lifetime", 0.5)
set_config_value!(config_manager, "risk.max_position_size", 0.1)
```

### Asset Configuration

Configure different asset sets for different environments:

```julia
# Set assets for different flags and exchanges
setassets!(:production, :binance, ["BTC/USDT", "ETH/USDT", "ADA/USDT"])
setassets!(:test, :binance, ["BTC/USDT"])
setassets!(:development, :phemex, ["BTC/USDT", "ETH/USDT"])

# Get current assets
current_assets = get_current_assets()
```

## Environment Variables

StrategyFramework recognizes the following environment variables:

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `STRATEGY_ID` | Strategy identifier for logging and configuration | "StrategyFramework" | "my_strategy" |
| `ASSETS_FLAG` | Asset configuration flag | "default" | "production" |
| `WATCHER_EXC` | Exchange for market data | "phemex" | "binance" |
| `OHLCV_METHOD` | OHLCV data source method | "ccxt" | "ccxt" |
| `PROFILING` | Enable performance profiling | "false" | "true" |

### Setting Environment Variables

#### Linux/macOS
```bash
export STRATEGY_ID="my_strategy"
export ASSETS_FLAG="production"
export WATCHER_EXC="binance"
```

#### Windows
```cmd
set STRATEGY_ID=my_strategy
set ASSETS_FLAG=production
set WATCHER_EXC=binance
```

#### Julia
```julia
ENV["STRATEGY_ID"] = "my_strategy"
ENV["ASSETS_FLAG"] = "production"
ENV["WATCHER_EXC"] = "binance"
```

## Examples

### Example 1: RSI-Based Strategy

```julia
using StrategyFramework
using Statistics

struct RSIStrategy <: SignalGenerator
    period::Int
    oversold::Float64
    overbought::Float64
    
    RSIStrategy(period=14, oversold=30.0, overbought=70.0) = new(period, oversold, overbought)
end

function calculate_rsi(prices::Vector{Float64}, period::Int)
    gains = Float64[]
    losses = Float64[]
    
    for i in 2:length(prices)
        change = prices[i] - prices[i-1]
        push!(gains, max(change, 0.0))
        push!(losses, max(-change, 0.0))
    end
    
    if length(gains) < period
        return 50.0  # Neutral RSI if not enough data
    end
    
    avg_gain = mean(gains[end-period+1:end])
    avg_loss = mean(losses[end-period+1:end])
    
    if avg_loss == 0.0
        return 100.0
    end
    
    rs = avg_gain / avg_loss
    rsi = 100.0 - (100.0 / (1.0 + rs))
    return rsi
end

function generate_buy_signal(sg::RSIStrategy, s::SC, ai, ats)
    ohlcv = s.universe[ai].ohlcv
    
    if length(ohlcv.close) < sg.period + 1
        return false
    end
    
    rsi = calculate_rsi(ohlcv.close, sg.period)
    return rsi < sg.oversold
end

function generate_sell_signal(sg::RSIStrategy, s::SC, ai, ats)
    ohlcv = s.universe[ai].ohlcv
    
    if length(ohlcv.close) < sg.period + 1
        return false
    end
    
    rsi = calculate_rsi(ohlcv.close, sg.period)
    return rsi > sg.overbought
end

function should_trade(sg::RSIStrategy, s::SC, ai, ats)
    # Don't trade if we don't have enough data
    ohlcv = s.universe[ai].ohlcv
    return length(ohlcv.close) >= sg.period + 1
end
```

### Example 2: Multi-Timeframe Strategy

```julia
struct MultiTimeframeStrategy <: SignalGenerator
    short_tf_period::Int
    long_tf_period::Int
    
    MultiTimeframeStrategy(short=5, long=20) = new(short, long)
end

function generate_buy_signal(sg::MultiTimeframeStrategy, s::SC, ai, ats)
    # Get data for different timeframes
    ohlcv_1m = s.universe[ai].ohlcv  # 1-minute data
    
    # Calculate short-term trend (last 5 minutes)
    if length(ohlcv_1m.close) < sg.short_tf_period
        return false
    end
    
    short_trend = ohlcv_1m.close[end] > mean(ohlcv_1m.close[end-sg.short_tf_period+1:end])
    
    # Calculate long-term trend (last 20 minutes)
    if length(ohlcv_1m.close) < sg.long_tf_period
        return false
    end
    
    long_trend = mean(ohlcv_1m.close[end-sg.short_tf_period+1:end]) > 
                 mean(ohlcv_1m.close[end-sg.long_tf_period+1:end-sg.short_tf_period])
    
    # Buy when both short and long term trends are up
    return short_trend && long_trend
end

function generate_sell_signal(sg::MultiTimeframeStrategy, s::SC, ai, ats)
    # Similar logic but for sell signals
    ohlcv_1m = s.universe[ai].ohlcv
    
    if length(ohlcv_1m.close) < sg.long_tf_period
        return false
    end
    
    short_trend = ohlcv_1m.close[end] < mean(ohlcv_1m.close[end-sg.short_tf_period+1:end])
    long_trend = mean(ohlcv_1m.close[end-sg.short_tf_period+1:end]) < 
                 mean(ohlcv_1m.close[end-sg.long_tf_period+1:end-sg.short_tf_period])
    
    return short_trend && long_trend
end
```

### Example 3: Position Management Integration

```julia
using StrategyFramework

struct PositionAwareStrategy <: SignalGenerator
    volatility_threshold::Float64
    trend_strength_min::Float64
    
    PositionAwareStrategy() = new(0.03, 0.6)
end

function generate_buy_signal(sg::PositionAwareStrategy, s::SC, ai, ats)
    # Use position management utilities
    position_adjustment = calculate_position_adjustment(s, ai, ats)
    target_size = get_target_position_size(s, ai, Long(), ats)
    
    # Only buy if position adjustment suggests favorable conditions
    if position_adjustment > 1.0 && target_size > ai.limits.amount.min
        # Your signal logic here
        return 0.8
    else
        return 0.2
    end
end

function generate_sell_signal(sg::PositionAwareStrategy, s::SC, ai, ats)
    # Check if we should reduce position size
    current_amount = trade_amount(s, ai, ats, Long())
    target_size = get_target_position_size(s, ai, Long(), ats)
    
    if current_amount > target_size * 1.2  # 20% over target
        return 0.9  # Strong sell signal to reduce position
    else
        return 0.1
    end
end
```

### Example 4: Data Management Integration

```julia
struct DataDrivenStrategy <: SignalGenerator
    pnl_lookback::Int
    trend_confirmation::Bool
    
    DataDrivenStrategy() = new(14, true)
end

function generate_buy_signal(sg::DataDrivenStrategy, s::SC, ai, ats)
    # Use data management utilities
    track_pnl!(s, ai, ats, now())
    track_trends!(s, ai, ats)
    
    # Access trend data
    if haskey(s.trend_data, ai)
        trend_info = s.trend_data[ai]
        if trend_info[:direction] == :up && trend_info[:strength] > 0.02
            return 0.8
        end
    end
    
    return 0.3
end

function generate_sell_signal(sg::DataDrivenStrategy, s::SC, ai, ats)
    # Check PnL history for exit signals
    if haskey(s.pnl_history, ai) && !isempty(s.pnl_history[ai])
        recent_pnl = s.pnl_history[ai][end]
        if recent_pnl < -0.05  # 5% loss
            return 0.9  # Strong sell signal
        end
    end
    
    return 0.2
end
```

### Example 5: Risk-Aware Strategy

```julia
struct RiskAwareStrategy <: SignalGenerator
    max_drawdown::Float64
    max_position_size::Float64
    
    RiskAwareStrategy(max_dd=0.05, max_pos=0.1) = new(max_dd, max_pos)
end

function should_trade(sg::RiskAwareStrategy, s::SC, ai, ats)
    # Check current drawdown
    current_cash = s.cash[]
    peak_cash = get(s.config, :peak_cash, current_cash)
    
    if peak_cash > 0
        drawdown = (peak_cash - current_cash) / peak_cash
        if drawdown > sg.max_drawdown
            @info "Trading halted due to drawdown" drawdown=drawdown max_allowed=sg.max_drawdown
            return false
        end
    end
    
    # Check position size
    pos = position(s, ai)
    if abs(pos.size) / current_cash > sg.max_position_size
        @info "Position size limit reached" current_size=abs(pos.size)/current_cash max_allowed=sg.max_position_size
        return false
    end
    
    return true
end

function generate_buy_signal(sg::RiskAwareStrategy, s::SC, ai, ats)
    # Your buy signal logic here
    # This will only be called if should_trade returns true
    return some_buy_condition
end

function generate_sell_signal(sg::RiskAwareStrategy, s::SC, ai, ats)
    # Your sell signal logic here
    return some_sell_condition
end
```

## Module Structure

```
src/
├── StrategyFramework.jl     # Main strategy module and exports
├── core/
│   ├── types.jl             # Core types and constants
│   ├── environment.jl       # Environment management
│   ├── initialization.jl    # Strategy initialization
│   ├── parameters.jl        # Parameter management
│   └── configuration.jl     # Configuration management
├── trading/
│   ├── position_management.jl  # Position sizing and management
│   ├── order_management.jl     # Order execution and handling
│   ├── risk_management.jl      # Risk controls and limits
│   └── market_making.jl        # Market making utilities
├── data/
│   ├── ohlcv_management.jl     # OHLCV data handling
│   ├── pnl_tracking.jl        # PnL calculation and tracking
│   └── trend_detection.jl     # Trend analysis utilities
├── utilities/
│   ├── async_utils.jl          # Async operation helpers
│   ├── math_utils.jl           # Mathematical calculations
│   ├── logging_utils.jl        # Logging and debugging
│   └── profiling_utils.jl      # Performance profiling
├── interfaces/
│   └── signal_interface.jl     # Signal generation interface
└── integration/
    ├── telegram_integration.jl # Telegram bot integration
    └── exchange_management.jl  # Exchange configuration
```

## API Reference

### Core Functions

#### Signal Generation
- `generate_buy_signal(sg, s, ai, ats)` - Generate buy signals
- `generate_sell_signal(sg, s, ai, ats)` - Generate sell signals
- `should_trade(sg, s, ai, ats)` - Check if trading is allowed
- `get_signal_lifetime(sg)` - Get signal lifetime

#### Strategy Lifecycle
- `initialize_strategy!(s, sg)` - Initialize strategy
- `reset_strategy!(s, sg)` - Reset strategy state
- `poll_strategy!(s, sg, ts)` - Main strategy polling loop

#### Configuration Management
- `load_configuration!(manager, file)` - Load configuration from file
- `get_config_value(manager, key)` - Get configuration value
- `set_config_value!(manager, key, value)` - Set configuration value
- `apply_configuration_to_strategy!(manager, s)` - Apply config to strategy

#### Environment Management
- `env_strategy_id()` - Get strategy ID from environment
- `env_assets_flag()` - Get assets flag from environment
- `setassets!(flag, exchange, assets)` - Set asset configuration
- `get_current_assets()` - Get current asset configuration

#### Parameter Management
- `register_parameter!(spec)` - Register parameter specification
- `set_parameter!(name, value)` - Set parameter value
- `get_parameter(name, default)` - Get parameter value
- `convert_params_to_float_vector(params)` - Convert for optimization

### Utility Functions

#### Mathematical Utilities
- `getincr(price, exchange)` - Get price increment
- `baseincr(price, exchange)` - Get base increment
- `tftodelay(timeframe)` - Convert timeframe to delay

#### Async Utilities
- `liveasync(f, args...)` - Strategy-appropriate async execution
- `livelock(f, lock)` - Strategy-appropriate locking
- `livesleep(duration)` - Strategy-appropriate sleep

#### Logging Utilities
- `log_trade_action(action, details)` - Log trading actions
- `log_signal_debug(signal_type, details)` - Log signal debugging
- `log_error_with_context(error, context)` - Log errors with context

#### Profiling Utilities
- `with_profiling(f, s; kwargs...)` - Execute function with optional performance profiling
- `enable_profiling!(enabled)` - Enable or disable profiling globally
- `is_profiling_enabled()` - Check if profiling is currently enabled
- `configure_profiling(; sample_rate, max_samples)` - Configure profiling parameters
- `profile_strategy_operation(f, name, s)` - Profile common strategy operations
- `profile_if_slow(f, threshold)` - Profile function only if execution is slow

Example usage:
```julia
# Enable profiling
enable_profiling!(true)

# Profile a trading operation
result = with_profiling(s, profile_name="signal_generation") do
    generate_complex_signals()
end

# Profile only slow operations
result = profile_if_slow(Second(1), profile_name="data_processing") do
    process_large_dataset()
end
```

## Advanced Integration Examples

### Order Management Integration

```julia
# Example: Custom order execution with comprehensive error handling
function execute_smart_trade!(s::SC, ai, side, amount, ats, ts)
    # Validate trade parameters first
    errors = validate_trade_parameters(s, ai, amount, closeat(ai, ats))
    if errors !== nothing
        for error in errors
            send_error_notification(s, error, "VALIDATION_ERROR")
        end
        return nothing
    end
    
    # Calculate optimal leverage based on market conditions
    market_conditions = Dict(
        :volatility => calculate_volatility(s, ai),
        :trend_strength => get_trend_strength(s, ai)
    )
    leverage = calculate_leverage_adjustment(s, ai, s.def_lev, market_conditions)
    
    # Execute trade with error handling
    try
        result = trade!(s, ai, ats, ts; 
                       pos = Long(), 
                       side = side, 
                       amount = amount,
                       leverage = leverage)
        
        if result !== nothing
            # Send success notification
            trade_data = Dict(
                "side" => string(side),
                "amount" => amount,
                "price" => closeat(ai, ats),
                "leverage" => leverage,
                "timestamp" => ts,
                "order_id" => result.id
            )
            send_trade_notification(s, ai, trade_data)
        end
        
        return result
    catch e
        handle_order_error(s, ai, nothing, e)
        send_error_notification(s, string(e), "ORDER_ERROR")
        return nothing
    end
end
```

### Telegram Integration Setup

```julia
# Example: Complete Telegram monitoring setup
function setup_comprehensive_monitoring!(s::SC)
    # Start Telegram integration
    if start_telegram(s)
        println("✓ Telegram monitoring enabled")
        
        # Send detailed startup notification
        startup_msg = """
        🚀 **Strategy Started**
        
        **Name:** $(s.config.strategy_id)
        **Assets:** $(length(s.universe)) pairs
        **Mode:** $(issim(s) ? "Simulation" : "Live")
        **Balance:** \$$(s.balance)
        **Leverage:** $(s.def_lev)x
        **Time:** $(now())
        """
        send_telegram_notification(s, startup_msg, :startup)
        
        # Schedule regular performance updates
        @async begin
            while s.running
                sleep(3600)  # Every hour
                performance_data = calculate_performance_metrics(s)
                send_performance_update(s, performance_data)
            end
        end
        
        return true
    else
        @warn "Failed to start Telegram monitoring"
        return false
    end
end

# Example: Custom risk alert notifications
function send_risk_alert!(s::SC, ai, risk_level::String, details::Dict)
    if !is_telegram_available(s)
        return false
    end
    
    risk_emoji = risk_level == "HIGH" ? "🚨" : "⚠️"
    
    message = """
    $risk_emoji **Risk Alert: $risk_level**
    
    **Asset:** $(ai.symbol)
    **Position:** $(get(details, "position", "None"))
    **Drawdown:** $(get(details, "drawdown", "N/A"))%
    **Volatility:** $(get(details, "volatility", "N/A"))%
    **Action:** $(get(details, "action", "Monitor"))
    
    **Time:** $(now())
    """
    
    return send_telegram_notification(s, message, :risk_alert)
end
```

### Data Management Integration

```julia
# Example: Comprehensive data tracking and analysis
function analyze_strategy_performance!(s::SC)
    performance_summary = Dict()
    
    for ai in s.universe
        # Track PnL and trends
        track_pnl!(s, ai, now(), now())
        track_trends!(s, ai, now())
        
        # Calculate asset-specific metrics
        if haskey(s.pnl_history, ai) && !isempty(s.pnl_history[ai])
            pnl_data = s.pnl_history[ai]
            
            performance_summary[ai] = Dict(
                "total_return" => sum(pnl_data),
                "avg_return" => mean(pnl_data),
                "volatility" => std(pnl_data),
                "win_rate" => count(x -> x > 0, pnl_data) / length(pnl_data),
                "max_drawdown" => minimum(cumsum(pnl_data) .- cummax(cumsum(pnl_data)))
            )
        end
        
        # Add trend information
        if haskey(s.trend_data, ai)
            trend_info = s.trend_data[ai]
            performance_summary[ai]["trend_direction"] = trend_info[:direction]
            performance_summary[ai]["trend_strength"] = trend_info[:strength]
        end
    end
    
    return performance_summary
end
```

## Testing

StrategyFramework includes comprehensive tests. Run them with:

```julia
using Pkg
Pkg.test("StrategyFramework")
```

### Test Categories

1. **Unit Tests**: Test individual functions and utilities
2. **Integration Tests**: Test strategy lifecycle and signal integration
3. **Configuration Tests**: Test configuration management
4. **Parameter Tests**: Test parameter management and optimization

### Running Specific Tests

```julia
# Run only utility tests
include("test/test_math_utils.jl")
include("test/test_async_utils.jl")

# Run configuration tests
include("test/test_configuration.jl")
include("test/test_environment.jl")
```

## Migration from SurgeV4

See the [Migration Guide](MIGRATION.md) for detailed instructions on migrating from SurgeV4 to StrategyFramework.

### Key Differences

1. **Signal Interface**: SurgeV4's signal logic is now abstracted into the `SignalGenerator` interface
2. **Modular Structure**: Code is organized into focused modules instead of a monolithic file
3. **Configuration Management**: Enhanced configuration system with environment support
4. **Parameter Management**: Improved parameter handling with optimization support

### Quick Migration Steps

1. Extract your signal logic from SurgeV4
2. Implement the `SignalGenerator` interface
3. Update configuration to use new environment variables
4. Test with the new framework

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Market Making

StrategyFramework includes comprehensive market making capabilities for providing liquidity while managing inventory risk.

### Basic Market Making

```julia
# Enable market making in your strategy
function poll_strategy!(s::SC, sg::SignalGenerator, ts::DateTime)
    for (ai, _) in s.universe
        # Check if market making conditions are met
        if should_market_make(s, ai, ts)
            # Execute market making
            result = market_make(s, ai, ts, ts; 
                               target_spread_pct=0.002,  # 0.2% spread
                               max_position_pct=0.1)     # 10% max position
            
            if result.success
                @info "Market making orders placed" ai=ai spread=result.spread_used
            end
        end
    end
end
```

### Market Making Configuration

```julia
# Configure market making parameters
s.config[:enable_market_making] = true
s.config[:mm_base_order_pct] = 0.02        # 2% of cash per order
s.config[:max_mm_single_order_pct] = 0.05  # 5% max single order
s.config[:min_mm_spread] = 0.0005          # 0.05% minimum spread
s.config[:max_mm_spread] = 0.01            # 1% maximum spread
s.config[:mm_cooldown] = Minute(5)         # 5 minute cooldown between MM
s.config[:inventory_adjustment_strength] = 0.5  # 50% inventory adjustment
```

### Advanced Market Making Features

#### Inventory Management
The framework automatically adjusts order sizes based on current position to manage inventory risk:

```julia
# Long position reduces buy orders, increases sell orders
# Short position increases buy orders, reduces sell orders
amounts = get_make_amounts(s, ai, 0.1)  # 10% max position
```

#### Dynamic Spread Adjustment
Spreads automatically adjust based on market conditions:

```julia
# Spreads widen with:
# - Higher volatility
# - Lower volume
# - Market stress conditions

optimal_spread = calculate_optimal_spread(s, ai, target_spread, market_conditions)
```

#### Market Making Functions

- `market_make(s, ai, ats, ts; kwargs...)` - Execute market making strategy
- `should_market_make(s, ai, ats)` - Check if conditions are suitable for market making
- `ensure_market_make(s, ai, ats, ts)` - Ensure market making orders are active
- `get_make_amounts(s, ai, max_position_pct)` - Calculate optimal order amounts
- `calculate_optimal_spread(s, ai, target_spread, conditions)` - Calculate dynamic spreads
- `analyze_market_making_conditions(s, ai)` - Analyze current market conditions

### Development Setup

```bash
# Clone the repository
git clone <repository-url>
cd StrategyFramework

# Install dependencies
julia --project -e "using Pkg; Pkg.instantiate()"

# Run tests
julia --project -e "using Pkg; Pkg.test()"
```

## License

This project is part of the Planar.jl ecosystem. See the main Planar.jl repository for license information.

## Support

For support and questions:
1. Check the documentation and examples above
2. Review the test files for usage patterns
3. Consult the main Planar.jl documentation
4. Open an issue in the repository