# Test profiling utilities

using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Planar

# Include the module being tested
include("../src/StrategyFramework.jl")
using .StrategyFramework

@testset "Profiling Utils Tests" begin
    
    @testset "Profile availability detection" begin
        # Test profile availability check
        available = StrategyFramework.is_profile_available()
        @test isa(available, Bool)
        
        # The result depends on whether Profile is loaded in Main
        # We can't guarantee it's available in test environment
        if available
            @test isdefined(Main, :Profile)
        end
    end
    
    @testset "Profiling enable/disable" begin
        # Test enabling profiling
        original_state = StrategyFramework.is_profiling_enabled()
        
        StrategyFramework.enable_profiling!(true)
        @test StrategyFramework.is_profiling_enabled() == true
        
        StrategyFramework.enable_profiling!(false)
        @test StrategyFramework.is_profiling_enabled() == false
        
        # Restore original state
        StrategyFramework.enable_profiling!(original_state)
    end
    
    @testset "Simple profiling wrapper" begin
        # Test basic profiling wrapper without strategy
        test_value = 42
        
        result = StrategyFramework.with_profiling() do
            test_value * 2
        end
        
        @test result == 84
        
        # Test with custom profile name
        result = StrategyFramework.with_profiling(profile_name="test_operation") do
            test_value + 10
        end
        
        @test result == 52
    end
    
    @testset "Profile configuration" begin
        # Test profiling configuration
        # This should not error even if Profile is not available
        @test_nowarn StrategyFramework.configure_profiling(sample_rate=0.02, max_samples=1000)
    end
    
    @testset "Profile utility functions" begin
        # Test clear profile (should not error)
        @test_nowarn StrategyFramework.clear_profile()
        
        # Test start/stop profiling (should not error)
        @test_nowarn StrategyFramework.start_profiling()
        @test_nowarn StrategyFramework.stop_profiling()
    end
    
    @testset "Profile if slow" begin
        # Test fast operation (should not trigger profiling)
        fast_result = StrategyFramework.profile_if_slow(Millisecond(1)) do
            1 + 1
        end
        @test fast_result == 2
        
        # Test with custom threshold
        result = StrategyFramework.profile_if_slow(Millisecond(1), profile_name="custom_test") do
            sum(1:100)
        end
        @test result == 5050
    end
    
    @testset "Error handling in profiling" begin
        # Test that errors are properly propagated
        @test_throws DivideByZeroError StrategyFramework.with_profiling() do
            1 ÷ 0
        end
        
        # Test error handling with profile name
        @test_throws BoundsError StrategyFramework.with_profiling(profile_name="error_test") do
            arr = [1, 2, 3]
            arr[10]  # This will throw BoundsError
        end
    end
    
    @testset "Profiling with different durations" begin
        # Test minimum duration threshold
        short_result = StrategyFramework.with_profiling(min_duration=Hour(1)) do
            "quick operation"
        end
        @test short_result == "quick operation"
        
        # Test with very short threshold
        long_result = StrategyFramework.with_profiling(min_duration=Millisecond(1)) do
            "operation"
        end
        @test long_result == "operation"
    end
end

@testset "Profiling Utils Integration Tests" begin
    
    @testset "Mock strategy profiling" begin
        # Create a mock strategy-like object for testing
        # Since we don't have access to actual Strategy objects in tests,
        # we'll test the non-strategy methods
        
        test_data = Dict("key" => "value")
        
        result = StrategyFramework.with_profiling(profile_name="integration_test") do
            # Simulate some work
            processed = Dict()
            for (k, v) in test_data
                processed[k] = uppercase(v)
            end
            processed
        end
        
        @test result["key"] == "VALUE"
    end
    
    @testset "Profile directory creation" begin
        # Test that profile directory would be created
        # We can't easily test the actual file creation without mocking
        # but we can test the logic doesn't error
        
        @test_nowarn StrategyFramework.with_profiling(profile_name="directory_test") do
            42
        end
    end
end

# Test with actual Profile module if available
@testset "Profile Module Integration" begin
    if StrategyFramework.is_profile_available()
        @testset "With Profile module available" begin
            # Enable profiling for these tests
            StrategyFramework.enable_profiling!(true)
            
            # Test actual profiling
            result = StrategyFramework.with_profiling(profile_name="profile_integration") do
                # Do some work that can be profiled
                sum(rand(1000))
            end
            
            @test isa(result, Float64)
            
            # Test configuration
            @test_nowarn StrategyFramework.configure_profiling(sample_rate=0.001, max_samples=1000)
            
            # Disable profiling after tests
            StrategyFramework.enable_profiling!(false)
        end
    else
        @testset "Without Profile module" begin
            @test_logs (:debug, r"Profile.*not available") StrategyFramework.with_profiling(profile_name="no_profile") do
                42
            end
        end
    end
end