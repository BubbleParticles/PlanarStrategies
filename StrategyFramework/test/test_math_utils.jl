# Unit tests for math utilities
using Test
using StrategyFramework
using Statistics
using Dates

@testset "Math Utils Tests" begin
    
    @testset "getincr function" begin
        # Test with tick_size
        exchange_info = Dict(:tick_size => 0.01)
        @test getincr(100.0, exchange_info) == 0.01
        
        # Test with price_precision
        exchange_info = Dict(:price_precision => 2)
        @test getincr(100.0, exchange_info) == 0.01
        
        # Test fallback behavior
        exchange_info = Dict()
        result = getincr(100.0, exchange_info)
        @test result >= 1e-8
        @test result <= 100.0 * 0.0001
        
        # Test edge cases
        @test getincr(0.0, Dict()) >= 1e-8
        @test getincr(1e-6, Dict()) >= 1e-8
    end
    
    @testset "baseincr function" begin
        # Test with lot_size
        exchange_info = Dict(:lot_size => 0.001)
        @test baseincr(1.0, exchange_info) == 0.001
        
        # Test with amount_precision
        exchange_info = Dict(:amount_precision => 3)
        @test baseincr(1.0, exchange_info) == 0.001
        
        # Test fallback behavior
        exchange_info = Dict()
        result = baseincr(1.0, exchange_info)
        @test result >= 1e-8
        @test result <= 1.0 * 0.0001
        
        # Test edge cases
        @test baseincr(0.0, Dict()) >= 1e-8
        @test baseincr(1e-6, Dict()) >= 1e-8
    end
    
    @testset "calculate_spread function" begin
        # Normal case
        result = calculate_spread(99.0, 101.0)
        @test result.absolute == 2.0
        @test result.relative == 2.0  # 2/100 * 100 = 2%
        @test result.mid_price == 100.0
        
        # Zero spread
        result = calculate_spread(100.0, 100.0)
        @test result.absolute == 0.0
        @test result.relative == 0.0
        @test result.mid_price == 100.0
        
        # Small spread
        result = calculate_spread(99.99, 100.01)
        @test result.absolute ≈ 0.02
        @test result.relative ≈ 0.02  # 0.02/100 * 100 = 0.02%
        @test result.mid_price == 100.0
        
        # Edge case: very small prices
        result = calculate_spread(0.001, 0.002)
        @test result.absolute == 0.001
        @test result.relative ≈ 66.67 atol=0.01
        @test result.mid_price == 0.0015
    end
    
    @testset "roc function" begin
        # Simple test case
        values = [100.0, 110.0, 121.0, 108.9, 119.79]
        result = roc(values, 1)
        
        @test isnan(result[1])
        @test result[2] ≈ 10.0  # (110-100)/100 * 100
        @test result[3] ≈ 10.0  # (121-110)/110 * 100
        @test result[4] ≈ -10.0 atol=0.01  # (108.9-121)/121 * 100
        @test result[5] ≈ 10.0 atol=0.01   # (119.79-108.9)/108.9 * 100
        
        # Test with period > 1
        result = roc(values, 2)
        @test isnan(result[1])
        @test isnan(result[2])
        @test result[3] ≈ 21.0  # (121-100)/100 * 100
        
        # Test with zero values
        values_with_zero = [0.0, 100.0, 110.0]
        result = roc(values_with_zero, 1)
        @test isnan(result[1])
        @test isnan(result[2])  # Division by zero
        @test result[3] ≈ 10.0
        
        # Empty vector
        @test length(roc(Float64[], 1)) == 0
        
        # Single element
        result = roc([100.0], 1)
        @test length(result) == 1
        @test isnan(result[1])
    end
    
    @testset "rolling_volatility function" begin
        # Create test price series
        prices = [100.0, 101.0, 99.0, 102.0, 98.0, 103.0, 97.0]
        
        # Test standard deviation method
        result = rolling_volatility(prices, 3, method=:std)
        @test isnan(result[1])
        @test isnan(result[2])
        @test !isnan(result[3])
        @test all(result[3:end] .>= 0)
        
        # Test with window larger than data
        result = rolling_volatility(prices, 10, method=:std)
        @test all(isnan.(result))
        
        # Test with unsupported method (should fall back to std)
        result = rolling_volatility(prices, 3, method=:parkinson)
        @test !isnan(result[3])  # Should work with fallback
        
        # Test edge cases
        constant_prices = [100.0, 100.0, 100.0, 100.0]
        result = rolling_volatility(constant_prices, 3, method=:std)
        @test result[3] ≈ 0.0 atol=1e-10
        
        # Single price
        result = rolling_volatility([100.0], 1, method=:std)
        @test isnan(result[1])
    end
    
    @testset "parkinson_volatility function" begin
        # Test data
        high = [102.0, 103.0, 101.0, 104.0, 99.0]
        low = [98.0, 99.0, 97.0, 100.0, 95.0]
        
        result = parkinson_volatility(high, low, 3)
        @test isnan(result[1])
        @test isnan(result[2])
        @test !isnan(result[3])
        @test all(result[3:end] .>= 0)
        
        # Test mismatched lengths
        @test_throws AssertionError parkinson_volatility([1.0, 2.0], [1.0], 2)
        
        # Test with zero range (high == low)
        high_eq_low = [100.0, 100.0, 100.0]
        low_eq_low = [100.0, 100.0, 100.0]
        result = parkinson_volatility(high_eq_low, low_eq_low, 2)
        @test result[2] ≈ 0.0 atol=1e-10
    end
    
    @testset "tftodelay function" begin
        # Test various timeframes
        @test tftodelay("1s") == 1000
        @test tftodelay("30s") == 30000
        @test tftodelay("1m") == 60000
        @test tftodelay("5m") == 300000
        @test tftodelay("1h") == 3600000
        @test tftodelay("4h") == 14400000
        @test tftodelay("1d") == 86400000
        
        # Test case insensitivity
        @test tftodelay("1M") == 60000
        @test tftodelay("1H") == 3600000
        @test tftodelay("1D") == 86400000
        
        # Test with whitespace
        @test tftodelay(" 1m ") == 60000
        
        # Test invalid formats
        @test_throws ArgumentError tftodelay("1x")
        @test_throws ArgumentError tftodelay("abc")
        @test_throws ArgumentError tftodelay("")
        @test_throws ArgumentError tftodelay("1")
        @test_throws ArgumentError tftodelay("m1")
    end
    
    @testset "timeframe_to_period function" begin
        # Test conversions
        @test timeframe_to_period("1s") == Second(1)
        @test timeframe_to_period("30s") == Second(30)
        @test timeframe_to_period("1m") == Minute(1)
        @test timeframe_to_period("5m") == Minute(5)
        @test timeframe_to_period("1h") == Hour(1)
        @test timeframe_to_period("4h") == Hour(4)
        @test timeframe_to_period("1d") == Day(1)
        
        # Test case insensitivity
        @test timeframe_to_period("1M") == Minute(1)
        @test timeframe_to_period("1H") == Hour(1)
        
        # Test invalid formats
        @test_throws ArgumentError timeframe_to_period("1x")
        @test_throws ArgumentError timeframe_to_period("invalid")
    end
    
    @testset "normalize_price function" begin
        # Normal cases
        @test normalize_price(100.123, 0.01) == 100.12
        @test normalize_price(100.126, 0.01) == 100.13
        @test normalize_price(100.0, 0.01) == 100.0
        
        # Different tick sizes
        @test normalize_price(100.123, 0.1) == 100.1
        @test normalize_price(100.123, 0.001) == 100.123
        @test normalize_price(100.1234, 0.001) == 100.123
        
        # Edge cases
        @test normalize_price(0.0, 0.01) == 0.0
        @test normalize_price(1e-8, 1e-8) == 1e-8
    end
    
    @testset "normalize_quantity function" begin
        # Normal cases
        @test normalize_quantity(1.123, 0.01, 0.0) == 1.12
        @test normalize_quantity(1.126, 0.01, 0.0) == 1.13
        @test normalize_quantity(1.0, 0.01, 0.0) == 1.0
        
        # With minimum quantity
        @test normalize_quantity(0.005, 0.01, 0.1) == 0.1
        @test normalize_quantity(1.123, 0.01, 0.5) == 1.12
        
        # Edge cases
        @test normalize_quantity(0.0, 0.01, 0.0) == 0.0
        @test normalize_quantity(0.0, 0.01, 0.1) == 0.1
    end
    
    @testset "calculate_atr function" begin
        # Test data
        high = [102.0, 103.0, 101.0, 104.0, 99.0, 105.0, 98.0, 106.0]
        low = [98.0, 99.0, 97.0, 100.0, 95.0, 101.0, 94.0, 102.0]
        close = [100.0, 101.0, 99.0, 102.0, 97.0, 103.0, 96.0, 104.0]
        
        result = calculate_atr(high, low, close, 3)
        
        # Check structure
        @test length(result) == length(high)
        @test isnan(result[1])
        @test isnan(result[2])
        @test !isnan(result[3])
        @test all(result[3:end] .>= 0)
        
        # Test default period
        result_default = calculate_atr(high, low, close)
        @test length(result_default) == length(high)
        
        # Test mismatched lengths
        @test_throws AssertionError calculate_atr([1.0, 2.0], [1.0], [1.0])
        @test_throws AssertionError calculate_atr([1.0], [1.0, 2.0], [1.0])
        @test_throws AssertionError calculate_atr([1.0], [1.0], [1.0, 2.0])
        
        # Test single data point
        result_single = calculate_atr([102.0], [98.0], [100.0], 1)
        @test !isnan(result_single[1])
        @test result_single[1] == 4.0  # high - low
        
        # Test constant prices (zero volatility)
        constant_high = [100.0, 100.0, 100.0, 100.0]
        constant_low = [100.0, 100.0, 100.0, 100.0]
        constant_close = [100.0, 100.0, 100.0, 100.0]
        result_constant = calculate_atr(constant_high, constant_low, constant_close, 2)
        @test result_constant[2] ≈ 0.0 atol=1e-10
    end
end