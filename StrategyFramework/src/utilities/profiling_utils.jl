# Profiling utilities for StrategyFramework
# Provides optional performance profiling integration with Main.Profile when available

using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

"""
    with_profiling(f, s::SC; enabled::Bool = PROFILING[], 
                   profile_name::String = "strategy_operation",
                   min_duration::Period = Millisecond(100))

Execute function `f` with optional performance profiling.
Profiling is only enabled when explicitly requested and Main.Profile is available.

# Arguments
- `f`: Function to execute and profile
- `s::SC`: Strategy instance (used for mode detection)
- `enabled::Bool`: Whether profiling is enabled (default: PROFILING[])
- `profile_name::String`: Name for the profiling session
- `min_duration::Period`: Minimum execution time to trigger profiling

# Returns
- Result of function `f`

# Examples
```julia
# Profile a trading operation
result = with_profiling(s) do
    execute_complex_trading_logic()
end

# Profile with custom settings
result = with_profiling(s; enabled=true, profile_name="signal_generation") do
    generate_signals()
end
```
"""
function with_profiling(f, s::SC; 
                       enabled::Bool = PROFILING[], 
                       profile_name::String = "strategy_operation",
                       min_duration::Period = Millisecond(100))
    
    # Skip profiling in simulation mode unless explicitly enabled
    if issim(s) && !enabled
        return f()
    end
    
    # Skip profiling if disabled globally
    if !enabled
        return f()
    end
    
    # Check if Profile module is available
    if !is_profile_available()
        @debug "Profiling requested but Main.Profile not available, executing without profiling"
        return f()
    end
    
    # Execute with timing to check if profiling is worthwhile
    start_time = now()
    
    # Clear any existing profile data
    clear_profile()
    
    # Start profiling
    start_profiling()
    
    try
        result = f()
        
        # Stop profiling
        stop_profiling()
        
        # Check execution duration
        execution_time = now() - start_time
        if execution_time >= min_duration
            # Save profile results
            save_profile_results(profile_name, execution_time)
        else
            @debug "Execution time ($execution_time) below minimum threshold ($min_duration), skipping profile save"
        end
        
        return result
        
    catch e
        # Stop profiling even on error
        stop_profiling()
        @error "Error during profiled execution" exception=e profile_name=profile_name
        rethrow(e)
    end
end

"""
    with_profiling(f; kwargs...)

Convenience method for profiling without strategy instance.
Uses global profiling settings.
"""
function with_profiling(f; kwargs...)
    # Execute with profiling if globally enabled
    if PROFILING[]
        return with_profiling_simple(f; kwargs...)
    else
        return f()
    end
end

"""
    with_profiling_simple(f; profile_name::String = "operation", 
                          min_duration::Period = Millisecond(100))

Simple profiling wrapper without strategy context.
"""
function with_profiling_simple(f; 
                              profile_name::String = "operation",
                              min_duration::Period = Millisecond(100))
    
    # Check if Profile module is available
    if !is_profile_available()
        @debug "Profiling requested but Main.Profile not available"
        return f()
    end
    
    start_time = now()
    
    clear_profile()
    start_profiling()
    
    try
        result = f()
        stop_profiling()
        
        execution_time = now() - start_time
        if execution_time >= min_duration
            save_profile_results(profile_name, execution_time)
        end
        
        return result
        
    catch e
        stop_profiling()
        @error "Error during profiled execution" exception=e profile_name=profile_name
        rethrow(e)
    end
end

"""
    is_profile_available()

Check if Main.Profile module is available for profiling.

# Returns
- `true` if Profile module is available, `false` otherwise
"""
function is_profile_available()
    try
        return isdefined(Main, :Profile) && 
               isdefined(Main.Profile, :@profile) &&
               isdefined(Main.Profile, :clear) &&
               isdefined(Main.Profile, :print)
    catch
        return false
    end
end

"""
    clear_profile()

Clear existing profile data if Profile module is available.
"""
function clear_profile()
    if is_profile_available()
        try
            Main.Profile.clear()
        catch e
            @debug "Failed to clear profile data" exception=e
        end
    end
end

"""
    start_profiling()

Start profiling if Profile module is available.
"""
function start_profiling()
    if is_profile_available()
        try
            # Enable profiling with reasonable sample rate
            Main.Profile.init(n = 10^7, delay = 0.01)
            Main.Profile.start_timer()
        catch e
            @debug "Failed to start profiling" exception=e
        end
    end
end

"""
    stop_profiling()

Stop profiling if Profile module is available.
"""
function stop_profiling()
    if is_profile_available()
        try
            Main.Profile.stop_timer()
        catch e
            @debug "Failed to stop profiling" exception=e
        end
    end
end

"""
    save_profile_results(profile_name::String, execution_time::Period)

Save profiling results to file and optionally print summary.

# Arguments
- `profile_name::String`: Name for the profiling session
- `execution_time::Period`: Total execution time
"""
function save_profile_results(profile_name::String, execution_time::Period)
    if !is_profile_available()
        return
    end
    
    try
        # Create profile output directory if it doesn't exist
        profile_dir = "user/logs/profiles"
        if !isdir(profile_dir)
            mkpath(profile_dir)
        end
        
        # Generate filename with timestamp
        timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
        filename = joinpath(profile_dir, "$(profile_name)_$(timestamp).txt")
        
        # Save profile to file
        open(filename, "w") do io
            println(io, "Profile: $profile_name")
            println(io, "Execution time: $execution_time")
            println(io, "Timestamp: $(now())")
            println(io, "=" ^ 50)
            Main.Profile.print(io)
        end
        
        @info "Profile saved" profile_name=profile_name execution_time=execution_time filename=filename
        
        # Print summary to console if in debug mode
        if get(ENV, "JULIA_DEBUG", "") != ""
            println("Profile summary for $profile_name (execution time: $execution_time):")
            Main.Profile.print(maxdepth=10)
        end
        
    catch e
        @error "Failed to save profile results" exception=e profile_name=profile_name
    end
end

"""
    enable_profiling!(enabled::Bool = true)

Enable or disable profiling globally.

# Arguments
- `enabled::Bool`: Whether to enable profiling (default: true)
"""
function enable_profiling!(enabled::Bool = true)
    PROFILING[] = enabled
    @info "Profiling $(enabled ? "enabled" : "disabled")"
end

"""
    is_profiling_enabled()

Check if profiling is currently enabled.

# Returns
- `true` if profiling is enabled, `false` otherwise
"""
function is_profiling_enabled()
    return PROFILING[]
end

"""
    profile_strategy_operation(f, operation_name::String, s::SC)

Convenience function for profiling common strategy operations.

# Arguments
- `f`: Function to profile
- `operation_name::String`: Name of the operation being profiled
- `s::SC`: Strategy instance

# Returns
- Result of function `f`
"""
function profile_strategy_operation(f, operation_name::String, s::SC)
    return with_profiling(f, s; 
                         profile_name="strategy_$(operation_name)",
                         min_duration=Millisecond(50))
end

"""
    profile_if_slow(f, threshold::Period = Second(1); profile_name::String = "slow_operation")

Profile function only if execution takes longer than threshold.

# Arguments
- `f`: Function to execute
- `threshold::Period`: Time threshold to trigger profiling
- `profile_name::String`: Name for profiling session

# Returns
- Result of function `f`
"""
function profile_if_slow(f, threshold::Period = Second(1); profile_name::String = "slow_operation")
    start_time = now()
    result = f()
    execution_time = now() - start_time
    
    if execution_time >= threshold && PROFILING[]
        @info "Slow operation detected, re-running with profiling" operation=profile_name execution_time=execution_time
        # Re-run with profiling
        return with_profiling(f; profile_name=profile_name, min_duration=Millisecond(0))
    end
    
    return result
end

"""
    configure_profiling(; sample_rate::Float64 = 0.01, max_samples::Int = 10^7)

Configure profiling parameters.

# Arguments
- `sample_rate::Float64`: Profiling sample rate in seconds (default: 0.01)
- `max_samples::Int`: Maximum number of samples to collect (default: 10^7)
"""
function configure_profiling(; sample_rate::Float64 = 0.01, max_samples::Int = 10^7)
    if is_profile_available()
        try
            Main.Profile.init(n = max_samples, delay = sample_rate)
            @info "Profiling configured" sample_rate=sample_rate max_samples=max_samples
        catch e
            @error "Failed to configure profiling" exception=e
        end
    else
        @warn "Profile module not available, cannot configure profiling"
    end
end