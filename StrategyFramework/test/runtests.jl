# Main test runner for StrategyFramework
using Test

# Include the StrategyFramework module directly
include("../src/StrategyFramework.jl")
using .StrategyFramework

# Run all tests
@testset "StrategyFramework Tests" begin
    @testset "Math Utilities" begin
        include("test_math_utils.jl")
    end
    
    @testset "Async Utilities" begin
        include("test_async_utils.jl")
    end
    
    @testset "Logging Utilities" begin
        include("test_logging_utils.jl")
    end
    
    @testset "Profiling Utilities" begin
        include("test_profiling_utils.jl")
    end
    
    @testset "Parameter Management" begin
        include("test_parameters.jl")
    end
    
    @testset "Environment Management" begin
        include("test_environment.jl")
    end
    
    @testset "Configuration Management" begin
        include("test_configuration.jl")
    end
    
    @testset "Market Making" begin
        include("test_market_making_standalone.jl")
    end
    
    @testset "Position Management" begin
        include("test_position_management.jl")
    end
    
    @testset "Order Management" begin
        include("test_order_management.jl")
    end
    
    @testset "Data Management" begin
        include("test_data_management.jl")
    end
    
    @testset "Telegram Integration" begin
        include("test_telegram_integration.jl")
    end
    
    @testset "Core Functions" begin
        include("test_core_functions.jl")
    end
    
    @testset "Framework Integration" begin
        include("test_framework_integration.jl")
    end
    
    @testset "Core Types" begin
        include("test_types.jl")
    end
    
    @testset "Strategy Initialization" begin
        include("test_initialization.jl")
    end
    
    @testset "Risk Management" begin
        include("test_risk_management.jl")
    end
    
    @testset "Exchange Management" begin
        include("test_exchange_management.jl")
    end
    
    @testset "OHLCV Management" begin
        include("test_ohlcv_management.jl")
    end
    
    @testset "PnL Tracking" begin
        include("test_pnl_tracking.jl")
    end
    
    @testset "Trend Detection" begin
        include("test_trend_detection.jl")
    end
end