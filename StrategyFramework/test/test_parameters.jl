# Unit tests for parameter management
using Test
using StrategyFramework
using Dates

@testset "Parameter Management Tests" begin
    
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
        
        # Test with unregistered parameter
        unregistered_result = convert_float_vector_to_params([1.5], [:unregistered])
        @test unregistered_result[:unregistered] == 1.5
    end
    
    @testset "convert_params_to_float_vector function" begin
        clear_parameter_cache!()
        
        register_parameter!(ParameterSpec(name=:float_param, type=Float64, default=1.0))
        register_parameter!(ParameterSpec(name=:int_param, type=Int, default=5))
        register_parameter!(ParameterSpec(name=:bool_param, type=Bool, default=true))
        register_parameter!(ParameterSpec(name=:second_param, type=Second, default=Second(30)))
        
        params = Dict{Symbol, Any}(
            :float_param => 2.5,
            :int_param => 8,
            :bool_param => false,
            :second_param => Second(45)
        )
        
        param_names = [:float_param, :int_param, :bool_param, :second_param]
        result = convert_params_to_float_vector(params, param_names)
        
        @test result == [2.5, 8.0, 0.0, 45.0]
        
        # Test with missing parameter (should use default)
        partial_params = Dict{Symbol, Any}(:float_param => 3.0)
        result_partial = convert_params_to_float_vector(partial_params, param_names)
        @test result_partial == [3.0, 5.0, 1.0, 30.0]  # uses defaults for missing params
        
        # Test with unregistered parameter
        result_unregistered = convert_params_to_float_vector(Dict{Symbol, Any}(), [:unregistered])
        @test result_unregistered == [0.0]  # fallback value
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
        
        # Test type conversion failure
        register_parameter!(ParameterSpec(name=:int_only, type=Int, default=1))
        @test_throws ArgumentError validate_parameter(:int_only, "not_a_number")
        
        # Test unregistered parameter (should warn but return true)
        @test validate_parameter(:unregistered_param, 123) == true
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
        
        # Test getting registered parameter that hasn't been set (should return spec default)
        register_parameter!(ParameterSpec(name=:unused_param, type=String, default="unused"))
        @test get_parameter(:unused_param) == "unused"
    end
    
    @testset "clear_parameter_cache! function" begin
        # Set some parameters
        set_parameter!(:test_clear, 123)
        @test get_parameter(:test_clear) == 123
        
        # Clear cache
        clear_parameter_cache!()
        
        # Parameter should be gone (but spec remains)
        @test get_parameter(:test_clear) === nothing
        
        # Check that last_update was reset
        @test PARAMETER_CACHE.last_update == DateTime(0)
    end
    
    @testset "get_optimization_bounds function" begin
        clear_parameter_cache!()
        
        register_parameter!(ParameterSpec(name=:bounded_float, type=Float64, default=5.0, min_val=0.0, max_val=10.0))
        register_parameter!(ParameterSpec(name=:bounded_int, type=Int, default=5, min_val=1, max_val=20))
        register_parameter!(ParameterSpec(name=:bounded_bool, type=Bool, default=true))
        register_parameter!(ParameterSpec(name=:unbounded, type=Float64, default=1.0))
        register_parameter!(ParameterSpec(name=:bounded_period, type=Minute, default=Minute(5), min_val=Minute(1), max_val=Minute(60)))
        
        param_names = [:bounded_float, :bounded_int, :bounded_bool, :unbounded, :bounded_period]
        lower_bounds, upper_bounds = get_optimization_bounds(param_names)
        
        @test lower_bounds == [0.0, 1.0, 0.0, -Inf, 1.0]
        @test upper_bounds == [10.0, 20.0, 1.0, Inf, 60.0]
        
        # Test with unregistered parameter
        unregistered_lower, unregistered_upper = get_optimization_bounds([:unregistered])
        @test unregistered_lower == [-Inf]
        @test unregistered_upper == [Inf]
    end
    
    @testset "Default parameter registration" begin
        # The module should have registered default parameters
        specs = get_parameter_specs()
        
        # Check that some expected default parameters exist
        expected_params = [
            :signal_lifetime, :trade_cooldown, :order_timeout, :def_lev,
            :reserve_cash_pct, :peak_cash, :ordertype, :ismake,
            :throttle, :sync_history_limit, :watch_idle_timeout
        ]
        
        for param in expected_params
            @test haskey(specs, param)
        end
        
        # Check specific parameter properties
        @test specs[:signal_lifetime].type == Float64
        @test specs[:signal_lifetime].default == 0.2
        @test specs[:signal_lifetime].min_val == 0.01
        @test specs[:signal_lifetime].max_val == 1.0
        
        @test specs[:trade_cooldown].type == Minute
        @test specs[:trade_cooldown].default == Minute(1)
        
        @test specs[:ordertype].type == Symbol
        @test specs[:ordertype].default == :gtc
        @test specs[:ordertype].validator !== nothing
        
        @test specs[:ismake].type == Bool
        @test specs[:ismake].default == true
    end
    
    @testset "Parameter validation with custom validators" begin
        clear_parameter_cache!()
        
        # Register parameter with custom validator
        even_validator(x) = x % 2 == 0
        register_parameter!(ParameterSpec(
            name = :even_number,
            type = Int,
            default = 2,
            validator = even_validator
        ))
        
        # Valid even number
        @test validate_parameter(:even_number, 4) == true
        set_parameter!(:even_number, 6)
        @test get_parameter(:even_number) == 6
        
        # Invalid odd number
        @test_throws ArgumentError validate_parameter(:even_number, 3)
        @test_throws ArgumentError set_parameter!(:even_number, 5)
        
        # Test ordertype validator (from default parameters)
        @test validate_parameter(:ordertype, :gtc) == true
        @test validate_parameter(:ordertype, :ioc) == true
        @test_throws ArgumentError validate_parameter(:ordertype, :invalid_type)
    end
    
    @testset "Edge cases and error handling" begin
        clear_parameter_cache!()
        
        # Test with Period types
        register_parameter!(ParameterSpec(name=:hour_param, type=Hour, default=Hour(1)))
        register_parameter!(ParameterSpec(name=:day_param, type=Day, default=Day(1)))
        
        # Test conversion from float vector
        result = convert_float_vector_to_params([2.0, 3.0], [:hour_param, :day_param])
        @test result[:hour_param] == Hour(2)
        @test result[:day_param] == Day(3)
        
        # Test conversion to float vector
        params = Dict(:hour_param => Hour(4), :day_param => Day(5))
        float_result = convert_params_to_float_vector(params, [:hour_param, :day_param])
        @test float_result == [4.0, 5.0]
        
        # Test bounds with Period types
        register_parameter!(ParameterSpec(
            name = :bounded_minute,
            type = Minute,
            default = Minute(5),
            min_val = Minute(1),
            max_val = Minute(10)
        ))
        
        @test validate_parameter(:bounded_minute, Minute(5)) == true
        @test_throws ArgumentError validate_parameter(:bounded_minute, Minute(0))
        @test_throws ArgumentError validate_parameter(:bounded_minute, Minute(15))
        
        # Test empty parameter names
        @test convert_float_vector_to_params(Float64[], Symbol[]) == Dict{Symbol, Any}()
        @test convert_params_to_float_vector(Dict{Symbol, Any}(), Symbol[]) == Float64[]
        
        # Test parameter cache timestamp update
        original_time = PARAMETER_CACHE.last_update
        sleep(0.001)  # Ensure time difference
        set_parameter!(:bounded_minute, Minute(3))
        @test PARAMETER_CACHE.last_update > original_time
    end
end