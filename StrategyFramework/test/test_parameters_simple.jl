# Simplified parameter management tests without Planar dependency
using Test
using Dates

# Simplified parameter spec for testing
@kwdef struct SimpleParameterSpec{T}
    name::Symbol
    type::Type{T}
    default::T
    min_val::Union{T, Nothing} = nothing
    max_val::Union{T, Nothing} = nothing
    validator::Union{Function, Nothing} = nothing
    description::String = ""
end

# Simple parameter cache
mutable struct SimpleParameterCache
    params::Dict{Symbol, Any}
    specs::Dict{Symbol, SimpleParameterSpec}
    
    SimpleParameterCache() = new(Dict{Symbol, Any}(), Dict{Symbol, SimpleParameterSpec}())
end

const SIMPLE_CACHE = SimpleParameterCache()

# Basic parameter functions for testing
function simple_register_parameter!(spec::SimpleParameterSpec)
    SIMPLE_CACHE.specs[spec.name] = spec
    if !haskey(SIMPLE_CACHE.params, spec.name)
        SIMPLE_CACHE.params[spec.name] = spec.default
    end
    return spec
end

function simple_get_parameter(name::Symbol, default::Any = nothing)
    if haskey(SIMPLE_CACHE.params, name)
        return SIMPLE_CACHE.params[name]
    elseif haskey(SIMPLE_CACHE.specs, name)
        return SIMPLE_CACHE.specs[name].default
    else
        return default
    end
end

function simple_set_parameter!(name::Symbol, value::Any)
    if haskey(SIMPLE_CACHE.specs, name)
        spec = SIMPLE_CACHE.specs[name]
        
        # Type conversion
        if !isa(value, spec.type)
            value = convert(spec.type, value)
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
    end
    
    SIMPLE_CACHE.params[name] = value
    return value
end

function simple_clear_cache!()
    empty!(SIMPLE_CACHE.params)
    empty!(SIMPLE_CACHE.specs)
end

function simple_convert_float_to_params(values::Vector{Float64}, param_names::Vector{Symbol})
    if length(values) != length(param_names)
        throw(ArgumentError("Length mismatch"))
    end
    
    params = Dict{Symbol, Any}()
    
    for (i, name) in enumerate(param_names)
        value = values[i]
        
        if haskey(SIMPLE_CACHE.specs, name)
            spec = SIMPLE_CACHE.specs[name]
            
            if spec.type == Int
                params[name] = round(Int, value)
            elseif spec.type == Bool
                params[name] = value > 0.5
            elseif spec.type <: Period
                if spec.type == Second
                    params[name] = Second(round(Int, value))
                elseif spec.type == Minute
                    params[name] = Minute(round(Int, value))
                else
                    params[name] = spec.type(round(Int, value))
                end
            else
                params[name] = convert(spec.type, value)
            end
            
            # Apply bounds
            if spec.min_val !== nothing && params[name] < spec.min_val
                params[name] = spec.min_val
            end
            if spec.max_val !== nothing && params[name] > spec.max_val
                params[name] = spec.max_val
            end
        else
            params[name] = value
        end
    end
    
    return params
end

@testset "Simple Parameter Management Tests" begin
    
    @testset "SimpleParameterSpec construction" begin
        spec = SimpleParameterSpec(
            name = :test_param,
            type = Float64,
            default = 1.0,
            min_val = 0.0,
            max_val = 10.0,
            description = "Test parameter"
        )
        
        @test spec.name == :test_param
        @test spec.type == Float64
        @test spec.default == 1.0
        @test spec.min_val == 0.0
        @test spec.max_val == 10.0
        @test spec.description == "Test parameter"
        @test spec.validator === nothing
    end
    
    @testset "simple_register_parameter! function" begin
        simple_clear_cache!()
        
        spec = SimpleParameterSpec(
            name = :test_register,
            type = Int,
            default = 42
        )
        
        result = simple_register_parameter!(spec)
        @test result === spec
        
        # Check that parameter was registered
        @test haskey(SIMPLE_CACHE.specs, :test_register)
        @test SIMPLE_CACHE.specs[:test_register] === spec
        
        # Check that default value was set
        @test simple_get_parameter(:test_register) == 42
    end
    
    @testset "simple_convert_float_to_params function" begin
        simple_clear_cache!()
        
        simple_register_parameter!(SimpleParameterSpec(name=:float_param, type=Float64, default=1.0))
        simple_register_parameter!(SimpleParameterSpec(name=:int_param, type=Int, default=5, min_val=1, max_val=10))
        simple_register_parameter!(SimpleParameterSpec(name=:bool_param, type=Bool, default=true))
        simple_register_parameter!(SimpleParameterSpec(name=:minute_param, type=Minute, default=Minute(5)))
        
        values = [2.5, 7.8, 0.3, 10.0]
        param_names = [:float_param, :int_param, :bool_param, :minute_param]
        
        result = simple_convert_float_to_params(values, param_names)
        
        @test result[:float_param] == 2.5
        @test result[:int_param] == 8  # rounded from 7.8
        @test result[:bool_param] == false  # 0.3 < 0.5
        @test result[:minute_param] == Minute(10)
        
        # Test with bounds enforcement
        values_with_bounds = [2.5, 15.0, 0.8, 3.0]  # int_param exceeds max
        result_bounded = simple_convert_float_to_params(values_with_bounds, param_names)
        @test result_bounded[:int_param] == 10  # clamped to max_val
        
        # Test mismatched lengths
        @test_throws ArgumentError simple_convert_float_to_params([1.0, 2.0], [:param1, :param2, :param3])
    end
    
    @testset "simple_set_parameter! and simple_get_parameter functions" begin
        simple_clear_cache!()
        
        simple_register_parameter!(SimpleParameterSpec(
            name = :test_set_get,
            type = Float64,
            default = 1.0,
            min_val = 0.0,
            max_val = 10.0
        ))
        
        # Test setting valid value
        result = simple_set_parameter!(:test_set_get, 5.0)
        @test result == 5.0
        @test simple_get_parameter(:test_set_get) == 5.0
        
        # Test type conversion during set
        simple_set_parameter!(:test_set_get, 7)  # Int to Float64
        @test simple_get_parameter(:test_set_get) == 7.0
        
        # Test bounds enforcement
        @test_throws ArgumentError simple_set_parameter!(:test_set_get, -1.0)
        @test_throws ArgumentError simple_set_parameter!(:test_set_get, 11.0)
        
        # Test getting unregistered parameter with default
        @test simple_get_parameter(:unregistered, "default_value") == "default_value"
        @test simple_get_parameter(:unregistered) === nothing
    end
    
    @testset "Parameter validation with custom validators" begin
        simple_clear_cache!()
        
        # Register parameter with custom validator
        even_validator(x) = x % 2 == 0
        simple_register_parameter!(SimpleParameterSpec(
            name = :even_number,
            type = Int,
            default = 2,
            validator = even_validator
        ))
        
        # Valid even number
        simple_set_parameter!(:even_number, 6)
        @test simple_get_parameter(:even_number) == 6
        
        # Invalid odd number
        @test_throws ArgumentError simple_set_parameter!(:even_number, 5)
    end
    
    @testset "Edge cases" begin
        simple_clear_cache!()
        
        # Test with Period types
        simple_register_parameter!(SimpleParameterSpec(name=:hour_param, type=Hour, default=Hour(1)))
        simple_register_parameter!(SimpleParameterSpec(name=:day_param, type=Day, default=Day(1)))
        
        # Test conversion from float vector
        result = simple_convert_float_to_params([2.0, 3.0], [:hour_param, :day_param])
        @test result[:hour_param] == Hour(2)
        @test result[:day_param] == Day(3)
        
        # Test bounds with Period types
        simple_register_parameter!(SimpleParameterSpec(
            name = :bounded_minute,
            type = Minute,
            default = Minute(5),
            min_val = Minute(1),
            max_val = Minute(10)
        ))
        
        simple_set_parameter!(:bounded_minute, Minute(5))
        @test simple_get_parameter(:bounded_minute) == Minute(5)
        
        @test_throws ArgumentError simple_set_parameter!(:bounded_minute, Minute(0))
        @test_throws ArgumentError simple_set_parameter!(:bounded_minute, Minute(15))
    end
end

println("✓ Simple parameter management tests passed")