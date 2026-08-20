# Async utilities for StrategyFramework
# Provides strategy-appropriate async operations, locking, and sleep utilities

using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

"""
    liveasync(f, s::SC)

Execute function `f` asynchronously in a strategy-appropriate manner.
In simulation mode, executes synchronously to maintain deterministic behavior.
In live/paper mode, executes asynchronously for better performance.

# Arguments
- `f`: Function to execute
- `s::SC`: Strategy instance

# Returns
- Task in live/paper mode, result directly in simulation mode
"""
function liveasync(f, s::SC)
    if issim(s)
        # In simulation, execute synchronously for deterministic behavior
        return f()
    else
        # In live/paper mode, execute asynchronously
        return @async f()
    end
end

"""
    livelock(f, lock, s::SC)

Execute function `f` with appropriate locking mechanism based on strategy mode.
In simulation mode, no locking is needed as execution is single-threaded.
In live/paper mode, uses the provided lock for thread safety.

# Arguments
- `f`: Function to execute
- `lock`: Lock object (ReentrantLock, etc.)
- `s::SC`: Strategy instance

# Returns
- Result of function `f`
"""
function livelock(f, lock, s::SC)
    if issim(s) || !THREADSAFE[]
        # In simulation or when thread safety is disabled, execute directly
        return f()
    else
        # In live/paper mode with thread safety, use lock
        return Base.lock(lock) do
            f()
        end
    end
end

"""
    livesleep(duration, s::SC)

Sleep for the specified duration in a strategy-appropriate manner.
In simulation mode, no actual sleep occurs to maintain speed.
In live/paper mode, performs actual sleep for timing control.

# Arguments
- `duration`: Sleep duration (Period, Real seconds, or DateTime)
- `s::SC`: Strategy instance

# Returns
- Nothing
"""
function livesleep(duration::Period, s::SC)
    if issim(s)
        # In simulation, no actual sleep
        return nothing
    else
        # In live/paper mode, perform actual sleep
        sleep(Dates.value(duration) / 1000.0)  # Convert to seconds
    end
end

function livesleep(duration::Real, s::SC)
    if issim(s)
        # In simulation, no actual sleep
        return nothing
    else
        # In live/paper mode, perform actual sleep
        sleep(duration)
    end
end

function livesleep(target_time::DateTime, s::SC)
    if issim(s)
        # In simulation, no actual sleep
        return nothing
    else
        # In live/paper mode, sleep until target time
        now_time = now()
        if target_time > now_time
            sleep_duration = (target_time - now_time).value / 1000.0
            sleep(sleep_duration)
        end
    end
end

"""
    async_with_timeout(f, timeout::Period, s::SC)

Execute function `f` asynchronously with a timeout.
Returns the result if completed within timeout, otherwise returns `nothing`.

# Arguments
- `f`: Function to execute
- `timeout`: Maximum execution time
- `s::SC`: Strategy instance

# Returns
- Result of `f` if completed within timeout, `nothing` otherwise
"""
function async_with_timeout(f, timeout::Period, s::SC)
    if issim(s)
        # In simulation, execute directly (no timeout needed)
        return f()
    else
        # In live/paper mode, use timeout
        task = @async f()
        timer = Timer(Dates.value(timeout) / 1000.0)
        
        # Wait for either task completion or timeout
        result = nothing
        try
            result = fetch(task)
            close(timer)
        catch e
            if isa(e, TaskFailedException) && !istaskdone(task)
                # Task timed out
                close(timer)
                return nothing
            else
                close(timer)
                rethrow(e)
            end
        end
        
        return result
    end
end

"""
    throttle_async(f, min_interval::Period, s::SC)

Create a throttled version of function `f` that ensures minimum interval between calls.
Returns a function that can be called repeatedly but will respect the minimum interval.

# Arguments
- `f`: Function to throttle
- `min_interval`: Minimum time between function calls
- `s::SC`: Strategy instance

# Returns
- Throttled function
"""
function throttle_async(f, min_interval::Period, s::SC)
    last_call = Ref{DateTime}(DateTime(0))
    
    return function throttled_f(args...; kwargs...)
        current_time = now()
        time_since_last = current_time - last_call[]
        min_interval_ms = Millisecond(min_interval)
        
        if time_since_last < min_interval_ms
            # Need to wait before executing
            wait_time = min_interval_ms - time_since_last
            livesleep(wait_time, s)
        end
        
        last_call[] = now()
        return f(args...; kwargs...)
    end
end

"""
    batch_async(tasks::Vector, batch_size::Int, s::SC)

Execute a vector of tasks in batches asynchronously.
Useful for rate-limited operations or memory management.

# Arguments
- `tasks`: Vector of functions/tasks to execute
- `batch_size`: Number of tasks to execute concurrently
- `s::SC`: Strategy instance

# Returns
- Vector of results in the same order as input tasks
"""
function batch_async(tasks::Vector, batch_size::Int, s::SC)
    if issim(s)
        # In simulation, execute all tasks synchronously
        return [task() for task in tasks]
    else
        # In live/paper mode, execute in batches
        results = Vector{Any}(undef, length(tasks))
        
        for i in 1:batch_size:length(tasks)
            batch_end = min(i + batch_size - 1, length(tasks))
            batch_tasks = [liveasync(tasks[j], s) for j in i:batch_end]
            
            # Wait for batch completion
            for (idx, task) in enumerate(batch_tasks)
                results[i + idx - 1] = fetch(task)
            end
        end
        
        return results
    end
end