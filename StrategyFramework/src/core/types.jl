# Core types and constants for StrategyFramework

using Dates
using Planar

# Generic strategy type that can be used by any strategy
const SC{E,M,R} = Strategy{M,STRATEGY_MODULE,E,R}

# Environment configuration constants
const ASSETS_CT = Dict{Tuple{Symbol,Symbol},Vector{String}}()
const ASSETS_FLAG = Ref{Symbol}()
const WATCHER_EXC = Ref{Symbol}()
const OHLCV_METHOD = Ref{Symbol}()

# Configuration constants
const PROFILING = Ref(false)

# Strategy configuration structure
@kwdef mutable struct StrategyConfig
    # Trading parameters
    signal_lifetime::Float64 = 0.2
    trade_cooldown::Period = Minute(1)
    order_timeout::Period = Minute(2)
    def_lev::Float64 = 1.0
    
    # Risk management
    reserve_cash_pct::Float64 = 0.1
    peak_cash::Float64 = 0.0
    
    # Execution settings
    ordertype::Symbol = :gtc
    ismake::Bool = true
    
    # Environment settings
    throttle::Period = Second(10)
    sync_history_limit::Int = 0
    watch_idle_timeout::Period = Second(Day(1))
end

# Position tracking structure
@kwdef mutable struct PositionTracker
    extremas::Dict{AssetInstance, MovingExtrema} = Dict{AssetInstance, MovingExtrema}()
    hl_trackers::Dict{AssetInstance, Tuple{Ref{DateTime}, WMA}} = Dict{AssetInstance, Tuple{Ref{DateTime}, WMA}}()
    backoff::Dict{AssetInstance, DateTime} = Dict{AssetInstance, DateTime}()
    uni_iter::Tuple{Vector{AssetInstance}, Ref{DateTime}} = (AssetInstance[], Ref(DateTime(0)))
end

# Performance metrics structure
@kwdef mutable struct PerformanceMetrics
    pnl_history::Dict{AssetInstance, CircularBuffer} = Dict{AssetInstance, CircularBuffer}()
    trade_history::Dict{AssetInstance, Vector{Trade}} = Dict{AssetInstance, Vector{Trade}}()
    peak_cash::Float64 = 0.0
    max_drawdown::Float64 = 0.0
    total_trades::Int = 0
    winning_trades::Int = 0
end