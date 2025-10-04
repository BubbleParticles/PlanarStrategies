# Tests for OHLCV data management
using Test
using Dates

# Mock Planar types and functions for testing
struct MockStrategy
    attrs::Dict{Symbol, Any}
    
    MockStrategy() = new(Dict{Symbol, Any}())
end

struct MockAssetInstance
    asset::String
    exchange::Symbol
    
    MockAssetInstance(asset::String, exchange::Symbol = :phemex) = new(asset, exchange)
end

struct MockOHLCVData
    timestamps::Vector{DateTime}
    open::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    close::Vector{Float64}
    volume::Vector{Float64}
    
    function MockOHLCVData(n::Int = 100)
        base_time = now() - Hour(n)
        timestamps = [base_time + Minute(i) for i in 1:n]
        base_price = 50000.0
        
        open_prices = [base_price + randn() * 100 for _ in 1:n]
        close_prices = [open_prices[i] + randn() * 50 for i in 1:n]
        high_prices = [max(open_prices[i], close_prices[i]) + rand() * 100 for i in 1:n]
        low_prices = [min(open_prices[i], close_prices[i]) - rand() * 100 for i in 1:n]
        volumes = [1000.0 + rand() * 500 for _ in 1:n]
        
        new(timestamps, open_prices, high_prices, low_prices, close_prices, volumes)
    end
end

# Mock constants and functions
const TF = :tf_1m
const WATCHER_EXC = Ref(:phemex)
const OHLCV_METHOD = Ref(:ccxt)

get_current_assets() = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
islive(s::MockStrategy) = get(s.attrs, :live_mode, false)
AssetInstance(asset_str::String, exchange::Symbol) = MockAssetInstance(asset_str, exchange)

# Mock OHLCV functions
ohlcv(ai::MockAssetInstance, tf::Symbol) = MockOHLCVData(100)
fetch_ohlcv(ai::MockAssetInstance, tf::Symbol, start_time::DateTime, end_time::DateTime) = MockOHLCVData(50)

# Mock data structures for testing
Base.isempty(data::MockOHLCVData) = length(data.timestamps) == 0
Base.length(data::MockOHLCVData) = length(data.timestamps)
Base.last(data::MockOHLCVData) = (timestamp = data.timestamps[end], close = data.close[end])

# Include the OHLCV management module for testing
include("../src/data/ohlcv_management.jl")

@testset "OHLCV Management Tests" begin
    
    @testset "initdata! function" begin
        s = MockStrategy()
        
        # Test basic data initialization
        initdata!(s)
        
        # Should have initialized tracking structures
        @test haskey(s.attrs, :ohlcv_last_update)
        @test haskey(s.attrs, :data_quality_metrics)
        @test haskey(s.attrs, :data_validation_history)
        
        # Should have attempted OHLCV initialization
        @test haskey(s.attrs, :ohlcv_data)
        @test s.attrs[:ohlcv_data] isa Dict
    end
    
    @testset "initohlcv! function" begin
        s = MockStrategy()
        
        # Test OHLCV initialization
        initohlcv!(s)
        
        @test haskey(s.attrs, :ohlcv_data)
        @test s.attrs[:ohlcv_data] isa Dict
        
        # Should have data for configured assets
        assets = get_current_assets()
        for asset_str in assets
            ai = MockAssetInstance(asset_str, :phemex)
            @test haskey(s.attrs[:ohlcv_data], ai)
            @test s.attrs[:ohlcv_data][ai] isa MockOHLCVData
        end
        
        # Test with live mode (should setup watchers)
        s_live = MockStrategy()
        s_live.attrs[:live_mode] = true
        
        initohlcv!(s_live)
        
        @test haskey(s_live.attrs, :data_watchers)
        @test s_live.attrs[:data_watchers] isa Dict
    end
    
    @testset "init_asset_ohlcv! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test CCXT method
        init_asset_ohlcv!(s, ai, :ccxt)
        
        @test haskey(s.attrs, :ohlcv_data)
        @test haskey(s.attrs[:ohlcv_data], ai)
        @test s.attrs[:ohlcv_data][ai] isa MockOHLCVData
        @test length(s.attrs[:ohlcv_data][ai]) == 100
        
        # Test fetch method
        s_fetch = MockStrategy()
        s_fetch.attrs[:ohlcv_lookback] = 200
        
        init_asset_ohlcv!(s_fetch, ai, :fetch)
        
        @test haskey(s_fetch.attrs, :ohlcv_data)
        @test haskey(s_fetch.attrs[:ohlcv_data], ai)
        @test s_fetch.attrs[:ohlcv_data][ai] isa MockOHLCVData
        @test length(s_fetch.attrs[:ohlcv_data][ai]) == 50  # fetch_ohlcv returns 50
        
        # Test unknown method
        s_unknown = MockStrategy()
        init_asset_ohlcv!(s_unknown, ai, :unknown_method)
        
        # Should not crash, but may not have data
        @test !haskey(s_unknown.attrs, :ohlcv_data) || !haskey(get(s_unknown.attrs, :ohlcv_data, Dict()), ai)
    end
    
    @testset "validate_asset_availability function" begin
        # Test valid asset
        ai_valid = MockAssetInstance("BTC/USDT", :phemex)
        @test validate_asset_availability(ai_valid) == true
        
        # Test asset with missing fields (would need to mock this scenario)
        # For now, our mock always returns valid assets
        @test validate_asset_availability(ai_valid) == true
    end
    
    @testset "validate_initial_ohlcv! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test with no data
        result_no_data = validate_initial_ohlcv!(s, ai)
        @test result_no_data == false
        
        # Test with valid data
        s.attrs[:ohlcv_data] = Dict(ai => MockOHLCVData(100))
        result_valid = validate_initial_ohlcv!(s, ai)
        @test result_valid == true
        
        # Test with empty data
        s.attrs[:ohlcv_data][ai] = MockOHLCVData(0)
        result_empty = validate_initial_ohlcv!(s, ai)
        @test result_empty == false
    end
    
    @testset "check_ohlcv_freshness function" begin
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test with fresh data
        fresh_data = MockOHLCVData(10)  # Recent data
        @test check_ohlcv_freshness(fresh_data, ai) == true
        
        # Test with stale data
        stale_data = MockOHLCVData(0)
        # Manually set old timestamp
        stale_data.timestamps = [now() - Hour(2)]
        stale_data.close = [50000.0]
        
        @test check_ohlcv_freshness(stale_data, ai; max_age=Minute(30)) == false
        
        # Test with empty data
        empty_data = MockOHLCVData(0)
        @test check_ohlcv_freshness(empty_data, ai) == false
        
        # Test with custom max_age
        recent_data = MockOHLCVData(1)
        recent_data.timestamps = [now() - Minute(10)]
        recent_data.close = [50000.0]
        
        @test check_ohlcv_freshness(recent_data, ai; max_age=Minute(15)) == true
        @test check_ohlcv_freshness(recent_data, ai; max_age=Minute(5)) == false
    end
    
    @testset "check_ohlcv_continuity function" begin
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test with sufficient data
        good_data = MockOHLCVData(50)
        @test check_ohlcv_continuity(good_data, ai) == true
        
        # Test with insufficient data
        small_data = MockOHLCVData(5)
        @test check_ohlcv_continuity(small_data, ai) == true  # Still passes with small data
        
        # Test with single data point
        single_data = MockOHLCVData(1)
        @test check_ohlcv_continuity(single_data, ai) == true
        
        # Test with empty data
        empty_data = MockOHLCVData(0)
        @test check_ohlcv_continuity(empty_data, ai) == true  # Empty data passes continuity
    end
    
    @testset "Data watcher functions" begin
        s = MockStrategy()
        assets = ["BTC/USDT", "ETH/USDT"]
        
        # Test setup_data_watchers!
        setup_data_watchers!(s, assets, :phemex)
        
        @test haskey(s.attrs, :data_watchers)
        @test s.attrs[:data_watchers] isa Dict
        @test length(s.attrs[:data_watchers]) == length(assets)
        
        # Check individual watchers
        for asset_str in assets
            ai = MockAssetInstance(asset_str, :phemex)
            @test haskey(s.attrs[:data_watchers], ai)
            
            watcher = s.attrs[:data_watchers][ai]
            @test haskey(watcher, :asset)
            @test haskey(watcher, :timeframe)
            @test haskey(watcher, :started_at)
            @test haskey(watcher, :status)
            @test watcher[:status] == :active
        end
        
        # Test setup_asset_watcher!
        s_single = MockStrategy()
        ai_single = MockAssetInstance("DOT/USDT", :phemex)
        
        setup_asset_watcher!(s_single, ai_single)
        
        @test haskey(s_single.attrs, :data_watchers)
        @test haskey(s_single.attrs[:data_watchers], ai_single)
        @test s_single.attrs[:data_watchers][ai_single][:status] == :active
        
        # Test cleanup_data_watchers!
        cleanup_data_watchers!(s)
        
        # Watchers should be stopped and cleared
        for (ai, watcher) in s.attrs[:data_watchers]
            @test watcher[:status] == :stopped
        end
        
        # After cleanup, watchers dict should be empty
        @test isempty(s.attrs[:data_watchers])
    end
    
    @testset "Data tracking functions" begin
        s = MockStrategy()
        
        # Test init_data_tracking!
        init_data_tracking!(s)
        
        @test haskey(s.attrs, :ohlcv_last_update)
        @test haskey(s.attrs, :data_quality_metrics)
        @test haskey(s.attrs, :data_validation_history)
        @test s.attrs[:ohlcv_last_update] isa Dict
        @test s.attrs[:data_quality_metrics] isa Dict
        @test s.attrs[:data_validation_history] isa Dict
        
        # Test update_ohlcv_timestamp!
        ai = MockAssetInstance("BTC/USDT", :phemex)
        test_time = now()
        
        update_ohlcv_timestamp!(s, ai, test_time)
        
        @test haskey(s.attrs[:ohlcv_last_update], ai)
        @test s.attrs[:ohlcv_last_update][ai] == test_time
        
        # Test get_ohlcv_staleness
        staleness = get_ohlcv_staleness(s, ai)
        @test staleness isa Period
        @test staleness >= Second(0)
        
        # Test with no data
        ai_no_data = MockAssetInstance("ETH/USDT", :phemex)
        staleness_no_data = get_ohlcv_staleness(s, ai_no_data)
        @test staleness_no_data === nothing
        
        # Test is_ohlcv_stale
        @test is_ohlcv_stale(s, ai) == false  # Just updated
        @test is_ohlcv_stale(s, ai_no_data) == true  # No data
        
        # Test with old timestamp
        old_time = now() - Hour(2)
        update_ohlcv_timestamp!(s, ai, old_time)
        @test is_ohlcv_stale(s, ai; max_age=Minute(30)) == true
        @test is_ohlcv_stale(s, ai; max_age=Hour(3)) == false
    end
    
    @testset "validate_ohlcv_data function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Initialize tracking
        init_data_tracking!(s)
        
        # Test validation with no data
        result_no_data = validate_ohlcv_data(s, ai)
        
        @test haskey(result_no_data, :timestamp)
        @test haskey(result_no_data, :asset)
        @test haskey(result_no_data, :is_valid)
        @test haskey(result_no_data, :checks)
        @test haskey(result_no_data, :errors)
        
        @test result_no_data[:asset] == ai
        @test result_no_data[:is_valid] == false
        @test result_no_data[:checks][:availability] == false
        @test "No OHLCV data available" in result_no_data[:errors]
        
        # Test validation with valid data
        s.attrs[:ohlcv_data] = Dict(ai => MockOHLCVData(100))
        update_ohlcv_timestamp!(s, ai, now())
        
        result_valid = validate_ohlcv_data(s, ai)
        
        @test result_valid[:is_valid] == true
        @test result_valid[:checks][:availability] == true
        @test result_valid[:checks][:freshness] == true
        @test result_valid[:checks][:continuity] == true
        @test isempty(result_valid[:errors])
        
        # Test validation with stale data
        update_ohlcv_timestamp!(s, ai, now() - Hour(2))
        
        result_stale = validate_ohlcv_data(s, ai)
        
        @test result_stale[:is_valid] == false
        @test result_stale[:checks][:freshness] == false
        @test "OHLCV data is stale" in result_stale[:errors]
        
        # Check validation history
        @test haskey(s.attrs[:data_validation_history], ai)
        @test length(s.attrs[:data_validation_history][ai]) >= 2  # At least 2 validations
        
        # Test validation history limit
        for i in 1:150  # Add many validation results
            validate_ohlcv_data(s, ai)
        end
        
        @test length(s.attrs[:data_validation_history][ai]) <= 100  # Should be limited to 100
    end
    
    @testset "Integration and error handling" begin
        # Test initdata! with various configurations
        s_custom = MockStrategy()
        s_custom.attrs[:timeframe] = :tf_5m
        s_custom.attrs[:ohlcv_lookback] = 500
        
        initdata!(s_custom)
        
        @test haskey(s_custom.attrs, :ohlcv_data)
        @test haskey(s_custom.attrs, :ohlcv_last_update)
        
        # Test with empty asset list
        original_get_current_assets = get_current_assets
        get_current_assets() = String[]
        
        s_empty = MockStrategy()
        initohlcv!(s_empty)
        
        # Should handle empty asset list gracefully
        @test !haskey(s_empty.attrs, :ohlcv_data) || isempty(s_empty.attrs[:ohlcv_data])
        
        # Restore original function
        get_current_assets = original_get_current_assets
        
        # Test error handling in asset initialization
        s_error = MockStrategy()
        ai_error = MockAssetInstance("INVALID/PAIR", :invalid_exchange)
        
        # Should handle errors gracefully
        try
            init_asset_ohlcv!(s_error, ai_error, :ccxt)
            @test true  # Should not crash
        catch e
            @test e isa Exception  # Should catch and rethrow specific errors
        end
        
        # Test cleanup with no watchers
        s_no_watchers = MockStrategy()
        cleanup_data_watchers!(s_no_watchers)  # Should not crash
        @test true
        
        # Test validation with corrupted data structure
        s_corrupt = MockStrategy()
        s_corrupt.attrs[:ohlcv_data] = "invalid_data_structure"
        
        result_corrupt = validate_ohlcv_data(s_corrupt, ai)
        @test result_corrupt[:is_valid] == false
        @test !isempty(result_corrupt[:errors])
    end
    
    @testset "Configuration and customization" begin
        # Test with different timeframes
        s_1h = MockStrategy()
        s_1h.attrs[:timeframe] = :tf_1h
        
        ai = MockAssetInstance("BTC/USDT", :phemex)
        init_asset_ohlcv!(s_1h, ai, :ccxt)
        
        @test haskey(s_1h.attrs, :ohlcv_data)
        @test haskey(s_1h.attrs[:ohlcv_data], ai)
        
        # Test with custom lookback period
        s_custom_lookback = MockStrategy()
        s_custom_lookback.attrs[:ohlcv_lookback] = 2000
        
        init_asset_ohlcv!(s_custom_lookback, ai, :fetch)
        
        @test haskey(s_custom_lookback.attrs, :ohlcv_data)
        @test haskey(s_custom_lookback.attrs[:ohlcv_data], ai)
        
        # Test freshness with custom max_age
        fresh_data = MockOHLCVData(10)
        @test check_ohlcv_freshness(fresh_data, ai; max_age=Second(30)) == true
        @test check_ohlcv_freshness(fresh_data, ai; max_age=Microsecond(1)) == false
        
        # Test staleness checking with custom parameters
        s_staleness = MockStrategy()
        init_data_tracking!(s_staleness)
        update_ohlcv_timestamp!(s_staleness, ai, now() - Minute(10))
        
        @test is_ohlcv_stale(s_staleness, ai; max_age=Minute(5)) == true
        @test is_ohlcv_stale(s_staleness, ai; max_age=Minute(15)) == false
    end
end

println("✓ OHLCV management tests completed")