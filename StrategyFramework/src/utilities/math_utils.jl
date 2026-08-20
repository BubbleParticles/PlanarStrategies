# Mathematical utilities for StrategyFramework
# Provides spread calculations, ROC calculations, volatility measurements, and timeframe conversions

using Statistics
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

"""
    getincr(price::Real, exchange_info)

Calculate the minimum price increment for a given price based on exchange rules.
Returns the smallest valid price step for order placement.

# Arguments
- `price::Real`: Current price
- `exchange_info`: Exchange-specific information containing tick size rules

# Returns
- Minimum price increment as Float64
"""
function getincr(price::Real, exchange_info)
    # Default implementation - should be overridden based on exchange specifics
    if haskey(exchange_info, :tick_size)
        return exchange_info[:tick_size]
    elseif haskey(exchange_info, :price_precision)
        return 10.0^(-exchange_info[:price_precision])
    else
        # Fallback: use 0.01% of price as minimum increment
        return max(price * 0.0001, 1e-8)
    end
end

"""
    baseincr(amount::Real, exchange_info)

Calculate the minimum quantity increment for a given amount based on exchange rules.
Returns the smallest valid quantity step for order placement.

# Arguments
- `amount::Real`: Current amount/quantity
- `exchange_info`: Exchange-specific information containing lot size rules

# Returns
- Minimum quantity increment as Float64
"""
function baseincr(amount::Real, exchange_info)
    # Default implementation - should be overridden based on exchange specifics
    if haskey(exchange_info, :lot_size)
        return exchange_info[:lot_size]
    elseif haskey(exchange_info, :amount_precision)
        return 10.0^(-exchange_info[:amount_precision])
    else
        # Fallback: use 0.01% of amount as minimum increment
        return max(amount * 0.0001, 1e-8)
    end
end

"""
    calculate_spread(bid::Real, ask::Real)

Calculate the bid-ask spread as both absolute and relative values.

# Arguments
- `bid::Real`: Bid price
- `ask::Real`: Ask price

# Returns
- NamedTuple with absolute spread, relative spread (%), and mid price
"""
function calculate_spread(bid::Real, ask::Real)
    abs_spread = ask - bid
    mid_price = (bid + ask) / 2
    rel_spread = abs_spread / mid_price * 100
    
    return (
        absolute = abs_spread,
        relative = rel_spread,
        mid_price = mid_price
    )
end

"""
    roc(values::AbstractVector{<:Real}, period::Int = 1)

Calculate Rate of Change (ROC) for a series of values.
ROC = (current_value - previous_value) / previous_value * 100

# Arguments
- `values::AbstractVector{<:Real}`: Time series of values
- `period::Int`: Number of periods to look back (default: 1)

# Returns
- Vector of ROC values (first `period` elements will be NaN)
"""
function roc(values::AbstractVector{<:Real}, period::Int = 1)
    n = length(values)
    result = Vector{Float64}(undef, n)
    
    # Fill initial values with NaN
    for i in 1:period
        result[i] = NaN
    end
    
    # Calculate ROC for remaining values
    for i in (period + 1):n
        if values[i - period] != 0
            result[i] = (values[i] - values[i - period]) / values[i - period] * 100
        else
            result[i] = NaN
        end
    end
    
    return result
end

"""
    rolling_volatility(prices::AbstractVector{<:Real}, window::Int; method::Symbol = :std)

Calculate rolling volatility using different methods.

# Arguments
- `prices::AbstractVector{<:Real}`: Price series
- `window::Int`: Rolling window size
- `method::Symbol`: Calculation method (:std, :parkinson, :garman_klass)

# Returns
- Vector of volatility values
"""
function rolling_volatility(prices::AbstractVector{<:Real}, window::Int; method::Symbol = :std)
    n = length(prices)
    result = Vector{Float64}(undef, n)
    
    # Fill initial values with NaN
    for i in 1:(window - 1)
        result[i] = NaN
    end
    
    if method == :std
        # Standard deviation of returns
        returns = diff(log.(prices))
        for i in window:n
            if i <= length(returns) + 1
                window_returns = returns[max(1, i - window):min(end, i - 1)]
                result[i] = std(window_returns) * sqrt(252)  # Annualized
            else
                result[i] = NaN
            end
        end
    else
        # For other methods, would need OHLC data
        @warn "Method $method requires OHLC data, falling back to standard deviation"
        return rolling_volatility(prices, window; method = :std)
    end
    
    return result
end

"""
    parkinson_volatility(high::AbstractVector{<:Real}, low::AbstractVector{<:Real}, window::Int)

Calculate Parkinson volatility estimator using high-low range.
More efficient than close-to-close volatility for intraday data.

# Arguments
- `high::AbstractVector{<:Real}`: High prices
- `low::AbstractVector{<:Real}`: Low prices  
- `window::Int`: Rolling window size

# Returns
- Vector of Parkinson volatility estimates
"""
function parkinson_volatility(high::AbstractVector{<:Real}, low::AbstractVector{<:Real}, window::Int)
    @assert length(high) == length(low) "High and low vectors must have same length"
    
    n = length(high)
    result = Vector{Float64}(undef, n)
    
    # Fill initial values with NaN
    for i in 1:(window - 1)
        result[i] = NaN
    end
    
    # Calculate Parkinson volatility
    for i in window:n
        hl_ratios = log.(high[(i - window + 1):i] ./ low[(i - window + 1):i])
        parkinson_var = mean(hl_ratios .^ 2) / (4 * log(2))
        result[i] = sqrt(parkinson_var * 252)  # Annualized
    end
    
    return result
end

"""
    tftodelay(timeframe::String)

Convert timeframe string to delay in milliseconds.
Supports standard timeframe notation (1m, 5m, 1h, 1d, etc.).

# Arguments
- `timeframe::String`: Timeframe string (e.g., "1m", "5m", "1h", "1d")

# Returns
- Delay in milliseconds as Int64
"""
function tftodelay(timeframe::String)
    # Parse timeframe string
    timeframe = lowercase(strip(timeframe))
    
    # Extract number and unit
    match_result = match(r"^(\d+)([smhd])$", timeframe)
    if match_result === nothing
        throw(ArgumentError("Invalid timeframe format: $timeframe. Use format like '1m', '5m', '1h', '1d'"))
    end
    
    number = parse(Int, match_result.captures[1])
    unit = match_result.captures[2]
    
    # Convert to milliseconds
    multiplier = Dict(
        "s" => 1000,        # seconds
        "m" => 60_000,      # minutes  
        "h" => 3_600_000,   # hours
        "d" => 86_400_000   # days
    )
    
    return number * multiplier[unit]
end

"""
    timeframe_to_period(timeframe::String)

Convert timeframe string to Julia Period object.

# Arguments
- `timeframe::String`: Timeframe string (e.g., "1m", "5m", "1h", "1d")

# Returns
- Period object (Minute, Hour, Day, etc.)
"""
function timeframe_to_period(timeframe::String)
    timeframe = lowercase(strip(timeframe))
    
    match_result = match(r"^(\d+)([smhd])$", timeframe)
    if match_result === nothing
        throw(ArgumentError("Invalid timeframe format: $timeframe"))
    end
    
    number = parse(Int, match_result.captures[1])
    unit = match_result.captures[2]
    
    return Dict(
        "s" => Second(number),
        "m" => Minute(number),
        "h" => Hour(number),
        "d" => Day(number)
    )[unit]
end

"""
    normalize_price(price::Real, tick_size::Real)

Normalize price to valid tick size.

# Arguments
- `price::Real`: Input price
- `tick_size::Real`: Minimum price increment

# Returns
- Normalized price as Float64
"""
function normalize_price(price::Real, tick_size::Real)
    return round(price / tick_size) * tick_size
end

"""
    normalize_quantity(quantity::Real, lot_size::Real, min_quantity::Real = 0.0)

Normalize quantity to valid lot size and ensure minimum quantity.

# Arguments
- `quantity::Real`: Input quantity
- `lot_size::Real`: Minimum quantity increment
- `min_quantity::Real`: Minimum allowed quantity

# Returns
- Normalized quantity as Float64
"""
function normalize_quantity(quantity::Real, lot_size::Real, min_quantity::Real = 0.0)
    normalized = round(quantity / lot_size) * lot_size
    return max(normalized, min_quantity)
end

"""
    calculate_atr(high::AbstractVector{<:Real}, low::AbstractVector{<:Real}, 
                  close::AbstractVector{<:Real}, period::Int = 14)

Calculate Average True Range (ATR) indicator.

# Arguments
- `high::AbstractVector{<:Real}`: High prices
- `low::AbstractVector{<:Real}`: Low prices
- `close::AbstractVector{<:Real}`: Close prices
- `period::Int`: ATR period (default: 14)

# Returns
- Vector of ATR values
"""
function calculate_atr(high::AbstractVector{<:Real}, low::AbstractVector{<:Real}, 
                      close::AbstractVector{<:Real}, period::Int = 14)
    @assert length(high) == length(low) == length(close) "All price vectors must have same length"
    
    n = length(high)
    tr = Vector{Float64}(undef, n)
    atr = Vector{Float64}(undef, n)
    
    # Calculate True Range
    tr[1] = high[1] - low[1]
    for i in 2:n
        tr[i] = max(
            high[i] - low[i],
            abs(high[i] - close[i-1]),
            abs(low[i] - close[i-1])
        )
    end
    
    # Calculate ATR using exponential moving average
    atr[1:period-1] .= NaN
    atr[period] = mean(tr[1:period])
    
    for i in (period + 1):n
        atr[i] = (atr[i-1] * (period - 1) + tr[i]) / period
    end
    
    return atr
end