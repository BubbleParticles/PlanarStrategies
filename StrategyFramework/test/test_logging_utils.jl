# Unit tests for logging utilities
using Test
using StrategyFramework
using Logging
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

# Mock strategy and asset types for testing
struct MockStrategy
    name::String
end

struct MockInstrument
    symbol::String
end

Base.string(s::MockStrategy) = s.name
Base.string(a::MockInstrument) = a.symbol

@testset "Logging Utils Tests" begin
    
    @testset "setup_logging! function" begin
        # Test basic setup
        original_logger = global_logger()
        
        try
            # Test console-only logging
            setup_logging!(Logging.Info; log_to_file=false, console_output=true)
            @test STRATEGY_LOGGER[] !== nothing
            @test LOG_LEVEL[] == Logging.Info
            @test LOG_TO_FILE[] == false
            
            # Test file-only logging
            test_log_file = tempname() * ".log"
            setup_logging!(Logging.Debug; log_to_file=true, log_file=test_log_file, console_output=false)
            @test LOG_LEVEL[] == Logging.Debug
            @test LOG_TO_FILE[] == true
            @test LOG_FILE_PATH[] == test_log_file
            
            # Test both console and file logging
            setup_logging!(Logging.Warn; log_to_file=true, log_file=test_log_file, console_output=true)
            @test STRATEGY_LOGGER[] !== nothing
            
            # Test no logging
            setup_logging!(Logging.Error; log_to_file=false, console_output=false)
            @test STRATEGY_LOGGER[] !== nothing  # Should be NullLogger
            
            # Clean up test file
            if isfile(test_log_file)
                rm(test_log_file)
            end
            
        finally
            global_logger(original_logger)
        end
    end
    
    @testset "log_trade function" begin
        strategy = MockStrategy("TestStrategy")
        asset = MockInstrument("BTC/USDT")
        
        # Capture log output
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Info)
        
        with_logger(logger) do
            log_trade(strategy, asset, "BUY", 1.5, 50000.0)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[TRADE]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "BTC/USDT")
        @test contains(log_output, "BUY")
        @test contains(log_output, "1.50000000")
        @test contains(log_output, "50000.00000000")
        
        # Test with optional parameters
        with_logger(logger) do
            log_trade(strategy, asset, "SELL", 2.0, 51000.0; 
                     order_id="12345", side=:long, custom_param="test")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "OrderID: 12345")
        @test contains(log_output, "Side: long")
        @test contains(log_output, "custom_param: test")
    end
    
    @testset "log_signal function" begin
        strategy = MockStrategy("TestStrategy")
        asset = MockInstrument("ETH/USDT")
        
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Debug)
        
        with_logger(logger) do
            log_signal(strategy, asset, "BUY_SIGNAL", 0.75)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[SIGNAL]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "ETH/USDT")
        @test contains(log_output, "BUY_SIGNAL")
        @test contains(log_output, "0.75")
        
        # Test with optional parameters
        with_logger(logger) do
            log_signal(strategy, asset, "SELL_SIGNAL", 0.25; 
                      confidence=0.8, lifetime=Millisecond(500), indicator="RSI")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "Confidence: 0.8000")
        @test contains(log_output, "Lifetime: 500 milliseconds")
        @test contains(log_output, "indicator: RSI")
    end
    
    @testset "log_position_update function" begin
        strategy = MockStrategy("TestStrategy")
        asset = MockInstrument("BTC/USDT")
        
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Info)
        
        with_logger(logger) do
            log_position_update(strategy, asset, 1.5, 1250.75)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[POSITION]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "BTC/USDT")
        @test contains(log_output, "Size: 1.50000000")
        @test contains(log_output, "UnrealizedPnL: 1250.75000000")
        
        # Test with optional parameters
        with_logger(logger) do
            log_position_update(strategy, asset, 2.0, 2500.0; 
                               realized_pnl=500.0, margin_used=10000.0, leverage=2.0)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "RealizedPnL: 500.00000000")
        @test contains(log_output, "MarginUsed: 10000.00000000")
        @test contains(log_output, "leverage: 2.0")
    end
    
    @testset "log_error function" begin
        strategy = MockStrategy("TestStrategy")
        asset = MockInstrument("BTC/USDT")
        
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Error)
        
        with_logger(logger) do
            log_error(strategy, asset, "ORDER_ERROR", "Insufficient balance")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[ERROR]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "BTC/USDT")
        @test contains(log_output, "ORDER_ERROR")
        @test contains(log_output, "Insufficient balance")
        
        # Test with exception
        test_exception = ArgumentError("Invalid parameter")
        with_logger(logger) do
            log_error(strategy, asset, "VALIDATION_ERROR", "Parameter validation failed"; 
                     exception=test_exception, order_id="67890", context="order_placement")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "Exception: ArgumentError")
        @test contains(log_output, "Invalid parameter")
        @test contains(log_output, "OrderID: 67890")
        @test contains(log_output, "context: order_placement")
    end
    
    @testset "log_performance function" begin
        strategy = MockStrategy("TestStrategy")
        
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Info)
        
        with_logger(logger) do
            log_performance(strategy, 1500.75, 65.5, 100)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[PERFORMANCE]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "TotalPnL: 1500.75000000")
        @test contains(log_output, "WinRate: 65.50%")
        @test contains(log_output, "Trades: 100")
        
        # Test with optional parameters
        with_logger(logger) do
            log_performance(strategy, 2000.0, 70.0, 150; 
                           max_drawdown=500.0, sharpe_ratio=1.25, avg_trade=13.33)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "MaxDrawdown: 500.00000000")
        @test contains(log_output, "SharpeRatio: 1.2500")
        @test contains(log_output, "avg_trade: 13.33")
    end
    
    @testset "log_market_data function" begin
        strategy = MockStrategy("TestStrategy")
        asset = MockInstrument("ETH/USDT")
        
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Debug)
        
        test_timestamp = DateTime(2023, 1, 1, 12, 0, 0)
        
        with_logger(logger) do
            log_market_data(strategy, asset, "OHLCV", test_timestamp)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[DATA]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "ETH/USDT")
        @test contains(log_output, "OHLCV")
        @test contains(log_output, "2023-01-01T12:00:00")
        
        # Test with optional parameters
        with_logger(logger) do
            log_market_data(strategy, asset, "TICKER", test_timestamp; 
                           price=3500.0, volume=1000.0, bid=3499.5, ask=3500.5)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "Price: 3500.00000000")
        @test contains(log_output, "Volume: 1000.00000000")
        @test contains(log_output, "bid: 3499.5")
        @test contains(log_output, "ask: 3500.5")
    end
    
    @testset "log_notification function" begin
        strategy = MockStrategy("TestStrategy")
        
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Info)
        
        # Test INFO level notification
        with_logger(logger) do
            log_notification(strategy, "TELEGRAM", "Strategy started successfully")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[NOTIFICATION]")
        @test contains(log_output, "TestStrategy")
        @test contains(log_output, "TELEGRAM")
        @test contains(log_output, "INFO")
        @test contains(log_output, "Strategy started successfully")
        
        # Test WARNING level notification
        logger_warn = SimpleLogger(io, Logging.Warn)
        with_logger(logger_warn) do
            log_notification(strategy, "ALERT", "High volatility detected"; 
                           urgency="WARNING", recipient="admin", channel="alerts")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "WARNING")
        @test contains(log_output, "High volatility detected")
        @test contains(log_output, "Recipient: admin")
        @test contains(log_output, "channel: alerts")
        
        # Test CRITICAL level notification
        logger_error = SimpleLogger(io, Logging.Error)
        with_logger(logger_error) do
            log_notification(strategy, "SYSTEM", "Exchange connection lost"; urgency="CRITICAL")
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "CRITICAL")
        @test contains(log_output, "Exchange connection lost")
    end
    
    @testset "create_log_summary function" begin
        # Create a temporary log file with test data
        test_log_file = tempname() * ".log"
        
        test_log_content = """
        2023-01-01T12:00:00 [TRADE] TestStrategy | BTC/USDT | BUY | Amount: 1.0 | Price: 50000.0
        2023-01-01T12:01:00 [SIGNAL] TestStrategy | BTC/USDT | BUY_SIGNAL | Value: 0.8
        2023-01-01T12:02:00 [ERROR] TestStrategy | BTC/USDT | ORDER_ERROR | Insufficient balance
        2023-01-01T12:03:00 [POSITION] TestStrategy | BTC/USDT | Size: 1.0 | UnrealizedPnL: 100.0
        2023-01-01T12:04:00 [NOTIFICATION] TestStrategy | TELEGRAM | INFO | Trade executed
        2023-01-01T12:05:00 [DATA] TestStrategy | BTC/USDT | OHLCV | DataTime: 2023-01-01T12:05:00
        2023-01-01T12:06:00 [PERFORMANCE] TestStrategy | TotalPnL: 100.0 | WinRate: 100.0% | Trades: 1
        2023-01-01T12:07:00 [TRADE] TestStrategy | BTC/USDT | SELL | Amount: 1.0 | Price: 51000.0
        """
        
        write(test_log_file, test_log_content)
        
        try
            summary = create_log_summary(test_log_file)
            
            @test summary[:total_lines] == 8
            @test summary[:trades] == 2
            @test summary[:signals] == 1
            @test summary[:errors] == 1
            @test summary[:positions] == 1
            @test summary[:notifications] == 1
            @test summary[:data_updates] == 1
            @test summary[:performance_logs] == 1
            
            # Test with non-existent file
            summary_empty = create_log_summary("non_existent_file.log")
            @test summary_empty == Dict()
            
        finally
            # Clean up
            if isfile(test_log_file)
                rm(test_log_file)
            end
        end
    end
    
    @testset "Edge cases and error handling" begin
        strategy = MockStrategy("TestStrategy")
        asset = MockInstrument("BTC/USDT")
        
        # Test with empty strings
        io = IOBuffer()
        logger = SimpleLogger(io, Logging.Info)
        
        with_logger(logger) do
            log_trade(strategy, asset, "", 0.0, 0.0)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[TRADE]")
        
        # Test with very large numbers
        with_logger(logger) do
            log_trade(strategy, asset, "BUY", 1e10, 1e15)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "10000000000.00000000")
        @test contains(log_output, "1000000000000000.00000000")
        
        # Test with negative numbers
        with_logger(logger) do
            log_position_update(strategy, asset, -1.5, -1000.0)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "Size: -1.50000000")
        @test contains(log_output, "UnrealizedPnL: -1000.00000000")
        
        # Test with special float values
        with_logger(logger) do
            log_performance(strategy, NaN, Inf, 0)
        end
        
        log_output = String(take!(io))
        @test contains(log_output, "[PERFORMANCE]")
        # NaN and Inf should be handled gracefully by the logging system
    end
end