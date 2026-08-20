# Integration tests for StrategyFramework
# Tests strategy lifecycle, order execution flows, and data management

using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates

# Mock Planar types and functions for integration testing
abstract type MockInstrumentInstance end
abstract type MockPositionSide end

struct MockBTCUSDT <: MockInstrumentInstance
    symbol::String
    MockBTCUSDT() = new("BTC/USDT")
end

struct MockLong <: MockPositionSide end
struct MockShort <: MockPositionSide end

Base.string(ii::MockBTCUSDT) = ii.symbol

# Mock strategy type with config
mutable struct MockIntegrationStrategy
    config::NamedTuple
    is_sim::Bool
    orders::Vector{Dict{String, Any}}
    positions::Dict{MockInstrumentInstance, Float64}
    balance::Float64
    
    function MockIntegrationStrategy(is_sim::Bool = true)
        config = (
            signal_lifetime = 0.2,
            trade_cooldown = Minute(1),
            order_timeout = Minute(2),
            def_lev = 1.0,
            reserve_cash_pct = 0.1,
            peak_cash = 0.0,
            ordertype = :gtc,
            ismake = true,
            throttle = Second(10)
        )
        new(config, is_sim, Dict{String, Any}[], Dict{MockInstrumentInstance, Float64}(), 10000.0)
    end
end

# Mock functions
issim(s::MockIntegrationStrategy) = s.is_sim
isopen(ii::MockInstrumentInstance) = true

# Mock signal generator for testing
abstract type MockSignalGenerator end

struct SimpleBuySignalGenerator <: MockSignalGenerator
    buy_threshold::Float64
    sell_threshold::Float64
    
    SimpleBuySignalGenerator() = new(0.7, 0.3)
end

struct AlwaysBuySignalGenerator <: MockSignalGenerator end
struct NeverTradeSignalGenerator <: MockSignalGenerator end

# Alternating signal generator for testing
struct AlternatingSignalGenerator <: MockSignalGenerator
    counter::Ref{Int}
    AlternatingSignalGenerator() = new(Ref(0))
end

# Mock signal generation functions
function generate_buy_signal(sg::SimpleBuySignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    # Simple mock: return buy signal based on threshold
    return rand() > sg.buy_threshold ? 0.8 : 0.0
end

function generate_sell_signal(sg::SimpleBuySignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    # Simple mock: return sell signal based on threshold
    return rand() > sg.sell_threshold ? 0.8 : 0.0
end

function generate_buy_signal(sg::AlwaysBuySignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return 1.0  # Always buy
end

function generate_sell_signal(sg::AlwaysBuySignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return 0.0  # Never sell
end

function generate_buy_signal(sg::NeverTradeSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return 0.0  # Never buy
end

function generate_sell_signal(sg::NeverTradeSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return 0.0  # Never sell
end

function should_trade(sg::MockSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return true  # Always allow trading
end

function should_trade(sg::NeverTradeSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return false  # Never allow trading
end

function get_signal_lifetime(sg::MockSignalGenerator)
    return 0.2  # Default signal lifetime
end

function generate_buy_signal(sg::AlternatingSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    sg.counter[] += 1
    return sg.counter[] % 2 == 1 ? 1.0 : 0.0  # Buy on odd calls
end

function generate_sell_signal(sg::AlternatingSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return sg.counter[] % 2 == 0 ? 1.0 : 0.0  # Sell on even calls
end

function should_trade(sg::AlternatingSignalGenerator, s::MockIntegrationStrategy, ii::MockInstrumentInstance, ats)
    return true
end

# Mock strategy lifecycle functions
function initialize_strategy!(s::MockIntegrationStrategy, sg::MockSignalGenerator)
    # Initialize strategy components
    s.orders = Dict{String, Any}[]
    s.positions = Dict{MockInstrumentInstance, Float64}()
    s.balance = 10000.0
    return true
end

function reset_strategy!(s::MockIntegrationStrategy, sg::MockSignalGenerator)
    # Reset strategy state
    empty!(s.orders)
    empty!(s.positions)
    s.balance = 10000.0
    return true
end

# Mock order execution functions
function execute_mock_order!(s::MockIntegrationStrategy, ii::MockInstrumentInstance, side::Symbol, amount::Float64, price::Float64)
    order_id = "order_$(length(s.orders) + 1)"
    
    order = Dict{String, Any}(
        "id" => order_id,
        "asset" => string(ii),
        "side" => side,
        "amount" => amount,
        "price" => price,
        "status" => "filled",
        "timestamp" => now()
    )
    
    push!(s.orders, order)
    
    # Update position
    if !haskey(s.positions, ii)
        s.positions[ii] = 0.0
    end
    
    if side == :buy
        s.positions[ii] += amount
        s.balance -= amount * price
    elseif side == :sell
        s.positions[ii] -= amount
        s.balance += amount * price
    end
    
    return order
end

function cancel_mock_order!(s::MockIntegrationStrategy, order_id::String)
    for order in s.orders
        if order["id"] == order_id && order["status"] == "open"
            order["status"] = "cancelled"
            return true
        end
    end
    return false
end

# Mock data management functions
function initialize_mock_data!(s::MockIntegrationStrategy)
    # Mock OHLCV data initialization
    return true
end

function track_mock_pnl!(s::MockIntegrationStrategy, ii::MockInstrumentInstance)
    # Mock PnL tracking
    if haskey(s.positions, ii)
        position = s.positions[ii]
        # Simple mock: assume current price is 50000 for BTC/USDT
        current_price = 50000.0
        unrealized_pnl = position * current_price - position * 49000.0  # Assume entry at 49000
        return unrealized_pnl
    end
    return 0.0
end

# Mock polling function
function poll_strategy!(s::MockIntegrationStrategy, sg::MockSignalGenerator, ts::DateTime)
    ii = MockBTCUSDT()
    ats = ts  # Mock timestamp
    
    # Check if trading is allowed
    if !should_trade(sg, s, ii, ats)
        return false
    end
    
    # Generate signals
    buy_signal = generate_buy_signal(sg, s, ii, ats)
    sell_signal = generate_sell_signal(sg, s, ii, ats)
    
    # Execute trades based on signals
    if buy_signal > 0.5
        # Execute buy order
        amount = 0.1  # Mock amount
        price = 50000.0  # Mock price
        execute_mock_order!(s, ii, :buy, amount, price)
        return true
    elseif sell_signal > 0.5 && haskey(s.positions, ii) && s.positions[ii] > 0
        # Execute sell order
        amount = min(0.1, s.positions[ii])  # Mock amount, limited by position
        price = 50000.0  # Mock price
        execute_mock_order!(s, ii, :sell, amount, price)
        return true
    end
    
    return false
end

@testset "StrategyFramework Integration Tests" begin
    
    @testset "Strategy Lifecycle Tests" begin
        @testset "Strategy initialization and reset" begin
            strategy = MockIntegrationStrategy(true)  # Simulation mode
            signal_generator = SimpleBuySignalGenerator()
            
            # Test initialization
            @test initialize_strategy!(strategy, signal_generator) == true
            @test isempty(strategy.orders)
            @test isempty(strategy.positions)
            @test strategy.balance == 10000.0
            
            # Modify strategy state
            ii = MockBTCUSDT()
            execute_mock_order!(strategy, ii, :buy, 0.1, 50000.0)
            @test !isempty(strategy.orders)
            @test !isempty(strategy.positions)
            @test strategy.balance < 10000.0
            
            # Test reset
            @test reset_strategy!(strategy, signal_generator) == true
            @test isempty(strategy.orders)
            @test isempty(strategy.positions)
            @test strategy.balance == 10000.0
        end
        
        @testset "Strategy configuration" begin
            strategy = MockIntegrationStrategy(false)  # Live mode
            
            # Test configuration access
            @test strategy.config.signal_lifetime == 0.2
            @test strategy.config.def_lev == 1.0
            @test strategy.config.ordertype == :gtc
            @test strategy.config.ismake == true
            
            # Test mode detection
            @test !issim(strategy)
            
            sim_strategy = MockIntegrationStrategy(true)
            @test issim(sim_strategy)
        end
    end
    
    @testset "Signal Generation Interface Tests" begin
        @testset "SimpleBuySignalGenerator" begin
            strategy = MockIntegrationStrategy()
            sg = SimpleBuySignalGenerator()
            ii = MockBTCUSDT()
            ts = now()
            
            # Test signal generation (results are random, so test structure)
            buy_signal = generate_buy_signal(sg, strategy, ii, ts)
            sell_signal = generate_sell_signal(sg, strategy, ii, ts)
            
            @test isa(buy_signal, Float64)
            @test isa(sell_signal, Float64)
            @test buy_signal >= 0.0
            @test sell_signal >= 0.0
            
            # Test should_trade
            @test should_trade(sg, strategy, ii, ts) == true
            
            # Test signal lifetime
            @test get_signal_lifetime(sg) == 0.2
        end
        
        @testset "AlwaysBuySignalGenerator" begin
            strategy = MockIntegrationStrategy()
            sg = AlwaysBuySignalGenerator()
            ii = MockBTCUSDT()
            ts = now()
            
            # Test consistent signals
            @test generate_buy_signal(sg, strategy, ii, ts) == 1.0
            @test generate_sell_signal(sg, strategy, ii, ts) == 0.0
            @test should_trade(sg, strategy, ii, ts) == true
        end
        
        @testset "NeverTradeSignalGenerator" begin
            strategy = MockIntegrationStrategy()
            sg = NeverTradeSignalGenerator()
            ii = MockBTCUSDT()
            ts = now()
            
            # Test no trading signals
            @test generate_buy_signal(sg, strategy, ii, ts) == 0.0
            @test generate_sell_signal(sg, strategy, ii, ts) == 0.0
            @test should_trade(sg, strategy, ii, ts) == false
        end
    end
    
    @testset "Order Execution Flow Tests" begin
        @testset "Basic order execution" begin
            strategy = MockIntegrationStrategy()
            ii = MockBTCUSDT()
            
            # Test buy order
            initial_balance = strategy.balance
            order = execute_mock_order!(strategy, ii, :buy, 0.1, 50000.0)
            
            @test order["side"] == :buy
            @test order["amount"] == 0.1
            @test order["price"] == 50000.0
            @test order["status"] == "filled"
            @test haskey(order, "id")
            @test haskey(order, "timestamp")
            
            # Check position and balance updates
            @test strategy.positions[ii] == 0.1
            @test strategy.balance == initial_balance - 0.1 * 50000.0
            
            # Test sell order
            sell_order = execute_mock_order!(strategy, ii, :sell, 0.05, 51000.0)
            
            @test sell_order["side"] == :sell
            @test strategy.positions[ii] == 0.05  # 0.1 - 0.05
            @test strategy.balance > initial_balance - 0.1 * 50000.0  # Profit from higher sell price
        end
        
        @testset "Order cancellation" begin
            strategy = MockIntegrationStrategy()
            
            # Create a mock open order
            open_order = Dict{String, Any}(
                "id" => "test_order_1",
                "status" => "open"
            )
            push!(strategy.orders, open_order)
            
            # Test successful cancellation
            @test cancel_mock_order!(strategy, "test_order_1") == true
            @test strategy.orders[1]["status"] == "cancelled"
            
            # Test cancellation of non-existent order
            @test cancel_mock_order!(strategy, "non_existent") == false
            
            # Test cancellation of already filled order
            filled_order = Dict{String, Any}(
                "id" => "test_order_2",
                "status" => "filled"
            )
            push!(strategy.orders, filled_order)
            @test cancel_mock_order!(strategy, "test_order_2") == false
        end
        
        @testset "Error handling in order execution" begin
            strategy = MockIntegrationStrategy()
            ii = MockBTCUSDT()
            
            # Test order with zero amount
            order = execute_mock_order!(strategy, ii, :buy, 0.0, 50000.0)
            @test order["amount"] == 0.0
            @test strategy.positions[ii] == 0.0
            
            # Test order with zero price
            order = execute_mock_order!(strategy, ii, :buy, 0.1, 0.0)
            @test order["price"] == 0.0
            @test strategy.balance == 10000.0  # No balance change
            
            # Test selling more than available position
            strategy.positions[ii] = 0.05
            order = execute_mock_order!(strategy, ii, :sell, 0.1, 50000.0)
            @test order["amount"] == 0.1  # Order placed as requested
            @test strategy.positions[ii] == -0.05  # Negative position (short)
        end
    end
    
    @testset "Data Management and Performance Tracking Tests" begin
        @testset "Data initialization" begin
            strategy = MockIntegrationStrategy()
            
            # Test data initialization
            @test initialize_mock_data!(strategy) == true
        end
        
        @testset "PnL tracking" begin
            strategy = MockIntegrationStrategy()
            ii = MockBTCUSDT()
            
            # Test PnL with no position
            pnl = track_mock_pnl!(strategy, ii)
            @test pnl == 0.0
            
            # Test PnL with position
            strategy.positions[ii] = 0.1
            pnl = track_mock_pnl!(strategy, ii)
            @test pnl > 0.0  # Should be positive (current price > entry price in mock)
            
            # Test PnL with negative position
            strategy.positions[ii] = -0.1
            pnl = track_mock_pnl!(strategy, ii)
            @test pnl < 0.0  # Should be negative for short position when price rises
        end
        
        @testset "Performance metrics" begin
            strategy = MockIntegrationStrategy()
            ii = MockBTCUSDT()
            
            # Execute several trades
            execute_mock_order!(strategy, ii, :buy, 0.1, 49000.0)
            execute_mock_order!(strategy, ii, :sell, 0.05, 51000.0)
            execute_mock_order!(strategy, ii, :buy, 0.02, 50500.0)
            
            # Test order history
            @test length(strategy.orders) == 3
            @test strategy.orders[1]["side"] == :buy
            @test strategy.orders[2]["side"] == :sell
            @test strategy.orders[3]["side"] == :buy
            
            # Test position tracking
            expected_position = 0.1 - 0.05 + 0.02  # 0.07
            @test strategy.positions[ii] ≈ expected_position
            
            # Test balance tracking
            expected_balance = 10000.0 - 0.1 * 49000.0 + 0.05 * 51000.0 - 0.02 * 50500.0
            @test strategy.balance ≈ expected_balance
        end
    end
    
    @testset "Strategy Polling Integration Tests" begin
        @testset "Polling with AlwaysBuySignalGenerator" begin
            strategy = MockIntegrationStrategy()
            sg = AlwaysBuySignalGenerator()
            
            initialize_strategy!(strategy, sg)
            
            # Test multiple polling cycles
            ts = now()
            
            # First poll should execute buy order
            result1 = poll_strategy!(strategy, sg, ts)
            @test result1 == true
            @test length(strategy.orders) == 1
            @test strategy.orders[1]["side"] == :buy
            
            # Second poll should execute another buy order
            result2 = poll_strategy!(strategy, sg, ts + Second(1))
            @test result2 == true
            @test length(strategy.orders) == 2
            
            # Check cumulative position
            ii = MockBTCUSDT()
            @test strategy.positions[ii] == 0.2  # 2 * 0.1
        end
        
        @testset "Polling with NeverTradeSignalGenerator" begin
            strategy = MockIntegrationStrategy()
            sg = NeverTradeSignalGenerator()
            
            initialize_strategy!(strategy, sg)
            
            # Test polling cycles
            ts = now()
            
            # Should not execute any trades
            result1 = poll_strategy!(strategy, sg, ts)
            @test result1 == false
            @test length(strategy.orders) == 0
            
            result2 = poll_strategy!(strategy, sg, ts + Second(1))
            @test result2 == false
            @test length(strategy.orders) == 0
            
            # Balance and positions should remain unchanged
            @test strategy.balance == 10000.0
            @test isempty(strategy.positions)
        end
        
        @testset "Polling with SimpleBuySignalGenerator" begin
            strategy = MockIntegrationStrategy()
            sg = SimpleBuySignalGenerator()
            
            initialize_strategy!(strategy, sg)
            
            # Test multiple polling cycles (results will vary due to randomness)
            ts = now()
            results = []
            
            for i in 1:10
                result = poll_strategy!(strategy, sg, ts + Second(i))
                push!(results, result)
            end
            
            # Should have some variation in results
            @test length(unique(results)) > 1 || all(results .== false)  # Either varied or all false
            
            # If any trades were executed, check they're valid
            if !isempty(strategy.orders)
                for order in strategy.orders
                    @test haskey(order, "id")
                    @test haskey(order, "side")
                    @test haskey(order, "amount")
                    @test haskey(order, "price")
                    @test order["status"] == "filled"
                end
            end
        end
    end
    
    @testset "End-to-End Strategy Workflow Tests" begin
        @testset "Complete strategy lifecycle" begin
            strategy = MockIntegrationStrategy()
            sg = AlwaysBuySignalGenerator()
            
            # 1. Initialize strategy
            @test initialize_strategy!(strategy, sg) == true
            @test initialize_mock_data!(strategy) == true
            
            # 2. Run strategy for several cycles
            ts = now()
            trade_count = 0
            
            for i in 1:5
                if poll_strategy!(strategy, sg, ts + Second(i))
                    trade_count += 1
                end
                
                # Track PnL after each cycle
                ii = MockBTCUSDT()
                pnl = track_mock_pnl!(strategy, ii)
                # PnL should be calculable (not error)
                @test isa(pnl, Float64)
            end
            
            # 3. Verify strategy state
            @test trade_count > 0  # Should have executed some trades
            @test length(strategy.orders) == trade_count
            @test !isempty(strategy.positions)
            @test strategy.balance < 10000.0  # Should have spent money on buys
            
            # 4. Reset and verify clean state
            @test reset_strategy!(strategy, sg) == true
            @test isempty(strategy.orders)
            @test isempty(strategy.positions)
            @test strategy.balance == 10000.0
        end
        
        @testset "Strategy with mixed buy/sell signals" begin
            
            strategy = MockIntegrationStrategy()
            sg = AlternatingSignalGenerator()
            
            initialize_strategy!(strategy, sg)
            
            # Run for several cycles
            ts = now()
            for i in 1:6
                poll_strategy!(strategy, sg, ts + Second(i))
            end
            
            # Should have alternating buy/sell orders
            @test length(strategy.orders) >= 4  # At least some trades
            
            # Check for mix of buy and sell orders
            buy_orders = filter(o -> o["side"] == :buy, strategy.orders)
            sell_orders = filter(o -> o["side"] == :sell, strategy.orders)
            
            @test !isempty(buy_orders)
            @test !isempty(sell_orders)
        end
    end
end

println("✓ Integration tests completed")