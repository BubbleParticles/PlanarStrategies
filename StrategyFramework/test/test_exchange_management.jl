# Tests for exchange and asset management utilities
using Test
using Dates

# Mock Planar types and functions for testing
struct MockStrategy
    attrs::Dict{Symbol, Any}
    universe::Vector{MockAssetInstance}
    timeframe::Symbol
    exchange_id::Symbol
    
    MockStrategy(exchange_id=:phemex) = new(Dict{Symbol, Any}(), MockAssetInstance[], :tf_1m, exchange_id)
end

struct MockAssetInstance
    symbol::String
end

struct MockExchange
    id::Symbol
    sandbox::Bool
    account::String
end

struct MockAssetCollection
    assets::Vector{String}
    exchange::Symbol
    timeframe::Symbol
end

# Mock Planar modules
module MockExchanges
    export getexchange!, tickers, exchangeid
    
    function getexchange!(exchange_id::Symbol; sandbox::Bool=false, account::String="default")
        return MockExchange(exchange_id, sandbox, account)
    end
    
    function tickers(exchange_id::Symbol, quote::Symbol)
        if exchange_id == :phemex
            return ["BTC/USDT", "ETH/USDT", "ADA/USDT", "DOT/USDT", "LINK/USDT"]
        elseif exchange_id == :binance
            return ["BTC/USDT", "ETH/USDT", "BNB/USDT", "ADA/USDT", "SOL/USDT"]
        else
            return String[]
        end
    end
    
    exchangeid(exchange::MockExchange) = string(exchange.id)
end

# Mock functions
exchange(s::MockStrategy) = MockExchange(s.exchange_id, false, "default")
AssetCollection(assets::Vector{String}; exc, load_data=false, timeframe=:tf_1m) = 
    MockAssetCollection(assets, exc.id, timeframe)

# Include the exchange management module for testing
include("../src/integration/exchange_management.jl")

# Override the Planar imports with our mocks
const Exchanges = MockExchanges

@testset "Exchange Management Tests" begin
    
    @testset "ExchangeConfig structure" begin
        # Test default configuration
        config = ExchangeConfig()
        
        @test config.exchange_id == :phemex
        @test config.sandbox == false
        @test config.account == "default"
        @test config.rate_limit_enabled == true
        @test config.requests_per_second == 10.0
        @test config.burst_limit == 50
        @test config.cooldown_period == Second(1)
        @test config.timeout == Second(30)
        @test config.retry_attempts == 3
        @test config.retry_delay == Second(1)
        @test config.enable_websocket == true
        @test config.websocket_timeout == Second(60)
        @test config.ohlcv_limit == 1000
        @test config.default_order_type == :limit
        @test config.enable_margin == false
        @test config.margin_mode == :cross
        
        # Test custom configuration
        custom_config = ExchangeConfig(
            exchange_id = :binance,
            sandbox = true,
            requests_per_second = 20.0,
            enable_margin = true,
            margin_mode = :isolated
        )
        
        @test custom_config.exchange_id == :binance
        @test custom_config.sandbox == true
        @test custom_config.requests_per_second == 20.0
        @test custom_config.enable_margin == true
        @test custom_config.margin_mode == :isolated
        
        # Test field mutability
        config.requests_per_second = 15.0
        @test config.requests_per_second == 15.0
        
        config.sandbox = true
        @test config.sandbox == true
    end
    
    @testset "AssetUniverseConfig structure" begin
        # Test default configuration
        config = AssetUniverseConfig()
        
        @test config.min_volume_24h == 1_000_000.0
        @test config.min_price == 0.0001
        @test config.max_price == 1_000_000.0
        @test config.quote_currencies == ["USDT", "USDC", "USD"]
        @test config.exclude_patterns == [".*UP.*", ".*DOWN.*", ".*BEAR.*", ".*BULL.*"]
        @test config.include_patterns == String[]
        @test config.enable_dynamic_universe == false
        @test config.universe_update_interval == Hour(24)
        @test config.max_assets == 50
        @test config.min_data_history == Day(30)
        @test config.required_timeframes == ["1m", "5m", "1h"]
        
        # Test custom configuration
        custom_config = AssetUniverseConfig(
            min_volume_24h = 5_000_000.0,
            quote_currencies = ["USDT"],
            max_assets = 10,
            enable_dynamic_universe = true
        )
        
        @test custom_config.min_volume_24h == 5_000_000.0
        @test custom_config.quote_currencies == ["USDT"]
        @test custom_config.max_assets == 10
        @test custom_config.enable_dynamic_universe == true
    end
    
    @testset "MarketDataConfig structure" begin
        # Test default configuration
        config = MarketDataConfig()
        
        @test config.primary_source == :ccxt
        @test config.backup_sources == Symbol[]
        @test config.enable_data_validation == true
        @test config.max_gap_tolerance == Minute(5)
        @test config.enable_gap_filling == true
        @test config.enable_caching == true
        @test config.cache_duration == Hour(1)
        @test config.max_cache_size == 1000
        @test config.enable_realtime == true
        @test config.realtime_update_interval == Second(1)
        @test config.enable_tick_data == false
        @test config.historical_data_limit == 10000
        @test config.enable_progressive_loading == true
        @test config.chunk_size == 1000
        
        # Test custom configuration
        custom_config = MarketDataConfig(
            primary_source = :websocket,
            backup_sources = [:ccxt, :rest],
            enable_realtime = false,
            enable_tick_data = true
        )
        
        @test custom_config.primary_source == :websocket
        @test custom_config.backup_sources == [:ccxt, :rest]
        @test custom_config.enable_realtime == false
        @test custom_config.enable_tick_data == true
    end
    
    @testset "Exchange configuration management" begin
        # Test configure_exchange!
        config = ExchangeConfig(
            exchange_id = :test_exchange,
            requests_per_second = 25.0,
            sandbox = true
        )
        
        result = configure_exchange!(:test_exchange, config)
        @test result == config
        @test haskey(EXCHANGE_CONFIGS, :test_exchange)
        @test EXCHANGE_CONFIGS[:test_exchange] == config
        
        # Test get_exchange_config
        retrieved_config = get_exchange_config(:test_exchange)
        @test retrieved_config == config
        
        # Test get_exchange_config for non-existent exchange
        default_config = get_exchange_config(:non_existent)
        @test default_config.exchange_id == :non_existent
        @test default_config isa ExchangeConfig
        
        # Test rate limiter initialization
        @test haskey(RATE_LIMITERS, :test_exchange)
        limiter = RATE_LIMITERS[:test_exchange]
        @test limiter["requests_per_second"] == 25.0
        @test limiter["burst_limit"] == 50  # Default value
        @test haskey(limiter, "last_request")
        @test haskey(limiter, "request_count")
        @test haskey(limiter, "cooldown_until")
    end
    
    @testset "setup_exchange! function" begin
        s = MockStrategy(:phemex)
        
        # Test basic exchange setup
        exchange = setup_exchange!(s, :phemex)
        @test exchange isa MockExchange
        @test exchange.id == :phemex
        @test exchange.sandbox == false
        @test exchange.account == "default"
        
        # Test exchange setup with custom parameters
        exchange_custom = setup_exchange!(s, :binance; sandbox=true, account="test_account")
        @test exchange_custom.id == :binance
        @test exchange_custom.sandbox == true
        @test exchange_custom.account == "test_account"
        
        # Test that configuration was updated
        config = get_exchange_config(:binance)
        @test config.sandbox == true
        @test config.account == "test_account"
    end
    
    @testset "Asset universe configuration" begin
        # Test configure_asset_universe!
        config = AssetUniverseConfig(
            min_volume_24h = 2_000_000.0,
            max_assets = 15,
            quote_currencies = ["USDT", "BUSD"]
        )
        
        result = configure_asset_universe!(:test_universe, config)
        @test result == config
        @test haskey(UNIVERSE_CONFIGS, :test_universe)
        @test UNIVERSE_CONFIGS[:test_universe] == config
        
        # Test get_universe_config
        retrieved_config = get_universe_config(:test_universe)
        @test retrieved_config == config
        
        # Test get_universe_config for non-existent universe
        default_config = get_universe_config(:non_existent)
        @test default_config isa AssetUniverseConfig
        @test default_config.min_volume_24h == 1_000_000.0  # Default value
    end
    
    @testset "create_asset_universe function" begin
        s = MockStrategy(:phemex)
        
        # Test basic universe creation
        assets = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
        universe = create_asset_universe(s, assets)
        
        @test universe isa MockAssetCollection
        @test universe.exchange == :phemex
        @test universe.timeframe == :tf_1m
        @test length(universe.assets) <= length(assets)  # May be filtered
        
        # Test with custom universe configuration
        config = AssetUniverseConfig(
            max_assets = 2,
            quote_currencies = ["USDT"]
        )
        configure_asset_universe!(:limited, config)
        
        universe_limited = create_asset_universe(s, assets; universe_id=:limited)
        @test length(universe_limited.assets) <= 2
        
        # Test asset filtering
        assets_with_excluded = ["BTC/USDT", "ETHUP/USDT", "BTCDOWN/USDT", "ADA/USDT"]
        universe_filtered = create_asset_universe(s, assets_with_excluded)
        
        # Should exclude UP/DOWN tokens
        for asset in universe_filtered.assets
            @test !contains(asset, "UP")
            @test !contains(asset, "DOWN")
        end
    end
    
    @testset "update_asset_universe! function" begin
        s = MockStrategy(:phemex)
        
        # Test universe update
        new_assets = ["BTC/USDT", "ETH/USDT", "DOT/USDT"]
        result = update_asset_universe!(s, new_assets)
        
        @test result == true
        @test s.universe isa MockAssetCollection
        @test s.universe.assets == new_assets || length(s.universe.assets) <= length(new_assets)
    end
    
    @testset "Market data configuration" begin
        # Test configure_market_data!
        config = MarketDataConfig(
            primary_source = :websocket,
            enable_realtime = false,
            cache_duration = Hour(2)
        )
        
        result = configure_market_data!(:test_data, config)
        @test result == config
        @test haskey(MARKET_DATA_CONFIGS, :test_data)
        @test MARKET_DATA_CONFIGS[:test_data] == config
        
        # Test get_market_data_config
        retrieved_config = get_market_data_config(:test_data)
        @test retrieved_config == config
        
        # Test get_market_data_config for non-existent config
        default_config = get_market_data_config(:non_existent)
        @test default_config isa MarketDataConfig
        @test default_config.primary_source == :ccxt  # Default value
    end
    
    @testset "setup_market_data_sources! function" begin
        s = MockStrategy(:phemex)
        
        # Test basic market data setup
        result = setup_market_data_sources!(s)
        @test result == true
        
        # Test with custom configuration
        config = MarketDataConfig(
            primary_source = :websocket,
            backup_sources = [:ccxt, :rest],
            enable_realtime = true
        )
        configure_market_data!(:custom_data, config)
        
        result_custom = setup_market_data_sources!(s; data_id=:custom_data)
        @test result_custom == true
    end
    
    @testset "get_available_assets function" begin
        # Test getting assets from Phemex
        assets_phemex = get_available_assets(:phemex)
        @test assets_phemex isa Vector{String}
        @test "BTC/USDT" in assets_phemex
        @test "ETH/USDT" in assets_phemex
        
        # Test getting assets from Binance
        assets_binance = get_available_assets(:binance)
        @test assets_binance isa Vector{String}
        @test "BTC/USDT" in assets_binance
        @test "BNB/USDT" in assets_binance
        
        # Test with different quote currency
        assets_btc = get_available_assets(:phemex; quote_currency="BTC")
        @test assets_btc isa Vector{String}
        
        # Test with non-existent exchange
        assets_none = get_available_assets(:non_existent)
        @test assets_none == String[]
    end
    
    @testset "validate_asset_universe function" begin
        s = MockStrategy(:phemex)
        
        # Test validation with valid assets
        valid_assets = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
        valid, invalid = validate_asset_universe(s, valid_assets)
        
        @test length(valid) >= 2  # At least BTC/USDT and ETH/USDT should be valid
        @test "BTC/USDT" in valid
        @test "ETH/USDT" in valid
        
        # Test validation with invalid assets
        mixed_assets = ["BTC/USDT", "INVALID/USDT", "ETH/USDT", "FAKE/USDT"]
        valid_mixed, invalid_mixed = validate_asset_universe(s, mixed_assets)
        
        @test "BTC/USDT" in valid_mixed
        @test "ETH/USDT" in valid_mixed
        @test "INVALID/USDT" in invalid_mixed
        @test "FAKE/USDT" in invalid_mixed
        
        # Test with all invalid assets
        invalid_assets = ["INVALID1/USDT", "INVALID2/USDT"]
        valid_none, invalid_all = validate_asset_universe(s, invalid_assets)
        
        @test isempty(valid_none)
        @test length(invalid_all) == 2
    end
    
    @testset "_filter_assets helper function" begin
        config = AssetUniverseConfig(
            exclude_patterns = [".*UP.*", ".*DOWN.*"],
            include_patterns = String[],
            quote_currencies = ["USDT"],
            max_assets = 3
        )
        
        # Test basic filtering
        assets = ["BTC/USDT", "ETH/USDT", "BTCUP/USDT", "ETHDOWN/USDT", "ADA/USDT"]
        filtered = _filter_assets(assets, config)
        
        @test "BTC/USDT" in filtered
        @test "ETH/USDT" in filtered
        @test "ADA/USDT" in filtered
        @test !("BTCUP/USDT" in filtered)
        @test !("ETHDOWN/USDT" in filtered)
        
        # Test max_assets limit
        @test length(filtered) <= 3
        
        # Test quote currency filtering
        config_btc = AssetUniverseConfig(quote_currencies = ["BTC"])
        assets_mixed = ["BTC/USDT", "ETH/BTC", "ADA/USDT", "DOT/BTC"]
        filtered_btc = _filter_assets(assets_mixed, config_btc)
        
        @test "ETH/BTC" in filtered_btc
        @test "DOT/BTC" in filtered_btc
        @test !("BTC/USDT" in filtered_btc)
        @test !("ADA/USDT" in filtered_btc)
        
        # Test inclusion patterns
        config_include = AssetUniverseConfig(
            include_patterns = ["BTC.*", "ETH.*"],
            quote_currencies = ["USDT"]
        )
        assets_include = ["BTC/USDT", "ETH/USDT", "ADA/USDT", "DOT/USDT"]
        filtered_include = _filter_assets(assets_include, config_include)
        
        @test "BTC/USDT" in filtered_include
        @test "ETH/USDT" in filtered_include
        @test !("ADA/USDT" in filtered_include)
        @test !("DOT/USDT" in filtered_include)
    end
    
    @testset "Rate limiting functionality" begin
        # Test rate limiter initialization
        config = ExchangeConfig(
            exchange_id = :rate_test,
            rate_limit_enabled = true,
            requests_per_second = 5.0,
            burst_limit = 20
        )
        
        configure_exchange!(:rate_test, config)
        
        @test haskey(RATE_LIMITERS, :rate_test)
        limiter = RATE_LIMITERS[:rate_test]
        @test limiter["requests_per_second"] == 5.0
        @test limiter["burst_limit"] == 20
        @test limiter["request_count"] == 0
        
        # Test rate limiter disabled
        config_no_limit = ExchangeConfig(
            exchange_id = :no_limit_test,
            rate_limit_enabled = false
        )
        
        configure_exchange!(:no_limit_test, config_no_limit)
        @test !haskey(RATE_LIMITERS, :no_limit_test)
    end
    
    @testset "Configuration persistence and retrieval" begin
        # Test that configurations persist across function calls
        exchange_config = ExchangeConfig(exchange_id = :persist_test, requests_per_second = 30.0)
        universe_config = AssetUniverseConfig(max_assets = 25)
        data_config = MarketDataConfig(primary_source = :test_source)
        
        configure_exchange!(:persist_test, exchange_config)
        configure_asset_universe!(:persist_test, universe_config)
        configure_market_data!(:persist_test, data_config)
        
        # Retrieve and verify
        retrieved_exchange = get_exchange_config(:persist_test)
        retrieved_universe = get_universe_config(:persist_test)
        retrieved_data = get_market_data_config(:persist_test)
        
        @test retrieved_exchange.requests_per_second == 30.0
        @test retrieved_universe.max_assets == 25
        @test retrieved_data.primary_source == :test_source
        
        # Test that they're the same objects
        @test retrieved_exchange === EXCHANGE_CONFIGS[:persist_test]
        @test retrieved_universe === UNIVERSE_CONFIGS[:persist_test]
        @test retrieved_data === MARKET_DATA_CONFIGS[:persist_test]
    end
    
    @testset "Error handling and edge cases" begin
        # Test setup_exchange! with invalid exchange
        s = MockStrategy(:invalid_exchange)
        
        # This should handle the error gracefully or throw a specific exception
        @test_throws Exception setup_exchange!(s, :invalid_exchange)
        
        # Test create_asset_universe with empty asset list
        empty_universe = create_asset_universe(s, String[])
        @test empty_universe isa MockAssetCollection
        @test isempty(empty_universe.assets)
        
        # Test _filter_assets with empty input
        config = AssetUniverseConfig()
        filtered_empty = _filter_assets(String[], config)
        @test isempty(filtered_empty)
        
        # Test _filter_assets with no matching assets
        config_strict = AssetUniverseConfig(
            quote_currencies = ["NONEXISTENT"],
            max_assets = 10
        )
        assets_no_match = ["BTC/USDT", "ETH/USDT"]
        filtered_no_match = _filter_assets(assets_no_match, config_strict)
        @test isempty(filtered_no_match)
        
        # Test validate_asset_universe with strategy that has no exchange
        s_no_exchange = MockStrategy(:nonexistent)
        valid_error, invalid_error = validate_asset_universe(s_no_exchange, ["BTC/USDT"])
        @test isempty(valid_error)
        @test "BTC/USDT" in invalid_error
    end
    
    @testset "Default configurations" begin
        # Test that default configurations are properly initialized
        default_exchange_phemex = get_exchange_config(:phemex)
        @test default_exchange_phemex.exchange_id == :phemex
        @test default_exchange_phemex.requests_per_second == 10.0
        @test default_exchange_phemex.enable_margin == true
        
        default_exchange_binance = get_exchange_config(:binance)
        @test default_exchange_binance.exchange_id == :binance
        @test default_exchange_binance.requests_per_second == 20.0
        @test default_exchange_binance.enable_margin == true
        
        default_universe = get_universe_config(:default)
        @test default_universe.min_volume_24h == 1_000_000.0
        @test default_universe.quote_currencies == ["USDT", "USDC"]
        @test default_universe.max_assets == 20
        
        default_data = get_market_data_config(:default)
        @test default_data.primary_source == :ccxt
        @test default_data.enable_realtime == true
        @test default_data.enable_caching == true
    end
    
    @testset "Configuration modification and updates" begin
        # Test modifying existing configurations
        original_config = get_exchange_config(:phemex)
        original_rps = original_config.requests_per_second
        
        # Modify the configuration
        original_config.requests_per_second = 15.0
        
        # Verify the change persists
        modified_config = get_exchange_config(:phemex)
        @test modified_config.requests_per_second == 15.0
        @test modified_config === original_config  # Same object
        
        # Test reconfiguring with new object
        new_config = ExchangeConfig(exchange_id = :phemex, requests_per_second = 25.0)
        configure_exchange!(:phemex, new_config)
        
        latest_config = get_exchange_config(:phemex)
        @test latest_config.requests_per_second == 25.0
        @test latest_config === new_config  # New object
        @test latest_config !== original_config  # Different from original
    end
end

println("✓ Exchange management tests completed")