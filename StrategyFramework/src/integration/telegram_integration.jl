"""
Telegram integration utilities for StrategyFramework.

This module provides Telegram bot integration for remote monitoring and control
of trading strategies, including notification utilities and remote control hooks.
"""

# Import from parent module when included
# using ..StrategyFramework: SC, StrategyConfig
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Logging

# Import Remote module functionality if available
const REMOTE_AVAILABLE = Ref(false)
const Remote = Ref{Union{Nothing, Module}}(nothing)

function __init_telegram__()
    try
        # Try to load Remote module
        Remote[] = Base.require(Main, :Remote)
        REMOTE_AVAILABLE[] = true
        @info "StrategyFramework: Telegram integration available via Remote module"
    catch e
        @debug "StrategyFramework: Remote module not available, Telegram integration disabled" exception=e
        REMOTE_AVAILABLE[] = false
    end
end

"""
    start_telegram(s::SC; force_restart=false)

Start Telegram bot integration for remote monitoring and control of the strategy.

This function initializes the Telegram bot client for the given strategy, enabling
remote monitoring capabilities including:
- Strategy status monitoring
- Performance metrics reporting  
- Remote control commands
- Alert notifications

# Arguments
- `s::SC`: The strategy instance
- `force_restart=false`: Whether to force restart if already running

# Environment Variables Required
- `TELEGRAM_BOT_TOKEN`: Bot token from BotFather
- `TELEGRAM_BOT_CHAT_ID`: Chat ID for notifications
- `TELEGRAM_BOT_USERNAME`: (Optional) Allowed username for security

# Returns
- `true` if successfully started
- `false` if failed to start or not available

# Example
```julia
# Start Telegram integration
if start_telegram(s)
    @info "Telegram bot started successfully"
else
    @warn "Failed to start Telegram bot"
end
```
"""
function start_telegram(s::SC; force_restart::Bool=false)
    if !REMOTE_AVAILABLE[]
        @warn "StrategyFramework: Telegram integration not available (Remote module not loaded)"
        return false
    end
    
    try
        # Check if already running and handle restart
        if force_restart
            stop_telegram(s)
        end
        
        # Validate required environment variables
        if !_validate_telegram_config()
            @error "StrategyFramework: Invalid Telegram configuration"
            return false
        end
        
        # Start the Telegram client
        Remote[].tgstart!(s)
        
        # Send startup notification
        send_telegram_notification(s, "🚀 Strategy $(nameof(s)) Telegram monitoring started")
        
        @info "StrategyFramework: Telegram integration started for strategy $(nameof(s))"
        return true
        
    catch e
        @error "StrategyFramework: Failed to start Telegram integration" exception=e
        return false
    end
end

"""
    stop_telegram(s::SC)

Stop Telegram bot integration for the strategy.

# Arguments
- `s::SC`: The strategy instance

# Returns
- `true` if successfully stopped
- `false` if failed to stop or not running
"""
function stop_telegram(s::SC)
    if !REMOTE_AVAILABLE[]
        return false
    end
    
    try
        Remote[].tgstop!(s)
        @info "StrategyFramework: Telegram integration stopped for strategy $(nameof(s))"
        return true
    catch e
        @error "StrategyFramework: Failed to stop Telegram integration" exception=e
        return false
    end
end

"""
    send_telegram_notification(s::SC, message::String; priority=:info)

Send a notification message via Telegram.

# Arguments
- `s::SC`: The strategy instance
- `message::String`: The message to send
- `priority=:info`: Message priority (:info, :warn, :error, :success)

# Returns
- `true` if message sent successfully
- `false` if failed to send
"""
function send_telegram_notification(s::SC, message::String; priority::Symbol=:info)
    if !REMOTE_AVAILABLE[]
        return false
    end
    
    try
        # Add emoji prefix based on priority
        emoji_message = _format_notification_message(message, priority)
        
        # Get Telegram client and send message
        client = Remote[].tgclient(s)
        chat_id = Remote[]._getoption(s, :tgchat_id)
        
        if !ismissing(chat_id)
            Remote[].Telegram.API.sendMessage(client; text=emoji_message, chat_id=chat_id)
            return true
        else
            @warn "StrategyFramework: No Telegram chat_id configured"
            return false
        end
        
    catch e
        @error "StrategyFramework: Failed to send Telegram notification" exception=e message
        return false
    end
end

"""
    send_trade_notification(s::SC, ii, side::Symbol, amount::Float64, price::Float64)

Send a trade execution notification via Telegram.

# Arguments
- `s::SC`: The strategy instance
- `ii`: Instrument instance
- `side::Symbol`: Trade side (:buy or :sell)
- `amount::Float64`: Trade amount
- `price::Float64`: Execution price
"""
function send_trade_notification(s::SC, ii, side::Symbol, amount::Float64, price::Float64)
    if !REMOTE_AVAILABLE[]
        return false
    end
    
    try
        emoji = side == :buy ? "📈" : "📉"
        side_str = uppercase(string(side))
        
        message = """
        $emoji Trade Executed
        Instrument: $(ii)
        Side: $side_str
        Amount: $(round(amount, digits=6))
        Price: $(round(price, digits=6))
        Time: $(Dates.format(now(), "HH:MM:SS"))
        """
        
        return send_telegram_notification(s, message; priority=:info)
        
    catch e
        @error "StrategyFramework: Failed to send trade notification" exception=e
        return false
    end
end

"""
    send_error_notification(s::SC, error_msg::String, context::String="")

Send an error notification via Telegram.

# Arguments
- `s::SC`: The strategy instance
- `error_msg::String`: The error message
- `context::String`: Additional context information
"""
function send_error_notification(s::SC, error_msg::String, context::String="")
    if !REMOTE_AVAILABLE[]
        return false
    end
    
    try
        message = """
        ❌ Strategy Error
        Strategy: $(nameof(s))
        Error: $error_msg
        $(isempty(context) ? "" : "Context: $context")
        Time: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
        """
        
        return send_telegram_notification(s, message; priority=:error)
        
    catch e
        @error "StrategyFramework: Failed to send error notification" exception=e
        return false
    end
end

"""
    send_performance_update(s::SC, pnl::Float64, drawdown::Float64, trades_count::Int)

Send a performance update notification via Telegram.

# Arguments
- `s::SC`: The strategy instance
- `pnl::Float64`: Current PnL
- `drawdown::Float64`: Current drawdown percentage
- `trades_count::Int`: Total number of trades
"""
function send_performance_update(s::SC, pnl::Float64, drawdown::Float64, trades_count::Int)
    if !REMOTE_AVAILABLE[]
        return false
    end
    
    try
        pnl_emoji = pnl >= 0 ? "💰" : "📉"
        
        message = """
        $pnl_emoji Performance Update
        Strategy: $(nameof(s))
        PnL: $(round(pnl, digits=2))
        Drawdown: $(round(drawdown * 100, digits=2))%
        Trades: $trades_count
        Time: $(Dates.format(now(), "HH:MM:SS"))
        """
        
        return send_telegram_notification(s, message; priority=:info)
        
    catch e
        @error "StrategyFramework: Failed to send performance update" exception=e
        return false
    end
end

"""
    setup_telegram_alerts(s::SC, config::StrategyConfig)

Setup automatic Telegram alerts based on strategy configuration.

This function configures automatic notifications for various strategy events
including trades, errors, and performance milestones.

# Arguments
- `s::SC`: The strategy instance
- `config::StrategyConfig`: Strategy configuration
"""
function setup_telegram_alerts(s::SC, config::StrategyConfig)
    if !REMOTE_AVAILABLE[]
        @debug "StrategyFramework: Telegram alerts not available"
        return false
    end
    
    try
        # Store alert configuration in strategy attributes
        if !haskey(s.attrs, :telegram_alerts)
            s.attrs[:telegram_alerts] = Dict{Symbol, Any}()
        end
        
        alerts = s.attrs[:telegram_alerts]
        
        # Configure default alert settings
        alerts[:enabled] = true
        alerts[:trade_notifications] = true
        alerts[:error_notifications] = true
        alerts[:performance_updates] = true
        alerts[:performance_interval] = Hour(1)  # Send performance updates every hour
        alerts[:last_performance_update] = now()
        
        @info "StrategyFramework: Telegram alerts configured for strategy $(nameof(s))"
        return true
        
    catch e
        @error "StrategyFramework: Failed to setup Telegram alerts" exception=e
        return false
    end
end

"""
    is_telegram_available()

Check if Telegram integration is available.

# Returns
- `true` if Telegram integration is available
- `false` if not available
"""
function is_telegram_available()
    return REMOTE_AVAILABLE[]
end

"""
    get_telegram_status(s::SC)

Get the current status of Telegram integration for the strategy.

# Arguments
- `s::SC`: The strategy instance

# Returns
- Dictionary with status information
"""
function get_telegram_status(s::SC)
    status = Dict{Symbol, Any}()
    
    status[:available] = REMOTE_AVAILABLE[]
    status[:running] = false
    status[:client_configured] = false
    
    if REMOTE_AVAILABLE[]
        try
            # Check if client is configured
            token = Remote[]._getoption(s, :tgtoken)
            chat_id = Remote[]._getoption(s, :tgchat_id)
            status[:client_configured] = !ismissing(token) && !ismissing(chat_id)
            
            # Check if task is running
            state = Remote[]._get_state(s)
            if state !== nothing
                status[:running] = !istaskdone(state.task) && state.running[]
            end
            
        catch e
            @debug "StrategyFramework: Error checking Telegram status" exception=e
        end
    end
    
    return status
end

# Private helper functions

function _validate_telegram_config()
    required_vars = ["TELEGRAM_BOT_TOKEN", "TELEGRAM_BOT_CHAT_ID"]
    
    for var in required_vars
        if !haskey(ENV, var) || isempty(ENV[var])
            @error "StrategyFramework: Missing required environment variable: $var"
            return false
        end
    end
    
    return true
end

function _format_notification_message(message::String, priority::Symbol)
    emoji_map = Dict(
        :info => "ℹ️",
        :warn => "⚠️", 
        :error => "❌",
        :success => "✅"
    )
    
    emoji = get(emoji_map, priority, "ℹ️")
    return "$emoji $message"
end

# Initialize Telegram integration on module load
__init_telegram__()