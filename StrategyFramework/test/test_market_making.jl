using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Statistics

# Mock Planar types and functions for testing
struct MockInstrumentInstance
    symbol::String
end

struct MockOHLCV
    close::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    volume::Vector{Float64}
end

struct MockStrategy
    universe::Dict{MockInstrumentInstance, MockOHLCV}
    config::Dict{Symbol, Any}
end

# Mock position side types
struct Long end
struct Short end

# Include the market making module for testing
include("../src/utilities/math_utils.jl")
include("../src/trading/market_making.jl")

# Mock helper functions
function cash(s::MockStrategy, ii::MockInstrumentInstance)
    return get(s.config, :available_cash, 10000.0)
end

function haspositions(s::MockStrategy, ii::MockInstrumentInstance)
    return haskey(s.config, :positions) && haskey(s.config[:positions], ii)
end

function position(s::MockStrategy, ii::MockInstrumentInstance)
    if haspositions(s, ii)
        return s.config[:positions][ii]
    else
        return 0.0
    end
end

function get_max_position_size(s::MockStrategy, ii::MockInstrumentInstance)
    return get(s.config, :max_position_size, 2500.0)  # 25% of cash
end

function get_min_position_size(s::MockStrategy, ii::MockInstrumentInstance)
    return get(s.config, :min_position_size, 10.0)
end

function get_tick_size(s::MockStrategy, ii::MockInstrumentInstance)
    return get(s.config, :tick_size, 0.01)
end

function get_lot_size(s::MockStrategy, ii::MockInstrumentInstance)
    return get(s.config, :lot_size, 0.001)
end

function get_min_quantity(s::MockStrategy, ii::MockInstrumentInstance)
    return get(s.config, :min_quantity, 0.001)
end

function generate_order_id()
    return "test_order_" * string(rand(1000:9999))
end

function is_market_open(s::MockStrategy, ii::MockInstrumentInstance, ts::DateTime)
    return true
end

@testset "Market Making Tests" begin
    
    @testset "should_market_make" begin
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Create mock OHLCV data
        prices = [50000.0 + i * 10 + randn() * 50 for i in 1:100]
        volumes = [1000.0 + randn() * 100 for _ in 1:100]
        ohlcv = MockOHLCV(
            prices,
            prices .+ rand(100) .* 100,  # highs
            prices .- rand(100) .* 100,  # lows
            volumes
        )
        
        s = MockStrategy(
            Dict(ii => ohlcv),
            Dict{Symbol, Any}(
                :enable_market_making => true,
                :available_cash => 10000.0,
                :max_position_size => 2500.0,
                :min_cash_for_mm => 1000.0
            )
        )
        
        @test should_market_make(s, ii, now()) == true
        
        # Test with market making disabled
        s.config[:enable_market_making] = false
        @test should_market_make(s, ii, now()) == false
        
        # Test with insufficient cash
        s.config[:enable_market_making] = true
        s.config[:available_cash] = 500.0
        @test should_market_make(s, ii, now()) == false
        
        # Test with insufficient data
        short_ohlcv = MockOHLCV([50000.0], [50100.0], [49900.0], [1000.0])
        s_short = MockStrategy(Dict(ii => short_ohlcv), s.config)
        s_short.config[:available_cash] = 10000.0
        @test should_market_make(s_short, ii, now()) == false
    end
    
    @testset "get_make_amounts" begin
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Create mock OHLCV data
        prices = [50000.0 for _ in 1:50]  # Stable price for testing
        ohlcv = MockOHLCV(
            prices,
            prices .+ 100,
            prices .- 100,
            [1000.0 for _ in 1:50]
        )
        
        s = MockStrategy(
            Dict(ii => ohlcv),
            Dict{Symbol, Any}(
                :available_cash => 10000.0,
                :mm_base_order_pct => 0.02,  # 2%
                :max_mm_single_order_pct => 0.05,  # 5%
                :tick_size => 0.01,
                :lot_size => 0.001,
                :min_quantity => 0.001,
                :min_position_size => 10.0
            )
        )
        
        amounts = get_make_amounts(s, ii, 0.1)  # 10% max position
        
        @test amounts.buy_amount > 0
        @test amounts.sell_amount > 0
        @test amounts.buy_quantity > 0
        @test amounts.sell_quantity > 0
        
        # Test with existing long position
        s.config[:positions] = Dict(ii => 0.1)  # Long position
        amounts_with_position = get_make_amounts(s, ii, 0.1)
        
        # Should reduce buy amount and increase sell amount due to inventory adjustment
        @test amounts_with_position.buy_amount <= amounts.buy_amount
        @test amounts_with_position.sell_amount >= amounts.sell_amount
    end
    
    @testset "calculate_optimal_spread" begin
        ii = MockInstrumentInstance("BTC/USDT")
        
        s = MockStrategy(
            Dict{MockInstrumentInstance, MockOHLCV}(),
            Dict{Symbol, Any}(
                :min_mm_spread => 0.0005,
                :max_mm_spread => 0.01
            )
        )
        
        # Test with normal market conditions
        market_conditions = (
            volatility = 0.02,
            volume_ratio = 1.0,
            current_spread_pct = 0.001,
            trend_strength = 0.0,
            price_stability = 0.5
        )
        
        spread = calculate_optimal_spread(s, ii, 0.002, market_conditions)
        @test spread >= s.config[:min_mm_spread]
        @test spread <= s.config[:max_mm_spread]
        @test spread >= 0.002  # Should be at least target spread
        
        # Test with high volatility
        high_vol_conditions = (
            volatility = 0.05,  # High volatility
            volume_ratio = 1.0,
            current_spread_pct = 0.001,
            trend_strength = 0.0,
            price_stability = 0.5
        )
        
        high_vol_spread = calculate_optimal_spread(s, ii, 0.002, high_vol_conditions)
        @test high_vol_spread > spread  # Should be wider with high volatility
        
        # Test with low volume
        low_vol_conditions = (
            volatility = 0.02,
            volume_ratio = 0.3,  # Low volume
            current_spread_pct = 0.001,
            trend_strength = 0.0,
            price_stability = 0.5
        )
        
        low_vol_spread = calculate_optimal_spread(s, ii, 0.002, low_vol_conditions)
        @test low_vol_spread > spread  # Should be wider with low volume
    end
    
    @testset "calculate_inventory_adjustment" begin
        # Test neutral position
        adjustment = calculate_inventory_adjustment(0.0, 1000.0)
        @test adjustment.buy_multiplier ≈ 1.0
        @test adjustment.sell_multiplier ≈ 1.0
        @test adjustment.position_ratio ≈ 0.0
        
        # Test long position
        long_adjustment = calculate_inventory_adjustment(500.0, 1000.0)  # 50% long
        @test long_adjustment.buy_multiplier < 1.0  # Should reduce buy orders
        @test long_adjustment.sell_multiplier > 1.0  # Should increase sell orders
        @test long_adjustment.position_ratio ≈ 0.5
        
        # Test short position
        short_adjustment = calculate_inventory_adjustment(-500.0, 1000.0)  # 50% short
        @test short_adjustment.buy_multiplier > 1.0  # Should increase buy orders
        @test short_adjustment.sell_multiplier < 1.0  # Should reduce sell orders
        @test short_adjustment.position_ratio ≈ -0.5
        
        # Test extreme position
        extreme_adjustment = calculate_inventory_adjustment(1000.0, 1000.0)  # 100% long
        @test extreme_adjustment.buy_multiplier < 1.0
        @test extreme_adjustment.sell_multiplier > 1.0
        @test extreme_adjustment.position_ratio ≈ 1.0
    end
    
    @testset "analyze_market_making_conditions" begin
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Create mock OHLCV data with some volatility
        base_price = 50000.0
        prices = [base_price + i * 10 + randn() * 100 for i in 1:100]
        volumes = [1000.0 + randn() * 200 for _ in 1:100]
        
        ohlcv = MockOHLCV(
            prices,
            prices .+ rand(100) .* 200,
            prices .- rand(100) .* 200,
            volumes
        )
        
        s = MockStrategy(Dict(ii => ohlcv), Dict{Symbol, Any}())
        
        conditions = analyze_market_making_conditions(s, ii)
        
        @test conditions.volatility >= 0
        @test conditions.volume_ratio >= 0
        @test conditions.current_spread_pct >= 0
        @test conditions.trend_strength >= 0
        @test conditions.price_stability >= 0
        @test conditions.price_stability <= 1.0
        
        # Test with insufficient data
        short_ohlcv = MockOHLCV([50000.0], [50100.0], [49900.0], [1000.0])
        s_short = MockStrategy(Dict(ii => short_ohlcv), Dict{Symbol, Any}())
        
        short_conditions = analyze_market_making_conditions(s_short, ii)
        @test short_conditions.volatility == 0.02  # Default value
        @test short_conditions.volume_ratio == 1.0  # Default value
    end
    
    @testset "place_market_making_order" begin
        ii = MockInstrumentInstance("BTC/USDT")
        
        s = MockStrategy(
            Dict{MockInstrumentInstance, MockOHLCV}(),
            Dict{Symbol, Any}(
                :mm_post_only => true
            )
        )
        
        # Test buy order
        buy_result = place_market_making_order(s, ii, Long(), 100.0, 50000.0, "test_buy")
        
        @test haskey(buy_result, :success)
        @test haskey(buy_result, :order_id)
        @test haskey(buy_result, :side)
        @test haskey(buy_result, :amount)
        @test haskey(buy_result, :price)
        @test haskey(buy_result, :reason)
        
        @test buy_result.side isa Long
        @test buy_result.amount == 100.0
        @test buy_result.price == 50000.0
        @test buy_result.reason == "test_buy"
        
        # Test sell order
        sell_result = place_market_making_order(s, ii, Short(), 100.0, 50100.0, "test_sell")
        
        @test sell_result.side isa Short
        @test sell_result.amount == 100.0
        @test sell_result.price == 50100.0
        @test sell_result.reason == "test_sell"
    end
    
    @testset "market_make integration" begin
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Create realistic market data
        prices = [50000.0 + i * 5 + randn() * 25 for i in 1:100]
        volumes = [1000.0 + randn() * 100 for _ in 1:100]
        
        ohlcv = MockOHLCV(
            prices,
            prices .+ rand(100) .* 50,
            prices .- rand(100) .* 50,
            volumes
        )
        
        s = MockStrategy(
            Dict(ii => ohlcv),
            Dict{Symbol, Any}(
                :enable_market_making => true,
                :available_cash => 10000.0,
                :max_position_size => 2500.0,
                :min_cash_for_mm => 1000.0,
                :mm_base_order_pct => 0.02,
                :min_mm_spread => 0.0005,
                :max_mm_spread => 0.01,
                :tick_size => 0.01,
                :lot_size => 0.001,
                :min_quantity => 0.001,
                :min_position_size => 10.0
            )
        )
        
        result = market_make(s, ii, now(), now())
        
        @test haskey(result, :success)
        @test haskey(result, :reason)
        @test haskey(result, :buy_order)
        @test haskey(result, :sell_order)
        @test haskey(result, :spread_used)
        
        if result.success
            @test result.spread_used >= s.config[:min_mm_spread]
            @test result.spread_used <= s.config[:max_mm_spread]
        end
    end
    
    @testset "helper functions" begin
        # Test volatility spread multiplier
        @test calculate_volatility_spread_multiplier(0.01) == 1.0  # Low volatility
        @test calculate_volatility_spread_multiplier(0.04) > 1.0   # High volatility
        
        # Test volume spread multiplier
        @test calculate_volume_spread_multiplier(1.0) == 1.0   # Normal volume
        @test calculate_volume_spread_multiplier(0.5) > 1.0    # Low volume
        @test calculate_volume_spread_multiplier(0.2) > calculate_volume_spread_multiplier(0.5)  # Very low volume
        
        # Test order refresh logic
        @test should_refresh_market_making_orders(MockStrategy(Dict(), Dict()), MockInstrumentInstance("BTC"), [], now()) == true
    end
end

println("Market making tests completed!")