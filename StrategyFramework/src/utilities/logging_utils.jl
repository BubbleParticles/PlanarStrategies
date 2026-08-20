# Logging utilities for StrategyFramework
# Provides comprehensive logging for trading operations, signals, and errors

using Logging
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Printf
using LoggingExtras: TeeLogger

# Global logger configuration
const STRATEGY_LOGGER = Ref{Union{AbstractLogger, Nothing}}(nothing)
const LOG_LEVEL = Ref{LogLevel}(Logging.Info)
const LOG_TO_FILE = Ref{Bool}(true)
const LOG_FILE_PATH = Ref{String}("strategy_framework.log")

"""
    setup_logging!(level::LogLevel = Logging.Info; 
                   log_to_file::Bool = true,
                   log_file::String = "strategy_framework.log",
                   console_output::Bool = true)

Setup logging configuration for StrategyFramework.

# Arguments
- `level::LogLevel`: Minimum log level (Debug, Info, Warn, Error)
- `log_to_file::Bool`: Whether to log to file
- `log_file::String`: Log file path
- `console_output::Bool`: Whether to also output to console

# Returns
- Nothing
"""
function setup_logging!(level::LogLevel = Logging.Info; 
                       log_to_file::Bool = true,
                       log_file::String = "strategy_framework.log",
                       console_output::Bool = true)
    LOG_LEVEL[] = level
    LOG_TO_FILE[] = log_to_file
    LOG_FILE_PATH[] = log_file
    
    loggers = AbstractLogger[]
    
    # Console logger
    if console_output
        console_logger = ConsoleLogger(stderr, level)
        push!(loggers, console_logger)
    end
    
    # File logger
    if log_to_file
        # Ensure log directory exists
        log_dir = dirname(log_file)
        if !isempty(log_dir) && !isdir(log_dir)
            mkpath(log_dir)
        end
        
        file_logger = SimpleLogger(open(log_file, "a"), level)
        push!(loggers, file_logger)
    end
    
    # Combine loggers if multiple
    if length(loggers) == 1
        STRATEGY_LOGGER[] = loggers[1]
    elseif length(loggers) > 1
        STRATEGY_LOGGER[] = TeeLogger(loggers...)
    else
        STRATEGY_LOGGER[] = NullLogger()
    end
    
    global_logger(STRATEGY_LOGGER[])
end

"""
    log_trade(s::SC, ii, action::String, amount::Real, price::Real; 
              order_id = nothing, side = nothing, kwargs...)

Log trading operations with structured information.

# Arguments
- `s::SC`: Strategy instance
- `ii`: Instrument instance
- `action::String`: Trading action (e.g., "BUY", "SELL", "CANCEL")
- `amount::Real`: Trade amount
- `price::Real`: Trade price
- `order_id`: Optional order ID
- `side`: Optional position side
- `kwargs...`: Additional parameters to log
"""
function log_trade(s::SC, ii, action::String, amount::Real, price::Real; 
                  order_id = nothing, side = nothing, kwargs...)
    timestamp = now()
    strategy_id = string(typeof(s))
    asset_symbol = string(ii)
    
    log_msg = @sprintf("[TRADE] %s | %s | %s | %s | Amount: %.8f | Price: %.8f", 
                      timestamp, strategy_id, asset_symbol, action, amount, price)
    
    if order_id !== nothing
        log_msg *= " | OrderID: $order_id"
    end
    
    if side !== nothing
        log_msg *= " | Side: $side"
    end
    
    # Add additional parameters
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    @info log_msg
end

"""
    log_signal(s::SC, ii, signal_type::String, signal_value; 
               confidence = nothing, lifetime = nothing, kwargs...)

Log signal generation and analysis with detailed information.

# Arguments
- `s::SC`: Strategy instance
- `ii`: Instrument instance
- `signal_type::String`: Type of signal (e.g., "BUY_SIGNAL", "SELL_SIGNAL")
- `signal_value`: Signal value or strength
- `confidence`: Optional confidence level
- `lifetime`: Optional signal lifetime
- `kwargs...`: Additional signal parameters
"""
function log_signal(s::SC, ii, signal_type::String, signal_value; 
                   confidence = nothing, lifetime = nothing, kwargs...)
    timestamp = now()
    strategy_id = string(typeof(s))
    asset_symbol = string(ii)
    
    log_msg = @sprintf("[SIGNAL] %s | %s | %s | %s | Value: %s", 
                      timestamp, strategy_id, asset_symbol, signal_type, signal_value)
    
    if confidence !== nothing
        log_msg *= @sprintf(" | Confidence: %.4f", confidence)
    end
    
    if lifetime !== nothing
        log_msg *= " | Lifetime: $lifetime"
    end
    
    # Add additional parameters
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    @debug log_msg
end

"""
    log_position_update(s::SC, ii, position_size::Real, unrealized_pnl::Real; 
                       realized_pnl = nothing, margin_used = nothing, kwargs...)

Log position updates and PnL changes.

# Arguments
- `s::SC`: Strategy instance
- `ii`: Instrument instance
- `position_size::Real`: Current position size
- `unrealized_pnl::Real`: Unrealized PnL
- `realized_pnl`: Optional realized PnL
- `margin_used`: Optional margin usage
- `kwargs...`: Additional position parameters
"""
function log_position_update(s::SC, ii, position_size::Real, unrealized_pnl::Real; 
                           realized_pnl = nothing, margin_used = nothing, kwargs...)
    timestamp = now()
    strategy_id = string(typeof(s))
    asset_symbol = string(ii)
    
    log_msg = @sprintf("[POSITION] %s | %s | %s | Size: %.8f | UnrealizedPnL: %.8f", 
                      timestamp, strategy_id, asset_symbol, position_size, unrealized_pnl)
    
    if realized_pnl !== nothing
        log_msg *= @sprintf(" | RealizedPnL: %.8f", realized_pnl)
    end
    
    if margin_used !== nothing
        log_msg *= @sprintf(" | MarginUsed: %.8f", margin_used)
    end
    
    # Add additional parameters
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    @info log_msg
end

"""
    log_error(s::SC, ii, error_type::String, error_msg::String; 
              exception = nothing, order_id = nothing, kwargs...)

Log errors with comprehensive context information.

# Arguments
- `s::SC`: Strategy instance
- `ii`: Instrument instance
- `error_type::String`: Type of error (e.g., "ORDER_ERROR", "DATA_ERROR")
- `error_msg::String`: Error message
- `exception`: Optional exception object
- `order_id`: Optional related order ID
- `kwargs...`: Additional error context
"""
function log_error(s::SC, ii, error_type::String, error_msg::String; 
                  exception = nothing, order_id = nothing, kwargs...)
    timestamp = now()
    strategy_id = string(typeof(s))
    asset_symbol = string(ii)
    
    log_msg = @sprintf("[ERROR] %s | %s | %s | %s | %s", 
                      timestamp, strategy_id, asset_symbol, error_type, error_msg)
    
    if order_id !== nothing
        log_msg *= " | OrderID: $order_id"
    end
    
    if exception !== nothing
        log_msg *= " | Exception: $(typeof(exception)) - $exception"
    end
    
    # Add additional context
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    @error log_msg
end

"""
    log_performance(s::SC, total_pnl::Real, win_rate::Real, total_trades::Int; 
                   max_drawdown = nothing, sharpe_ratio = nothing, kwargs...)

Log performance metrics and statistics.

# Arguments
- `s::SC`: Strategy instance
- `total_pnl::Real`: Total profit/loss
- `win_rate::Real`: Win rate percentage
- `total_trades::Int`: Total number of trades
- `max_drawdown`: Optional maximum drawdown
- `sharpe_ratio`: Optional Sharpe ratio
- `kwargs...`: Additional performance metrics
"""
function log_performance(s::SC, total_pnl::Real, win_rate::Real, total_trades::Int; 
                        max_drawdown = nothing, sharpe_ratio = nothing, kwargs...)
    timestamp = now()
    strategy_id = string(typeof(s))
    
    log_msg = @sprintf("[PERFORMANCE] %s | %s | TotalPnL: %.8f | WinRate: %.2f%% | Trades: %d", 
                      timestamp, strategy_id, total_pnl, win_rate, total_trades)
    
    if max_drawdown !== nothing
        log_msg *= @sprintf(" | MaxDrawdown: %.8f", max_drawdown)
    end
    
    if sharpe_ratio !== nothing
        log_msg *= @sprintf(" | SharpeRatio: %.4f", sharpe_ratio)
    end
    
    # Add additional metrics
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    @info log_msg
end

"""
    log_market_data(s::SC, ii, data_type::String, timestamp::DateTime; 
                   price = nothing, volume = nothing, kwargs...)

Log market data updates and quality issues.

# Arguments
- `s::SC`: Strategy instance
- `ii`: Instrument instance
- `data_type::String`: Type of market data (e.g., "OHLCV", "TICKER", "ORDERBOOK")
- `timestamp::DateTime`: Data timestamp
- `price`: Optional price information
- `volume`: Optional volume information
- `kwargs...`: Additional data parameters
"""
function log_market_data(s::SC, ii, data_type::String, timestamp::DateTime; 
                        price = nothing, volume = nothing, kwargs...)
    log_timestamp = now()
    strategy_id = string(typeof(s))
    asset_symbol = string(ii)
    
    log_msg = @sprintf("[DATA] %s | %s | %s | %s | DataTime: %s", 
                      log_timestamp, strategy_id, asset_symbol, data_type, timestamp)
    
    if price !== nothing
        log_msg *= @sprintf(" | Price: %.8f", price)
    end
    
    if volume !== nothing
        log_msg *= @sprintf(" | Volume: %.8f", volume)
    end
    
    # Add additional data
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    @debug log_msg
end

"""
    log_notification(s::SC, notification_type::String, message::String; 
                    urgency = "INFO", recipient = nothing, kwargs...)

Log notifications and alerts (e.g., for Telegram integration).

# Arguments
- `s::SC`: Strategy instance
- `notification_type::String`: Type of notification
- `message::String`: Notification message
- `urgency`: Urgency level ("INFO", "WARNING", "CRITICAL")
- `recipient`: Optional recipient information
- `kwargs...`: Additional notification parameters
"""
function log_notification(s::SC, notification_type::String, message::String; 
                         urgency = "INFO", recipient = nothing, kwargs...)
    timestamp = now()
    strategy_id = string(typeof(s))
    
    log_msg = @sprintf("[NOTIFICATION] %s | %s | %s | %s | %s", 
                      timestamp, strategy_id, notification_type, urgency, message)
    
    if recipient !== nothing
        log_msg *= " | Recipient: $recipient"
    end
    
    # Add additional parameters
    for (key, value) in kwargs
        log_msg *= " | $key: $value"
    end
    
    # Log at appropriate level based on urgency
    if urgency == "CRITICAL"
        @error log_msg
    elseif urgency == "WARNING"
        @warn log_msg
    else
        @info log_msg
    end
end

"""
    create_log_summary(log_file::String; 
                      start_time = nothing, end_time = nothing)

Create a summary of log entries for analysis.

# Arguments
- `log_file::String`: Path to log file
- `start_time`: Optional start time filter
- `end_time`: Optional end time filter

# Returns
- Dictionary with log summary statistics
"""
function create_log_summary(log_file::String; 
                           start_time = nothing, end_time = nothing)
    if !isfile(log_file)
        @warn "Log file not found: $log_file"
        return Dict()
    end
    
    summary = Dict(
        :total_lines => 0,
        :trades => 0,
        :signals => 0,
        :errors => 0,
        :positions => 0,
        :notifications => 0,
        :data_updates => 0,
        :performance_logs => 0
    )
    
    open(log_file, "r") do file
        for line in eachline(file)
            summary[:total_lines] += 1
            
            # Count different log types
            if contains(line, "[TRADE]")
                summary[:trades] += 1
            elseif contains(line, "[SIGNAL]")
                summary[:signals] += 1
            elseif contains(line, "[ERROR]")
                summary[:errors] += 1
            elseif contains(line, "[POSITION]")
                summary[:positions] += 1
            elseif contains(line, "[NOTIFICATION]")
                summary[:notifications] += 1
            elseif contains(line, "[DATA]")
                summary[:data_updates] += 1
            elseif contains(line, "[PERFORMANCE]")
                summary[:performance_logs] += 1
            end
        end
    end
    
    return summary
end
