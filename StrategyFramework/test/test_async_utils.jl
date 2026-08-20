# Unit tests for async utilities
using Test
using StrategyFramework
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

# Mock strategy type for testing
struct MockStrategy
    is_sim::Bool
end

# Mock issim function for testing
issim(s::MockStrategy) = s.is_sim

@testset "Async Utils Tests" begin
    
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
        
        # Test with function that has side effects
        counter = Ref(0)
        side_effect_func() = (counter[] += 1; counter[])
        
        counter[] = 0
        result_sim = liveasync(side_effect_func, sim_strategy)
        @test result_sim == 1
        @test counter[] == 1
        
        counter[] = 0
        result_live = liveasync(side_effect_func, live_strategy)
        @test fetch(result_live) == 1
        @test counter[] == 1
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
        
        # In live mode, should use lock (harder to test directly, but should work)
        counter[] = 0
        result_live = livelock(test_func, test_lock, live_strategy)
        @test result_live == 1
        
        # Test with THREADSAFE disabled
        original_threadsafe = THREADSAFE[]
        try
            THREADSAFE[] = false
            counter[] = 0
            result = livelock(test_func, test_lock, live_strategy)
            @test result == 1
        finally
            THREADSAFE[] = original_threadsafe
        end
    end
    
    @testset "livesleep function" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Test with Period
        start_time = time()
        livesleep(Millisecond(10), sim_strategy)
        sim_duration = time() - start_time
        @test sim_duration < 0.005  # Should be very fast in sim mode
        
        start_time = time()
        livesleep(Millisecond(10), live_strategy)
        live_duration = time() - start_time
        @test live_duration >= 0.008  # Should actually sleep in live mode
        
        # Test with Real (seconds)
        start_time = time()
        livesleep(0.01, sim_strategy)
        sim_duration = time() - start_time
        @test sim_duration < 0.005  # Should be very fast in sim mode
        
        start_time = time()
        livesleep(0.01, live_strategy)
        live_duration = time() - start_time
        @test live_duration >= 0.008  # Should actually sleep in live mode
        
        # Test with DateTime (future time)
        future_time = now() + Millisecond(10)
        start_time = time()
        livesleep(future_time, sim_strategy)
        sim_duration = time() - start_time
        @test sim_duration < 0.005  # Should be very fast in sim mode
        
        start_time = time()
        livesleep(now() + Millisecond(10), live_strategy)
        live_duration = time() - start_time
        @test live_duration >= 0.008  # Should actually sleep in live mode
        
        # Test with DateTime (past time - should not sleep)
        past_time = now() - Millisecond(10)
        start_time = time()
        livesleep(past_time, live_strategy)
        duration = time() - start_time
        @test duration < 0.005  # Should not sleep for past time
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
        
        # Slow function (should timeout in live mode, but complete in sim mode)
        slow_func() = (sleep(0.05); 42)
        
        result_sim = async_with_timeout(slow_func, Millisecond(10), sim_strategy)
        @test result_sim == 42  # No timeout in sim mode
        
        result_live = async_with_timeout(slow_func, Millisecond(10), live_strategy)
        @test result_live === nothing  # Should timeout in live mode
        
        # Function that throws an error
        error_func() = error("Test error")
        
        @test_throws ErrorException async_with_timeout(error_func, Millisecond(100), sim_strategy)
        @test_throws TaskFailedException async_with_timeout(error_func, Millisecond(100), live_strategy)
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
        
        # Test throttling in live mode
        counter[] = 0
        throttled_func_live = throttle_async(count_func, Millisecond(20), live_strategy)
        
        start_time = time()
        result1 = throttled_func_live()
        result2 = throttled_func_live()
        duration = time() - start_time
        
        @test result1 == 1
        @test result2 == 2
        @test duration >= 0.015  # Should actually throttle in live mode
        
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
        
        empty_results_live = batch_async(Function[], 2, live_strategy)
        @test empty_results_live == []
        
        # Test with batch size larger than task count
        small_tasks = [() -> i for i in 1:2]
        results_large_batch = batch_async(small_tasks, 5, live_strategy)
        @test results_large_batch == [1, 2]
        
        # Test with batch size of 1
        results_single_batch = batch_async(tasks, 1, live_strategy)
        @test results_single_batch == [1, 4, 9, 16, 25]
        
        # Test with tasks that have different execution times
        timed_tasks = [
            () -> (sleep(0.001); 1),
            () -> (sleep(0.002); 2),
            () -> (sleep(0.001); 3)
        ]
        results_timed = batch_async(timed_tasks, 2, live_strategy)
        @test results_timed == [1, 2, 3]
    end
    
    @testset "Edge cases and error handling" begin
        sim_strategy = MockStrategy(true)
        live_strategy = MockStrategy(false)
        
        # Test liveasync with function that throws
        error_func() = error("Test error")
        
        @test_throws ErrorException liveasync(error_func, sim_strategy)
        
        task_result = liveasync(error_func, live_strategy)
        @test isa(task_result, Task)
        @test_throws TaskFailedException fetch(task_result)
        
        # Test livelock with function that throws
        test_lock = ReentrantLock()
        @test_throws ErrorException livelock(error_func, test_lock, sim_strategy)
        @test_throws ErrorException livelock(error_func, test_lock, live_strategy)
        
        # Test throttle_async with zero interval
        counter = Ref(0)
        count_func() = (counter[] += 1; counter[])
        throttled_zero = throttle_async(count_func, Millisecond(0), live_strategy)
        
        counter[] = 0
        result1 = throttled_zero()
        result2 = throttled_zero()
        @test result1 == 1
        @test result2 == 2
    end
end