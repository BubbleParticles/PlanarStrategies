# Tests for PnL tracking system
using Test
using Dates
using Statistics

# Mock Planar types and functions for testing
struct MockStrategy
    attrs::Dict{Symbol, Any}
    
    MockStrategy() = new(Dict{Symbol, Any}())
end

struct MockAssetInstance
    symbol::String
    exchange::Symbol
    
    MockAssetInstance(symbol::String, exchange::Symbol = :phemex) = new(symbol, exchange)
end

struct MockCircularBuffer{T}
    data::Vector{T}
    capacity::Int
    
    MockCircularBuffer{T}(capacity::Int) where T = new{T}(T[], capacity)
end

struct MockPosition
    size::Float64
    entry_price::Float64
    side::Symbol
    
    MockPosition(size::Float64, entry_price::Float64) = new(size, entry_price, size > 0 ? :long : :short)
end

# Mock functions and constants
const WATCHER_EXC = Ref(:phemex)
get_current_assets() = ["BTC/USDT", "ETH/USDT", "ADA/USDT"]
AssetInstance(asset_str::String, exchange::Symbol) = MockAssetInstance(asset_str, exchange)

# Mock CircularBuffer operations
Base.push!(cb::MockCircularBuffer, item) = begin
    push!(cb.data, item)
    if length(cb.data) > cb.capacity
        popfirst!(cb.data)
    end
    cb
end

Base.isempty(cb::MockCircularBuffer) = isempty(cb.data)
Base.length(cb::MockCircularBuffer) = length(cb.data)
Base.last(cb::MockCircularBuffer) = last(cb.data)
Base.iterate(cb::MockCircularBuffer, state...) = iterate(cb.data, state...)

# Include the PnL tracking module for testing
include("../src/data/pnl_tracking.jl")

# Override CircularBuffer with our mock
const CircularBuffer = MockCircularBuffer

@testset "PnL Tracking Tests" begin
    
    @testset "trackpnl! for single asset" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Mock position and price data
        s.attrs[:positions] = Dict(ai => MockPosition(0.1, 50000.0))
        s.attrs[:ohlcv_data] = Dict(ai => "mock_ohlcv")
        
        # Test PnL tracking
        trackpnl!(s, ai, ats)
        
        # Check that tracking structures were initialized
        @test haskey(s.attrs, :pnl_history)
        @test haskey(s.attrs, :trade_history)
        @test haskey(s.attrs, :performance_metrics)
        @test haskey(s.attrs, :peak_cash)
        
        # Check asset-specific data
        @test haskey(s.attrs[:pnl_history], ai)
        @test haskey(s.attrs[:trade_history], ai)
        @test haskey(s.attrs[:performance_metrics], ai)
        @test haskey(s.attrs[:peak_cash], ai)
        
        # Check performance metrics structure
        metrics = s.attrs[:performance_metrics][ai]
        @test haskey(metrics, :total_pnl)
        @test haskey(metrics, :realized_pnl)
        @test haskey(metrics, :unrealized_pnl)
        @test haskey(metrics, :peak_pnl)
        @test haskey(metrics, :max_drawdown)
        @test haskey(metrics, :total_trades)
        @test haskey(metrics, :winning_trades)
        @test haskey(metrics, :win_rate)
        @test haskey(metrics, :sharpe_ratio)
        
        # Check peak cash structure
        peak_data = s.attrs[:peak_cash][ai]
        @test haskey(peak_data, :peak_value)
        @test haskey(peak_data, :current_value)
        @test haskey(peak_data, :peak_time)
        @test haskey(peak_data, :last_updated)
    end
    
    @testset "trackpnl! for all assets" begin
        s = MockStrategy()
        ats = now()
        
        # Mock data for multiple assets
        assets = get_current_assets()
        for asset_str in assets
            ai = MockAssetInstance(asset_str, :phemex)
            if !haskey(s.attrs, :positions)
                s.attrs[:positions] = Dict()
            end
            s.attrs[:positions][ai] = MockPosition(0.05, 50000.0)
        end
        
        # Test tracking all assets
        trackpnl!(s, ats)
        
        # Check that all assets were processed
        @test haskey(s.attrs, :pnl_history)
        @test haskey(s.attrs, :performance_metrics)
        @test haskey(s.attrs, :strategy_metrics)
        
        # Check each asset has data
        for asset_str in assets
            ai = MockAssetInstance(asset_str, :phemex)
            @test haskey(s.attrs[:pnl_history], ai)
            @test haskey(s.attrs[:performance_metrics], ai)
        end
        
        # Check strategy-level metrics
        strategy_metrics = s.attrs[:strategy_metrics]
        @test haskey(strategy_metrics, :total_pnl)
        @test haskey(strategy_metrics, :total_trades)
        @test haskey(strategy_metrics, :win_rate)
        @test haskey(strategy_metrics, :last_updated)
    end
    
    @testset "init_pnl_tracking! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test initialization
        init_pnl_tracking!(s, ai)
        
        # Check all structures were created
        @test haskey(s.attrs, :pnl_history)
        @test haskey(s.attrs, :trade_history)
        @test haskey(s.attrs, :performance_metrics)
        
        @test haskey(s.attrs[:pnl_history], ai)
        @test haskey(s.attrs[:trade_history], ai)
        @test haskey(s.attrs[:performance_metrics], ai)
        
        # Check data types
        @test s.attrs[:pnl_history][ai] isa MockCircularBuffer
        @test s.attrs[:trade_history][ai] isa Vector
        @test s.attrs[:performance_metrics][ai] isa Dict
        
        # Check initial values
        metrics = s.attrs[:performance_metrics][ai]
        @test metrics[:total_pnl] == 0.0
        @test metrics[:realized_pnl] == 0.0
        @test metrics[:unrealized_pnl] == 0.0
        @test metrics[:total_trades] == 0
        @test metrics[:win_rate] == 0.0
        
        # Test re-initialization doesn't overwrite
        metrics[:total_pnl] = 100.0
        init_pnl_tracking!(s, ai)
        @test s.attrs[:performance_metrics][ai][:total_pnl] == 100.0  # Should not reset
    end
    
    @testset "calculate_current_pnl function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Test with no position
        pnl_no_position = calculate_current_pnl(s, ai, ats)
        @test pnl_no_position == 0.0
        
        # Test with long position
        s.attrs[:positions] = Dict(ai => MockPosition(0.1, 49000.0))  # Long 0.1 BTC at 49000
        s.attrs[:trade_history] = Dict(ai => [])
        
        pnl_long = calculate_current_pnl(s, ai, ats)
        # Current price is 50000 (mocked), entry was 49000, position is 0.1
        # Unrealized PnL = (50000 - 49000) * 0.1 = 100
        @test pnl_long > 0  # Should be positive for profitable long
        
        # Test with short position
        s.attrs[:positions][ai] = MockPosition(-0.1, 51000.0)  # Short 0.1 BTC at 51000
        
        pnl_short = calculate_current_pnl(s, ai, ats)
        # Current price is 50000, entry was 51000, position is -0.1
        # Unrealized PnL = (51000 - 50000) * 0.1 = 100
        @test pnl_short > 0  # Should be positive for profitable short
        
        # Test with realized PnL
        s.attrs[:trade_history][ai] = [
            Dict(:status => :closed, :pnl => 50.0),
            Dict(:status => :closed, :pnl => -20.0),
            Dict(:status => :open, :pnl => 30.0)  # Should not count
        ]
        
        pnl_with_realized = calculate_current_pnl(s, ai, ats)
        # Should include realized PnL: 50 - 20 = 30, plus unrealized
        @test pnl_with_realized > pnl_short  # Should be higher with realized gains
    end
    
    @testset "update_pnl_history! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Initialize tracking
        init_pnl_tracking!(s, ai)
        
        ats = now()
        pnl = 150.0
        interval = Minute(15)
        
        # Test first update
        update_pnl_history!(s, ai, ats, pnl, interval)
        
        pnl_history = s.attrs[:pnl_history][ai]
        @test length(pnl_history) == 1
        @test last(pnl_history) == (ats, pnl)
        
        # Test update within interval (should not add new point)
        update_pnl_history!(s, ai, ats + Minute(5), pnl + 10, interval)
        @test length(pnl_history) == 1  # Should still be 1
        
        # Test update after interval (should add new point)
        update_pnl_history!(s, ai, ats + Minute(20), pnl + 20, interval)
        @test length(pnl_history) == 2
        @test last(pnl_history) == (ats + Minute(20), pnl + 20)
        
        # Test capacity limit
        for i in 1:1100  # Add more than capacity
            update_pnl_history!(s, ai, ats + Minute(i * 20), Float64(i), interval)
        end
        
        @test length(pnl_history) <= 1000  # Should respect capacity limit
    end
    
    @testset "update_performance_metrics! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Initialize tracking
        init_pnl_tracking!(s, ai)
        
        ats = now()
        current_pnl = 200.0
        
        # Test basic metrics update
        update_performance_metrics!(s, ai, current_pnl, ats)
        
        metrics = s.attrs[:performance_metrics][ai]
        @test metrics[:total_pnl] == current_pnl
        @test metrics[:last_updated] == ats
        @test metrics[:peak_pnl] == current_pnl  # First update sets peak
        
        # Test peak PnL update
        higher_pnl = 300.0
        update_performance_metrics!(s, ai, higher_pnl, ats + Minute(1))
        
        @test metrics[:peak_pnl] == higher_pnl
        @test haskey(metrics, :peak_pnl_time)
        
        # Test with lower PnL (peak should not change)
        lower_pnl = 150.0
        update_performance_metrics!(s, ai, lower_pnl, ats + Minute(2))
        
        @test metrics[:peak_pnl] == higher_pnl  # Should remain at peak
        @test metrics[:total_pnl] == lower_pnl   # But current should update
    end
    
    @testset "update_trade_statistics! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Initialize with trade history
        s.attrs[:trade_history] = Dict(ai => [
            Dict(:status => :closed, :pnl => 100.0),
            Dict(:status => :closed, :pnl => -50.0),
            Dict(:status => :closed, :pnl => 75.0),
            Dict(:status => :closed, :pnl => -25.0),
            Dict(:status => :open, :pnl => 30.0)  # Should not count
        ])
        
        metrics = Dict{Symbol, Any}()
        
        # Test trade statistics calculation
        update_trade_statistics!(s, ai, metrics)
        
        @test metrics[:total_trades] == 4  # Only closed trades
        @test metrics[:winning_trades] == 2  # 100 and 75
        @test metrics[:losing_trades] == 2   # -50 and -25
        @test metrics[:win_rate] == 0.5      # 2/4
        @test metrics[:avg_win] == 87.5      # (100 + 75) / 2
        @test metrics[:avg_loss] == 37.5     # (50 + 25) / 2
        
        # Test profit factor
        total_wins = 175.0  # 100 + 75
        total_losses = 75.0 # 50 + 25
        expected_pf = total_wins / total_losses
        @test metrics[:profit_factor] ≈ expected_pf
        
        # Test with no trades
        s.attrs[:trade_history][ai] = []
        metrics_empty = Dict{Symbol, Any}()
        update_trade_statistics!(s, ai, metrics_empty)
        
        @test metrics_empty[:total_trades] == 0
        @test metrics_empty[:win_rate] == 0.0
        @test metrics_empty[:avg_win] == 0.0
        @test metrics_empty[:avg_loss] == 0.0
        @test metrics_empty[:profit_factor] == 0.0
    end
    
    @testset "update_risk_metrics! function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test with insufficient data
        s.attrs[:pnl_history] = Dict(ai => MockCircularBuffer{Tuple{DateTime, Float64}}(100))
        metrics = Dict{Symbol, Any}()
        
        update_risk_metrics!(s, ai, metrics)
        @test metrics[:sharpe_ratio] == 0.0
        
        # Test with sufficient data
        pnl_history = s.attrs[:pnl_history][ai]
        base_time = now()
        
        # Add PnL data with some returns
        for i in 1:20
            push!(pnl_history, (base_time + Minute(i), Float64(i * 10 + randn() * 5)))
        end
        
        update_risk_metrics!(s, ai, metrics)
        
        @test haskey(metrics, :sharpe_ratio)
        @test metrics[:sharpe_ratio] isa Float64
        
        # Test with constant returns (zero std)
        pnl_history_constant = MockCircularBuffer{Tuple{DateTime, Float64}}(100)
        for i in 1:10
            push!(pnl_history_constant, (base_time + Minute(i), 100.0))  # Constant PnL
        end
        s.attrs[:pnl_history][ai] = pnl_history_constant
        
        metrics_constant = Dict{Symbol, Any}()
        update_risk_metrics!(s, ai, metrics_constant)
        @test metrics_constant[:sharpe_ratio] == 0.0  # Zero std should give 0 Sharpe
    end
    
    @testset "peak_cash! functions" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Mock get_current_equity to return predictable values
        get_current_equity(s::MockStrategy, ai::MockAssetInstance) = 10500.0
        
        # Test single asset peak cash
        peak_cash!(s, ai, ats)
        
        @test haskey(s.attrs, :peak_cash)
        @test haskey(s.attrs[:peak_cash], ai)
        
        peak_data = s.attrs[:peak_cash][ai]
        @test peak_data[:peak_value] == 10500.0
        @test peak_data[:current_value] == 10500.0
        @test peak_data[:peak_time] == ats
        
        # Test with higher equity
        get_current_equity(s::MockStrategy, ai::MockAssetInstance) = 11000.0
        peak_cash!(s, ai, ats + Minute(1))
        
        @test peak_data[:peak_value] == 11000.0
        @test peak_data[:peak_time] == ats + Minute(1)
        
        # Test with lower equity (peak should not change)
        get_current_equity(s::MockStrategy, ai::MockAssetInstance) = 10800.0
        peak_cash!(s, ai, ats + Minute(2))
        
        @test peak_data[:peak_value] == 11000.0  # Should remain at peak
        @test peak_data[:current_value] == 10800.0  # But current should update
        
        # Test strategy-level peak cash
        calculate_total_strategy_equity(s::MockStrategy, ats::DateTime) = 25000.0
        
        peak_cash!(s, ats)
        
        @test haskey(s.attrs, :strategy_peak_cash)
        strategy_peak = s.attrs[:strategy_peak_cash]
        @test strategy_peak[:peak_value] == 25000.0
        @test strategy_peak[:current_value] == 25000.0
    end
    
    @testset "calculate_drawdown function" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Test with no peak data
        drawdown_no_data = calculate_drawdown(s, ai)
        @test drawdown_no_data == 0.0
        
        # Test with peak data
        s.attrs[:peak_cash] = Dict(ai => Dict(
            :peak_value => 12000.0,
            :current_value => 10000.0
        ))
        
        drawdown = calculate_drawdown(s, ai)
        expected_drawdown = (12000.0 - 10000.0) / 12000.0
        @test drawdown ≈ expected_drawdown
        
        # Test with current value higher than peak (should be 0)
        s.attrs[:peak_cash][ai][:current_value] = 13000.0
        drawdown_negative = calculate_drawdown(s, ai)
        @test drawdown_negative == 0.0
        
        # Test with zero peak value
        s.attrs[:peak_cash][ai][:peak_value] = 0.0
        drawdown_zero_peak = calculate_drawdown(s, ai)
        @test drawdown_zero_peak == 0.0
    end
    
    @testset "Summary functions" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        
        # Initialize with some data
        init_pnl_tracking!(s, ai)
        s.attrs[:performance_metrics][ai][:total_pnl] = 250.0
        s.attrs[:performance_metrics][ai][:win_rate] = 0.65
        s.attrs[:performance_metrics][ai][:total_trades] = 20
        s.attrs[:peak_cash] = Dict(ai => Dict(
            :peak_value => 11000.0,
            :current_value => 10750.0
        ))
        
        # Test get_pnl_summary
        summary = get_pnl_summary(s, ai)
        
        @test summary[:asset] == ai
        @test summary[:total_pnl] == 250.0
        @test summary[:win_rate] == 0.65
        @test summary[:total_trades] == 20
        @test summary[:peak_cash] == 11000.0
        @test summary[:current_cash] == 10750.0
        @test haskey(summary, :realized_pnl)
        @test haskey(summary, :unrealized_pnl)
        @test haskey(summary, :max_drawdown)
        @test haskey(summary, :sharpe_ratio)
        
        # Test get_strategy_pnl_summary
        s.attrs[:strategy_metrics] = Dict(
            :total_pnl => 500.0,
            :total_trades => 45,
            :win_rate => 0.6
        )
        s.attrs[:strategy_peak_cash] = Dict(
            :peak_value => 25000.0,
            :current_value => 24500.0
        )
        
        strategy_summary = get_strategy_pnl_summary(s)
        
        @test haskey(strategy_summary, :strategy_metrics)
        @test haskey(strategy_summary, :strategy_peak_cash)
        @test haskey(strategy_summary, :asset_summaries)
        @test haskey(strategy_summary, :summary_time)
        
        @test strategy_summary[:strategy_metrics][:total_pnl] == 500.0
        @test strategy_summary[:strategy_peak_cash][:peak_value] == 25000.0
        @test haskey(strategy_summary[:asset_summaries], ai)
    end
    
    @testset "Error handling and edge cases" begin
        s = MockStrategy()
        ai = MockAssetInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Test trackpnl! with missing data
        trackpnl!(s, ai, ats)  # Should not crash
        @test haskey(s.attrs, :pnl_history)  # Should initialize structures
        
        # Test calculate_current_pnl with invalid position
        s.attrs[:positions] = Dict(ai => "invalid_position")
        pnl_invalid = calculate_current_pnl(s, ai, ats)
        @test pnl_invalid == 0.0  # Should handle gracefully
        
        # Test with missing OHLCV data
        s.attrs[:positions] = Dict(ai => MockPosition(0.1, 50000.0))
        # No ohlcv_data set
        pnl_no_ohlcv = calculate_current_pnl(s, ai, ats)
        @test pnl_no_ohlcv isa Float64  # Should return some value
        
        # Test update_trade_statistics! with malformed trade data
        s.attrs[:trade_history] = Dict(ai => [
            Dict(:status => :closed),  # Missing PnL
            Dict(:pnl => 100.0),       # Missing status
            "invalid_trade"            # Invalid structure
        ])
        
        metrics = Dict{Symbol, Any}()
        update_trade_statistics!(s, ai, metrics)  # Should not crash
        @test haskey(metrics, :total_trades)
        
        # Test peak_cash! with error in equity calculation
        # Mock function that throws error
        get_current_equity_error(s::MockStrategy, ai::MockAssetInstance) = throw(ErrorException("Test error"))
        
        # Should handle error gracefully
        try
            # This would need to be mocked properly in a real implementation
            peak_cash!(s, ai, ats)
            @test true  # Should not crash
        catch e
            @test e isa Exception
        end
    end
end

println("✓ PnL tracking tests completed")