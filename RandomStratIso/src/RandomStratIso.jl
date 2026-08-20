module RandomStratIso

using Planar: @strategyenv!, @contractsenv!
using Statistics: mean

const DESCRIPTION = "RandomStratIso"
const EXC = :bybit

@strategyenv!
@contractsenv!
# @optenv!

const TF = tf"1m"

function call!(s::S, ::ResetStrategy) end

call!(_::S, ::WarmupPeriod) = Day(1)

function ordertp(
    ii, ::BySide{O}=ifelse(P == Long, Buy, Sell), ::ByPos{P}=posside(ii)
) where {O,P}
    ifelse(P == Long, MarketOrder{O}, ShortMarketOrder{O})
end

function call!(s::T, ts::DateTime, ctx) where {T<:SC}
    date = ts
    foreach(s.universe) do ii
        oside = rand((Buy, Sell))
        pside = rand((Long, Short))
        tp = ordertp(ii, oside, pside)
        if isopen(ii)
            if posside(ii) == pside
                tp = ordertp(ii, oside, pside)
                call!(s, ii, tp; amount=float(ii) / 3, date)
            else
                this_pos = position(ii)
                this_side = posside(this_pos)
                while isopen(this_pos)
                    call!(s, ii, this_side, date, PositionClose())
                end
                call!(s, ii, tp; amount=ii.limits.amount.min, date)
            end
        elseif cash(s) > ii.limits.cost.min
            call!(s, ii, tp; amount=ii.limits.amount.min, date)
        end
    end
end

function call!(t::Type{<:SC}, config, ::LoadStrategy)
    assets = marketsid(t)
    config.margin = Isolated()
    sandbox = config.mode == Paper() ? false : config.sandbox
    s = Strategy(@__MODULE__, assets; config, sandbox)
    @assert marginmode(s) == config.margin
    @assert execmode(s) == config.mode
    s[:verbose] = false
    s
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
end

## Optimization
# function call!(s::S, ::OptSetup)
#     (;
#         ctx=Context(Sim(), tf"15m", dt"2020-", now()),
#         params=(),
#         # space=(kind=:MixedPrecisionRectSearchSpace, precision=Int[]),
#     )
# end
# function call!(s::S, params, ::OptRun) end

# function call!(s::S, ::OptScore)::Vector
#     [mt.sharpe(s)]
# end

end
