function call!(s::SC, o::Order, err::OrderError, ai::AssetInstance)
    # @info 2 "surge: order error" o err ai
    pside = posside(o)
    if err isa OrderCanceled
        return nothing
    end
    if o isa ReduceOrder && isopen(ai, pside) && !iszero(cash(ai, pside))
        @lwarn 1 "surge: trade failed" ai = raw(ai) position(ai) o
        ts = apply(s.timeframe, o.date)
        ats = available(s.timeframe, ts)
        amount = abs(cash(position(ai, pside)))
        ot = select_ordertype(s, orderside(o), pside; t=:market)[1]
        handle_fail(s, ai, ats, ts; pside, ot, amount)
    end
end

function call!(tp::Type{<:SC}, ::StrategyMarkets)
    em = execmode(tp)
    eid = exchangeid(tp)
    flag = ASSETS_FLAG[]
    assets = @lget! ASSETS_CT (eid.parameters[1], flag) String[]
    if !isempty(assets)
        assets
    else
        v = if flag === :default
            get_exchange_assets(eid)
        else
            get_custom_assets(flag)
        end
        append!(assets, v)
    end
end

function get_exchange_assets(eid)
    if eid <: ExchangeID{:hyperliquid}
        [
            "BTC/USDC:USDC",
            "ETH/USDC:USDC",
            "SOL/USDC:USDC",
            "ATOM/USDC:USDC",
            "OP/USDC:USDC",
            "ARB/USDC:USDC",
            "PEOPLE/USDC:USDC",
            "STX/USDC:USDC",
            "RUNE/USDC:USDC",
        ]
    elseif eid <: ExchangeID{:bitrue}
        [
            "BTC/USDT:USDT",
            "ETH/USDT:USDT",
            "SOL/USDT:USDT",
            "ATOM/USDT:USDT",
            "OP/USDT:USDT",
            "ARB/USDT:USDT",
            "PEOPLE/USDT:USDT",
            "MANA/USDT:USDT",
            "STX/USDT:USDT",
        ]
    elseif eid <: ExchangeID{:phemex}
        [
            "SOL/USDT:USDT",
            "ATOM/USDT:USDT",
            "ENJ/USDT:USDT",
            "MANA/USDT:USDT",
            "FLOW/USDT:USDT",
            "RUNE/USDT:USDT",
        ]
    else
        [
            "SOL/USDT:USDT",
            "ATOM/USDT:USDT",
            "ENJ/USDT:USDT",
            "OP/USDT:USDT",
            "C98/USDT:USDT",
            "PEOPLE/USDT:USDT",
            "MANA/USDT:USDT",
            "FLOW/USDT:USDT",
            "STX/USDT:USDT",
            "RUNE/USDT:USDT",
        ]
    end
end

function get_custom_assets(flag::Symbol)
    if flag === :phemex_e6
        [
            "THE/USDT:USDT",
            "VINE/USDT:USDT",
            "ZORA/USDT:USDT",
            "LPT/USDT:USDT",
            "DRIFT/USDT:USDT",
            "NOT/USDT:USDT",
            "RUNE/USDT:USDT",
            "FORM/USDT:USDT",
            "1000BONK/USDT:USDT",
            "ZEC/USDT:USDT",
            "1000SATS/USDT:USDT",
            "ICP/USDT:USDT",
            "KAITO/USDT:USDT",
            "BRETT/USDT:USDT",
            "SUN/USDT:USDT",
            "KAIA/USDT:USDT",
            "ORDI/USDT:USDT",
            "BOME/USDT:USDT",
            "MEME/USDT:USDT",
            "S/USDT:USDT",
            "SIGN/USDT:USDT",
            "PYTH/USDT:USDT",
            "SEI/USDT:USDT",
            "VIRTUAL/USDT:USDT",
            "ATH/USDT:USDT",
            "BERA/USDT:USDT",
            "BIO/USDT:USDT",
            "TURBO/USDT:USDT",
            "AIXBT/USDT:USDT",
            "MANA/USDT:USDT",
            "COMP/USDT:USDT",
            "HIFI/USDT:USDT",
            "SUSHI/USDT:USDT",
            "SAND/USDT:USDT",
            "POPCAT/USDT:USDT",
            "VET/USDT:USDT",
            "AEVO/USDT:USDT",
            "KAS/USDT:USDT",
            "MOODENG/USDT:USDT",
            "IMX/USDT:USDT",
            "ENS/USDT:USDT",
            "EIGEN/USDT:USDT",
            "CFX/USDT:USDT",
            "PENGU/USDT:USDT",
            "POL/USDT:USDT",
            "1000FLOKI/USDT:USDT",
            "TIA/USDT:USDT",
            "FIL/USDT:USDT",
            "PEOPLE/USDT:USDT",
            "STRK/USDT:USDT",
            "GALA/USDT:USDT",
            "PNUT/USDT:USDT",
            "JTO/USDT:USDT",
            "TRUMP/USDT:USDT",
            "CAKE/USDT:USDT",
            "ALGO/USDT:USDT",
            "LDO/USDT:USDT",
            "TRX/USDT:USDT",
            "SPX/USDT:USDT",
            "NEIRO/USDT:USDT",
            "DOT/USDT:USDT",
            "APE/USDT:USDT",
            "PUMP/USDT:USDT",
            "ARKM/USDT:USDT",
            "ATOM/USDT:USDT",
            "INJ/USDT:USDT",
            "FET/USDT:USDT",
            "CRV/USDT:USDT",
            "BB/USDT:USDT",
            "IP/USDT:USDT",
            "APT/USDT:USDT",
            "HYPE/USDT:USDT",
            "RENDER/USDT:USDT",
            "AAVE/USDT:USDT",
            "LTC/USDT:USDT",
            "HBAR/USDT:USDT",
            "ZRO/USDT:USDT",
            "NMR/USDT:USDT",
            "UNI/USDT:USDT",
            "FLUID/USDT:USDT",
            "WLD/USDT:USDT",
            "FARTCOIN/USDT:USDT",
            "TON/USDT:USDT",
            "SNX/USDT:USDT",
            "NEAR/USDT:USDT",
            "PENDLE/USDT:USDT",
            "ONDO/USDT:USDT",
            "W/USDT:USDT",
            "WIF/USDT:USDT",
            "BCH/USDT:USDT",
            "TAO/USDT:USDT",
            "1000SHIB/USDT:USDT",
            "ETC/USDT:USDT",
            "ETHFI/USDT:USDT",
            "AVAX/USDT:USDT",
            "XLM/USDT:USDT",
            "ENA/USDT:USDT",
            "LINK/USDT:USDT",
            "ADA/USDT:USDT",
            "ARB/USDT:USDT",
            "1000PEPE/USDT:USDT",
            "DOGE/USDT:USDT",
            "OP/USDT:USDT",
            "SUI/USDT:USDT",
            "BNB/USDT:USDT",
            "XRP/USDT:USDT",
            "SOL/USDT:USDT",
            "ETH/USDT:USDT",
            "BTC/USDT:USDT",
        ]
    elseif flag === :phemex_top20
        "XLM/USDT:USDT",
        "ETHFI/USDT:USDT",
        "TAO/USDT:USDT",
        "WIF/USDT:USDT",
        "ARB/USDT:USDT",
        "ENA/USDT:USDT",
        "1000SHIB/USDT:USDT",
        "ADA/USDT:USDT",
        "FARTCOIN/USDT:USDT",
        "BCH/USDT:USDT",
        "DOGE/USDT:USDT",
        "OP/USDT:USDT",
        "LINK/USDT:USDT",
        "SOL/USDT:USDT",
        "1000PEPE/USDT:USDT",
        "XRP/USDT:USDT",
        "BNB/USDT:USDT",
        "SUI/USDT:USDT",
        "ETH/USDT:USDT",
        "BTC/USDT:USDT"
    else
        throw(ArgumentError("Unknown asset flag: $flag"))
    end
end