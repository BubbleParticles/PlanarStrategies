function baseincr(s, ii; modifier=identity)
    ti = s[:hl][ii][2]
    if ti.n < ti.period
        simfees(s, ot.AnyImmediateOrder)
    else
        abs(1.0 - @coalesce ti.value 0.99) |> modifier
    end
end

function getincr(s, ii, ats; side, base=baseincr(s, ii))
    salt = max(base, sml.spreadat(ii, ats, Val(:edge2)), 0.0)
    return (buy=1.0 - salt, sell=1.0 + salt)
end

function trade!(
    s,
    ii,
    ats,
    ts;
    pos,
    side,
    amount,
    t=:gtc,
    tag="",
    incr=getincr(s, ii, ats; side),
    o_kwargs=select_orderkwargs(:gtc, side, ii, ats; incr),
    o_otsym=select_ordertype(s, side, pos; t),
)
    @assert amount isa Number
    ot, otsym = o_otsym
    @ldebug 2 "trade" ats ot otsym ii = raw(ii) side = posside(pos) amount

    # Check if position is already open
    is_position_open = isopen(ii, pos)

    if is_position_open
        # Use the actual leverage of the open position
        this_lev = leverage(position(ii, pos))
    else
        # Position is closed - adjust leverage for new position
        adjustment_mult = calculate_position_adjustment(s, ii, ats)
        this_lev = s.def_lev * adjustment_mult

        # Clamp leverage to reasonable bounds (0.1x to 5x)
        this_lev = clamp(this_lev, 0.1, 5.0)

        @ldebug 2 "adjusting leverage for new position" ii s.def_lev this_lev adjustment_mult
    end

    lev_side = posside(ot)
    if hasorders(s, ii, ot)
        cancelorders!(s, ii; side=orderside(ot))
    end

    # Only update leverage if position is not open (new position)
    if !is_position_open
        if !call!(s, ii, this_lev, UpdateLeverage(); pos=lev_side, synced=true) &&
            ot isa IncreaseOrder
            @ldebug 1 "surge: failed to set leverage, skipping trade" ii = raw(ii) this_lev
            return nothing
        end
    end

    # Skip trade if amount is too small
    if amount < ii.limits.amount.min
        if is_position_open
            @ldebug 1 "amount below minimum, closing position" ii amount min_amount =
                ii.limits.amount.min
            closeposition!(s, ii, ts; pside=pos)
            return missing
        else
            @ldebug 2 "skipping trade - amount too small" ii amount min_amount =
                ii.limits.amount.min
            return nothing
        end
    end

    if isopen(ii, opposite(posside(ot)))
        @lwarn 1 "surge: double position in non hedged mode" ii = raw(ii) position(ii) order_type =
            ot
    end

    @ldebug 1 "surge: trade pong"
    t = call!(s, ii, ot; amount, date=ts, fees=simfees(s, ot), tag, o_kwargs...)
    @ldebug 1 "surge: after pong" t
    check_posside(s, ii, ats; ot, t)
    t
end

function get_make_amount(s::SC, ii, this_pos)
    abs(freecash(ii, posside(this_pos)))
end

function market_make(s, ii, ts; ats, pos)
    local t = nothing
    local this_pos = pos
    if isnothing(this_pos)
        return t
    end
    local make_amount = get_make_amount(s, ii, pos)
    local this_pside = posside(this_pos)
    local make_side = ifelse(isshort(this_pside), Buy, Sell)
    local this_ts = ts + Millisecond(1)
    @linfo 1 "surge: market making" ii = raw(ii) this_pos
    function dotrade(
        incr=getincr(s, ii, ats; side=make_side),
        amount=get_make_amount(s, ii, this_pos),
        o_kwargs=select_orderkwargs(:gtc, make_side, ii, ats; incr),
        o_otsym=select_ordertype(s, make_side, this_pside; t=:gtc),
    )
        trade!(
            s,
            ii,
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
    while isnothing(t) && tries > 0 && should_market_make(s, ii, ats)
        tries -= 1
        pad += 0.0025
        # Check free cash before trading
        make_amount = get_make_amount(s, ii, this_pos)
        incr = (; buy=1.0 - pad, sell=1.0 + pad)
        o_kwargs = select_orderkwargs(:gtc, make_side, ii, ats; incr)
        o_otsym = select_ordertype(s, make_side, this_pside; t=:gtc)
        if iszero(make_amount)
            return t
        end
        t = dotrade(incr, make_amount, o_kwargs, o_otsym)
    end
    if isnothing(t) && should_market_make(s, ii, ats)
        @error "surge: failed to make market" ii leverage(ii) this_pside make_side make_amount free = freecash(ii, posside(ii)) ii.limits.amount.min
        ENV["JULIA_DEBUG"] = "Executors"
        incr = (; buy=1.0 - pad, sell=1.0 + pad)
        t = dotrade(incr)
        ENV["JULIA_DEBUG"] = ""
    end
    t
end

function should_market_make(s, ii, ats)
    isopen(ii) && !hasorders(s, ii)
end

function ensure_market_make(s, ii, ts; ats)
    if should_market_make(s, ii, ats)
        market_make(s, ii, ts; ats, pos=position(ii))
    end
end