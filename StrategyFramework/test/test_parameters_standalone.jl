# Standalone tests for parameter management
using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

# Mock Planar dependency
module MockPlanar
end

# Include the parameters module directly (skip Planar import)
include("../src/core/parameters.jl")

@testset "Parameter Management Standalone Tests" begin
    
    @testset "ParameterSpec construction" begin
        # Test basic construction
        spec = ParameterSpec(
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
        
        # Test with validator
        validator_func(x) = x > 0
        spec_with_validator = ParameterSpec(
            name = :positive_param,
            type = Float64,
            default = 1.0,
            validator = validator_func
        )
        
        @test spec_with_validator.validator === validator_func
        @test spec_with_validator.min_val === nothing
        @test spec_with_validator.max_val === nothing
    end
    
    @testset "register_parameter! function" begin
        # Clear cache for clean testing
        clear_parameter_cache!()
        
        spec = ParameterSpec(
            name = :test_register,
            type = Int,
            default = 42
        )
        
        result = register_parameter!(spec)
        @test result === spec
        
        # Check that parameter was registered
        specs = get_parameter_specs()
        @test haskey(specs, :test_register)
        @test specs[:test_register] === spec
        
        # Check that default value was set
        @test get_parameter(:test_register) == 42
    end
    
    @testset "convert_float_vector_to_params function" begin
        # Clear cache and register test parameters
        clear_parameter_cache!()
        
        register_parameter!(ParameterSpec(name=:float_param, type=Float64, default=1.0))
        register_parameter!(ParameterSpec(name=:int_param, type=Int, default=5, min_val=1, max_val=10))
        register_parameter!(ParameterSpec(name=:bool_param, type=Bool, default=true))
        register_parameter!(ParameterSpec(name=:minute_param, type=Minute, default=Minute(5)))
        
        values = [2.5, 7.8, 0.3, 10.0]
        param_names = [:float_param, :int_param, :bool_param, :minute_param]
        
        result = convert_float_vector_to_params(values, param_names)
        
        @test result[:float_param] == 2.5
        @test result[:int_param] == 8  # rounded from 7.8
        @test result[:bool_param] == false  # 0.3 < 0.5
        @test result[:minute_param] == Minute(10)
        
        # Test with bounds enforcement
        values_with_bounds = [2.5, 15.0, 0.8, 3.0]  # int_param exceeds max
        result_bounded = convert_float_vector_to_params(values_with_bounds, param_names)
        @test result_bounded[:int_param] == 10  # clamped to max_val
        
        # Test mismatched lengths
        @test_throws ArgumentError convert_float_vector_to_params([1.0, 2.0], [:param1, :param2, :param3])
    end
    
    @testset "validate_parameter function" begin
        clear_parameter_cache!()
        
        # Register parameter with bounds and validator
        validator_func(x) = x != 42  # reject value 42
        register_parameter!(ParameterSpec(
            name = :validated_param,
            type = Float64,
            default = 1.0,
            min_val = 0.0,
            max_val = 100.0,
            validator = validator_func
        ))
        
        # Valid value
        @test validate_parameter(:validated_param, 50.0) == true
        
        # Test type conversion
        @test validate_parameter(:validated_param, 50) == true  # Int to Float64
        
        # Test bounds violations
        @test_throws ArgumentError validate_parameter(:validated_param, -1.0)  # below min
        @test_throws ArgumentError validate_parameter(:validated_param, 101.0)  # above max
        
        # Test custom validator failure
        @test_throws ArgumentError validate_parameter(:validated_param, 42.0)  # validator rejects
    end
    
    @testset "set_parameter! and get_parameter functions" begin
        clear_parameter_cache!()
        
        register_parameter!(ParameterSpec(
            name = :test_set_get,
            type = Float64,
            default = 1.0,
            min_val = 0.0,
            max_val = 10.0
        ))
        
        # Test setting valid value
        result = set_parameter!(:test_set_get, 5.0)
        @test result == 5.0
        @test get_parameter(:test_set_get) == 5.0
        
        # Test type conversion during set
        set_parameter!(:test_set_get, 7)  # Int to Float64
        @test get_parameter(:test_set_get) == 7.0
        
        # Test bounds enforcement
        @test_throws ArgumentError set_parameter!(:test_set_get, -1.0)
        @test_throws ArgumentError set_parameter!(:test_set_get, 11.0)
        
        # Test getting unregistered parameter with default
        @test get_parameter(:unregistered, "default_value") == "default_value"
        @test get_parameter(:unregistered) === nothing
    end
    
    @testset "get_optimization_bounds function" begin
        clear_parameter_cache!()
        
        register_parameter!(ParameterSpec(name=:bounded_float, type=Float64, default=5.0, min_val=0.0, max_val=10.0))
        register_parameter!(ParameterSpec(name=:bounded_int, type=Int, default=5, min_val=1, max_val=20))
        register_parameter!(ParameterSpec(name=:bounded_bool, type=Bool, default=true))
        register_parameter!(ParameterSpec(name=:unbounded, type=Float64, default=1.0))
        
        param_names = [:bounded_float, :bounded_int, :bounded_bool, :unbounded]
        lower_bounds, upper_bounds = get_optimization_bounds(param_names)
        
        @test lower_bounds == [0.0, 1.0, 0.0, -Inf]
        @test upper_bounds == [10.0, 20.0, 1.0, Inf]
        
        # Test with unregistered parameter
        unregistered_lower, unregistered_upper = get_optimization_bounds([:unregistered])
        @test unregistered_lower == [-Inf]
        @test unregistered_upper == [Inf]
    end
end

println("✓ Parameter management tests passed")