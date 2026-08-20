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
    foreach(s.universe) do ii
        closepair(s, ii, ii.ats, ind_timeframe(s))
        price = float(ii)
        this_close = _thisclose(ii)
        prev_close = _prevclose(ii)
        if isnothing(prev_close) || !iszero(prev_close)
            isbuy(s, ii, ii.ats) && buy!(s, ii, ii.ats, date)
            issell(s, ii, ii.ats) && sell!(s, ii, ii.ats, date)
            _prevclose!(ii, this_close)
        else
            _prevclose!(ii, nothing)
        end
    end
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["ETH/USDT", "BTC/USDT", "SOL/USDT"]
end

function call!(::SC{ExchangeID{:bybit}}, ::StrategyMarkets)
    ["ETH/USDT", "BTC/USDT", "ATOM/USDT"]
end

function buy!(s, ii, ats, ts)
    for (_ii, at) in ats
        if st.attr(at, :prev_sell, nothing) !== nothing
            st.attr(at, :prev_sell, nothing)
            closepair(s, _ii, ats, ind_timeframe(s))
        end
    end
    buydiff = st.attr(s, :buydiff, 1.01)
    val = float(ii) * buydiff
    ot = select_ordertype(st.attr(s, :ordertype, :fok))
    okwargs = select_orderkwargs(ot, Buy, ii, ats)
    call!(s, ii, ot; amount=val / float(ii), date=ts, okwargs...)
end

function sell!(s, ii, ats, ts)
    selldiff = st.attr(s, :selldiff, 1.005)
    val = float(ii) * selldiff
    ot = select_ordertype(st.attr(s, :ordertype, :fok))
    okwargs = select_orderkwargs(ot, Sell, ii, ats)
    call!(s, ii, ot; amount=val / float(ii), date=ts, okwargs...)
end

function isbuy(s, ii, ats)
    this_close = _thisclose(ii)
    prev_close = _prevclose(ii)
    this_close === nothing && return false
    prev_close === nothing && return false
    prev_close < this_close && this_close > float(ii)
end

function issell(s, ii, ats)
    this_close = _thisclose(ii)
    prev_close = _prevclose(ii)
    this_close === nothing && return false
    prev_close === nothing && return false
    prev_close > this_close && this_close < float(ii)
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
