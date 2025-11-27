# Unit tests for environment management
using Test
using StrategyFramework

@testset "Environment Management Tests" begin
    
    @testset "Environment variable reading functions" begin
        # Store original environment values
        original_env = Dict(
            "STRATEGY_ID" => get(ENV, "STRATEGY_ID", nothing),
            "ASSETS_FLAG" => get(ENV, "ASSETS_FLAG", nothing),
            "WATCHER_EXC" => get(ENV, "WATCHER_EXC", nothing),
            "OHLCV_METHOD" => get(ENV, "OHLCV_METHOD", nothing),
            "PROFILING" => get(ENV, "PROFILING", nothing)
        )
        
        try
            # Test env_strategy_id
            ENV["STRATEGY_ID"] = "TestStrategy"
            @test env_strategy_id() == "TestStrategy"
            
            delete!(ENV, "STRATEGY_ID")
            @test env_strategy_id() == "StrategyFramework"  # default
            
            # Test env_assets_flag
            ENV["ASSETS_FLAG"] = "production"
            @test env_assets_flag() == :production
            
            delete!(ENV, "ASSETS_FLAG")
            @test env_assets_flag() == :default  # default
            
            # Test env_watcher_exchange
            ENV["WATCHER_EXC"] = "binance"
            @test env_watcher_exchange() == :binance
            
            delete!(ENV, "WATCHER_EXC")
            @test env_watcher_exchange() == :phemex  # default
            
            # Test env_ohlcv_method
            ENV["OHLCV_METHOD"] = "websocket"
            @test env_ohlcv_method() == :websocket
            
            delete!(ENV, "OHLCV_METHOD")
            @test env_ohlcv_method() == :ccxt  # default
            
            # Test env_profiling_enabled
            ENV["PROFILING"] = "true"
            @test env_profiling_enabled() == true
            
            ENV["PROFILING"] = "1"
            @test env_profiling_enabled() == true
            
            ENV["PROFILING"] = "yes"
            @test env_profiling_enabled() == true
            
            ENV["PROFILING"] = "on"
            @test env_profiling_enabled() == true
            
            ENV["PROFILING"] = "TRUE"  # test case insensitivity
            @test env_profiling_enabled() == true
            
            ENV["PROFILING"] = "false"
            @test env_profiling_enabled() == false
            
            ENV["PROFILING"] = "0"
            @test env_profiling_enabled() == false
            
            ENV["PROFILING"] = "no"
            @test env_profiling_enabled() == false
            
            ENV["PROFILING"] = "random"
            @test env_profiling_enabled() == false
            
            delete!(ENV, "PROFILING")
            @test env_profiling_enabled() == false  # default
            
        finally
            # Restore original environment
            for (key, value) in original_env
                if value !== nothing
                    ENV[key] = value
                else
                    delete!(ENV, key)
                end
            end
        end
    end
    
    @testset "Asset configuration functions" begin
        # Clear existing assets for clean testing
        empty!(ASSETS_CT)
        
        # Test setassets!
        test_assets = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
        setassets!(:test, :binance, test_assets)
        
        @test haskey(ASSETS_CT, (:test, :binance))
        @test ASSETS_CT[(:test, :binance)] == test_assets
        @test ASSETS_CT[(:test, :binance)] !== test_assets  # should be a copy
        
        # Test get_exchange_assets
        retrieved_assets = get_exchange_assets(:test, :binance)
        @test retrieved_assets == test_assets
        
        # Test with non-existent combination
        empty_assets = get_exchange_assets(:nonexistent, :exchange)
        @test empty_assets == String[]
        
        # Test get_custom_assets
        setassets!(:test, :phemex, ["BTC/USDT", "ETH/USDT"])
        setassets!(:test, :kraken, ["BTC/USD", "ETH/USD"])
        setassets!(:production, :binance, ["BTC/USDT"])
        
        test_custom_assets = get_custom_assets(:test)
        @test length(test_custom_assets) == 3
        @test test_custom_assets[:binance] == ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
        @test test_custom_assets[:phemex] == ["BTC/USDT", "ETH/USDT"]
        @test test_custom_assets[:kraken] == ["BTC/USD", "ETH/USD"]
        
        production_custom_assets = get_custom_assets(:production)
        @test length(production_custom_assets) == 1
        @test production_custom_assets[:binance] == ["BTC/USDT"]
        
        # Test with non-existent flag
        empty_custom_assets = get_custom_assets(:nonexistent)
        @test empty_custom_assets == Dict{Symbol, Vector{String}}()
    end
    
    @testset "get_current_assets function" begin
        # Clear and set up test data
        empty!(ASSETS_CT)
        
        # Set current flag and exchange
        original_flag = ASSETS_FLAG[]
        original_exchange = WATCHER_EXC[]
        
        try
            ASSETS_FLAG[] = :current_test
            WATCHER_EXC[] = :test_exchange
            
            # Set assets for current configuration
            current_assets = ["BTC/USDT", "ETH/USDT"]
            setassets!(:current_test, :test_exchange, current_assets)
            
            # Test get_current_assets
            retrieved_current = get_current_assets()
            @test retrieved_current == current_assets
            
            # Test with no assets for current configuration
            ASSETS_FLAG[] = :empty_flag
            WATCHER_EXC[] = :empty_exchange
            
            empty_current = get_current_assets()
            @test empty_current == String[]
            
        finally
            # Restore original values
            ASSETS_FLAG[] = original_flag
            WATCHER_EXC[] = original_exchange
        end
    end
    
    @testset "Module initialization (__init__)" begin
        # Store original values
        original_flag = ASSETS_FLAG[]
        original_exchange = WATCHER_EXC[]
        original_method = OHLCV_METHOD[]
        original_profiling = PROFILING[]
        original_assets = copy(ASSETS_CT)
        
        # Store original environment
        original_env = Dict(
            "ASSETS_FLAG" => get(ENV, "ASSETS_FLAG", nothing),
            "WATCHER_EXC" => get(ENV, "WATCHER_EXC", nothing),
            "OHLCV_METHOD" => get(ENV, "OHLCV_METHOD", nothing),
            "PROFILING" => get(ENV, "PROFILING", nothing)
        )
        
        try
            # Clear current state
            empty!(ASSETS_CT)
            
            # Set test environment variables
            ENV["ASSETS_FLAG"] = "test_init"
            ENV["WATCHER_EXC"] = "test_exchange"
            ENV["OHLCV_METHOD"] = "test_method"
            ENV["PROFILING"] = "true"
            
            # Call __init__ function
            StrategyFramework.__init__()
            
            # Check that environment variables were read correctly
            @test ASSETS_FLAG[] == :test_init
            @test WATCHER_EXC[] == :test_exchange
            @test OHLCV_METHOD[] == :test_method
            @test PROFILING[] == true
            
            # Check that default assets were set
            @test !isempty(ASSETS_CT)
            @test haskey(ASSETS_CT, (:default, :phemex))
            @test haskey(ASSETS_CT, (:default, :binance))
            @test haskey(ASSETS_CT, (:test, :phemex))
            @test haskey(ASSETS_CT, (:test, :binance))
            
            # Check default asset contents
            expected_default = ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT"]
            expected_primary = ["BTC/USDT:USDT"]
            @test ASSETS_CT[(:default, :phemex)] == expected_default
            @test ASSETS_CT[(:default, :binance)] == expected_default
            @test ASSETS_CT[(:test, :phemex)] == expected_primary
            @test ASSETS_CT[(:test, :binance)] == expected_primary
            
            # Test initialization with existing assets (should not overwrite)
            setassets!(:custom, :custom_exchange, ["CUSTOM/PAIR"])
            existing_assets = copy(ASSETS_CT)
            
            StrategyFramework.__init__()
            
            # Custom assets should still exist
            @test ASSETS_CT[(:custom, :custom_exchange)] == ["CUSTOM/PAIR"]
            # Default assets should still be there
            @test haskey(ASSETS_CT, (:default, :phemex))
            
        finally
            # Restore original state
            ASSETS_FLAG[] = original_flag
            WATCHER_EXC[] = original_exchange
            OHLCV_METHOD[] = original_method
            PROFILING[] = original_profiling
            empty!(ASSETS_CT)
            merge!(ASSETS_CT, original_assets)
            
            # Restore original environment
            for (key, value) in original_env
                if value !== nothing
                    ENV[key] = value
                else
                    delete!(ENV, key)
                end
            end
        end
    end
    
    @testset "Edge cases and error handling" begin
        # Test setassets! with empty asset list
        setassets!(:empty_test, :test_exchange, String[])
        @test get_exchange_assets(:empty_test, :test_exchange) == String[]
        
        # Test setassets! with duplicate assets
        duplicate_assets = ["BTC/USDT", "ETH/USDT", "BTC/USDT"]
        setassets!(:duplicate_test, :test_exchange, duplicate_assets)
        retrieved = get_exchange_assets(:duplicate_test, :test_exchange)
        @test retrieved == duplicate_assets  # Should preserve duplicates
        
        # Test with special characters in asset names
        special_assets = ["BTC/USDT:USDT", "ETH-PERP", "1INCH/USD"]
        setassets!(:special_test, :test_exchange, special_assets)
        @test get_exchange_assets(:special_test, :test_exchange) == special_assets
        
        # Test case sensitivity
        setassets!(:Case_Test, :Exchange_Test, ["btc/usdt"])
        @test get_exchange_assets(:Case_Test, :Exchange_Test) == ["btc/usdt"]
        @test get_exchange_assets(:case_test, :exchange_test) == String[]  # Different case
        
        # Test with very long asset lists
        long_assets = ["ASSET$i/USDT" for i in 1:1000]
        setassets!(:long_test, :test_exchange, long_assets)
        @test length(get_exchange_assets(:long_test, :test_exchange)) == 1000
        
        # Test get_custom_assets with overlapping flags
        setassets!(:overlap1, :exchange1, ["A/B"])
        setassets!(:overlap1, :exchange2, ["C/D"])
        setassets!(:overlap2, :exchange1, ["E/F"])
        
        overlap1_assets = get_custom_assets(:overlap1)
        @test length(overlap1_assets) == 2
        @test overlap1_assets[:exchange1] == ["A/B"]
        @test overlap1_assets[:exchange2] == ["C/D"]
        
        overlap2_assets = get_custom_assets(:overlap2)
        @test length(overlap2_assets) == 1
        @test overlap2_assets[:exchange1] == ["E/F"]
    end
    
    @testset "Thread safety and concurrent access" begin
        # Test concurrent setassets! calls
        # This is a basic test - full thread safety would require more complex testing
        
        assets1 = ["BTC/USDT", "ETH/USDT"]
        assets2 = ["ADA/USDT", "DOT/USDT"]
        
        # Simulate concurrent access
        setassets!(:concurrent1, :exchange1, assets1)
        setassets!(:concurrent2, :exchange2, assets2)
        
        @test get_exchange_assets(:concurrent1, :exchange1) == assets1
        @test get_exchange_assets(:concurrent2, :exchange2) == assets2
        
        # Test that modifications don't affect each other
        retrieved1 = get_exchange_assets(:concurrent1, :exchange1)
        retrieved2 = get_exchange_assets(:concurrent2, :exchange2)
        
        push!(retrieved1, "NEW/PAIR")  # Modify retrieved copy
        
        # Original should be unchanged
        @test get_exchange_assets(:concurrent1, :exchange1) == assets1
        @test get_exchange_assets(:concurrent2, :exchange2) == assets2
    end
end