function baseincr(s, ai; modifier=identity)
    ti = s[:hl][ai][2]
    if ti.n < ti.period
        simfees(s, ot.AnyImmediateOrder)
    else
        abs(1.0 - @coalesce ti.value 0.99) |> modifier
    end
end

function getincr(s, ai, ats; side, base=baseincr(s, ai))
    salt = max(base, sml.spreadat(ai, ats, Val(:edge2)), 0.0)
    return (buy=1.0 - salt, sell=1.0 + salt)
end

function trade!(
    s,
    ai,
    ats,
    ts;
    pos,
    side,
    amount,
    t=:gtc,
    tag="",
    incr=getincr(s, ai, ats; side),
    o_kwargs=select_orderkwargs(:gtc, side, ai, ats; incr),
    o_otsym=select_ordertype(s, side, pos; t),
)
    @assert amount isa Number
    ot, otsym = o_otsym
    @ldebug 2 "trade" ats ot otsym ai = raw(ai) side = posside(pos) amount

    # Check if position is already open
    is_position_open = isopen(ai, pos)

    if is_position_open
        # Use the actual leverage of the open position
        this_lev = leverage(position(ai, pos))
    else
        # Position is closed - adjust leverage for new position
        adjustment_mult = calculate_position_adjustment(s, ai, ats)
        this_lev = s.def_lev * adjustment_mult

        # Clamp leverage to reasonable bounds (0.1x to 5x)
        this_lev = clamp(this_lev, 0.1, 5.0)

        @ldebug 2 "adjusting leverage for new position" ai s.def_lev this_lev adjustment_mult
    end

    lev_side = posside(ot)
    if hasorders(s, ai, ot)
        cancelorders!(s, ai; side=orderside(ot))
    end

    # Only update leverage if position is not open (new position)
    if !is_position_open
        if !call!(s, ai, this_lev, UpdateLeverage(); pos=lev_side, synced=true) &&
            ot isa IncreaseOrder
            @ldebug 1 "surge: failed to set leverage, skipping trade" ai = raw(ai) this_lev
            return nothing
        end
    end

    # Skip trade if amount is too small
    if amount < ai.limits.amount.min
        if is_position_open
            @ldebug 1 "amount below minimum, closing position" ai amount min_amount =
                ai.limits.amount.min
            closeposition!(s, ai, ts; pside=pos)
            return missing
        else
            @ldebug 2 "skipping trade - amount too small" ai amount min_amount =
                ai.limits.amount.min
            return nothing
        end
    end

    if isopen(ai, opposite(posside(ot)))
        @lwarn 1 "surge: double position in non hedged mode" ai = raw(ai) position(ai) order_type =
            ot
    end

    @ldebug 1 "surge: trade pong"
    t = call!(s, ai, ot; amount, date=ts, fees=simfees(s, ot), tag, o_kwargs...)
    @ldebug 1 "surge: after pong" t
    check_posside(s, ai, ats; ot, t)
    t
end

function get_make_amount(s::SC, ai, this_pos)
    abs(freecash(ai, posside(this_pos)))
end

function market_make(s, ai, ts; ats, pos)
    local t = nothing
    local this_pos = pos
    if isnothing(this_pos)
        return t
    end
    local make_amount = get_make_amount(s, ai, pos)
    local this_pside = posside(this_pos)
    local make_side = ifelse(isshort(this_pside), Buy, Sell)
    local this_ts = ts + Millisecond(1)
    @linfo 1 "surge: market making" ai = raw(ai) this_pos
    function dotrade(
        incr=getincr(s, ai, ats; side=make_side),
        amount=get_make_amount(s, ai, this_pos),
        o_kwargs=select_orderkwargs(:gtc, make_side, ai, ats; incr),
        o_otsym=select_ordertype(s, make_side, this_pside; t=:gtc),
    )
        trade!(
            s,
            ai,
            ats,
            this_ts;
            pos=this_pside,
            side=make_side,
            amount,
            incr,
            tag="market_make",
            t=:gtc,
            o_kwargs,
            o_otsym,
        )
    end
    tries = 10
    pad = 0.0
    while isnothing(t) && tries > 0 && should_market_make(s, ai, ats)
        tries -= 1
        pad += 0.0025
        # Check free cash before trading
        make_amount = get_make_amount(s, ai, this_pos)
        incr = (; buy=1.0 - pad, sell=1.0 + pad)
        o_kwargs = select_orderkwargs(:gtc, make_side, ai, ats; incr)
        o_otsym = select_ordertype(s, make_side, this_pside; t=:gtc)
        if iszero(make_amount)
            return t
        end
        t = dotrade(incr, make_amount, o_kwargs, o_otsym)
    end
    if isnothing(t) && should_market_make(s, ai, ats)
        @error "surge: failed to make market" ai leverage(ai) this_pside make_side make_amount free = freecash(ai, posside(ai)) ai.limits.amount.min
        ENV["JULIA_DEBUG"] = "Executors"
        incr = (; buy=1.0 - pad, sell=1.0 + pad)
        t = dotrade(incr)
        ENV["JULIA_DEBUG"] = ""
    end
    t
end

function should_market_make(s, ai, ats)
    isopen(ai) && !hasorders(s, ai)
end

function ensure_market_make(s, ai, ts; ats)
    if should_market_make(s, ai, ats)
        market_make(s, ai, ts; ats, pos=position(ai))
    end
end