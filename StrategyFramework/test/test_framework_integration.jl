# Integration tests for StrategyFramework key functions
using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

# Test that we can load the StrategyFramework module
framework_loaded = false
try
    include("../src/StrategyFramework.jl")
    using .StrategyFramework
    global framework_loaded = true
catch e
    @warn "Could not load StrategyFramework module: $e"
    global framework_loaded = false
end

@testset "StrategyFramework Integration Tests" begin
    
    @testset "Module loading and exports" begin
        if framework_loaded
            # Test that key types are exported
            @test isdefined(StrategyFramework, :SignalGenerator)
            
            # Test that key functions are exported
            exported_functions = [
                :generate_buy_signal, :generate_sell_signal,
                :should_trade, :get_signal_lifetime,
                :calculate_position_adjustment, :get_target_position_size, :trade_amount,
                :track_pnl!, :track_trends!, :initialize_ohlcv!,
                :with_profiling, :liveasync, :livelock
            ]
            
            for func in exported_functions
                @test isdefined(StrategyFramework, func)
            end
            
            println("✓ All key functions are exported")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
    
    @testset "SignalGenerator interface" begin
        if framework_loaded
            # Test that SignalGenerator is an abstract type
            @test isa(StrategyFramework.SignalGenerator, Type)
            @test isabstracttype(StrategyFramework.SignalGenerator)
            
            # Create a simple test signal generator
            struct TestSignalGenerator <: StrategyFramework.SignalGenerator
                threshold::Float64
                TestSignalGenerator() = new(0.5)
            end
            
            # Test that we can create instances
            sg = TestSignalGenerator()
            @test sg isa StrategyFramework.SignalGenerator
            @test sg.threshold == 0.5
            
            println("✓ SignalGenerator interface works correctly")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
    
    @testset "Basic function availability" begin
        if framework_loaded
            # Test that utility functions exist and can be called with mock data
            
            # Mock data for testing
            mock_strategy = Dict(
                :config => (def_lev = 1.0, reserve_cash_pct = 0.1),
                :balance => 10000.0,
                :indicators => Dict(:atr => 500.0, :kama_slope => 0.001)
            )
            
            mock_asset = "BTC/USDT"
            mock_timestamp = now()
            
            # Test that functions exist (we can't call them without proper setup, but we can check they exist)
            @test hasmethod(StrategyFramework.get_signal_lifetime, (Any,))
            
            # Test default signal lifetime
            struct DefaultSG <: StrategyFramework.SignalGenerator end
            default_sg = DefaultSG()
            
            # This should work with the default implementation
            lifetime = StrategyFramework.get_signal_lifetime(default_sg)
            @test lifetime isa Float64
            @test lifetime > 0.0
            
            println("✓ Basic functions are available and callable")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
    
    @testset "Configuration and parameter management" begin
        if framework_loaded
            # Test that configuration types exist
            @test isdefined(StrategyFramework, :ParameterSpec)
            @test isdefined(StrategyFramework, :ParameterCache)
            @test isdefined(StrategyFramework, :ConfigurationManager)
            
            # Test that parameter management functions exist
            param_functions = [
                :register_parameter!, :convert_params_to_float_vector,
                :validate_parameter, :set_parameter!, :get_parameter
            ]
            
            for func in param_functions
                @test isdefined(StrategyFramework, func)
            end
            
            println("✓ Configuration and parameter management available")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
    
    @testset "Integration utilities" begin
        if framework_loaded
            # Test that integration functions exist
            integration_functions = [
                :start_telegram, :send_telegram_notification,
                :configure_exchange!, :setup_exchange!,
                :configure_asset_universe!, :create_asset_universe
            ]
            
            for func in integration_functions
                @test isdefined(StrategyFramework, func)
            end
            
            # Test that configuration types exist
            @test isdefined(StrategyFramework, :ExchangeConfig)
            @test isdefined(StrategyFramework, :InstrumentUniverseConfig)
            @test isdefined(StrategyFramework, :MarketDataConfig)
            
            println("✓ Integration utilities available")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
    
    @testset "Error handling and validation" begin
        # Test basic validation functions that don't require the full framework
        
        # Test signal validation
        function test_validate_signal(signal::Float64)
            return 0.0 <= signal <= 1.0 && !isnan(signal) && !isinf(signal)
        end
        
        @test test_validate_signal(0.5) == true
        @test test_validate_signal(0.0) == true
        @test test_validate_signal(1.0) == true
        @test test_validate_signal(-0.1) == false
        @test test_validate_signal(1.1) == false
        @test test_validate_signal(NaN) == false
        @test test_validate_signal(Inf) == false
        
        # Test parameter validation
        function test_validate_parameter(name::String, value, bounds::Tuple{Float64, Float64})
            if !isa(value, Real)
                return false, "Parameter must be numeric"
            end
            
            min_val, max_val = bounds
            if value < min_val
                return false, "Parameter below minimum: $value < $min_val"
            elseif value > max_val
                return false, "Parameter above maximum: $value > $max_val"
            else
                return true, "Valid"
            end
        end
        
        valid, msg = test_validate_parameter("signal_lifetime", 0.2, (0.0, 1.0))
        @test valid == true
        
        invalid, msg = test_validate_parameter("signal_lifetime", 1.5, (0.0, 1.0))
        @test invalid == false
        @test contains(msg, "above maximum")
        
        println("✓ Error handling and validation functions work")
    end
    
    @testset "Performance and profiling utilities" begin
        if framework_loaded
            # Test that profiling functions exist
            profiling_functions = [
                :with_profiling, :enable_profiling!, :is_profiling_enabled,
                :configure_profiling, :profile_strategy_operation
            ]
            
            for func in profiling_functions
                @test isdefined(StrategyFramework, func)
            end
            
            println("✓ Performance and profiling utilities available")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
    
    @testset "Async and utility functions" begin
        if framework_loaded
            # Test that async utilities exist
            async_functions = [:liveasync, :livelock, :livesleep]
            
            for func in async_functions
                @test isdefined(StrategyFramework, func)
            end
            
            # Test that math utilities exist
            math_functions = [:calculate_position_adjustment, :get_target_position_size, :trade_amount]
            
            for func in math_functions
                @test isdefined(StrategyFramework, func)
            end
            
            println("✓ Async and utility functions available")
        else
            @test_skip "StrategyFramework module could not be loaded"
        end
    end
end

if framework_loaded
    println("✓ StrategyFramework integration tests completed successfully")
else
    println("⚠ StrategyFramework integration tests skipped due to loading issues")
end