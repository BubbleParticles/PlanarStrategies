module QuickStart
using Core: kwfunc
using Planar
using .Planar.Pkg
using PlanarStrategyTools: PlanarStrategyTools as stt
using .stt: initqt!, inittrends!, initlev!, initpnl!
using .stt: copypnl!, liveloop, livesleep, signals!, signals, getlev, strategy_signal
using .stt: signal_value
using .stt: Up, Down, Stationary, isuptrend, isdowntrend, istrending!, iscrossed, oti
using .stt: trackpnl!, trackqt!
using .stt: belowtotal, hasentrycash, hasexitcash
using .stt: select_ordertype, select_orderkwargs, TradeResult
using .stt: isrecenttrade, isstaleohlcv, isstalesignal
using .stt: InitSimWarmup, SimWarmup

const DESCRIPTION = "QuickStart"
const MARGIN = Isolated
const EXC = :phemex
const TF = tf"1m"
const THREADSAFE = Ref(true)
const CACHED_PARAMS_IDX = Ref(0)

@strategyenv!
@contractsenv!

# after macro defs
include("utils.jl")
include("call_utils.jl")
include("trade_utils.jl")
include("signal_placeholders.jl")

# using Engine.SimMode: SimMode as sm
using .Engine.Simulations: Simulations as sml
using .Engine.Exchanges: Exchanges as exs
using .Engine.OrderTypes: postoside
using .Engine.LiveMode:
    ohlcv_watchers,
    isstarted,
    Watcher,
    sourceohlcv!,
    ensure_propagate!,
    addcallback!,
    stack_propagate_ohlcv_callback,
    addpropagatetask!

# Generic strategy type that can be used by any strategy
const SC{E,M,R} = Strategy{M,STRATEGY_MODULE,E,R}

@kwdef mutable struct LongShortRatio
    long::Int = 0
    short::Int = 0
    ratio::DFT = 0.0
end

@enum ParamsFrom begin
    cache
    ref
end

default_params = ()

get_params_tuple() = let k = get(ENV, "QUICKSTART_PARAMS_KEY", "default_params")
    getglobal(@__MODULE__, Symbol(k))
end

function call!(s::SC, ::ResetStrategy)
    @ldebug 1 "_reset!"
    attrs = s.attrs

    # for backtesting / optimization
    attrs[:sim_fees_taker] = 0.006
    attrs[:sim_fees_maker] = 0.001
    get!(attrs, :isopt, false) # true during optimization

    # Assign non-param defaults directly
    attrs[:throttle] = Second(10)
    # don't sync any closed orders on live start
    attrs[:sync_history_limit] = 0
    # don't replay execution history from storage on start
    attrs[:replay_from_trace] = false
    # each watcher will stop watching for new events after 1 day of inactivity
    attrs[:watch_idle_timeout] = Second(Day(1))

    # which order type to use when executing orders
    attrs[:ordertype] = :gtc
    attrs[:peak_cash] = 0.0
    # fixed cash to reserve for committment/fees
    attrs[:reserve_cash_pct] = 1.0 / length(s.universe)
    get!(attrs, :ismake, true)

    @assert s.timeframe == tf"1m"
    initqt!(s)
    attrs[:qt_base] = inv(length(universe(s)))
    attrs[:hl] = Dict(
        ai => (Ref(DateTime(0)), oti.WMA{DFT}(; period=120)) for ai in s.universe
    )
    # attrs[:slope_window] = 180
    attrs[:extremas] = Dict(ai => stt.MovingExtrema(60) for ai in s.universe)
    attrs[:uni_iter] = ([s.universe...], Ref(DateTime(0)))
    attrs[:backoff] = Dict(ai => DateTime(0) for ai in s.universe)
    attrs[:lsr] = LongShortRatio()
    kama_kwargs = (; period=60, slow_ema_constant_period=15, fast_ema_constant_period=120)
    attrs[:buysigs] = Dict(ai => oti.KAMA{DFT}(; kama_kwargs...) for ai in s.universe)
    attrs[:sellsigs] = Dict(ai => oti.KAMA{DFT}(; kama_kwargs...) for ai in s.universe)
    attrs[:pnl_n] = 21

    call!(s, InitSimWarmup())
    apply_params!(s; from=ref)

    initpnl!(s; n=s.pnl_n)
    initlev!(s)
    initdata!(s)
    setsignals!(s)
end

# setsignals! function is now defined in signal_placeholders.jl
# Users can customize it there to set up their own signals/indicators

function apply_params!(s; from::ParamsFrom=cache)
    # Params override
    if from == cache
        params_idx = CACHED_PARAMS_IDX[]
        if params_idx != 0
            if isdefined(@__MODULE__, :cached_params)
                saved_params = cached_params(s)
                s[:cached_params] = true
                call!(s, saved_params[params_idx], OptRun())
            else
                @warn "QuickStart: cached_params not defined" params_idx
            end
        end
    elseif from == ref
        params_tuple = get_params_tuple()
        params = convert_float_vector_to_params(
            params_tuple, keys(params_tuple), nothing
        )
        for (k, v) in pairs(params)
            s[k] = v
        end
    end
end

function call!(t::Type{<:SC}, config, ::LoadStrategy)
    assets = st.marketsid(t)
    config.margin = Isolated()
    config.timeframes = [timeframe(t) for t in ("1m", "5m", "15m", "1d")]
    sort!(config.timeframes)
    issandboxset = !config.sandbox # if false we assume it's set (because default true)
    s = Strategy(
        @__MODULE__,
        assets;
        config,
        sandbox=(issandboxset ? false : (config.mode != Paper())),
    )
    @assert s isa IsolatedStrategy
    Engine.LiveMode.ohlcvmethod!(s, :average)
    s[:watcher_exchanges] = ["bybit", "binance", "mexc"]
    s[:watcher_ohlcvmethod] = :tickers
    exs.ratelimit!(exchange(s), false)
    call!(s, ResetStrategy())
    for ai in s.universe
        data = ohlcv_dict(ai)
        for tf in config.timeframes
            @lget! data tf Data.empty_ohlcv()
        end
    end
    s
end

call!(_::SC, ::WarmupPeriod) = Day(15)

function call!(s::SC, ::StartStrategy)
    w = ohlcv_watchers(s)
    call!(s, InitSimWarmup())
    if !isnothing(w) && !isstarted(w)
        start!(w)
    end
end

function call!(s::SC, ts::DateTime, _)
    with_profiling(s, ts) do
        poll(s, ts)
    end
end

function initohlcv!(s::RTStrategy)
    # NOTE: bybit ban US ip addresses (only use locally)
    attrs = s.attrs
    watch_exc = WATCHER_EXC[]
    n_candles = attrs[:live_view_capacity] = attrs[:warmup_candles] = 1440 * 16
    @warn "ensure $watch_exc supports pre-fetching $n_candles candles"
    from_strat = attr(s, :ohlcv_source, nothing)
    if from_strat isa Strategy
        sourceohlcv!(s, from_strat)
    else
        call!(s, WatchOHLCV(); exc=getexchange!(watch_exc; s.sandbox))
    end
end

function initdata!(s::Strategy)
    attrs = s.attrs
    # Generate stub funding rate data, only in sim mode
    if !attrs[:isopt] && issim(s)
        isdefined(Main, :Random) && Main.Random.seed!(1)
        attrs[:warmup_candles] = 0
        foreach(s.universe) do ai
            if isempty(ohlcv(ai))
                @warn "Can' stub funding rate without source data." maxlog = 1
            else
                stub!(ai, Val(:funding))
            end
        end
    elseif !issim(s)
        initohlcv!(s)
    end
    # only start telegram if not sim
    if !issim(s)
        start_telegram(s)
    end
end

function iswarm(s::RTStrategy, ai)
    getfield(s, :config)[:warmup][ai]
end

function iswarm(s::SimStrategy, ai)
    true
end

function dowarmup(s, ai=nothing, ats=nothing)
    if islive(s)
        if !isnothing(ai)
            call!(copypnl!, s, ai, ats, SimWarmup(); n_candles=s.warmup_candles)
        else
            ats = @something ats available(s.timeframe, now())
            n_candles = s.warmup_candles
            for ai in universe(s)
                call!(copypnl!, s, ai, ats, SimWarmup(); n_candles)
            end
        end
    end
end

function trackhl!(s, ai, ats)
    data = ohlcv(ai)
    idx = dateindex(data, ats)
    if iszero(idx)
        return nothing
    end
    high = data.high[idx]
    low = data.low[idx]
    spread = high > low ? high / low : low / high
    date, ti = s[:hl][ai]
    if date[] < ats
        date[] = ats
        oti.fit!(ti, spread)
    end
end

function poll(s, ts)
    ats = available(s.timeframe, ts)
    attrs = s.attrs
    signals!(s, ats, Val(:update))

    tf = attrs[:timeframe]
    backoff = attrs[:backoff]
    cooldown = attrs[:trade_cooldown]
    lifetime = attrs[:signal_lifetime]
    pnl_interval = tf * 2 * attrs[:pnl_n]
    order_timeout = attrs[:order_timeout]
    buysigs = attrs[:buysigs]
    sellsigs = attrs[:sellsigs]
    uni_iter, last_sort = attrs[:uni_iter]
    if last_sort[] < ats
        extremas = s.extremas
        sort!(uni_iter; by=ai -> mmvol(s, ai, ats, extremas))
        last_sort[] = ats
    end

    liveloop(s, uni_iter) do ai
        dowarmup(s, ai, ats)
        # cancel orders older than 2 timeframes
        for o in values(s, ai)
            if ts - o.date >= order_timeout
                @ldebug 1 "quickstart: cancelling stale orders"
                cancelorders!(s, ai)
                break
            end
        end

        trackhl!(s, ai, ats)
        # short circuit if a recent trade has been executed or ohlcv is not up-to-date
        if !iswarm(s, ai) ||
            stt.isstaleohlcv(s, ai; ats, tf, backoff) ||
            stt.isstalesignal(s, ats; lifetime)
            # @ldebug 3 "quickstart: stale"
            return nothing
        end
        # pnl at time `ats`
        trackpnl!(s, ai, ats, ts; interval=pnl_interval)
        
        # Note: QuickStart uses placeholder signal functions instead of specific trend checks
        # Users can customize these checks in their signal implementation
        # if !istrending!(s, ai, ats, :sma) ||
        #     !istrending!(s, ai, ats, :vtx) ||
        #     !istrending!(s, ai, ats, :roc)
        #     @ldebug 1 "quickstart: stop hit (or trend fail)" ai
        #     return nothing
        # end
        
        trackqt!(s, ai, ats)

        # Use placeholder signal functions - users can customize these
        buy = isbuy(s, ai, ats)
        sell = issell(s, ai, ats)
        oti.fit!(buysigs[ai], DFT(buy))
        oti.fit!(sellsigs[ai], DFT(sell))

        if stt.isrecenttrade(ai, ats, tf; cd=cooldown)
            return nothing
        end

        thisbuy = @coalesce buysigs[ai].value 0.0
        thissell = @coalesce sellsigs[ai].value 0.0
        ratio = thisbuy / thissell
        if ratio > s[:buy_trigger]
            @ldebug 2 "quickstart: isbuy" ai
            buyorsell!(s, ai, ats, ts, Buy)
        elseif ratio < s[:sell_trigger]
            @ldebug 2 "quickstart: issell" ai
            buyorsell!(s, ai, ats, ts, Sell)
        end
        @ldebug 2 "quickstart: nosignal" ai
        if s.ismake
            ensure_market_make(s, ai, ts; ats)
        end
    end
end

function mmvol(s, ai, ats, exts)
    obj = exts[ai]
    ov = ohlcv(ai)
    idx = dateindex(ov, ats)
    if iszero(idx)
        0.0
    else
        this_vol = volumeat(ai, ats)
        push!(obj, this_vol)
        mn, mx = extrema(obj)
        this_vol - mn / (mx - mn)
    end
end

# ROC calculation functions removed - these were specific to SurgeV4 signals
# Users can implement their own ROC or other indicator calculations as needed

function calculate_position_adjustment(s::SC, ai, ats)
    # Generic position adjustment function - users can customize this
    # to use their own indicators and adjustment logic
    
    # Default implementation: no adjustment (1.0x multiplier)
    # Users can implement their own logic here based on their signals
    
    # Example of how users might implement custom adjustments:
    # if haskey(s.attrs, :signals_def)
    #     # Get custom indicator values
    #     # atr_sig = strategy_signal(s, ai, :my_atr)
    #     # trend_sig = strategy_signal(s, ai, :my_trend)
    #     # Apply custom adjustment logic
    # end
    
    final_mult = 1.0  # Default: no adjustment
    
    # Clamp to reasonable bounds (0.1x to 2.0x)
    final_mult = clamp(final_mult, 0.1, 2.0)

    @ldebug 2 "position adjustment calc" ai final_mult
    return final_mult
end

function get_target_position_size(s::SC, ai, ps::PositionSide, ats)
    # Get the base position size (what it would be without adjustments)
    tot = st.current_total(s)
    drawdown = tot / s.peak_cash
    c = freecash(s)
    c *= 1.0 - s.reserve_cash_pct

    c = let pos = position(ai, ps)
        ai_coll = collateral(pos)
        avl_stake = tot * min(s.qt[ai], s.qt_base) - ai_coll
        # Note: VTX signal reference removed - users can add their own signal logic here
        plus_rate = 1.0  # Default rate, users can customize based on their signals
        min(avl_stake * plus_rate, c * drawdown^13)
    end

    if c <= zero(c)
        return ai.limits.amount.min
    end

    price = closeat(ai, ats)
    base_amount = abs(c / price)

    # Apply adjustment to get target size
    adjustment_mult = calculate_position_adjustment(s, ai, ats)
    target_amount = base_amount * adjustment_mult

    return target_amount
end

peak_cash!(s) = st.modifyattr!(s, st.current_total(s), max, :peak_cash)

function call!(s::SC, ai, trade::Trade, ::NewTrade)
    @ldebug 2 "quickstart: new trade func" ai trade
    lsr = s.lsr
    lsr.long = 0
    lsr.short = 0
    for ai in s.universe
        pside = islong(posside(ai)) ? :long : :short
        setfield!(lsr, pside, getproperty(lsr, pside) + 1)
    end
    lsr.ratio = lsr.long / lsr.short
    peak_cash!(s)
end

function trade_amount(s, ai, ats, ps::PositionSide)
    @ldebug 2 "quickstart: trade amount" ai ps
    lev = getlev(s, ai)
    if lev < one(lev)
        return ai.limits.amount.min
    end
    tot = st.current_total(s)
    # The larger the maximum drawdown, the smaller the trade will be
    drawdown = tot / s.peak_cash
    c = freecash(s)
    c *= 1.0 - s.reserve_cash_pct

    # Check if position is already open
    is_position_open = isopen(ai, ps)

    if is_position_open
        # For existing positions, use target size approach
        target_size = get_target_position_size(s, ai, ps, ats)
        price = closeat(ai, ats)
        c = target_size * price  # Convert back to cash amount

        @ldebug 2 "using target position size" ai target_size c
    end

    @ldebug 2 "quickstart: trade amount" ai c
    c = let pos = position(ai, ps)
        ai_coll = collateral(pos)
        # `qt` is set to be the share of the total cash that can be used
        avl_stake = tot * min(s.qt[ai], s.qt_base) - ai_coll
        # Note: VTX signal reference removed - users can add their own signal logic here
        plus_rate = 1.0  # Default rate, users can customize based on their signals
        @ldebug 2 "quickstart: trade amount" ai avl_stake
        # The cash should not exceed the maximum available stake for the asset
        min(avl_stake * plus_rate, c * drawdown^13)
    end
    # If the cash is less than 1$, do not trade
    c <= zero(c) && return ai.limits.amount.min
    price = closeat(ai, ats)
    amt = abs(c / price)
    amt / lev
end

function calculate_trade_amount(s::SC, ai, ats, ts, side, pos_side)
    # Check if position is already open
    is_position_open = isopen(ai, pos_side)

    if is_position_open
        # Position is open - calculate target size and adjust accordingly
        current_pos = position(ai, pos_side)
        current_size = abs(value(cash(current_pos)))
        target_size = get_target_position_size(s, ai, pos_side, ats)

        # Calculate the adjustment needed with threshold
        size_diff = abs(target_size - current_size)
        size_threshold = max(current_size * 0.1, ai.limits.amount.min)  # 10% of current size or min amount

        if size_diff > size_threshold
            if target_size > current_size
                # Need to increase position
                amount = target_size - current_size
                @ldebug 2 "increasing position size" ai current_size target_size amount size_threshold
            else
                # Need to decrease position
                amount = current_size - target_size
                @ldebug 2 "decreasing position size" ai current_size target_size amount size_threshold
                # If the new target size is at or below min, close the position
                if target_size <= ai.limits.amount.min
                    @ldebug 1 "closing position due to reduction below min" ai current_size target_size amount min_amount =
                        ai.limits.amount.min
                    closeposition!(s, ai, ts; pside=pos_side)
                    return missing, missing
                end
            end
        else
            # No adjustment needed - difference is too small
            amount = 0.0
            @ldebug 2 "no position adjustment needed" ai current_size target_size size_diff size_threshold
        end
    else
        # Position is closed - use trade_amount for new position
        amount = trade_amount(s, ai, ats, pos_side)
    end

    return amount
end

function buyorsell!(s::SC, ai, ats, ts, side)
    @ldebug 2 "quickstart: buyorsell" ai = raw(ai) side
    trade_pos_side = ifelse(side == Buy, Long(), Short())
    @deassert ai.asset.qc == nameof(s.cash)
    p = @something position(ai) position(ai, trade_pos_side)
    amount = 0.0

    if posside(p) == trade_pos_side
        @ldebug 2 "same side" raw(ai) amount
        if hasentrycash(s, ai) && belowtotal(s, ai, p)
            amount = trade_amount(s, ai, ats, trade_pos_side)
            # amount = calculate_trade_amount(s, ai, ats, ts, side, trade_pos_side)

            if amount isa Number && amount > 0.0
                trade!(s, ai, ats, ts; pos=trade_pos_side, side, amount)::TradeResult
            end
        end
    else
        @ldebug 2 "oppo side" raw(ai) amount
        open_pos_side = opposite(trade_pos_side)
        amount = abs(freecash(ai, open_pos_side))
        if amount > 0.0
            trade!(s, ai, ats, ts; pos=open_pos_side, side, amount)::TradeResult
        end
        # amount = calculate_trade_amount(s, ai, ats, ts, side, trade_pos_side)
        amount = trade_amount(s, ai, ats, trade_pos_side)
        trade!(s, ai, ats, ts; pos=trade_pos_side, side, amount)::TradeResult
    end
end

function convert_float_vector_to_params(p, setup)
    convert_float_vector_to_params(collect(values(p)), keys(p), setup.space.categorical)
end

# Convert a float vector of parameter values into a NamedTuple using
# the provided ordered parameter names and optional categorical metadata.
function convert_float_vector_to_params(params, param_names, categorical_info)
    converted_params = NamedTuple()
    param_idx = 1
    for param_name in param_names
        if param_name == :trade_cooldown || param_name == :order_timeout
            converted_params = merge(
                converted_params,
                NamedTuple{(param_name,)}((Minute(round(Int, params[param_idx])),)),
            )
        elseif param_name == :pnl_n
            converted_params = merge(
                converted_params,
                NamedTuple{(param_name,)}((round(Int, params[param_idx]),)),
            )
        elseif param_name == :ordertype
            ordertype_idx = findfirst(x -> x == param_name, param_names)
            ordertype_categories =
                if !isnothing(categorical_info) &&
                    !isnothing(categorical_info[ordertype_idx])
                    categorical_info[ordertype_idx]
                else
                    [:gtc, :fok, :ioc]
                end
            converted_params = merge(
                converted_params,
                NamedTuple{(param_name,)}((
                    ordertype_categories[round(Int, params[param_idx])],
                )),
            )
        else
            converted_params = merge(
                converted_params, NamedTuple{(param_name,)}((params[param_idx],))
            )
        end
        param_idx += 1
    end
    converted_params
end

end
