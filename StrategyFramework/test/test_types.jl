# Tests for core types and constants
using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

# Mock Planar types for testing
struct MockInstrumentInstance
    symbol::String
end

struct MockMovingExtrema
    min_val::Float64
    max_val::Float64
end

struct MockWMA
    value::Float64
end

struct MockCircularBuffer
    data::Vector{Float64}
    capacity::Int
    
    MockCircularBuffer(capacity::Int) = new(Float64[], capacity)
end

struct MockTrade
    asset::MockInstrumentInstance
    side::Symbol
    amount::Float64
    price::Float64
    timestamp::DateTime
end

# Include the types module for testing
include("../src/core/types.jl")

@testset "Core Types Tests" begin
    
    @testset "StrategyConfig structure" begin
        # Test default configuration
        config = StrategyConfig()
        
        @test config.signal_lifetime == 0.2
        @test config.trade_cooldown == Minute(1)
        @test config.order_timeout == Minute(2)
        @test config.def_lev == 1.0
        @test config.reserve_cash_pct == 0.1
        @test config.peak_cash == 0.0
        @test config.ordertype == :gtc
        @test config.ismake == true
        @test config.throttle == Second(10)
        @test config.sync_history_limit == 0
        @test config.watch_idle_timeout == Second(Day(1))
        
        # Test custom configuration
        custom_config = StrategyConfig(
            signal_lifetime = 0.5,
            def_lev = 2.0,
            reserve_cash_pct = 0.2,
            ordertype = :market,
            ismake = false
        )
        
        @test custom_config.signal_lifetime == 0.5
        @test custom_config.def_lev == 2.0
        @test custom_config.reserve_cash_pct == 0.2
        @test custom_config.ordertype == :market
        @test custom_config.ismake == false
        
        # Test that other fields retain defaults
        @test custom_config.trade_cooldown == Minute(1)
        @test custom_config.order_timeout == Minute(2)
        @test custom_config.peak_cash == 0.0
        
        # Test field mutability
        config.signal_lifetime = 0.8
        @test config.signal_lifetime == 0.8
        
        config.def_lev = 3.0
        @test config.def_lev == 3.0
        
        config.reserve_cash_pct = 0.15
        @test config.reserve_cash_pct == 0.15
    end
    
    @testset "PositionTracker structure" begin
        # Test default position tracker
        tracker = PositionTracker()
        
        @test tracker.extremas isa Dict
        @test isempty(tracker.extremas)
        @test tracker.hl_trackers isa Dict
        @test isempty(tracker.hl_trackers)
        @test tracker.backoff isa Dict
        @test isempty(tracker.backoff)
        @test tracker.uni_iter isa Tuple
        @test length(tracker.uni_iter[1]) == 0
        @test tracker.uni_iter[2] isa Ref{DateTime}
        @test tracker.uni_iter[2][] == DateTime(0)
        
        # Test adding data to tracker
        ii = MockInstrumentInstance("BTC/USDT")
        extrema = MockMovingExtrema(49000.0, 51000.0)
        wma = MockWMA(50000.0)
        
        tracker.extremas[ii] = extrema
        tracker.hl_trackers[ii] = (Ref(now()), wma)
        tracker.backoff[ii] = now() - Hour(1)
        
        @test haskey(tracker.extremas, ii)
        @test tracker.extremas[ii] == extrema
        @test haskey(tracker.hl_trackers, ii)
        @test tracker.hl_trackers[ii][2] == wma
        @test haskey(tracker.backoff, ii)
        
        # Test universe iterator
        assets = [MockInstrumentInstance("BTC/USDT"), MockInstrumentInstance("ETH/USDT")]
        timestamp = now()
        
        tracker.uni_iter = (assets, Ref(timestamp))
        @test length(tracker.uni_iter[1]) == 2
        @test tracker.uni_iter[2][] == timestamp
    end
    
    @testset "PerformanceMetrics structure" begin
        # Test default performance metrics
        metrics = PerformanceMetrics()
        
        @test metrics.pnl_history isa Dict
        @test isempty(metrics.pnl_history)
        @test metrics.trade_history isa Dict
        @test isempty(metrics.trade_history)
        @test metrics.peak_cash == 0.0
        @test metrics.max_drawdown == 0.0
        @test metrics.total_trades == 0
        @test metrics.winning_trades == 0
        
        # Test custom performance metrics
        custom_metrics = PerformanceMetrics(
            peak_cash = 10000.0,
            max_drawdown = -0.15,
            total_trades = 100,
            winning_trades = 65
        )
        
        @test custom_metrics.peak_cash == 10000.0
        @test custom_metrics.max_drawdown == -0.15
        @test custom_metrics.total_trades == 100
        @test custom_metrics.winning_trades == 65
        
        # Test adding data to metrics
        ii = MockInstrumentInstance("BTC/USDT")
        buffer = MockCircularBuffer(100)
        trade = MockTrade(ii, :buy, 0.1, 50000.0, now())
        
        metrics.pnl_history[ii] = buffer
        metrics.trade_history[ii] = [trade]
        
        @test haskey(metrics.pnl_history, ii)
        @test metrics.pnl_history[ii] == buffer
        @test haskey(metrics.trade_history, ii)
        @test length(metrics.trade_history[ii]) == 1
        @test metrics.trade_history[ii][1] == trade
        
        # Test metrics calculations
        metrics.total_trades = 50
        metrics.winning_trades = 32
        win_rate = metrics.winning_trades / metrics.total_trades
        @test win_rate ≈ 0.64
        
        # Test drawdown calculation
        metrics.peak_cash = 12000.0
        current_cash = 10200.0
        drawdown = (current_cash - metrics.peak_cash) / metrics.peak_cash
        @test drawdown ≈ -0.15
        
        if drawdown < metrics.max_drawdown
            metrics.max_drawdown = drawdown
        end
        @test metrics.max_drawdown == -0.15
    end
    
    @testset "Configuration constants" begin
        # Test that constants are properly defined
        @test ASSETS_CT isa Dict
        @test ASSETS_FLAG isa Ref{Symbol}
        @test WATCHER_EXC isa Ref{Symbol}
        @test OHLCV_METHOD isa Ref{Symbol}
        @test PROFILING isa Ref{Bool}
        
        # Test constant mutability
        PROFILING[] = true
        @test PROFILING[] == true
        
        PROFILING[] = false
        @test PROFILING[] == false
        
        # Test assets configuration
        test_key = (:phemex, :spot)
        test_assets = ["BTC/USDT", "ETH/USDT"]
        ASSETS_CT[test_key] = test_assets
        
        @test haskey(ASSETS_CT, test_key)
        @test ASSETS_CT[test_key] == test_assets
        
        # Test flag settings
        ASSETS_FLAG[] = :test_flag
        @test ASSETS_FLAG[] == :test_flag
        
        WATCHER_EXC[] = :phemex
        @test WATCHER_EXC[] == :phemex
        
        OHLCV_METHOD[] = :websocket
        @test OHLCV_METHOD[] == :websocket
    end
    
    @testset "Type validation and constraints" begin
        # Test StrategyConfig field types
        config = StrategyConfig()
        
        @test config.signal_lifetime isa Float64
        @test config.trade_cooldown isa Period
        @test config.order_timeout isa Period
        @test config.def_lev isa Float64
        @test config.reserve_cash_pct isa Float64
        @test config.peak_cash isa Float64
        @test config.ordertype isa Symbol
        @test config.ismake isa Bool
        @test config.throttle isa Period
        @test config.sync_history_limit isa Int
        @test config.watch_idle_timeout isa Period
        
        # Test reasonable value ranges
        @test 0.0 <= config.signal_lifetime <= 1.0
        @test config.def_lev > 0.0
        @test 0.0 <= config.reserve_cash_pct <= 1.0
        @test config.peak_cash >= 0.0
        @test config.sync_history_limit >= 0
        
        # Test Period types
        @test config.trade_cooldown >= Second(0)
        @test config.order_timeout >= Second(0)
        @test config.throttle >= Second(0)
        @test config.watch_idle_timeout >= Second(0)
        
        # Test symbol values
        valid_order_types = [:gtc, :market, :limit, :stop]
        @test config.ordertype in valid_order_types || config.ordertype isa Symbol
    end
    
    @testset "Structure initialization edge cases" begin
        # Test StrategyConfig with extreme values
        extreme_config = StrategyConfig(
            signal_lifetime = 0.0,
            def_lev = 0.1,
            reserve_cash_pct = 1.0,
            sync_history_limit = 1000000
        )
        
        @test extreme_config.signal_lifetime == 0.0
        @test extreme_config.def_lev == 0.1
        @test extreme_config.reserve_cash_pct == 1.0
        @test extreme_config.sync_history_limit == 1000000
        
        # Test PositionTracker with pre-populated data
        ii1 = MockInstrumentInstance("BTC/USDT")
        ii2 = MockInstrumentInstance("ETH/USDT")
        
        extremas = Dict(ii1 => MockMovingExtrema(45000.0, 55000.0))
        backoff = Dict(ii1 => now() - Hour(2), ii2 => now() - Minute(30))
        
        tracker = PositionTracker(
            extremas = extremas,
            backoff = backoff
        )
        
        @test length(tracker.extremas) == 1
        @test length(tracker.backoff) == 2
        @test haskey(tracker.extremas, ii1)
        @test haskey(tracker.backoff, ii1)
        @test haskey(tracker.backoff, ii2)
        
        # Test PerformanceMetrics with pre-populated data
        pnl_data = Dict(ii1 => MockCircularBuffer(50))
        trade_data = Dict(ii1 => MockTrade[])
        
        metrics = PerformanceMetrics(
            pnl_history = pnl_data,
            trade_history = trade_data,
            peak_cash = 15000.0,
            total_trades = 200
        )
        
        @test length(metrics.pnl_history) == 1
        @test length(metrics.trade_history) == 1
        @test metrics.peak_cash == 15000.0
        @test metrics.total_trades == 200
        @test metrics.winning_trades == 0  # Default value
    end
    
    @testset "Type compatibility and conversions" begin
        # Test Period arithmetic
        config = StrategyConfig()
        
        # Test that periods can be compared and manipulated
        @test config.trade_cooldown < config.order_timeout
        @test config.throttle < config.trade_cooldown
        
        # Test period conversions
        cooldown_seconds = config.trade_cooldown.value / 1000  # Convert to seconds
        @test cooldown_seconds == 60.0  # 1 minute
        
        timeout_seconds = config.order_timeout.value / 1000
        @test timeout_seconds == 120.0  # 2 minutes
        
        # Test DateTime operations with backoff
        tracker = PositionTracker()
        ii = MockInstrumentInstance("BTC/USDT")
        
        current_time = now()
        tracker.backoff[ii] = current_time - config.trade_cooldown
        
        # Check if cooldown has expired
        cooldown_expired = current_time >= tracker.backoff[ii] + config.trade_cooldown
        @test cooldown_expired == true
        
        # Test with recent backoff
        tracker.backoff[ii] = current_time - Second(30)  # 30 seconds ago
        cooldown_expired = current_time >= tracker.backoff[ii] + config.trade_cooldown
        @test cooldown_expired == false
    end
end

println("✓ Core types tests completed")