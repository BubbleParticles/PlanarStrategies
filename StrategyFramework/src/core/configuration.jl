# Configuration management system for StrategyFramework

using Planar
using TOML
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

"""
    ConfigurationManager

Manages strategy configuration loading, validation, and environment-specific overrides.
"""
mutable struct ConfigurationManager
    base_config::Dict{String, Any}
    environment_configs::Dict{Symbol, Dict{String, Any}}
    current_environment::Symbol
    config_file_path::String
    last_loaded::DateTime
    
    ConfigurationManager() = new(
        Dict{String, Any}(),
        Dict{Symbol, Dict{String, Any}}(),
        :default,
        "",
        DateTime(0)
    )
end

# Global configuration manager
const CONFIG_MANAGER = ConfigurationManager()

"""
    load_configuration!(config_path::String; environment::Symbol = :default)

Load strategy configuration from a TOML file with environment-specific overrides.
"""
function load_configuration!(config_path::String; environment::Symbol = :default)
    if !isfile(config_path)
        @warn "Configuration file not found: $config_path. Using defaults."
        return CONFIG_MANAGER
    end
    
    try
        config_data = TOML.parsefile(config_path)
        
        # Store base configuration
        CONFIG_MANAGER.base_config = config_data
        CONFIG_MANAGER.config_file_path = config_path
        CONFIG_MANAGER.current_environment = environment
        CONFIG_MANAGER.last_loaded = now()
        
        # Load environment-specific configurations
        if haskey(config_data, "environments")
            for (env_name, env_config) in config_data["environments"]
                CONFIG_MANAGER.environment_configs[Symbol(env_name)] = env_config
            end
        end
        
        @info "Configuration loaded from $config_path for environment $environment"
        
    catch e
        @error "Failed to load configuration from $config_path: $e"
        rethrow(e)
    end
    
    return CONFIG_MANAGER
end

"""
    get_config_value(key::String, default::Any = nothing; environment::Symbol = CONFIG_MANAGER.current_environment)

Get a configuration value with environment-specific override support.
"""
function get_config_value(key::String, default::Any = nothing; environment::Symbol = CONFIG_MANAGER.current_environment)
    # Check environment-specific config first
    if haskey(CONFIG_MANAGER.environment_configs, environment)
        env_config = CONFIG_MANAGER.environment_configs[environment]
        if haskey(env_config, key)
            return env_config[key]
        end
    end
    
    # Check base config
    if haskey(CONFIG_MANAGER.base_config, key)
        return CONFIG_MANAGER.base_config[key]
    end
    
    # Return default
    return default
end

"""
    set_config_value!(key::String, value::Any; environment::Symbol = CONFIG_MANAGER.current_environment)

Set a configuration value for the specified environment.
"""
function set_config_value!(key::String, value::Any; environment::Symbol = CONFIG_MANAGER.current_environment)
    if environment == :default
        CONFIG_MANAGER.base_config[key] = value
    else
        if !haskey(CONFIG_MANAGER.environment_configs, environment)
            CONFIG_MANAGER.environment_configs[environment] = Dict{String, Any}()
        end
        CONFIG_MANAGER.environment_configs[environment][key] = value
    end
end

"""
    validate_configuration()

Validate the current configuration against parameter specifications.
"""
function validate_configuration()
    errors = String[]
    
    # Get all parameter specs
    specs = get_parameter_specs()
    
    for (param_name, spec) in specs
        key = string(param_name)
        value = get_config_value(key)
        
        if value !== nothing
            try
                validate_parameter(param_name, value)
            catch e
                push!(errors, "Parameter $param_name: $(e.msg)")
            end
        end
    end
    
    if !isempty(errors)
        error_msg = "Configuration validation failed:\n" * join(errors, "\n")
        throw(ArgumentError(error_msg))
    end
    
    return true
end

"""
    apply_configuration_to_strategy!(s::SC)

Apply the current configuration to a strategy instance.
"""
function apply_configuration_to_strategy!(s::SC)
    # Get strategy config from strategy instance
    if !hasfield(typeof(s), :config)
        @warn "Strategy does not have a config field"
        return
    end
    
    config = s.config
    
    # Apply configuration values to strategy config
    specs = get_parameter_specs()
    
    for (param_name, spec) in specs
        key = string(param_name)
        value = get_config_value(key)
        
        if value !== nothing
            try
                # Convert value to appropriate type
                converted_value = convert(spec.type, value)
                
                # Validate the value
                validate_parameter(param_name, converted_value)
                
                # Set the value in strategy config
                if hasfield(typeof(config), param_name)
                    setfield!(config, param_name, converted_value)
                end
                
                # Also set in parameter cache
                set_parameter!(param_name, converted_value)
                
            catch e
                @warn "Failed to apply configuration for $param_name: $e"
            end
        end
    end
end

"""
    load_environment_variables!()

Load configuration from environment variables with STRATEGY_FRAMEWORK_ prefix.
"""
function load_environment_variables!()
    prefix = "STRATEGY_FRAMEWORK_"
    
    for (env_key, env_value) in ENV
        if startswith(env_key, prefix)
            # Remove prefix and convert to lowercase
            config_key = lowercase(env_key[length(prefix)+1:end])
            
            # Try to parse the value
            parsed_value = try_parse_env_value(env_value)
            
            # Set in configuration
            set_config_value!(config_key, parsed_value)
            
            @info "Loaded environment variable: $config_key = $parsed_value"
        end
    end
end

"""
    try_parse_env_value(value::String)

Try to parse an environment variable value to appropriate type.
"""
function try_parse_env_value(value::String)
    # Try boolean
    if lowercase(value) in ["true", "false"]
        return lowercase(value) == "true"
    end
    
    # Try integer
    try
        return parse(Int, value)
    catch
    end
    
    # Try float
    try
        return parse(Float64, value)
    catch
    end
    
    # Return as string
    return value
end

"""
    save_configuration!(config_path::String = CONFIG_MANAGER.config_file_path)

Save the current configuration to a TOML file.
"""
function save_configuration!(config_path::String = CONFIG_MANAGER.config_file_path)
    if isempty(config_path)
        throw(ArgumentError("No configuration file path specified"))
    end
    
    # Prepare configuration data
    config_data = copy(CONFIG_MANAGER.base_config)
    
    # Add environments section if there are environment-specific configs
    if !isempty(CONFIG_MANAGER.environment_configs)
        config_data["environments"] = Dict{String, Any}()
        for (env_name, env_config) in CONFIG_MANAGER.environment_configs
            config_data["environments"][string(env_name)] = env_config
        end
    end
    
    try
        # Ensure directory exists
        config_dir = dirname(config_path)
        if !isdir(config_dir)
            mkpath(config_dir)
        end
        
        # Write configuration
        open(config_path, "w") do io
            TOML.print(io, config_data)
        end
        
        @info "Configuration saved to $config_path"
        
    catch e
        @error "Failed to save configuration to $config_path: $e"
        rethrow(e)
    end
end

"""
    get_configuration_summary()

Get a summary of the current configuration.
"""
function get_configuration_summary()
    summary = Dict{String, Any}()
    
    summary["config_file"] = CONFIG_MANAGER.config_file_path
    summary["current_environment"] = CONFIG_MANAGER.current_environment
    summary["last_loaded"] = CONFIG_MANAGER.last_loaded
    summary["base_config_keys"] = collect(keys(CONFIG_MANAGER.base_config))
    summary["environments"] = collect(keys(CONFIG_MANAGER.environment_configs))
    
    # Get current parameter values
    current_params = Dict{String, Any}()
    specs = get_parameter_specs()
    
    for (param_name, spec) in specs
        key = string(param_name)
        value = get_config_value(key, spec.default)
        current_params[key] = value
    end
    
    summary["current_parameters"] = current_params
    
    return summary
end

"""
    reset_configuration!()

Reset configuration to defaults.
"""
function reset_configuration!()
    empty!(CONFIG_MANAGER.base_config)
    empty!(CONFIG_MANAGER.environment_configs)
    CONFIG_MANAGER.current_environment = :default
    CONFIG_MANAGER.config_file_path = ""
    CONFIG_MANAGER.last_loaded = DateTime(0)
    
    # Clear parameter cache
    clear_parameter_cache!()
    
    # Re-register default parameters
    register_default_parameters!()
    
    @info "Configuration reset to defaults"
end

"""
    create_default_config_file(config_path::String)

Create a default configuration file with all available parameters.
"""
function create_default_config_file(config_path::String)
    config_data = Dict{String, Any}()
    
    # Add header comment
    config_data["_comment"] = "StrategyFramework Configuration File"
    
    # Add all default parameters
    specs = get_parameter_specs()
    
    for (param_name, spec) in specs
        key = string(param_name)
        config_data[key] = spec.default
        
        # Add description as comment if available
        if !isempty(spec.description)
            config_data["_comment_$key"] = spec.description
        end
    end
    
    # Add example environments section
    config_data["environments"] = Dict{String, Any}(
        "development" => Dict{String, Any}(
            "signal_lifetime" => 0.1,
            "def_lev" => 0.5,
            "_comment" => "Development environment with conservative settings"
        ),
        "production" => Dict{String, Any}(
            "signal_lifetime" => 0.2,
            "def_lev" => 2.0,
            "_comment" => "Production environment with optimized settings"
        )
    )
    
    # Ensure directory exists
    config_dir = dirname(config_path)
    if !isdir(config_dir)
        mkpath(config_dir)
    end
    
    # Write configuration
    open(config_path, "w") do io
        TOML.print(io, config_data)
    end
    
    @info "Default configuration file created at $config_path"
end

"""
    switch_environment!(environment::Symbol)

Switch to a different configuration environment.
"""
function switch_environment!(environment::Symbol)
    if environment != :default && !haskey(CONFIG_MANAGER.environment_configs, environment)
        @warn "Environment $environment not found in configuration. Available: $(keys(CONFIG_MANAGER.environment_configs))"
    end
    
    CONFIG_MANAGER.current_environment = environment
    @info "Switched to environment: $environment"
end

"""
    merge_configurations!(source_config::Dict{String, Any})

Merge a configuration dictionary into the current configuration.
"""
function merge_configurations!(source_config::Dict{String, Any})
    for (key, value) in source_config
        if key == "environments" && isa(value, Dict)
            # Merge environment configurations
            for (env_name, env_config) in value
                env_symbol = Symbol(env_name)
                if !haskey(CONFIG_MANAGER.environment_configs, env_symbol)
                    CONFIG_MANAGER.environment_configs[env_symbol] = Dict{String, Any}()
                end
                merge!(CONFIG_MANAGER.environment_configs[env_symbol], env_config)
            end
        else
            # Merge base configuration
            CONFIG_MANAGER.base_config[key] = value
        end
    end
    
    @info "Configuration merged successfully"
end