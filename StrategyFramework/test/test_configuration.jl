# Unit tests for configuration management
using Test
using StrategyFramework
using TOML
using Dates

@testset "Configuration Management Tests" begin
    
    @testset "ConfigurationManager construction" begin
        # Test default construction
        cm = ConfigurationManager()
        @test cm.base_config == Dict{String, Any}()
        @test cm.environment_configs == Dict{Symbol, Dict{String, Any}}()
        @test cm.current_environment == :default
        @test cm.config_file_path == ""
        @test cm.last_loaded == DateTime(0)
    end
    
    @testset "load_configuration! function" begin
        # Create a temporary config file
        config_path = tempname() * ".toml"
        
        config_data = Dict{String, Any}(
            "signal_lifetime" => 0.3,
            "def_lev" => 2.0,
            "ordertype" => "gtc",
            "environments" => Dict{String, Any}(
                "test" => Dict{String, Any}(
                    "signal_lifetime" => 0.1,
                    "def_lev" => 1.0
                ),
                "production" => Dict{String, Any}(
                    "signal_lifetime" => 0.5,
                    "def_lev" => 3.0
                )
            )
        )
        
        # Write test config file
        open(config_path, "w") do io
            TOML.print(io, config_data)
        end
        
        try
            # Reset configuration manager
            reset_configuration!()
            
            # Load configuration
            result = load_configuration!(config_path; environment=:test)
            @test result === CONFIG_MANAGER
            
            # Check that configuration was loaded
            @test CONFIG_MANAGER.base_config["signal_lifetime"] == 0.3
            @test CONFIG_MANAGER.base_config["def_lev"] == 2.0
            @test CONFIG_MANAGER.base_config["ordertype"] == "gtc"
            @test CONFIG_MANAGER.config_file_path == config_path
            @test CONFIG_MANAGER.current_environment == :test
            @test CONFIG_MANAGER.last_loaded > DateTime(0)
            
            # Check environment configs
            @test haskey(CONFIG_MANAGER.environment_configs, :test)
            @test haskey(CONFIG_MANAGER.environment_configs, :production)
            @test CONFIG_MANAGER.environment_configs[:test]["signal_lifetime"] == 0.1
            @test CONFIG_MANAGER.environment_configs[:production]["def_lev"] == 3.0
            
            # Test loading non-existent file
            reset_configuration!()
            result_missing = load_configuration!("non_existent_file.toml")
            @test result_missing === CONFIG_MANAGER
            @test isempty(CONFIG_MANAGER.base_config)
            
            # Test loading invalid TOML file
            invalid_config_path = tempname() * ".toml"
            write(invalid_config_path, "invalid toml content [[[")
            
            @test_throws Exception load_configuration!(invalid_config_path)
            
            # Clean up
            rm(invalid_config_path)
            
        finally
            rm(config_path)
        end
    end
    
    @testset "get_config_value function" begin
        reset_configuration!()
        
        # Set up test configuration
        CONFIG_MANAGER.base_config["base_param"] = "base_value"
        CONFIG_MANAGER.base_config["override_param"] = "base_override"
        
        CONFIG_MANAGER.environment_configs[:test] = Dict{String, Any}(
            "env_param" => "env_value",
            "override_param" => "env_override"
        )
        
        CONFIG_MANAGER.current_environment = :test
        
        # Test base parameter
        @test get_config_value("base_param") == "base_value"
        
        # Test environment-specific parameter
        @test get_config_value("env_param") == "env_value"
        
        # Test environment override
        @test get_config_value("override_param") == "env_override"
        
        # Test non-existent parameter with default
        @test get_config_value("missing_param", "default_value") == "default_value"
        
        # Test non-existent parameter without default
        @test get_config_value("missing_param") === nothing
        
        # Test with different environment
        @test get_config_value("override_param", nothing; environment=:default) == "base_override"
        @test get_config_value("env_param", nothing; environment=:default) === nothing
    end
    
    @testset "set_config_value! function" begin
        reset_configuration!()
        
        # Test setting base config value
        set_config_value!("base_test", "base_value"; environment=:default)
        @test CONFIG_MANAGER.base_config["base_test"] == "base_value"
        
        # Test setting environment-specific value
        set_config_value!("env_test", "env_value"; environment=:test)
        @test haskey(CONFIG_MANAGER.environment_configs, :test)
        @test CONFIG_MANAGER.environment_configs[:test]["env_test"] == "env_value"
        
        # Test overriding existing value
        set_config_value!("base_test", "new_base_value"; environment=:default)
        @test CONFIG_MANAGER.base_config["base_test"] == "new_base_value"
        
        # Test setting multiple values in same environment
        set_config_value!("env_test2", "env_value2"; environment=:test)
        @test CONFIG_MANAGER.environment_configs[:test]["env_test"] == "env_value"
        @test CONFIG_MANAGER.environment_configs[:test]["env_test2"] == "env_value2"
    end
    
    @testset "validate_configuration function" begin
        reset_configuration!()
        
        # Set valid configuration values
        set_config_value!("signal_lifetime", 0.2)
        set_config_value!("def_lev", 2.0)
        set_config_value!("ordertype", "gtc")
        
        # Should validate successfully
        @test validate_configuration() == true
        
        # Set invalid value (violates bounds)
        set_config_value!("signal_lifetime", -0.1)  # Below minimum
        @test_throws ArgumentError validate_configuration()
        
        # Fix the invalid value
        set_config_value!("signal_lifetime", 0.2)
        @test validate_configuration() == true
        
        # Set invalid ordertype
        set_config_value!("ordertype", "invalid_type")
        @test_throws ArgumentError validate_configuration()
    end
    
    @testset "load_environment_variables! function" begin
        # Store original environment
        original_env = Dict{String, String}()
        prefix = "STRATEGY_FRAMEWORK_"
        
        for (key, value) in ENV
            if startswith(key, prefix)
                original_env[key] = value
            end
        end
        
        try
            # Clear existing strategy framework env vars
            for key in keys(ENV)
                if startswith(key, prefix)
                    delete!(ENV, key)
                end
            end
            
            reset_configuration!()
            
            # Set test environment variables
            ENV["STRATEGY_FRAMEWORK_SIGNAL_LIFETIME"] = "0.15"
            ENV["STRATEGY_FRAMEWORK_DEF_LEV"] = "1.5"
            ENV["STRATEGY_FRAMEWORK_ISMAKE"] = "false"
            ENV["STRATEGY_FRAMEWORK_CUSTOM_PARAM"] = "custom_value"
            
            # Load environment variables
            load_environment_variables!()
            
            # Check that values were loaded
            @test get_config_value("signal_lifetime") == 0.15
            @test get_config_value("def_lev") == 1.5
            @test get_config_value("ismake") == false
            @test get_config_value("custom_param") == "custom_value"
            
        finally
            # Restore original environment
            for key in keys(ENV)
                if startswith(key, prefix)
                    delete!(ENV, key)
                end
            end
            for (key, value) in original_env
                ENV[key] = value
            end
        end
    end
    
    @testset "try_parse_env_value function" begin
        # Test boolean parsing
        @test try_parse_env_value("true") == true
        @test try_parse_env_value("false") == false
        @test try_parse_env_value("TRUE") == true
        @test try_parse_env_value("FALSE") == false
        
        # Test integer parsing
        @test try_parse_env_value("42") == 42
        @test try_parse_env_value("-10") == -10
        @test try_parse_env_value("0") == 0
        
        # Test float parsing
        @test try_parse_env_value("3.14") == 3.14
        @test try_parse_env_value("-2.5") == -2.5
        @test try_parse_env_value("1.0") == 1.0
        
        # Test string fallback
        @test try_parse_env_value("hello") == "hello"
        @test try_parse_env_value("not_a_number") == "not_a_number"
        @test try_parse_env_value("") == ""
    end
    
    @testset "save_configuration! function" begin
        reset_configuration!()
        
        # Set up test configuration
        set_config_value!("signal_lifetime", 0.25)
        set_config_value!("def_lev", 1.8)
        set_config_value!("test_param", "test_value"; environment=:test)
        set_config_value!("prod_param", "prod_value"; environment=:production)
        
        # Save configuration
        config_path = tempname() * ".toml"
        
        try
            save_configuration!(config_path)
            @test isfile(config_path)
            
            # Load and verify saved configuration
            saved_config = TOML.parsefile(config_path)
            @test saved_config["signal_lifetime"] == 0.25
            @test saved_config["def_lev"] == 1.8
            @test haskey(saved_config, "environments")
            @test saved_config["environments"]["test"]["test_param"] == "test_value"
            @test saved_config["environments"]["production"]["prod_param"] == "prod_value"
            
            # Test saving without config file path set
            reset_configuration!()
            @test_throws ArgumentError save_configuration!()
            
        finally
            if isfile(config_path)
                rm(config_path)
            end
        end
    end
    
    @testset "get_configuration_summary function" begin
        reset_configuration!()
        
        # Set up test configuration
        CONFIG_MANAGER.config_file_path = "test_config.toml"
        CONFIG_MANAGER.current_environment = :test
        CONFIG_MANAGER.last_loaded = DateTime(2023, 1, 1)
        
        set_config_value!("base_param", "base_value")
        set_config_value!("env_param", "env_value"; environment=:test)
        
        summary = get_configuration_summary()
        
        @test summary["config_file"] == "test_config.toml"
        @test summary["current_environment"] == :test
        @test summary["last_loaded"] == DateTime(2023, 1, 1)
        @test "base_param" in summary["base_config_keys"]
        @test :test in summary["environments"]
        @test haskey(summary, "current_parameters")
        @test haskey(summary["current_parameters"], "signal_lifetime")  # Default parameter
    end
    
    @testset "reset_configuration! function" begin
        # Set up some configuration
        set_config_value!("test_param", "test_value")
        set_config_value!("env_param", "env_value"; environment=:test)
        CONFIG_MANAGER.config_file_path = "test_path"
        CONFIG_MANAGER.current_environment = :test
        
        # Reset configuration
        reset_configuration!()
        
        # Check that everything was reset
        @test isempty(CONFIG_MANAGER.base_config)
        @test isempty(CONFIG_MANAGER.environment_configs)
        @test CONFIG_MANAGER.current_environment == :default
        @test CONFIG_MANAGER.config_file_path == ""
        @test CONFIG_MANAGER.last_loaded == DateTime(0)
        
        # Check that default parameters were re-registered
        specs = get_parameter_specs()
        @test !isempty(specs)
        @test haskey(specs, :signal_lifetime)
    end
    
    @testset "create_default_config_file function" begin
        config_path = tempname() * ".toml"
        
        try
            create_default_config_file(config_path)
            @test isfile(config_path)
            
            # Load and verify default configuration
            default_config = TOML.parsefile(config_path)
            @test haskey(default_config, "signal_lifetime")
            @test haskey(default_config, "def_lev")
            @test haskey(default_config, "ordertype")
            @test haskey(default_config, "environments")
            @test haskey(default_config["environments"], "development")
            @test haskey(default_config["environments"], "production")
            
            # Check that default values match parameter specs
            specs = get_parameter_specs()
            @test default_config["signal_lifetime"] == specs[:signal_lifetime].default
            @test default_config["def_lev"] == specs[:def_lev].default
            
        finally
            if isfile(config_path)
                rm(config_path)
            end
        end
    end
    
    @testset "switch_environment! function" begin
        reset_configuration!()
        
        # Set up environments
        set_config_value!("env1_param", "env1_value"; environment=:env1)
        set_config_value!("env2_param", "env2_value"; environment=:env2)
        
        # Switch to env1
        switch_environment!(:env1)
        @test CONFIG_MANAGER.current_environment == :env1
        
        # Switch to env2
        switch_environment!(:env2)
        @test CONFIG_MANAGER.current_environment == :env2
        
        # Switch to non-existent environment (should still work but warn)
        switch_environment!(:nonexistent)
        @test CONFIG_MANAGER.current_environment == :nonexistent
        
        # Switch back to default
        switch_environment!(:default)
        @test CONFIG_MANAGER.current_environment == :default
    end
    
    @testset "merge_configurations! function" begin
        reset_configuration!()
        
        # Set initial configuration
        set_config_value!("existing_param", "original_value")
        set_config_value!("env_existing", "original_env"; environment=:test)
        
        # Prepare merge configuration
        merge_config = Dict{String, Any}(
            "existing_param" => "merged_value",
            "new_param" => "new_value",
            "environments" => Dict{String, Any}(
                "test" => Dict{String, Any}(
                    "env_existing" => "merged_env",
                    "env_new" => "new_env"
                ),
                "production" => Dict{String, Any}(
                    "prod_param" => "prod_value"
                )
            )
        )
        
        # Merge configurations
        merge_configurations!(merge_config)
        
        # Check merged values
        @test get_config_value("existing_param") == "merged_value"
        @test get_config_value("new_param") == "new_value"
        @test get_config_value("env_existing", nothing; environment=:test) == "merged_env"
        @test get_config_value("env_new", nothing; environment=:test) == "new_env"
        @test get_config_value("prod_param", nothing; environment=:production) == "prod_value"
    end
    
    @testset "Edge cases and error handling" begin
        reset_configuration!()
        
        # Test with empty configuration
        summary_empty = get_configuration_summary()
        @test summary_empty["config_file"] == ""
        @test summary_empty["current_environment"] == :default
        @test isempty(summary_empty["base_config_keys"])
        
        # Test get_config_value with complex nested values
        nested_config = Dict{String, Any}(
            "nested" => Dict{String, Any}(
                "level1" => Dict{String, Any}(
                    "level2" => "deep_value"
                )
            )
        )
        
        merge_configurations!(nested_config)
        nested_value = get_config_value("nested")
        @test isa(nested_value, Dict)
        @test nested_value["level1"]["level2"] == "deep_value"
        
        # Test save_configuration! with directory creation
        nested_config_path = joinpath(tempdir(), "nested", "dir", "config.toml")
        
        try
            save_configuration!(nested_config_path)
            @test isfile(nested_config_path)
            
        finally
            if isfile(nested_config_path)
                rm(nested_config_path)
                # Clean up created directories
                parent_dir = dirname(nested_config_path)
                while parent_dir != tempdir() && isdir(parent_dir)
                    try
                        rm(parent_dir)
                        parent_dir = dirname(parent_dir)
                    catch
                        break
                    end
                end
            end
        end
        
        # Test merge_configurations! with non-dict environments
        invalid_merge = Dict{String, Any}(
            "environments" => "not_a_dict"
        )
        
        # Should not crash, just skip the environments section
        merge_configurations!(invalid_merge)
        
        # Test try_parse_env_value with edge cases
        @test try_parse_env_value("1.0e10") == 1.0e10
        @test try_parse_env_value("1e-5") == 1e-5
        @test try_parse_env_value("Inf") == "Inf"  # Should remain as string
        @test try_parse_env_value("NaN") == "NaN"  # Should remain as string
    end
end