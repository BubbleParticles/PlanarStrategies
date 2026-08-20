# Parameter conversion and management utilities for StrategyFramework

using Planar
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

"""
    ParameterSpec

Specification for a strategy parameter including its type, bounds, and validation rules.
"""
@kwdef struct ParameterSpec{T}
    name::Symbol
    type::Type{T}
    default::T
    min_val::Union{T, Nothing} = nothing
    max_val::Union{T, Nothing} = nothing
    validator::Union{Function, Nothing} = nothing
    description::String = ""
end

"""
    ParameterCache

Cache for storing converted and validated parameters.
"""
mutable struct ParameterCache
    params::Dict{Symbol, Any}
    specs::Dict{Symbol, ParameterSpec}
    last_update::DateTime
    
    ParameterCache() = new(Dict{Symbol, Any}(), Dict{Symbol, ParameterSpec}(), DateTime(0))
end

# Global parameter cache for the framework
const PARAMETER_CACHE = ParameterCache()

"""
    register_parameter!(spec::ParameterSpec)

Register a parameter specification in the global cache.
"""
function register_parameter!(spec::ParameterSpec)
    PARAMETER_CACHE.specs[spec.name] = spec
    # Set default value if not already set
    if !haskey(PARAMETER_CACHE.params, spec.name)
        PARAMETER_CACHE.params[spec.name] = spec.default
    end
    return spec
end

"""
    convert_float_vector_to_params(values::Vector{Float64}, param_names::Vector{Symbol})

Convert a vector of float values to named parameters for optimization.
This function is used by optimization algorithms to convert parameter vectors
back to named parameter dictionaries.
"""
function convert_float_vector_to_params(values::Vector{Float64}, param_names::Vector{Symbol})
    if length(values) != length(param_names)
        throw(ArgumentError("Length of values ($(length(values))) must match length of param_names ($(length(param_names)))"))
    end
    
    params = Dict{Symbol, Any}()
    
    for (i, name) in enumerate(param_names)
        value = values[i]
        
        # Get parameter specification if available
        if haskey(PARAMETER_CACHE.specs, name)
            spec = PARAMETER_CACHE.specs[name]
            
            # Convert to appropriate type
            if spec.type == Int
                params[name] = round(Int, value)
            elseif spec.type == Bool
                params[name] = value > 0.5
            elseif spec.type <: Period
                # Convert to appropriate period type
                if spec.type == Second
                    params[name] = Second(round(Int, value))
                elseif spec.type == Minute
                    params[name] = Minute(round(Int, value))
                elseif spec.type == Hour
                    params[name] = Hour(round(Int, value))
                else
                    params[name] = spec.type(round(Int, value))
                end
            else
                params[name] = convert(spec.type, value)
            end
            
            # Validate bounds
            if spec.min_val !== nothing && params[name] < spec.min_val
                params[name] = spec.min_val
            end
            if spec.max_val !== nothing && params[name] > spec.max_val
                params[name] = spec.max_val
            end
            
            # Apply custom validator if present
            if spec.validator !== nothing
                if !spec.validator(params[name])
                    throw(ArgumentError("Parameter $name with value $(params[name]) failed validation"))
                end
            end
        else
            # No specification available, use raw float value
            params[name] = value
        end
    end
    
    return params
end

"""
    convert_params_to_float_vector(params::Dict{Symbol, Any}, param_names::Vector{Symbol})

Convert named parameters to a vector of float values for optimization.
"""
function convert_params_to_float_vector(params::Dict{Symbol, Any}, param_names::Vector{Symbol})
    values = Float64[]
    
    for name in param_names
        if haskey(params, name)
            value = params[name]
            
            # Convert to float based on type
            if value isa Bool
                push!(values, value ? 1.0 : 0.0)
            elseif value isa Period
                push!(values, Float64(value.value))
            else
                push!(values, Float64(value))
            end
        else
            # Use default value if available
            if haskey(PARAMETER_CACHE.specs, name)
                default_val = PARAMETER_CACHE.specs[name].default
                if default_val isa Bool
                    push!(values, default_val ? 1.0 : 0.0)
                elseif default_val isa Period
                    push!(values, Float64(default_val.value))
                else
                    push!(values, Float64(default_val))
                end
            else
                push!(values, 0.0)  # Fallback
            end
        end
    end
    
    return values
end

"""
    validate_parameter(name::Symbol, value::Any)

Validate a parameter value against its specification.
"""
function validate_parameter(name::Symbol, value::Any)
    if !haskey(PARAMETER_CACHE.specs, name)
        @warn "No specification found for parameter $name"
        return true
    end
    
    spec = PARAMETER_CACHE.specs[name]
    
    # Type validation
    if !isa(value, spec.type)
        try
            value = convert(spec.type, value)
        catch e
            throw(ArgumentError("Cannot convert parameter $name to type $(spec.type): $e"))
        end
    end
    
    # Bounds validation
    if spec.min_val !== nothing && value < spec.min_val
        throw(ArgumentError("Parameter $name value $value is below minimum $(spec.min_val)"))
    end
    
    if spec.max_val !== nothing && value > spec.max_val
        throw(ArgumentError("Parameter $name value $value is above maximum $(spec.max_val)"))
    end
    
    # Custom validation
    if spec.validator !== nothing && !spec.validator(value)
        throw(ArgumentError("Parameter $name with value $value failed custom validation"))
    end
    
    return true
end

"""
    set_parameter!(name::Symbol, value::Any)

Set a parameter value with validation and caching.
"""
function set_parameter!(name::Symbol, value::Any)
    validate_parameter(name, value)
    
    # Convert to proper type if needed
    if haskey(PARAMETER_CACHE.specs, name)
        spec = PARAMETER_CACHE.specs[name]
        value = convert(spec.type, value)
    end
    
    PARAMETER_CACHE.params[name] = value
    PARAMETER_CACHE.last_update = now()
    
    return value
end

"""
    get_parameter(name::Symbol, default::Any = nothing)

Get a parameter value from the cache.
"""
function get_parameter(name::Symbol, default::Any = nothing)
    if haskey(PARAMETER_CACHE.params, name)
        return PARAMETER_CACHE.params[name]
    elseif haskey(PARAMETER_CACHE.specs, name)
        return PARAMETER_CACHE.specs[name].default
    else
        return default
    end
end

"""
    clear_parameter_cache!()

Clear the parameter cache.
"""
function clear_parameter_cache!()
    empty!(PARAMETER_CACHE.params)
    PARAMETER_CACHE.last_update = DateTime(0)
end

"""
    get_parameter_specs()

Get all registered parameter specifications.
"""
function get_parameter_specs()
    return copy(PARAMETER_CACHE.specs)
end

"""
    get_optimization_bounds(param_names::Vector{Symbol})

Get optimization bounds for the specified parameters.
Returns (lower_bounds, upper_bounds) as vectors of Float64.
"""
function get_optimization_bounds(param_names::Vector{Symbol})
    lower_bounds = Float64[]
    upper_bounds = Float64[]
    
    for name in param_names
        if haskey(PARAMETER_CACHE.specs, name)
            spec = PARAMETER_CACHE.specs[name]
            
            # Convert bounds to float
            if spec.min_val !== nothing
                if spec.min_val isa Bool
                    push!(lower_bounds, 0.0)
                elseif spec.min_val isa Period
                    push!(lower_bounds, Float64(spec.min_val.value))
                else
                    push!(lower_bounds, Float64(spec.min_val))
                end
            else
                push!(lower_bounds, -Inf)
            end
            
            if spec.max_val !== nothing
                if spec.max_val isa Bool
                    push!(upper_bounds, 1.0)
                elseif spec.max_val isa Period
                    push!(upper_bounds, Float64(spec.max_val.value))
                else
                    push!(upper_bounds, Float64(spec.max_val))
                end
            else
                push!(upper_bounds, Inf)
            end
        else
            # No bounds available
            push!(lower_bounds, -Inf)
            push!(upper_bounds, Inf)
        end
    end
    
    return (lower_bounds, upper_bounds)
end

# Register default StrategyConfig parameters
function register_default_parameters!()
    # Trading parameters
    register_parameter!(ParameterSpec(
        name = :signal_lifetime,
        type = Float64,
        default = 0.2,
        min_val = 0.01,
        max_val = 1.0,
        description = "Signal lifetime in seconds"
    ))
    
    register_parameter!(ParameterSpec(
        name = :trade_cooldown,
        type = Minute,
        default = Minute(1),
        min_val = Minute(0),
        max_val = Minute(60),
        description = "Cooldown period between trades"
    ))
    
    register_parameter!(ParameterSpec(
        name = :order_timeout,
        type = Minute,
        default = Minute(2),
        min_val = Minute(1),
        max_val = Minute(30),
        description = "Order timeout period"
    ))
    
    register_parameter!(ParameterSpec(
        name = :def_lev,
        type = Float64,
        default = 1.0,
        min_val = 0.1,
        max_val = 10.0,
        description = "Default leverage"
    ))
    
    # Risk management parameters
    register_parameter!(ParameterSpec(
        name = :reserve_cash_pct,
        type = Float64,
        default = 0.1,
        min_val = 0.0,
        max_val = 0.5,
        description = "Reserve cash percentage"
    ))
    
    register_parameter!(ParameterSpec(
        name = :peak_cash,
        type = Float64,
        default = 0.0,
        min_val = 0.0,
        max_val = nothing,
        description = "Peak cash amount"
    ))
    
    # Execution settings
    register_parameter!(ParameterSpec(
        name = :ordertype,
        type = Symbol,
        default = :gtc,
        validator = x -> x in [:gtc, :ioc, :fok, :market],
        description = "Default order type"
    ))
    
    register_parameter!(ParameterSpec(
        name = :ismake,
        type = Bool,
        default = true,
        description = "Use maker orders by default"
    ))
    
    # Environment settings
    register_parameter!(ParameterSpec(
        name = :throttle,
        type = Second,
        default = Second(10),
        min_val = Second(1),
        max_val = Second(300),
        description = "Throttle period for operations"
    ))
    
    register_parameter!(ParameterSpec(
        name = :sync_history_limit,
        type = Int,
        default = 0,
        min_val = 0,
        max_val = 10000,
        description = "Sync history limit"
    ))
    
    register_parameter!(ParameterSpec(
        name = :watch_idle_timeout,
        type = Second,
        default = Second(Day(1)),
        min_val = Second(Hour(1)),
        max_val = Second(Day(7)),
        description = "Watch idle timeout"
    ))
end

# Initialize default parameters when module loads
register_default_parameters!()