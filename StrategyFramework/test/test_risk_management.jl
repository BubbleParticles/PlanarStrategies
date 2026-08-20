# Tests for risk management system
using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Statistics

# Mock Planar types and functions for testing
struct MockStrategy
    attrs::Dict{Symbol, Any}
    universe::Dict{MockInstrumentInstance, MockOHLCV}
    config::Dict{Symbol, Any}
    
    MockStrategy() = new(Dict{Symbol, Any}(), Dict{MockInstrumentInstance, MockOHLCV}(), Dict{Symbol, Any}())
end

struct MockInstrumentInstance
    symbol::String
end

struct MockOHLCV
    close::Vector{Float64}
    high::Vector{Float64}
    low::Vector{Float64}
    volume::Vector{Float64}
    
    MockOHLCV(close_prices::Vector{Float64}) = new(
        close_prices,
        close_prices .+ rand(length(close_prices)) .* 100,
        close_prices .- rand(length(close_prices)) .* 100,
        rand(length(close_prices)) .* 1000 .+ 500
    )
end

struct MockLong end
struct MockShort end

# Mock functions
haspositions(s::MockStrategy, ii::MockInstrumentInstance) = haskey(s.config, :positions) && haskey(s.config[:positions], ii)
position(s::MockStrategy, ii::MockInstrumentInstance) = get(get(s.config, :positions, Dict()), ii, 0.0)
cash(s::MockStrategy, ii::MockInstrumentInstance) = get(get(s.config, :cash, Dict()), ii, 10000.0)
get_min_position_size(s::MockStrategy, ii::MockInstrumentInstance) = 10.0
get_max_position_size(s::MockStrategy, ii::MockInstrumentInstance) = 5000.0
last(prices::Vector{Float64}) = isempty(prices) ? 50000.0 : prices[end]

# Position side types
struct Long end
struct Short end

# Include the risk management module for testing
include("../src/trading/risk_management.jl")

@testset "Risk Management Tests" begin
    
    @testset "closeposition! function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Set up mock OHLCV data
        s.universe[ii] = MockOHLCV([50000.0, 50100.0, 49900.0, 50200.0])
        
        # Mock helper functions
        normalize_price(price::Float64, tick_size::Float64) = round(price / tick_size) * tick_size
        normalize_quantity(qty::Float64, lot_size::Float64, min_qty::Float64) = max(round(qty / lot_size) * lot_size, min_qty)
        
        # Test closing non-existent position
        result = closeposition!(s, ii)
        @test result == true  # Should return true for no position
        
        # Test closing existing position
        s.config[:positions] = Dict(ii => 0.1)  # Long position
        
        result = closeposition!(s, ii; reason="test_close")
        @test result == true
        
        # Check tracking was updated
        @test haskey(s.config, :last_close_time)
        @test haskey(s.config[:last_close_time], ii)
        @test haskey(s.config, :close_reasons)
        @test s.config[:close_reasons]["test_close"] == 1
        @test s.config[:total_closes] == 1
        
        # Test emergency close
        s.config[:positions][ii] = -0.05  # Short position
        
        result = closeposition!(s, ii; reason="emergency_test", emergency=true)
        @test result == true
        @test s.config[:close_reasons]["emergency_test"] == 1
        @test s.config[:total_closes] == 2
        
        # Test closing very small position
        s.config[:positions][ii] = 0.0001  # Very small position
        
        result = closeposition!(s, ii; reason="small_position")
        @test result == true  # Should return true for position too small to close
    end
    
    @testset "manage_cash_reserves function" begin
        s = MockStrategy()
        ii1 = MockInstrumentInstance("BTC/USDT")
        ii2 = MockInstrumentInstance("ETH/USDT")
        
        # Set up universe and cash
        s.universe[ii1] = MockOHLCV([50000.0])
        s.universe[ii2] = MockOHLCV([3000.0])
        s.config[:cash] = Dict(ii1 => 8000.0, ii2 => 2000.0)  # Total: 10000
        
        # Test default reserve calculation
        reserve = manage_cash_reserves(s)
        @test reserve >= 1000.0  # 10% of 10000
        @test reserve <= 5000.0   # Max 50% of total
        
        # Test with custom reserve percentage
        s.config[:reserve_cash_pct] = 0.2  # 20%
        reserve_custom = manage_cash_reserves(s)
        @test reserve_custom >= 2000.0
        
        # Test with minimum reserve
        s.config[:min_cash_reserve] = 3000.0
        s.config[:reserve_cash_pct] = 0.05  # 5% would be 500, but min is 3000
        reserve_min = manage_cash_reserves(s)
        @test reserve_min >= 3000.0
        
        # Test with high volatility (mock volatility calculation)
        # Add more price data to simulate volatility
        s.universe[ii1] = MockOHLCV([50000.0, 52000.0, 48000.0, 51000.0, 47000.0, 53000.0] .+ randn(6) .* 1000)
        s.universe[ii2] = MockOHLCV([3000.0, 3200.0, 2800.0, 3100.0, 2900.0, 3300.0] .+ randn(6) .* 100)
        
        reserve_volatile = manage_cash_reserves(s)
        @test reserve_volatile > 0
        
        # Test error handling
        s_error = MockStrategy()
        reserve_error = manage_cash_reserves(s_error)
        @test reserve_error == 0.0
    end
    
    @testset "calculate_volatility_reserve_multiplier function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Test with low volatility data
        low_vol_prices = [50000.0 + i * 10 + randn() * 50 for i in 1:30]  # Low volatility
        s.universe[ii] = MockOHLCV(low_vol_prices)
        
        multiplier_low = calculate_volatility_reserve_multiplier(s)
        @test multiplier_low >= 1.0
        @test multiplier_low <= 2.0
        
        # Test with high volatility data
        high_vol_prices = [50000.0 + randn() * 5000 for _ in 1:30]  # High volatility
        s.universe[ii] = MockOHLCV(high_vol_prices)
        
        multiplier_high = calculate_volatility_reserve_multiplier(s)
        @test multiplier_high >= 1.0
        @test multiplier_high <= 2.0
        @test multiplier_high >= multiplier_low  # Should be higher for high volatility
        
        # Test with insufficient data
        s.universe[ii] = MockOHLCV([50000.0, 50100.0])  # Only 2 data points
        
        multiplier_insufficient = calculate_volatility_reserve_multiplier(s)
        @test multiplier_insufficient == 1.0
        
        # Test with no data
        s_empty = MockStrategy()
        multiplier_empty = calculate_volatility_reserve_multiplier(s_empty)
        @test multiplier_empty == 1.0
    end
    
    @testset "calculate_drawdown_reserve_multiplier function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        s.universe[ii] = MockOHLCV([50000.0])
        
        # Test with no drawdown
        s.config[:peak_cash] = 10000.0
        s.config[:cash] = Dict(ii => 10000.0)
        
        multiplier_no_dd = calculate_drawdown_reserve_multiplier(s)
        @test multiplier_no_dd == 1.0
        
        # Test with 10% drawdown
        s.config[:cash] = Dict(ii => 9000.0)
        
        multiplier_10_dd = calculate_drawdown_reserve_multiplier(s)
        @test multiplier_10_dd > 1.0
        @test multiplier_10_dd <= 1.2
        
        # Test with 20% drawdown
        s.config[:cash] = Dict(ii => 8000.0)
        
        multiplier_20_dd = calculate_drawdown_reserve_multiplier(s)
        @test multiplier_20_dd > multiplier_10_dd
        @test multiplier_20_dd <= 1.5
        
        # Test with 30% drawdown
        s.config[:cash] = Dict(ii => 7000.0)
        
        multiplier_30_dd = calculate_drawdown_reserve_multiplier(s)
        @test multiplier_30_dd > multiplier_20_dd
        @test multiplier_30_dd <= 2.0
        
        # Test with no peak cash
        s.config[:peak_cash] = 0.0
        
        multiplier_no_peak = calculate_drawdown_reserve_multiplier(s)
        @test multiplier_no_peak == 1.0
    end
    
    @testset "manage_collateral function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Set up mock data
        s.universe[ii] = MockOHLCV([50000.0])
        s.config[:cash] = Dict(ii => 10000.0)
        s.config[:def_lev] = 2.0
        
        # Test with no position
        collateral_info = manage_collateral(s, ii)
        
        @test collateral_info.position_value == 0.0
        @test collateral_info.required_collateral == 0.0
        @test collateral_info.available_collateral == 10000.0
        @test collateral_info.collateral_utilization == 0.0
        @test collateral_info.margin_level == Inf
        @test collateral_info.status == :healthy
        
        # Test with leveraged position
        s.config[:positions] = Dict(ii => 0.2)  # 0.2 BTC position
        
        collateral_leveraged = manage_collateral(s, ii)
        
        expected_position_value = 0.2 * 50000.0  # 10000
        expected_required_collateral = expected_position_value / 2.0  # 5000 (2x leverage)
        
        @test collateral_leveraged.position_value ≈ expected_position_value
        @test collateral_leveraged.required_collateral ≈ expected_required_collateral
        @test collateral_leveraged.available_collateral == 10000.0
        @test collateral_leveraged.collateral_utilization ≈ 0.5
        @test collateral_leveraged.margin_level ≈ 2.0
        @test collateral_leveraged.status == :healthy
        
        # Test with critical collateral level
        s.config[:cash] = Dict(ii => 6000.0)  # Reduced cash
        
        collateral_critical = manage_collateral(s, ii)
        
        @test collateral_critical.margin_level < 1.5
        @test collateral_critical.status == :critical
        
        # Test with warning level
        s.config[:cash] = Dict(ii => 8000.0)
        
        collateral_warning = manage_collateral(s, ii)
        
        @test collateral_warning.margin_level >= 1.5
        @test collateral_warning.margin_level < 2.0
        @test collateral_warning.status == :warning
    end
    
    @testset "peak_cash! function" begin
        s = MockStrategy()
        ii1 = MockInstrumentInstance("BTC/USDT")
        ii2 = MockInstrumentInstance("ETH/USDT")
        
        # Set up universe and cash
        s.universe[ii1] = MockOHLCV([50000.0])
        s.universe[ii2] = MockOHLCV([3000.0])
        s.config[:cash] = Dict(ii1 => 8000.0, ii2 => 2000.0)
        
        # Test initial peak cash
        peak = peak_cash!(s)
        @test peak == 10000.0
        @test s.config[:peak_cash] == 10000.0
        @test haskey(s.config, :peak_cash_time)
        @test haskey(s.config, :peak_cash_history)
        
        # Test with higher cash (should update peak)
        s.config[:cash] = Dict(ii1 => 9000.0, ii2 => 3000.0)
        
        peak_higher = peak_cash!(s)
        @test peak_higher == 12000.0
        @test s.config[:peak_cash] == 12000.0
        
        # Test with lower cash (should not update peak)
        s.config[:cash] = Dict(ii1 => 7000.0, ii2 => 2000.0)
        
        peak_lower = peak_cash!(s)
        @test peak_lower == 12000.0  # Should remain at previous peak
        
        # Test with positions (unrealized PnL)
        s.config[:positions] = Dict(ii1 => 0.1, ii2 => 1.0)  # Positions
        
        peak_with_positions = peak_cash!(s)
        expected_equity = 9000.0 + (0.1 * 50000.0) + (1.0 * 3000.0)  # Cash + position values
        @test peak_with_positions >= 12000.0  # Should consider unrealized PnL
        
        # Test history management
        for i in 1:1100  # Add more than 1000 entries
            s.config[:cash] = Dict(ii1 => 8000.0 + i, ii2 => 2000.0)
            peak_cash!(s)
        end
        
        @test length(s.config[:peak_cash_history]) <= 1000  # Should be trimmed
    end
    
    @testset "calculate_drawdown function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Set up mock data
        s.universe[ii] = MockOHLCV([50000.0])
        s.config[:cash] = Dict(ii => 10000.0)
        s.config[:peak_cash] = 12000.0
        s.config[:peak_cash_time] = now() - Hour(2)
        
        # Test current drawdown calculation
        drawdown_info = calculate_drawdown(s)
        
        @test drawdown_info.current_drawdown ≈ 2000.0  # 12000 - 10000
        @test drawdown_info.current_drawdown_pct ≈ 2000.0 / 12000.0
        @test drawdown_info.drawdown_duration >= Hour(2)
        @test drawdown_info.recovery_factor ≈ 12000.0 / 10000.0
        
        # Test with no peak cash
        s_no_peak = MockStrategy()
        s_no_peak.universe[ii] = MockOHLCV([50000.0])
        s_no_peak.config[:cash] = Dict(ii => 10000.0)
        
        drawdown_no_peak = calculate_drawdown(s_no_peak)
        
        @test drawdown_no_peak.current_drawdown == 0.0
        @test drawdown_no_peak.current_drawdown_pct == 0.0
        @test drawdown_no_peak.max_drawdown == 0.0
        @test drawdown_no_peak.recovery_factor == 1.0
        
        # Test maximum drawdown tracking
        s.config[:max_drawdown] = 1500.0
        s.config[:max_drawdown_pct] = 0.125
        
        # Current drawdown is higher, should update max
        drawdown_update = calculate_drawdown(s)
        
        @test s.config[:max_drawdown] ≈ 2000.0
        @test s.config[:max_drawdown_pct] ≈ 2000.0 / 12000.0
        @test haskey(s.config, :max_drawdown_time)
        
        # Test with positions
        s.config[:positions] = Dict(ii => 0.1)  # Long position
        
        drawdown_with_positions = calculate_drawdown(s)
        
        # Should include unrealized PnL in calculation
        @test drawdown_with_positions.current_drawdown < 2000.0  # Position adds value
    end
    
    @testset "check_risk_limits function" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Set up mock data
        s.universe[ii] = MockOHLCV([50000.0])
        s.config[:cash] = Dict(ii => 10000.0)
        s.config[:positions] = Dict(ii => 0.05)  # Small position
        
        # Mock closeposition! function for testing
        closeposition!(s::MockStrategy, ii::MockInstrumentInstance; reason::String="", emergency::Bool=false) = true
        
        # Test normal conditions (no violations)
        risk_check = check_risk_limits(s, ii)
        
        @test isempty(risk_check.violations)
        @test isempty(risk_check.actions_taken)
        @test risk_check.risk_level == :normal
        
        # Test position size violation
        s.config[:positions] = Dict(ii => 0.15)  # Large position (0.15 * 50000 = 7500 > 5000 limit)
        
        risk_check_size = check_risk_limits(s, ii)
        
        @test "position_size_exceeded" in risk_check_size.violations
        @test "position_closed_size_limit" in risk_check_size.actions_taken
        @test risk_check_size.risk_level in [:medium, :high]
        
        # Test drawdown violation
        s.config[:positions] = Dict(ii => 0.05)  # Reset position
        s.config[:peak_cash] = 15000.0
        s.config[:max_drawdown_limit] = 0.20  # 20% limit
        # Current cash 10000, peak 15000 = 33% drawdown > 20% limit
        
        risk_check_drawdown = check_risk_limits(s, ii)
        
        @test "max_drawdown_exceeded" in risk_check_drawdown.violations
        @test "emergency_close_drawdown" in risk_check_drawdown.actions_taken
        
        # Test collateral violation
        s.config[:peak_cash] = 12000.0  # Reset peak
        s.config[:def_lev] = 5.0  # High leverage
        s.config[:positions] = Dict(ii => 0.2)  # Large leveraged position
        s.config[:cash] = Dict(ii => 1500.0)  # Low cash for collateral
        
        risk_check_collateral = check_risk_limits(s, ii)
        
        @test "critical_collateral_level" in risk_check_collateral.violations
        @test "emergency_close_collateral" in risk_check_collateral.actions_taken
        
        # Test concentration violation
        s.config[:def_lev] = 1.0  # Reset leverage
        s.config[:cash] = Dict(ii => 10000.0)  # Reset cash
        s.config[:positions] = Dict(ii => 0.08)  # Position value: 0.08 * 50000 = 4000
        s.config[:max_concentration] = 0.30  # 30% limit
        # Concentration: 4000 / 10000 = 40% > 30% limit
        
        risk_check_concentration = check_risk_limits(s, ii)
        
        @test "concentration_limit_exceeded" in risk_check_concentration.violations
        @test "position_reduced_concentration" in risk_check_concentration.actions_taken
        
        # Test multiple violations
        s.config[:positions] = Dict(ii => 0.15)  # Large position
        s.config[:peak_cash] = 20000.0
        s.config[:max_drawdown_limit] = 0.30  # 30% limit
        # Multiple violations should result in high risk level
        
        risk_check_multiple = check_risk_limits(s, ii)
        
        @test length(risk_check_multiple.violations) >= 2
        @test risk_check_multiple.risk_level == :high
    end
    
    @testset "Helper functions" begin
        s = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Test get_tick_size
        tick_size = get_tick_size(s, ii)
        @test tick_size == 0.01  # Default value
        
        s.config[:tick_size] = 0.1
        tick_size_custom = get_tick_size(s, ii)
        @test tick_size_custom == 0.1
        
        # Test get_lot_size
        lot_size = get_lot_size(s, ii)
        @test lot_size == 0.001  # Default value
        
        s.config[:lot_size] = 0.01
        lot_size_custom = get_lot_size(s, ii)
        @test lot_size_custom == 0.01
        
        # Test get_min_quantity
        min_qty = get_min_quantity(s, ii)
        @test min_qty == 0.001  # Default value
        
        s.config[:min_quantity] = 0.1
        min_qty_custom = get_min_quantity(s, ii)
        @test min_qty_custom == 0.1
        
        # Test generate_order_id
        order_id1 = generate_order_id()
        order_id2 = generate_order_id()
        
        @test order_id1 isa String
        @test order_id2 isa String
        @test order_id1 != order_id2  # Should be unique
        @test contains(order_id1, "_")  # Should contain separator
        
        # Test normalize functions
        normalized_price = normalize_price(50000.123, 0.01)
        @test normalized_price == 50000.12
        
        normalized_qty = normalize_quantity(0.1234, 0.001, 0.001)
        @test normalized_qty == 0.123
        
        # Test with minimum quantity constraint
        normalized_qty_min = normalize_quantity(0.0005, 0.001, 0.001)
        @test normalized_qty_min == 0.001  # Should use minimum
    end
    
    @testset "Error handling and edge cases" begin
        # Test with empty strategy
        s_empty = MockStrategy()
        ii = MockInstrumentInstance("BTC/USDT")
        
        # Should handle missing data gracefully
        reserve = manage_cash_reserves(s_empty)
        @test reserve == 0.0
        
        collateral_info = manage_collateral(s_empty, ii)
        @test collateral_info.status == :error
        
        drawdown_info = calculate_drawdown(s_empty)
        @test drawdown_info.current_drawdown == 0.0
        
        # Test with corrupted data
        s_corrupt = MockStrategy()
        s_corrupt.universe[ii] = MockOHLCV(Float64[])  # Empty price data
        s_corrupt.config[:cash] = Dict(ii => -1000.0)  # Negative cash
        
        peak = peak_cash!(s_corrupt)
        @test peak >= 0.0  # Should handle gracefully
        
        # Test risk limits with no position
        risk_check_no_pos = check_risk_limits(s_empty, ii)
        @test risk_check_no_pos.risk_level in [:normal, :error]
        
        # Test closeposition! with errors
        s_error = MockStrategy()
        s_error.universe[ii] = MockOHLCV([50000.0])
        s_error.config[:positions] = Dict(ii => 0.1)
        
        # Mock functions that might fail
        normalize_price_error(price::Float64, tick_size::Float64) = throw(ErrorException("Price normalization failed"))
        
        # Should handle errors gracefully
        result = closeposition!(s_error, ii; reason="error_test")
        @test result isa Bool  # Should return boolean even on error
    end
end

println("✓ Risk management tests completed")