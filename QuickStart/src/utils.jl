# Core Planar imports
using Planar
using Planar.Engine
using Planar.Engine.Executors
using Planar.Engine.Executors.Instruments
using Planar.Engine.OrderTypes
using Planar.Engine.Strategies
using Planar.Engine.Lang
using Planar.Engine.Misc
using Planar.Remote

# Planar.Engine specific imports
using Planar.Engine: DateTime, Millisecond
using Planar.Engine.Executors:
    AnyPostOnlyOrder,
    AnyImmediateOrder,
    CancelOrders,
    PositionClose,
    UpdateLeverage,
    call!,
    values
using Planar.Engine.Executors: cash, position, isopen, posside, opposite, collateral, value
using Planar.Engine.Executors.Instruments: freecash
using Planar.Engine.OrderTypes:
    Order,
    OrderError,
    OrderCanceled,
    BuyOrSell,
    ReduceOrder,
    IncreaseOrder,
    Buy,
    Sell,
    GTCOrder
using Planar.Engine.OrderTypes: orderside, islong, isshort
using Planar.Engine.Strategies: Strategy
using Planar.Engine.Lang: withoutkws
using Planar.Engine: raw
using PlanarStrategyTools: select_ordertype, livesleep

# Planar utility imports

# QuickStart was written against a level-first logging API (`@ldebug level "msg"`),
# but Planar's current macros are strategy-first (`@ldebug s "msg"`). Compatibility
# shims forward to Base logging, ignoring the leading level argument.
macro ldebug(args...)
    quote
        @debug $(esc(args[2])) $(esc.(args[3:end])...)
    end
end
macro linfo(args...)
    quote
        @info $(esc(args[2])) $(esc.(args[3:end])...)
    end
end
macro lwarn(args...)
    quote
        @warn $(esc(args[2])) $(esc.(args[3:end])...)
    end
end
macro lerror(args...)
    quote
        @error $(esc(args[2])) $(esc.(args[3:end])...)
    end
end
using Planar.Engine.Misc: @kwdef, DFT
using Planar.Engine.Lang: @deassert

# External package imports
using PlanarStrategyTools
using PlanarStrategyTools: Trade, TradeResult

const PROFILING = Ref(false)
const REVISE_CALLBACK = Ref{Any}(nothing)

const STRATEGY_MODULE = nameof(@__MODULE__)
# Define a generic strategy type that can be used by any strategy
if !isdefined(@__MODULE__, :SC)
    const SC{E,M,R} = Strategy{M,STRATEGY_MODULE,E,R}
end

# Refactored env_ functions to not accept any arguments, using module-level constants

# All env_ functions now use STRATEGY_ID from ENV

env_strategy_id() = get(ENV, "STRATEGY_ID", "default")
env_assets_flag() = Symbol(get(ENV, string(env_strategy_id(), "_ASSETS_FLAG"), "default"))
env_watcher_exc() = get(ENV, string(env_strategy_id(), "_WATCHER_EXC"), "bybit") |> Symbol
env_ohlcv_method() = get(ENV, string(env_strategy_id(), "_OHLCV_METHOD"), "candles") |> Symbol

const ASSETS_CT = Dict{Tuple{Symbol,Symbol},Vector{String}}()
const ASSETS_FLAG = Ref(env_assets_flag())
const WATCHER_EXC = Ref(env_watcher_exc())
const OHLCV_METHOD = Ref(env_ohlcv_method())

function __init__()
    if hasproperty(Main, :Profile) && get(ENV, "STRATEGY_PROFILING", "0") == "1"
        PROFILING[] = true
    end
    ASSETS_FLAG[] = env_assets_flag()
end

function setassets!(kind::Option{Symbol}=nothing)
    ASSETS_FLAG[] = isnothing(kind) ? env_assets_flag() : kind
    empty!(ASSETS_CT)
end

liveasync(f::Function, ::Planar.RTStrategy) = @async f()
liveasync(f::Function, ::Planar.SimStrategy) = f()
livelock(l::ReentrantLock, s::Planar.RTStrategy) = lock(s)
livelock(l::ReentrantLock, s::Planar.SimStrategy) = nothing

function closeposition!(s::SC, ai, ts; pside=posside(ai))
    closed = true
    if !isnothing(pside) && isopen(ai, pside)
        closed = call!(s, ai, pside, ts, PositionClose(); fees=simfees(s, GTCOrder))
        call!(s, ai, s.def_lev, UpdateLeverage(); pos=pside, synced=true)
    end
    return closed
end

function handle_fail(s::SC, ai, ats, ts; kwargs=(;), pside, ot, amount)
    this_kwargs = withoutkws(:price; kwargs=pairs(kwargs))
    if !(ot <: ReduceOrder)
        @lerror 1 "$(id(s)): only handle fails for reduce orders" ai ot
        return nothing
    end
    this_ot, _ = select_ordertype(s, orderside(ot), posside(ot); t=:gtc)
    liveasync(s) do
        t = call!(s, ai, this_ot; amount, date=ts, fees=simfees(s, this_ot), this_kwargs...)
        if isnothing(t)
            @lerror 1 "$(id(s)): failed to reduce position attempting last full close" ai
            closeposition!(s, ai, ts; pside)
            if isopen(ai, pside)
                @lerror 1 "$(id(s)): last position close attempt failed" pside ai ts
            end
        end
    end
end

function cancelorders!(s::SC, ai; side=BuyOrSell)
    tries = 1
    while tries < 3
        if call!(s, ai, CancelOrders(); t=side)
            return true
        end
        livesleep(s, 1)
        tries += 1
    end
    return false
end

function check_posside(s::Planar.RTStrategy, ai, ats; ot, t)
    if t isa Trade
        check_1 = posside(t.order) != posside(ot)
        check_2 = isshort(t) && isshort(ot)
        check_3 = islong(t) && islong(ot)
        if check_1 || !(check_2 || check_3)
            @lerror 1 "$(id(s)): trade order side mismatch" ai ats t.order ot check_1 check_2 check_3
        end
    elseif ismissing(t)
        for o in values(s, ai, orderside(ot))
            if o.date >= ats
                check_1 = posside(o) != posside(ot)
                check_2 = isshort(o) && isshort(ot)
                check_3 = islong(o) && islong(ot)
                if check_1 || !(check_2 || check_3)
                    @lerror 1 "$(id(s)): order side mismatch" ai ats o ot check_1 check_2 check_3
                end
            end
        end
    end
end

check_posside(s::Planar.SimStrategy, ai, ats; ot, t) = nothing

function with_profiling(f::Function, s::SC, ts)
    if hasproperty(Main, :Profile)
        @warn "$(id(s)): Profiling activated!" maxlog = 1
        try
            Main.Profile.start_timer()
            f()
        finally
            Main.Profile.stop_timer()
        end
    else
        f()
    end
end

function start_telegram(s::SC)
    try
        Remote.tgstart!(s)
    catch
        @warn "$(id(s)): failed to start telegram (env vars not set?)"
    end
end

function simfees(s::SC, t)
    if t <: AnyPostOnlyOrder
        s.sim_fees_maker
    else
        s.sim_fees_taker
    end
end

function opt!()
    prev = Base.active_project()
    Main.Pkg.activate(dirname(@__DIR__); io=devnull)
    try
        file_path = joinpath(dirname(@__DIR__), "src", "opt.jl")
        include(file_path)
        if !isnothing(REVISE_CALLBACK[])
            Main.Revise.remove_callback(REVISE_CALLBACK[])
        end
        REVISE_CALLBACK[] = Main.Revise.add_callback(opt!, [file_path])
    finally
        Main.Pkg.activate(prev; io=devnull)
    end
end

tftodelay(tf) =
    let u = round(Int, period(tf"1m") / period(tf))
        rand((u * 5):(u * 10))
    end