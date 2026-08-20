# Core types and constants for StrategyFramework

using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Planar
using PlanarStrategyTools: PlanarStrategyTools as stt
using .stt: oti

# Generic strategy type that can be used by any strategy
const SC{E,M,R} = Strategy{M,STRATEGY_MODULE,E,R}

const MovingExtrema = stt.MovingExtrema
const WMA = oti.WMA

# Environment configuration constants
const ASSETS_CT = Dict{Tuple{Symbol,Symbol},Vector{String}}()
const ASSETS_FLAG = Ref{Symbol}(:default)
const WATCHER_EXC = Ref{Symbol}(:binance)
const OHLCV_METHOD = Ref{Symbol}(:candles)

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
    extremas::Dict{InstrumentInstance, MovingExtrema} = Dict{InstrumentInstance, MovingExtrema}()
    hl_trackers::Dict{InstrumentInstance, Tuple{Ref{DateTime}, WMA}} = Dict{InstrumentInstance, Tuple{Ref{DateTime}, WMA}}()
    backoff::Dict{InstrumentInstance, DateTime} = Dict{InstrumentInstance, DateTime}()
    uni_iter::Tuple{Vector{InstrumentInstance}, Ref{DateTime}} = (InstrumentInstance[], Ref(DateTime(0)))
end

# Performance metrics structure
@kwdef mutable struct PerformanceMetrics
    pnl_history::Dict{InstrumentInstance, CircularBuffer} = Dict{InstrumentInstance, CircularBuffer}()
    trade_history::Dict{InstrumentInstance, Vector{Trade}} = Dict{InstrumentInstance, Vector{Trade}}()
    peak_cash::Float64 = 0.0
    max_drawdown::Float64 = 0.0
    total_trades::Int = 0
    winning_trades::Int = 0
end