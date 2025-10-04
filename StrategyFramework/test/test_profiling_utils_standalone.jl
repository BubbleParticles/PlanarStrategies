# Standalone test for profiling utilities
# This test can be run independently without the full StrategyFramework

using Test
using Dates

# Mock the required constants and types for testing
const PROFILING = Ref(false)

# Mock Strategy type for testing
struct MockStrategy end
const SC = MockStrategy

# Mock issim function for testing
issim(x) = false

# Include just the profiling utilities
include("../src/utilities/profiling_utils.jl")

@testset "Profiling Utils Standalone Tests" begin
    
    @testset "Profile availability" begin
        available = is_profile_available()
        @test isa(available, Bool)
        
        # Test the detection logic
        if isdefined(Main, :Profile)
            @test available == (isdefined(Main.Profile, :@profile) && 
                              isdefined(Main.Profile, :clear) && 
                              isdefined(Main.Profile, :print))
        else
            @test available == false
        end
    end
    
    @testset "Global profiling state" begin
        # Test initial state
        @test is_profiling_enabled() == false
        
        # Test enabling
        enable_profiling!(true)
        @test is_profiling_enabled() == true
        @test PROFILING[] == true
        
        # Test disabling
        enable_profiling!(false)
        @test is_profiling_enabled() == false
        @test PROFILING[] == false
    end
    
    @testset "Simple profiling execution" begin
        # Test basic execution without profiling
        result = with_profiling() do
            2 + 2
        end
        @test result == 4
        
        # Test with profiling enabled
        enable_profiling!(true)
        result = with_profiling() do
            3 * 4
        end
        @test result == 12
        
        # Reset state
        enable_profiling!(false)
    end
    
    @testset "Profiling with parameters" begin
        result = with_profiling_simple(profile_name="test", min_duration=Millisecond(1)) do
            "hello world"
        end
        @test result == "hello world"
    end
    
    @testset "Profile utility functions" begin
        # These should not error regardless of Profile availability
        @test_nowarn clear_profile()
        @test_nowarn start_profiling()
        @test_nowarn stop_profiling()
        # configure_profiling may warn if Profile is not available, but should not error
        try
            configure_profiling(sample_rate=0.01, max_samples=1000)
            @test true  # No error occurred
        catch e
            @test false  # Should not error
        end
    end
    
    @testset "Profile if slow functionality" begin
        # Fast operation
        result = profile_if_slow(Millisecond(1000)) do
            1 + 1
        end
        @test result == 2
        
        # Test with custom profile name
        result = profile_if_slow(Millisecond(1000), profile_name="custom") do
            [1, 2, 3]
        end
        @test result == [1, 2, 3]
    end
    
    @testset "Error propagation" begin
        # Test that errors are properly propagated through profiling wrapper
        @test_throws DivideError with_profiling() do
            1 ÷ 0
        end
        
        @test_throws BoundsError with_profiling_simple() do
            arr = [1, 2]
            arr[5]
        end
    end
    
    @testset "Profile results saving" begin
        # Test save function doesn't error (even if it can't actually save)
        @test_nowarn save_profile_results("test_profile", Millisecond(100))
    end
end

# Test with Profile module if it's available
if isdefined(Main, :Profile)
    @testset "With Profile Module Available" begin
        @testset "Profile operations" begin
            # Test that profile operations work when module is available
            @test_nowarn clear_profile()
            @test_nowarn start_profiling()
            @test_nowarn stop_profiling()
        end
        
        @testset "Actual profiling" begin
            enable_profiling!(true)
            
            result = with_profiling(profile_name="actual_test") do
                # Some work to profile
                sum(1:1000)
            end
            
            @test result == 500500
            
            enable_profiling!(false)
        end
    end
else
    @testset "Without Profile Module" begin
        @test is_profile_available() == false
        
        # Operations should still work but do nothing
        @test_nowarn clear_profile()
        @test_nowarn start_profiling()
        @test_nowarn stop_profiling()
    end
end

println("Profiling utils standalone tests completed successfully!")