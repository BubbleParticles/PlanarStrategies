# Tests for data management functions (OHLCV, PnL, trends)
using Test
using Dates
using Statistics

# Mock types for testing
abstract type MockAssetInstance end

struct MockBTCUSDT <: MockAssetInstance
    symbol::String
    MockBTCUSDT() = new("BTC/USDT")
end

# Mock OHLCV data structure
mutable struct MockOHLCVData
    timestamps::Vector{DateTime}
    open::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    close::Vector{Float64}
    volume::Vector{Float64}
    
    function MockOHLCVData()
        new(DateTime[], Float64[], Float64[], Float64[], Float64[], Float64[])
    end
end

# Mock strategy with data management
mutable struct MockDataStrategy
    config::NamedTuple
    ohlcv_data::Dict{MockAssetInstance, MockOHLCVData}
    pnl_history::Dict{MockAssetInstance, Vector{Float64}}
    trend_data::Dict{MockAssetInstance, Dict{Symbol, Any}}
    performance_metrics::Dict{Symbol, Float64}
    
    function MockDataStrategy()
        config = (
            pnl_n = 14,
            warmup_candles = 100,
            sync_history_limit = 1000
        )
        new(
            config,
            Dict{MockAssetInstance, MockOHLCVData}(),
            Dict{MockAssetInstance, Vector{Float64}}(),
            Dict{MockAssetInstance, Dict{Symbol, Any}}(),
            Dict{Symbol, Float64}()
        )
    end
end

# Helper function to generate mock OHLCV data
function generate_mock_ohlcv!(data::MockOHLCVData, start_time::DateTime, periods::Int, base_price::Float64 = 50000.0)
    for i in 1:periods
        timestamp = start_time + Minute(i)
        
        # Generate realistic OHLCV data with some randomness
        prev_close = isempty(data.close) ? base_price : data.close[end]
        change_pct = (rand() - 0.5) * 0.02  # ±1% change
        
        open_price = prev_close * (1 + change_pct * 0.5)
        close_price = prev_close * (1 + change_pct)
        
        high_price = max(open_price, close_price) * (1 + rand() * 0.005)
        low_price = min(open_price, close_price) * (1 - rand() * 0.005)
        
        volume = 100.0 + rand() * 50.0
        
        push!(data.timestamps, timestamp)
        push!(data.open, open_price)
        push!(data.high, high_price)
        push!(data.low, low_price)
        push!(data.close, close_price)
        push!(data.volume, volume)
    end
end

@testset "Data Management Tests" begin
    
    @testset "initialize_ohlcv! function" begin
        s = MockDataStrategy()
        ai = MockBTCUSDT()
        
        # Mock the initialize_ohlcv! function
        function initialize_ohlcv!(s::MockDataStrategy, ai::MockAssetInstance; periods::Int = 100)
            if !haskey(s.ohlcv_data, ai)
                s.ohlcv_data[ai] = MockOHLCVData()
            end
            
            data = s.ohlcv_data[ai]
            start_time = now() - Minute(periods)
            
            generate_mock_ohlcv!(data, start_time, periods)
            
            return length(data.timestamps) == periods
        end
        
        # Test initialization
        @test initialize_ohlcv!(s, ai; periods = 50)
        @test haskey(s.ohlcv_data, ai)
        @test length(s.ohlcv_data[ai].timestamps) == 50
        @test length(s.ohlcv_data[ai].close) == 50
        
        # Test data quality
        data = s.ohlcv_data[ai]
        @test all(data.high .>= data.low)
        @test all(data.high .>= data.open)
        @test all(data.high .>= data.close)
        @test all(data.low .<= data.open)
        @test all(data.low .<= data.close)
        @test all(data.volume .> 0)
        
        # Test timestamps are sequential
        for i in 2:length(data.timestamps)
            @test data.timestamps[i] > data.timestamps[i-1]
        end
        
        # Test re-initialization doesn't duplicate data
        initial_length = length(data.timestamps)
        initialize_ohlcv!(s, ai; periods = 25)
        @test length(s.ohlcv_data[ai].timestamps) == 25  # Should replace, not append
        
        # Test with zero periods
        @test !initialize_ohlcv!(s, ai; periods = 0)
        
        # Test with large periods
        @test initialize_ohlcv!(s, ai; periods = 1000)
        @test length(s.ohlcv_data[ai].timestamps) == 1000
    end
    
    @testset "track_pnl! function" begin
        s = MockDataStrategy()
        ai = MockBTCUSDT()
        
        # Initialize with some OHLCV data
        initialize_ohlcv!(s, ai; periods = 50)
        
        # Mock the track_pnl! function
        function track_pnl!(s::MockDataStrategy, ai::MockAssetInstance, ats::DateTime, ts::DateTime; 
                           interval::Period = Minute(s.config.pnl_n))
            
            if !haskey(s.pnl_history, ai)
                s.pnl_history[ai] = Float64[]
            end
            
            # Calculate PnL based on price movement
            data = s.ohlcv_data[ai]
            if isempty(data.close)
                return 0.0
            end
            
            current_price = data.close[end]
            
            # Find price from interval ago
            target_time = ats - interval
            past_price = current_price  # Default to current if not found
            
            for i in length(data.timestamps):-1:1
                if data.timestamps[i] <= target_time
                    past_price = data.close[i]
                    break
                end
            end
            
            # Calculate percentage change
            pnl_pct = (current_price - past_price) / past_price
            
            # Store PnL
            push!(s.pnl_history[ai], pnl_pct)
            
            # Keep only recent PnL history
            if length(s.pnl_history[ai]) > s.config.pnl_n * 2
                s.pnl_history[ai] = s.pnl_history[ai][end-s.config.pnl_n+1:end]
            end
            
            return pnl_pct
        end
        
        # Test PnL tracking
        ats = now()
        ts = now()
        pnl = track_pnl!(s, ai, ats, ts)
        
        @test pnl isa Float64
        @test haskey(s.pnl_history, ai)
        @test length(s.pnl_history[ai]) == 1
        @test s.pnl_history[ai][1] == pnl
        
        # Test multiple PnL calculations
        for i in 1:20
            pnl_i = track_pnl!(s, ai, ats + Minute(i), ts + Minute(i))
            @test pnl_i isa Float64
        end
        
        @test length(s.pnl_history[ai]) == 21
        
        # Test PnL history limit
        for i in 1:50
            track_pnl!(s, ai, ats + Minute(i + 20), ts + Minute(i + 20))
        end
        
        @test length(s.pnl_history[ai]) <= s.config.pnl_n * 2
        
        # Test with custom interval
        pnl_custom = track_pnl!(s, ai, ats, ts; interval = Minute(5))
        @test pnl_custom isa Float64
        
        # Test edge cases
        empty_strategy = MockDataStrategy()
        pnl_empty = track_pnl!(empty_strategy, ai, ats, ts)
        @test pnl_empty == 0.0
    end
    
    @testset "track_trends! function" begin
        s = MockDataStrategy()
        ai = MockBTCUSDT()
        
        # Initialize with OHLCV data
        initialize_ohlcv!(s, ai; periods = 100)
        
        # Mock the track_trends! function
        function track_trends!(s::MockDataStrategy, ai::MockAssetInstance, ats::DateTime)
            if !haskey(s.trend_data, ai)
                s.trend_data[ai] = Dict{Symbol, Any}()
            end
            
            data = s.ohlcv_data[ai]
            if length(data.close) < 20
                return false
            end
            
            trends = s.trend_data[ai]
            
            # Calculate simple moving averages
            sma_5 = sum(data.close[end-4:end]) / 5
            sma_20 = sum(data.close[end-19:end]) / 20
            
            # Determine trend direction
            if sma_5 > sma_20 * 1.01  # 1% threshold
                trends[:direction] = :up
            elseif sma_5 < sma_20 * 0.99
                trends[:direction] = :down
            else
                trends[:direction] = :sideways
            end
            
            # Calculate trend strength
            price_range = maximum(data.high[end-19:end]) - minimum(data.low[end-19:end])
            current_price = data.close[end]
            trends[:strength] = abs(sma_5 - sma_20) / current_price
            
            # Calculate volatility
            returns = [data.close[i] / data.close[i-1] - 1 for i in 2:length(data.close)]
            trends[:volatility] = std(returns[end-19:end])
            
            # Track extremes
            trends[:recent_high] = maximum(data.high[end-19:end])
            trends[:recent_low] = minimum(data.low[end-19:end])
            
            # Update timestamp
            trends[:last_update] = ats
            
            return true
        end
        
        # Test trend tracking
        ats = now()
        result = track_trends!(s, ai, ats)
        
        @test result == true
        @test haskey(s.trend_data, ai)
        
        trends = s.trend_data[ai]
        @test haskey(trends, :direction)
        @test haskey(trends, :strength)
        @test haskey(trends, :volatility)
        @test haskey(trends, :recent_high)
        @test haskey(trends, :recent_low)
        @test haskey(trends, :last_update)
        
        @test trends[:direction] in [:up, :down, :sideways]
        @test trends[:strength] isa Float64
        @test trends[:strength] >= 0.0
        @test trends[:volatility] isa Float64
        @test trends[:volatility] >= 0.0
        @test trends[:recent_high] >= trends[:recent_low]
        @test trends[:last_update] == ats
        
        # Test with insufficient data
        empty_strategy = MockDataStrategy()
        empty_ai = MockBTCUSDT()
        initialize_ohlcv!(empty_strategy, empty_ai; periods = 5)  # Too few periods
        
        result_empty = track_trends!(empty_strategy, empty_ai, ats)
        @test result_empty == false
        
        # Test trend consistency over time
        for i in 1:10
            track_trends!(s, ai, ats + Minute(i))
        end
        
        # Should still have valid trend data
        @test haskey(s.trend_data[ai], :direction)
        @test s.trend_data[ai][:last_update] == ats + Minute(10)
    end
    
    @testset "Performance metrics calculation" begin
        s = MockDataStrategy()
        ai = MockBTCUSDT()
        
        # Initialize with data and PnL history
        initialize_ohlcv!(s, ai; periods = 100)
        
        # Generate some PnL history
        for i in 1:30
            track_pnl!(s, ai, now() - Minute(30 - i), now() - Minute(30 - i))
        end
        
        # Mock performance metrics calculation
        function calculate_performance_metrics!(s::MockDataStrategy, ai::MockAssetInstance)
            if !haskey(s.pnl_history, ai) || isempty(s.pnl_history[ai])
                return false
            end
            
            pnl_data = s.pnl_history[ai]
            
            # Calculate basic metrics
            s.performance_metrics[:total_return] = sum(pnl_data)
            s.performance_metrics[:avg_return] = mean(pnl_data)
            s.performance_metrics[:volatility] = std(pnl_data)
            
            # Calculate Sharpe ratio (assuming risk-free rate of 0)
            if s.performance_metrics[:volatility] > 0
                s.performance_metrics[:sharpe_ratio] = s.performance_metrics[:avg_return] / s.performance_metrics[:volatility]
            else
                s.performance_metrics[:sharpe_ratio] = 0.0
            end
            
            # Calculate maximum drawdown
            cumulative_returns = cumsum(pnl_data)
            running_max = cumsum([max(cumulative_returns[i], i > 1 ? running_max[i-1] : cumulative_returns[i]) for i in 1:length(cumulative_returns)])
            drawdowns = cumulative_returns .- running_max
            s.performance_metrics[:max_drawdown] = minimum(drawdowns)
            
            # Win rate
            winning_periods = count(x -> x > 0, pnl_data)
            s.performance_metrics[:win_rate] = winning_periods / length(pnl_data)
            
            return true
        end
        
        # Test performance calculation
        result = calculate_performance_metrics!(s, ai)
        @test result == true
        
        @test haskey(s.performance_metrics, :total_return)
        @test haskey(s.performance_metrics, :avg_return)
        @test haskey(s.performance_metrics, :volatility)
        @test haskey(s.performance_metrics, :sharpe_ratio)
        @test haskey(s.performance_metrics, :max_drawdown)
        @test haskey(s.performance_metrics, :win_rate)
        
        @test s.performance_metrics[:volatility] >= 0.0
        @test 0.0 <= s.performance_metrics[:win_rate] <= 1.0
        @test s.performance_metrics[:max_drawdown] <= 0.0
        
        # Test with empty PnL history
        empty_strategy = MockDataStrategy()
        result_empty = calculate_performance_metrics!(empty_strategy, ai)
        @test result_empty == false
    end
    
    @testset "Data validation and staleness checking" begin
        s = MockDataStrategy()
        ai = MockBTCUSDT()
        
        # Mock data validation functions
        function is_ohlcv_stale(s::MockDataStrategy, ai::MockAssetInstance, max_age::Period = Minute(5))
            if !haskey(s.ohlcv_data, ai)
                return true
            end
            
            data = s.ohlcv_data[ai]
            if isempty(data.timestamps)
                return true
            end
            
            last_update = data.timestamps[end]
            return now() - last_update > max_age
        end
        
        function validate_ohlcv_data(s::MockDataStrategy, ai::MockAssetInstance)
            if !haskey(s.ohlcv_data, ai)
                return false, ["No OHLCV data found"]
            end
            
            data = s.ohlcv_data[ai]
            errors = String[]
            
            # Check data consistency
            if length(data.timestamps) != length(data.close)
                push!(errors, "Inconsistent data lengths")
            end
            
            # Check OHLC relationships
            for i in 1:length(data.close)
                if data.high[i] < data.low[i]
                    push!(errors, "High < Low at index $i")
                end
                if data.high[i] < data.open[i] || data.high[i] < data.close[i]
                    push!(errors, "High < Open/Close at index $i")
                end
                if data.low[i] > data.open[i] || data.low[i] > data.close[i]
                    push!(errors, "Low > Open/Close at index $i")
                end
            end
            
            # Check for negative values
            if any(data.volume .<= 0)
                push!(errors, "Non-positive volume values found")
            end
            
            # Check timestamp ordering
            for i in 2:length(data.timestamps)
                if data.timestamps[i] <= data.timestamps[i-1]
                    push!(errors, "Timestamps not in ascending order at index $i")
                end
            end
            
            return isempty(errors), errors
        end
        
        # Test with fresh data
        initialize_ohlcv!(s, ai; periods = 50)
        @test !is_ohlcv_stale(s, ai)
        
        is_valid, errors = validate_ohlcv_data(s, ai)
        @test is_valid == true
        @test isempty(errors)
        
        # Test staleness
        @test is_ohlcv_stale(s, ai, Microsecond(1))  # Very short max age
        @test !is_ohlcv_stale(s, ai, Hour(1))       # Long max age
        
        # Test with no data
        empty_strategy = MockDataStrategy()
        @test is_ohlcv_stale(empty_strategy, ai)
        
        is_valid_empty, errors_empty = validate_ohlcv_data(empty_strategy, ai)
        @test is_valid_empty == false
        @test !isempty(errors_empty)
        
        # Test with corrupted data
        corrupted_strategy = MockDataStrategy()
        initialize_ohlcv!(corrupted_strategy, ai; periods = 10)
        
        # Corrupt the data
        corrupted_data = corrupted_strategy.ohlcv_data[ai]
        corrupted_data.high[1] = corrupted_data.low[1] - 100  # Make high < low
        corrupted_data.volume[2] = -10.0  # Negative volume
        
        is_valid_corrupted, errors_corrupted = validate_ohlcv_data(corrupted_strategy, ai)
        @test is_valid_corrupted == false
        @test length(errors_corrupted) >= 2
        @test any(contains.(errors_corrupted, "High < Low"))
        @test any(contains.(errors_corrupted, "Non-positive volume"))
    end
    
    @testset "Data synchronization and limits" begin
        s = MockDataStrategy()
        ai = MockBTCUSDT()
        
        # Mock data synchronization function
        function sync_ohlcv_data!(s::MockDataStrategy, ai::MockAssetInstance, new_data::Vector{Tuple{DateTime, Float64, Float64, Float64, Float64, Float64}})
            if !haskey(s.ohlcv_data, ai)
                s.ohlcv_data[ai] = MockOHLCVData()
            end
            
            data = s.ohlcv_data[ai]
            
            # Add new data
            for (timestamp, open, high, low, close, volume) in new_data
                push!(data.timestamps, timestamp)
                push!(data.open, open)
                push!(data.high, high)
                push!(data.low, low)
                push!(data.close, close)
                push!(data.volume, volume)
            end
            
            # Apply sync limit
            if s.config.sync_history_limit > 0 && length(data.timestamps) > s.config.sync_history_limit
                excess = length(data.timestamps) - s.config.sync_history_limit
                
                data.timestamps = data.timestamps[excess+1:end]
                data.open = data.open[excess+1:end]
                data.high = data.high[excess+1:end]
                data.low = data.low[excess+1:end]
                data.close = data.close[excess+1:end]
                data.volume = data.volume[excess+1:end]
            end
            
            return length(data.timestamps)
        end
        
        # Test data synchronization
        new_data = [
            (now() - Minute(5), 50000.0, 50100.0, 49900.0, 50050.0, 100.0),
            (now() - Minute(4), 50050.0, 50200.0, 50000.0, 50150.0, 120.0),
            (now() - Minute(3), 50150.0, 50300.0, 50100.0, 50250.0, 110.0)
        ]
        
        result_length = sync_ohlcv_data!(s, ai, new_data)
        @test result_length == 3
        @test length(s.ohlcv_data[ai].timestamps) == 3
        
        # Test sync limit
        s.config = merge(s.config, (sync_history_limit = 2,))
        
        additional_data = [
            (now() - Minute(2), 50250.0, 50350.0, 50200.0, 50300.0, 105.0),
            (now() - Minute(1), 50300.0, 50400.0, 50250.0, 50350.0, 115.0)
        ]
        
        result_length_limited = sync_ohlcv_data!(s, ai, additional_data)
        @test result_length_limited == 2  # Should be limited to sync_history_limit
        @test length(s.ohlcv_data[ai].timestamps) == 2
        
        # Verify the oldest data was removed
        @test s.ohlcv_data[ai].timestamps[1] == now() - Minute(2)
        @test s.ohlcv_data[ai].timestamps[2] == now() - Minute(1)
    end
end

println("✓ Data management tests completed")