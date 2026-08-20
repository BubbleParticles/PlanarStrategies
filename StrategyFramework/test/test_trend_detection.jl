# Tests for trend detection system
using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Statistics

# Mock Planar types and functions for testing
struct MockStrategy
    attrs::Dict{Symbol, Any}
    
    MockStrategy() = new(Dict{Symbol, Any}())
end

struct MockInstrumentInstance
    symbol::String
    exchange::Symbol
    
    MockInstrumentInstance(symbol::String, exchange::Symbol = :phemex) = new(symbol, exchange)
end

struct MockMovingExtrema
    data::Vector{Float64}
    capacity::Int
    
    MockMovingExtrema(capacity::Int) = new(Float64[], capacity)
end

struct MockWMA
    data::Vector{Float64}
    weights::Vector{Float64}
    period::Int
    
    MockWMA(period::Int) = new(Float64[], Float64[], period)
end

struct MockCircularBuffer{T}
    data::Vector{T}
    capacity::Int
    
    MockCircularBuffer{T}(capacity::Int) where T = new{T}(T[], capacity)
end

# Mock functions for Planar types
Base.push!(me::MockMovingExtrema, value::Float64) = begin
    push!(me.data, value)
    if length(me.data) > me.capacity
        popfirst!(me.data)
    end
    me
end

Base.push!(wma::MockWMA, value::Float64) = begin
    push!(wma.data, value)
    if length(wma.data) > wma.period
        popfirst!(wma.data)
    end
    wma
end

Base.push!(cb::MockCircularBuffer, item) = begin
    push!(cb.data, item)
    if length(cb.data) > cb.capacity
        popfirst!(cb.data)
    end
    cb
end

Base.minimum(me::MockMovingExtrema) = isempty(me.data) ? 0.0 : minimum(me.data)
Base.maximum(me::MockMovingExtrema) = isempty(me.data) ? 0.0 : maximum(me.data)
value(wma::MockWMA) = isempty(wma.data) ? 0.0 : mean(wma.data)  # Simplified WMA
Base.isempty(cb::MockCircularBuffer) = isempty(cb.data)
Base.length(cb::MockCircularBuffer) = length(cb.data)
Base.iterate(cb::MockCircularBuffer, state...) = iterate(cb.data, state...)

# Mock constants and functions
InstrumentInstance(asset_str::String, exchange::Symbol) = MockInstrumentInstance(asset_str, exchange)

# Include the trend detection module for testing
include("../src/data/trend_detection.jl")

# Override Planar types with our mocks
const MovingExtrema = MockMovingExtrema
const WMA = MockWMA
const CircularBuffer = MockCircularBuffer

@testset "Trend Detection Tests" begin
    
    @testset "trackhl! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Mock OHLCV data
        s.attrs[:ohlcv_data] = Dict(ii => "mock_ohlcv")
        
        # Test high-low tracking
        trackhl!(s, ii, ats)
        
        # Check that tracking structures were initialized
        @test haskey(s.attrs, :extremas)
        @test haskey(s.attrs, :hl_trackers)
        
        # Check asset-specific data
        @test haskey(s.attrs[:extremas], ii)
        @test haskey(s.attrs[:hl_trackers], ii)
        
        # Check HL tracker structure
        hl_tracker = s.attrs[:hl_trackers][ii]
        @test haskey(hl_tracker, :last_update)
        @test haskey(hl_tracker, :wma)
        @test haskey(hl_tracker, :trend_direction)
        @test haskey(hl_tracker, :trend_strength)
        @test haskey(hl_tracker, :support_level)
        @test haskey(hl_tracker, :resistance_level)
        @test haskey(hl_tracker, :breakout_signals)
        
        @test hl_tracker[:trend_direction] in [:up, :down, :neutral]
        @test hl_tracker[:trend_strength] isa Float64
        @test hl_tracker[:support_level] isa Float64
        @test hl_tracker[:resistance_level] isa Float64
    end
    
    @testset "trackqt! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Mock OHLCV data
        s.attrs[:ohlcv_data] = Dict(ii => "mock_ohlcv")
        
        # Test quote trend tracking
        trackqt!(s, ii, ats)
        
        # Check that tracking structures were initialized
        @test haskey(s.attrs, :qt_trackers)
        @test haskey(s.attrs[:qt_trackers], ii)
        
        # Check QT tracker structure
        qt_tracker = s.attrs[:qt_trackers][ii]
        @test haskey(qt_tracker, :last_update)
        @test haskey(qt_tracker, :price_history)
        @test haskey(qt_tracker, :volume_history)
        @test haskey(qt_tracker, :roc_short)
        @test haskey(qt_tracker, :roc_long)
        @test haskey(qt_tracker, :momentum)
        @test haskey(qt_tracker, :trend_quality)
        @test haskey(qt_tracker, :volatility)
        @test haskey(qt_tracker, :volume_trend)
        @test haskey(qt_tracker, :price_momentum)
        
        @test qt_tracker[:momentum] isa Float64
        @test qt_tracker[:trend_quality] isa Float64
        @test qt_tracker[:volatility] isa Float64
        @test qt_tracker[:volume_trend] in [:increasing, :decreasing, :neutral]
        @test qt_tracker[:price_momentum] in [:bullish, :bearish, :neutral]
    end
    
    @testset "track_trends! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Mock OHLCV data
        s.attrs[:ohlcv_data] = Dict(ii => "mock_ohlcv")
        
        # Test comprehensive trend tracking
        track_trends!(s, ii, ats)
        
        # Check that all tracking components were initialized
        @test haskey(s.attrs, :extremas)
        @test haskey(s.attrs, :hl_trackers)
        @test haskey(s.attrs, :qt_trackers)
        @test haskey(s.attrs, :composite_trends)
        @test haskey(s.attrs, :trend_validation)
        
        # Check composite trend structure
        composite = s.attrs[:composite_trends][ii]
        @test haskey(composite, :overall_trend)
        @test haskey(composite, :trend_strength)
        @test haskey(composite, :trend_confidence)
        @test haskey(composite, :signal_quality)
        @test haskey(composite, :last_update)
        
        @test composite[:overall_trend] in [:bullish, :bearish, :neutral]
        @test composite[:trend_strength] isa Float64
        @test composite[:trend_confidence] isa Float64
        @test composite[:signal_quality] isa Float64
        
        # Check validation structure
        validation = s.attrs[:trend_validation][ii]
        @test haskey(validation, :validation_history)
        @test haskey(validation, :signal_reliability)
        @test haskey(validation, :last_validation)
        
        @test validation[:signal_reliability] isa Float64
        @test 0.0 <= validation[:signal_reliability] <= 1.0
    end
    
    @testset "init_hl_tracking! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        
        # Test initialization
        init_hl_tracking!(s, ii)
        
        # Check structures were created
        @test haskey(s.attrs, :extremas)
        @test haskey(s.attrs, :hl_trackers)
        @test haskey(s.attrs[:extremas], ii)
        @test haskey(s.attrs[:hl_trackers], ii)
        
        # Check extrema
        extrema = s.attrs[:extremas][ii]
        @test extrema isa MockMovingExtrema
        @test extrema.capacity == 100
        
        # Check HL tracker
        hl_tracker = s.attrs[:hl_trackers][ii]
        @test hl_tracker[:wma] isa MockWMA
        @test hl_tracker[:trend_direction] == :neutral
        @test hl_tracker[:trend_strength] == 0.0
        @test hl_tracker[:breakout_signals] isa MockCircularBuffer
        
        # Test re-initialization doesn't overwrite
        hl_tracker[:trend_strength] = 0.5
        init_hl_tracking!(s, ii)
        @test s.attrs[:hl_trackers][ii][:trend_strength] == 0.5  # Should not reset
    end
    
    @testset "init_qt_tracking! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        
        # Test initialization
        init_qt_tracking!(s, ii)
        
        # Check structures were created
        @test haskey(s.attrs, :qt_trackers)
        @test haskey(s.attrs[:qt_trackers], ii)
        
        qt_tracker = s.attrs[:qt_trackers][ii]
        @test qt_tracker[:price_history] isa MockCircularBuffer
        @test qt_tracker[:volume_history] isa MockCircularBuffer
        @test qt_tracker[:roc_short] isa MockCircularBuffer
        @test qt_tracker[:roc_long] isa MockCircularBuffer
        @test qt_tracker[:momentum] == 0.0
        @test qt_tracker[:trend_quality] == 0.0
        @test qt_tracker[:volatility] == 0.0
        @test qt_tracker[:volume_trend] == :neutral
        @test qt_tracker[:price_momentum] == :neutral
    end
    
    @testset "get_current_ohlcv function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Test with no OHLCV data
        result_no_data = get_current_ohlcv(s, ii, ats)
        @test result_no_data === nothing
        
        # Test with OHLCV data
        s.attrs[:ohlcv_data] = Dict(ii => "mock_ohlcv")
        
        result_with_data = get_current_ohlcv(s, ii, ats)
        @test result_with_data isa Dict
        @test haskey(result_with_data, :open)
        @test haskey(result_with_data, :high)
        @test haskey(result_with_data, :low)
        @test haskey(result_with_data, :close)
        @test haskey(result_with_data, :volume)
        @test haskey(result_with_data, :timestamp)
        
        @test result_with_data[:open] isa Float64
        @test result_with_data[:high] >= result_with_data[:low]
        @test result_with_data[:volume] > 0
    end
    
    @testset "update_moving_extrema! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize tracking
        init_hl_tracking!(s, ii)
        
        # Test extrema update
        current_data = Dict{Symbol, Float64}(
            :high => 51000.0,
            :low => 49000.0,
            :close => 50500.0
        )
        
        update_moving_extrema!(s, ii, current_data, ats)
        
        extrema = s.attrs[:extremas][ii]
        hl_tracker = s.attrs[:hl_trackers][ii]
        
        # Check that extrema were updated
        @test length(extrema.data) == 2  # High and low added
        @test 51000.0 in extrema.data
        @test 49000.0 in extrema.data
        
        # Check support and resistance levels
        @test hl_tracker[:support_level] == minimum(extrema)
        @test hl_tracker[:resistance_level] == maximum(extrema)
        @test hl_tracker[:support_level] <= hl_tracker[:resistance_level]
    end
    
    @testset "update_hl_trend! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize tracking
        init_hl_tracking!(s, ii)
        
        current_data = Dict{Symbol, Float64}(
            :open => 50000.0,
            :high => 51000.0,
            :low => 49000.0,
            :close => 50500.0
        )
        
        # Test trend update
        update_hl_trend!(s, ii, current_data, ats)
        
        hl_tracker = s.attrs[:hl_trackers][ii]
        
        # Check that WMA was updated
        wma = hl_tracker[:wma]
        @test length(wma.data) == 1
        @test wma.data[1] == 50500.0
        
        # Check trend direction calculation
        @test hl_tracker[:trend_direction] in [:up, :down, :neutral]
        @test hl_tracker[:trend_strength] isa Float64
        @test hl_tracker[:trend_strength] >= 0.0
        @test hl_tracker[:last_update] == ats
        @test haskey(hl_tracker, :previous_wma)
        @test haskey(hl_tracker, :avg_range)
        
        # Test multiple updates for trend direction
        for i in 1:5
            higher_data = Dict{Symbol, Float64}(
                :open => 50000.0 + i * 100,
                :high => 51000.0 + i * 100,
                :low => 49000.0 + i * 100,
                :close => 50500.0 + i * 100
            )
            update_hl_trend!(s, ii, higher_data, ats + Minute(i))
        end
        
        # Should detect upward trend
        @test hl_tracker[:trend_direction] == :up
    end
    
    @testset "check_breakout_signals! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize tracking with some support/resistance levels
        init_hl_tracking!(s, ii)
        hl_tracker = s.attrs[:hl_trackers][ii]
        hl_tracker[:support_level] = 49000.0
        hl_tracker[:resistance_level] = 51000.0
        
        # Test resistance breakout
        breakout_data = Dict{Symbol, Float64}(
            :high => 51200.0,  # Above resistance
            :low => 50000.0,
            :close => 51100.0
        )
        
        check_breakout_signals!(s, ii, breakout_data, ats)
        
        breakout_signals = hl_tracker[:breakout_signals]
        @test length(breakout_signals) == 1
        @test breakout_signals.data[1][2] == :resistance_break
        @test breakout_signals.data[1][3] == 51200.0
        
        # Test support breakdown
        breakdown_data = Dict{Symbol, Float64}(
            :high => 50000.0,
            :low => 48800.0,  # Below support
            :close => 48900.0
        )
        
        check_breakout_signals!(s, ii, breakdown_data, ats + Minute(1))
        
        @test length(breakout_signals) == 2
        @test breakout_signals.data[2][2] == :support_break
        @test breakout_signals.data[2][3] == 48800.0
        
        # Test no breakout
        normal_data = Dict{Symbol, Float64}(
            :high => 50800.0,  # Within range
            :low => 49200.0,   # Within range
            :close => 50400.0
        )
        
        check_breakout_signals!(s, ii, normal_data, ats + Minute(2))
        
        @test length(breakout_signals) == 2  # Should remain 2
    end
    
    @testset "update_trend_quality! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize tracking
        init_qt_tracking!(s, ii)
        
        # Add some price history
        qt_tracker = s.attrs[:qt_trackers][ii]
        base_time = ats - Minute(15)
        
        # Add upward trending prices
        for i in 1:15
            price = 50000.0 + i * 50  # Consistent upward trend
            volume = 1000.0 + i * 10
            current_data = Dict{Symbol, Float64}(
                :close => price,
                :volume => volume
            )
            
            update_trend_quality!(s, ii, current_data, base_time + Minute(i))
        end
        
        # Check trend quality calculation
        @test qt_tracker[:trend_quality] > 0.5  # Should be high for consistent trend
        @test qt_tracker[:price_momentum] == :bullish
        @test qt_tracker[:last_update] == base_time + Minute(15)
        
        # Check price and volume history
        @test length(qt_tracker[:price_history]) == 15
        @test length(qt_tracker[:volume_history]) == 15
        
        # Test with mixed price movements
        s_mixed = MockStrategy()
        init_qt_tracking!(s_mixed, ii)
        qt_tracker_mixed = s_mixed.attrs[:qt_trackers][ii]
        
        # Add alternating price movements
        for i in 1:15
            price = 50000.0 + (i % 2 == 0 ? 50 : -50)  # Alternating up/down
            current_data = Dict{Symbol, Float64}(
                :close => price,
                :volume => 1000.0
            )
            
            update_trend_quality!(s_mixed, ii, current_data, base_time + Minute(i))
        end
        
        @test qt_tracker_mixed[:trend_quality] <= 0.6  # Should be lower for mixed trend
        @test qt_tracker_mixed[:price_momentum] in [:bullish, :bearish, :neutral]
    end
    
    @testset "update_momentum_indicators! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize tracking
        init_qt_tracking!(s, ii)
        qt_tracker = s.attrs[:qt_trackers][ii]
        
        # Add sufficient price history for ROC calculation
        base_time = ats - Minute(25)
        base_price = 50000.0
        
        for i in 1:25
            price = base_price + i * 20  # Steady upward trend
            push!(qt_tracker[:price_history], (base_time + Minute(i), price))
        end
        
        current_data = Dict{Symbol, Float64}(
            :close => base_price + 25 * 20
        )
        
        # Test momentum calculation
        update_momentum_indicators!(s, ii, current_data, ats)
        
        # Check ROC calculations
        @test length(qt_tracker[:roc_short]) >= 1
        @test length(qt_tracker[:roc_long]) >= 1
        
        # Check momentum calculation
        @test qt_tracker[:momentum] isa Float64
        
        # For upward trend, short-term ROC should be positive
        @test qt_tracker[:roc_short].data[end] > 0
        @test qt_tracker[:roc_long].data[end] > 0
        
        # Test with insufficient data
        s_short = MockStrategy()
        init_qt_tracking!(s_short, ii)
        
        # Add only a few data points
        for i in 1:5
            push!(s_short.attrs[:qt_trackers][ii][:price_history], (base_time + Minute(i), base_price + i * 10))
        end
        
        update_momentum_indicators!(s_short, ii, current_data, ats)
        
        # Should handle insufficient data gracefully
        @test isempty(s_short.attrs[:qt_trackers][ii][:roc_short])
        @test isempty(s_short.attrs[:qt_trackers][ii][:roc_long])
    end
    
    @testset "update_volatility_tracking! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize tracking
        init_qt_tracking!(s, ii)
        qt_tracker = s.attrs[:qt_trackers][ii]
        
        # Add price and volume history
        base_time = ats - Minute(25)
        base_price = 50000.0
        
        for i in 1:25
            price = base_price + randn() * 500  # Random price movements for volatility
            volume = 1000.0 + randn() * 200
            push!(qt_tracker[:price_history], (base_time + Minute(i), price))
            push!(qt_tracker[:volume_history], (base_time + Minute(i), volume))
        end
        
        current_data = Dict{Symbol, Float64}(
            :volume => 1200.0
        )
        
        # Test volatility calculation
        update_volatility_tracking!(s, ii, current_data, ats)
        
        # Check volatility calculation
        @test qt_tracker[:volatility] isa Float64
        @test qt_tracker[:volatility] >= 0.0
        
        # Check volume trend analysis
        @test qt_tracker[:volume_trend] in [:increasing, :decreasing, :neutral]
        
        # Test with high volume
        high_volume_data = Dict{Symbol, Float64}(:volume => 2000.0)  # Much higher than average
        update_volatility_tracking!(s, ii, high_volume_data, ats + Minute(1))
        @test qt_tracker[:volume_trend] == :increasing
        
        # Test with low volume
        low_volume_data = Dict{Symbol, Float64}(:volume => 500.0)  # Much lower than average
        update_volatility_tracking!(s, ii, low_volume_data, ats + Minute(2))
        @test qt_tracker[:volume_trend] == :decreasing
    end
    
    @testset "update_composite_trend! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize with some trend data
        init_hl_tracking!(s, ii)
        init_qt_tracking!(s, ii)
        
        # Set up bullish conditions
        s.attrs[:hl_trackers][ii][:trend_direction] = :up
        s.attrs[:hl_trackers][ii][:trend_strength] = 0.8
        s.attrs[:qt_trackers][ii][:price_momentum] = :bullish
        s.attrs[:qt_trackers][ii][:momentum] = 0.05
        s.attrs[:qt_trackers][ii][:trend_quality] = 0.7
        s.attrs[:qt_trackers][ii][:volatility] = 0.02
        s.attrs[:qt_trackers][ii][:volume_trend] = :increasing
        
        # Test composite trend calculation
        update_composite_trend!(s, ii, ats)
        
        @test haskey(s.attrs, :composite_trends)
        @test haskey(s.attrs[:composite_trends], ii)
        
        composite = s.attrs[:composite_trends][ii]
        @test composite[:overall_trend] == :bullish
        @test composite[:trend_strength] > 0.0
        @test composite[:trend_confidence] > 0.0
        @test composite[:signal_quality] > 0.0
        @test composite[:last_update] == ats
        
        # Test bearish conditions
        s.attrs[:hl_trackers][ii][:trend_direction] = :down
        s.attrs[:qt_trackers][ii][:price_momentum] = :bearish
        
        update_composite_trend!(s, ii, ats + Minute(1))
        
        @test composite[:overall_trend] == :bearish
        
        # Test neutral conditions
        s.attrs[:hl_trackers][ii][:trend_direction] = :neutral
        s.attrs[:qt_trackers][ii][:price_momentum] = :neutral
        
        update_composite_trend!(s, ii, ats + Minute(2))
        
        @test composite[:overall_trend] == :neutral
    end
    
    @testset "validate_trend_signals! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize with consistent trend data
        init_hl_tracking!(s, ii)
        init_qt_tracking!(s, ii)
        update_composite_trend!(s, ii, ats)
        
        # Set up consistent bullish signals
        s.attrs[:composite_trends][ii][:overall_trend] = :bullish
        s.attrs[:composite_trends][ii][:trend_strength] = 0.8
        s.attrs[:hl_trackers][ii][:trend_direction] = :up
        s.attrs[:hl_trackers][ii][:last_update] = ats
        s.attrs[:qt_trackers][ii][:price_momentum] = :bullish
        s.attrs[:qt_trackers][ii][:last_update] = ats
        
        # Test validation
        validate_trend_signals!(s, ii, ats)
        
        @test haskey(s.attrs, :trend_validation)
        @test haskey(s.attrs[:trend_validation], ii)
        
        validation = s.attrs[:trend_validation][ii]
        @test haskey(validation, :validation_history)
        @test haskey(validation, :signal_reliability)
        @test haskey(validation, :last_validation)
        
        @test length(validation[:validation_history]) >= 1
        @test validation[:signal_reliability] isa Float64
        @test 0.0 <= validation[:signal_reliability] <= 1.0
        
        # Check that consistent signals pass validation
        last_validation = validation[:validation_history].data[end]
        @test last_validation[2] == true  # Should be valid
        @test last_validation[3] == "OK"  # No errors
        
        # Test inconsistent signals
        s.attrs[:hl_trackers][ii][:trend_direction] = :down  # Inconsistent with bullish overall
        
        validate_trend_signals!(s, ii, ats + Minute(1))
        
        @test length(validation[:validation_history]) >= 2
        inconsistent_validation = validation[:validation_history].data[end]
        @test inconsistent_validation[2] == false  # Should be invalid
        @test contains(inconsistent_validation[3], "Inconsistent")
        
        # Test stale data
        s.attrs[:hl_trackers][ii][:last_update] = ats - Hour(2)  # Stale data
        
        validate_trend_signals!(s, ii, ats + Minute(2))
        
        stale_validation = validation[:validation_history].data[end]
        @test stale_validation[2] == false  # Should be invalid
        @test contains(stale_validation[3], "Stale")
    end
    
    @testset "Summary and utility functions" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Initialize with comprehensive trend data
        track_trends!(s, ii, ats)
        
        # Set up some trend data
        s.attrs[:composite_trends][ii][:overall_trend] = :bullish
        s.attrs[:composite_trends][ii][:trend_strength] = 0.75
        s.attrs[:composite_trends][ii][:trend_confidence] = 0.8
        s.attrs[:hl_trackers][ii][:support_level] = 49000.0
        s.attrs[:hl_trackers][ii][:resistance_level] = 51000.0
        s.attrs[:qt_trackers][ii][:momentum] = 0.03
        s.attrs[:qt_trackers][ii][:volatility] = 0.025
        
        # Test get_trend_summary
        summary = get_trend_summary(s, ii)
        
        @test summary[:asset] == ii
        @test summary[:overall_trend] == :bullish
        @test summary[:trend_strength] == 0.75
        @test summary[:trend_confidence] == 0.8
        @test summary[:support_level] == 49000.0
        @test summary[:resistance_level] == 51000.0
        @test summary[:momentum] == 0.03
        @test summary[:volatility] == 0.025
        @test haskey(summary, :signal_quality)
        @test haskey(summary, :hl_direction)
        @test haskey(summary, :price_momentum)
        @test haskey(summary, :volume_trend)
        @test haskey(summary, :signal_reliability)
        @test haskey(summary, :last_update)
        
        # Test get_breakout_signals
        # Add some breakout signals
        breakout_signals = s.attrs[:hl_trackers][ii][:breakout_signals]
        push!(breakout_signals, (ats - Minute(5), :resistance_break, 51200.0))
        push!(breakout_signals, (ats - Minute(3), :support_break, 48800.0))
        push!(breakout_signals, (ats - Minute(1), :resistance_break, 51500.0))
        
        signals = get_breakout_signals(s, ii; limit=2)
        
        @test length(signals) == 2  # Should respect limit
        @test signals[1][:type] == :resistance_break
        @test signals[1][:price] == 51500.0  # Most recent first
        @test signals[1][:asset] == ii
        @test signals[2][:type] == :support_break
        @test signals[2][:price] == 48800.0
        
        # Test with no breakout signals
        s_no_signals = MockStrategy()
        init_hl_tracking!(s_no_signals, ii)
        
        no_signals = get_breakout_signals(s_no_signals, ii)
        @test isempty(no_signals)
    end
    
    @testset "Error handling and edge cases" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Test tracking with no OHLCV data
        trackhl!(s, ii, ats)  # Should not crash
        trackqt!(s, ii, ats)  # Should not crash
        track_trends!(s, ii, ats)  # Should not crash
        
        # Should initialize structures even without data
        @test haskey(s.attrs, :extremas)
        @test haskey(s.attrs, :hl_trackers)
        @test haskey(s.attrs, :qt_trackers)
        
        # Test update functions with missing data
        s_empty = MockStrategy()
        
        # Should handle missing structures gracefully
        update_composite_trend!(s_empty, ii, ats)
        validate_trend_signals!(s_empty, ii, ats)
        
        @test haskey(s_empty.attrs, :composite_trends)
        @test haskey(s_empty.attrs, :trend_validation)
        
        # Test get_trend_summary with missing data
        summary_empty = get_trend_summary(s_empty, ii)
        
        @test summary_empty[:asset] == ii
        @test summary_empty[:overall_trend] == :neutral  # Default value
        @test summary_empty[:trend_strength] == 0.0      # Default value
        @test summary_empty[:support_level] == 0.0       # Default value
        
        # Test with corrupted data structures
        s_corrupt = MockStrategy()
        s_corrupt.attrs[:hl_trackers] = "invalid_structure"
        s_corrupt.attrs[:qt_trackers] = Dict(ii => "invalid_tracker")
        
        # Should handle gracefully
        update_composite_trend!(s_corrupt, ii, ats)
        validate_trend_signals!(s_corrupt, ii, ats)
        
        summary_corrupt = get_trend_summary(s_corrupt, ii)
        @test summary_corrupt[:asset] == ii  # Should still return basic info
    end
    
    @testset "Integration with update_asset_tracking!" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT", :phemex)
        ats = now()
        
        # Mock the PnL tracking function
        trackpnl!(s::MockStrategy, ii::MockInstrumentInstance, ats::DateTime) = begin
            if !haskey(s.attrs, :pnl_tracked)
                s.attrs[:pnl_tracked] = Dict()
            end
            s.attrs[:pnl_tracked][ii] = ats
        end
        
        # Test comprehensive asset tracking
        update_asset_tracking!(s, ii, ats)
        
        # Should have called all tracking functions
        @test haskey(s.attrs, :extremas)          # From trend tracking
        @test haskey(s.attrs, :composite_trends)  # From trend tracking
        @test haskey(s.attrs, :pnl_tracked)       # From PnL tracking
        @test haskey(s.attrs, :position_tracking) # From position tracking
        @test haskey(s.attrs, :signal_tracking)   # From signal tracking
        
        @test s.attrs[:pnl_tracked][ii] == ats
        @test s.attrs[:position_tracking][ii][:last_update] == ats
        @test s.attrs[:signal_tracking][ii][:last_update] == ats
    end
end

println("✓ Trend detection tests completed")