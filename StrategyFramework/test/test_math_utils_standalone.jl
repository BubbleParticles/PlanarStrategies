# Standalone tests for math utilities
using Test
using Statistics
using Dates

# Include the math utils directly
include("../src/utilities/math_utils.jl")

@testset "Math Utils Standalone Tests" begin
    
    @testset "getincr function" begin
        # Test with tick_size
        exchange_info = Dict(:tick_size => 0.01)
        @test getincr(100.0, exchange_info) == 0.01
        
        # Test with price_precision
        exchange_info = Dict(:price_precision => 2)
        @test getincr(100.0, exchange_info) ≈ 0.01
        
        # Test fallback behavior
        exchange_info = Dict()
        result = getincr(100.0, exchange_info)
        @test result >= 1e-8
        @test result <= 100.0 * 0.0001
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
        
        # Test invalid formats
        @test_throws ArgumentError tftodelay("1x")
        @test_throws ArgumentError tftodelay("abc")
        @test_throws ArgumentError tftodelay("")
    end
    
    @testset "normalize_price function" begin
        # Normal cases
        @test normalize_price(100.123, 0.01) == 100.12
        @test normalize_price(100.126, 0.01) == 100.13
        @test normalize_price(100.0, 0.01) == 100.0
        
        # Different tick sizes
        @test normalize_price(100.123, 0.1) ≈ 100.1
        @test normalize_price(100.123, 0.001) ≈ 100.123
        @test normalize_price(100.1234, 0.001) ≈ 100.123
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
        
        # Test mismatched lengths
        @test_throws AssertionError calculate_atr([1.0, 2.0], [1.0], [1.0])
    end
end

println("✓ Math utilities tests passed")