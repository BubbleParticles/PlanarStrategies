# Standalone tests for async utilities
using Test
using Dates

# Mock the required constants and functions for testing
const THREADSAFE = Ref{Bool}(true)

# Mock strategy type for testing
struct MockStrategy
    is_sim::Bool
end

# Define SC type alias for compatibility
const SC = MockStrategy

# Mock issim function for testing
issim(s::MockStrategy) = s.is_sim

# Include the async utils directly
include("../src/utilities/async_utils.jl")

@testset "Async Utils Standalone Tests" begin
    
    @testset "liveasync function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Test function that returns a value
        test_func() = 42
        
        # In simulation mode, should execute synchronously
        result_sim = liveasync(test_func, sim_strategy)
        @test result_sim == 42
        @test !isa(result_sim, Task)
        
        # In live mode, should return a Task
        result_live = liveasync(test_func, live_strategy)
        @test isa(result_live, Task)
        @test fetch(result_live) == 42
    end
    
    @testset "livelock function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Mock lock object
        test_lock = ReentrantLock()
        
        # Test function
        counter = Ref(0)
        test_func() = (counter[] += 1; counter[])
        
        # In simulation mode, should execute without locking
        counter[] = 0
        result_sim = livelock(test_func, test_lock, sim_strategy)
        @test result_sim == 1
        
        # In live mode, should use lock
        counter[] = 0
        result_live = livelock(test_func, test_lock, live_strategy)
        @test result_live == 1
    end
    
    @testset "livesleep function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Test with Period - should be fast in sim mode
        start_time = time()
        livesleep(Millisecond(10), sim_strategy)
        sim_duration = time() - start_time
        @test sim_duration < 0.1  # Should be reasonably fast in sim mode
        
        # Test with Real (seconds) - should be fast in sim mode
        start_time = time()
        livesleep(0.01, sim_strategy)
        sim_duration = time() - start_time
        @test sim_duration < 0.1  # Should be reasonably fast in sim mode
        
        # Test with DateTime (past time - should not sleep)
        past_time = now() - Millisecond(10)
        start_time = time()
        livesleep(past_time, live_strategy)
        duration = time() - start_time
        @test duration < 0.1  # Should not sleep for past time
    end
    
    @testset "async_with_timeout function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Fast function (should complete within timeout)
        fast_func() = 42
        
        result_sim = async_with_timeout(fast_func, Millisecond(100), sim_strategy)
        @test result_sim == 42
        
        result_live = async_with_timeout(fast_func, Millisecond(100), live_strategy)
        @test result_live == 42
        
        # Function that throws an error
        error_func() = error("Test error")
        
        @test_throws ErrorException async_with_timeout(error_func, Millisecond(100), sim_strategy)
    end
    
    @testset "throttle_async function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Create a counter function
        counter = Ref(0)
        count_func() = (counter[] += 1; counter[])
        
        # Test throttling in simulation mode
        counter[] = 0
        throttled_func_sim = throttle_async(count_func, Millisecond(50), sim_strategy)
        
        start_time = time()
        result1 = throttled_func_sim()
        result2 = throttled_func_sim()
        duration = time() - start_time
        
        @test result1 == 1
        @test result2 == 2
        @test duration < 0.01  # Should be fast in sim mode (no actual throttling)
        
        # Test with arguments
        add_func(x, y) = x + y
        throttled_add = throttle_async(add_func, Millisecond(10), live_strategy)
        
        @test throttled_add(2, 3) == 5
        @test throttled_add(4, 5) == 9
    end
    
    @testset "batch_async function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Create test tasks
        tasks = [() -> i^2 for i in 1:5]
        
        # Test in simulation mode
        results_sim = batch_async(tasks, 2, sim_strategy)
        @test results_sim == [1, 4, 9, 16, 25]
        
        # Test in live mode
        results_live = batch_async(tasks, 2, live_strategy)
        @test results_live == [1, 4, 9, 16, 25]
        
        # Test with empty task list
        empty_results_sim = batch_async(Function[], 2, sim_strategy)
        @test empty_results_sim == []
    end
end

println("✓ Async utilities tests passed")