module Example

using Planar: @strategyenv!, @optenv!

const DESCRIPTION = "Example"
const EXC = :phemex

@strategyenv!
# @optenv!

include(joinpath(@__DIR__, "..", "..", "common.jl"))

const TF = tf"1m"

call!(s::SC, ::ResetStrategy) = begin
    skip_watcher = attr(s, :skip_watcher, false)
    _reset!(s)
    _initparams!(s)
    _overrides!(s)
    skip_watcher || _tickers_watcher(s)
end
function call!(t::Type{<:SC}, config, ::LoadStrategy)
    s = st.default_load(@__MODULE__, t, config)
    if s isa Union{PaperStrategy,LiveStrategy} && !(attr(s, :skip_watcher, false))
        _tickers_watcher(s)
    end
    s
end

call!(_::SC, ::WarmupPeriod) = Day(1)

_initparams!(s) = begin
    params_index = st.attr(s, :params_index)
    empty!(params_index)
    params_index[:buydiff] = 1
    params_index[:selldiff] = 2
    params_index[:leverage] = 3
end

function call!(s::T, ts::DateTime, _) where {T<:SC}
    date = ts
    foreach(s.universe) do ai
        closepair(s, ai, ai.ats, ind_timeframe(s))
        price = float(ai)
        this_close = _thisclose(ai)
        prev_close = _prevclose(ai)
        if isnothing(prev_close) || !iszero(prev_close)
            isbuy(s, ai, ai.ats) && buy!(s, ai, ai.ats, date)
            issell(s, ai, ai.ats) && sell!(s, ai, ai.ats, date)
            _prevclose!(ai, this_close)
        else
            _prevclose!(ai, nothing)
        end
    end
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["ETH/USDT", "BTC/USDT", "SOL/USDT"]
end

function call!(::SC{ExchangeID{:bybit}}, ::StrategyMarkets)
    ["ETH/USDT", "BTC/USDT", "ATOM/USDT"]
end

function buy!(s, ai, ats, ts)
    for (_ai, at) in ats
        if st.attr(at, :prev_sell, nothing) !== nothing
            st.attr(at, :prev_sell, nothing)
            closepair(s, _ai, ats, ind_timeframe(s))
        end
    end
    buydiff = st.attr(s, :buydiff, 1.01)
    val = float(ai) * buydiff
    ot = select_ordertype(st.attr(s, :ordertype, :fok))
    okwargs = select_orderkwargs(ot, Buy, ai, ats)
    call!(s, ai, ot; amount=val / float(ai), date=ts, okwargs...)
end

function sell!(s, ai, ats, ts)
    selldiff = st.attr(s, :selldiff, 1.005)
    val = float(ai) * selldiff
    ot = select_ordertype(st.attr(s, :ordertype, :fok))
    okwargs = select_orderkwargs(ot, Sell, ai, ats)
    call!(s, ai, ot; amount=val / float(ai), date=ts, okwargs...)
end

function isbuy(s, ai, ats)
    this_close = _thisclose(ai)
    prev_close = _prevclose(ai)
    this_close === nothing && return false
    prev_close === nothing && return false
    prev_close < this_close && this_close > float(ai)
end

function issell(s, ai, ats)
    this_close = _thisclose(ai)
    prev_close = _prevclose(ai)
    this_close === nothing && return false
    prev_close === nothing && return false
    prev_close > this_close && this_close < float(ai)
end

## Optimization
function call!(s::SC, ::OptSetup)
    (;
        ctx=Context(Sim(), tf"15m", dt"2020-01-01", now()),
        params=(;
            buydiff=(kind=:RangeStep, range=1.001:0.001:1.1),
            selldiff=(kind=:RangeStep, range=1.001:0.001:1.1),
        ),
    )
end
function call!(s::SC, params, ::OptRun)
    s[:buydiff] = params[1]
    s[:selldiff] = params[2]
end

function call!(s::SC, ::OptScore)
    [st.sharpe(s), st.profit(s)]
end
weightsfunc(weights) = weights[1] * 0.8 + weights[2] * 0.2

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"]
end

end
