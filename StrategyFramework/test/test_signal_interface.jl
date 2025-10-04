# Tests for signal generation interface
using Test
using Dates
using Statistics

# Mock types for testing
abstract type MockAssetInstance end

struct MockBTCUSDT <: MockAssetInstance
    symbol::String
    MockBTCUSDT() = new("BTC/USDT")
end

# Mock strategy for signal testing
mutable struct MockSignalStrategy
    config::NamedTuple
    signal_states::Dict{MockAssetInstance, Any}
    market_data::Dict{MockAssetInstance, Dict{Symbol, Float64}}
    
    function MockSignalStrategy()
        config = (
            signal_lifetime = 0.2,
            strategy_id = "test_strategy"
        )
        new(config, Dict(), Dict())
    end
end

# Import the SignalGenerator interface (mock it for testing)
abstract type SignalGenerator end

# Mock signal state
mutable struct MockSignalState
    last_buy_signal::DateTime
    last_sell_signal::DateTime
    buy_signal_active::Bool
    sell_signal_active::Bool
    signal_lifetime::Float64
    
    function MockSignalState(lifetime::Float64 = 0.2)
        new(DateTime(0), DateTime(0), false, false, lifetime)
    end
end

# Test signal generators
struct SimpleBuySignalGenerator <: SignalGenerator
    buy_threshold::Float64
    sell_threshold::Float64
    
    SimpleBuySignalGenerator() = new(0.7, 0.3)
end

struct AlwaysBuySignalGenerator <: SignalGenerator end
struct NeverTradeSignalGenerator <: SignalGenerator end
struct RSISignalGenerator <: SignalGenerator
    rsi_oversold::Float64
    rsi_overbought::Float64
    
    RSISignalGenerator() = new(30.0, 70.0)
end

struct MovingAverageCrossoverGenerator <: SignalGenerator
    fast_period::Int
    slow_period::Int
    
    MovingAverageCrossoverGenerator() = new(5, 20)
end

# Mock signal generation functions
function generate_buy_signal(sg::SimpleBuySignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    # Simple mock: return buy signal based on threshold and random factor
    market_factor = get(get(s.market_data, ai, Dict()), :momentum, 0.5)
    return market_factor > sg.buy_threshold ? 0.8 : 0.2
end

function generate_sell_signal(sg::SimpleBuySignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    # Simple mock: return sell signal based on threshold
    market_factor = get(get(s.market_data, ai, Dict()), :momentum, 0.5)
    return market_factor < sg.sell_threshold ? 0.8 : 0.2
end

function generate_buy_signal(sg::AlwaysBuySignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    return 1.0  # Always buy
end

function generate_sell_signal(sg::AlwaysBuySignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    return 0.0  # Never sell
end

function generate_buy_signal(sg::NeverTradeSignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    return 0.0  # Never buy
end

function generate_sell_signal(sg::NeverTradeSignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    return 0.0  # Never sell
end

function generate_buy_signal(sg::RSISignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    rsi = get(get(s.market_data, ai, Dict()), :rsi, 50.0)
    return rsi < sg.rsi_oversold ? 0.9 : 0.1
end

function generate_sell_signal(sg::RSISignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    rsi = get(get(s.market_data, ai, Dict()), :rsi, 50.0)
    return rsi > sg.rsi_overbought ? 0.9 : 0.1
end

function generate_buy_signal(sg::MovingAverageCrossoverGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    fast_ma = get(get(s.market_data, ai, Dict()), :fast_ma, 50000.0)
    slow_ma = get(get(s.market_data, ai, Dict()), :slow_ma, 50000.0)
    return fast_ma > slow_ma ? 0.8 : 0.2
end

function generate_sell_signal(sg::MovingAverageCrossoverGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    fast_ma = get(get(s.market_data, ai, Dict()), :fast_ma, 50000.0)
    slow_ma = get(get(s.market_data, ai, Dict()), :slow_ma, 50000.0)
    return fast_ma < slow_ma ? 0.8 : 0.2
end

# Optional methods with defaults
function should_trade(sg::SignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    return true  # Default: always allow trading
end

function should_trade(sg::NeverTradeSignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
    return false  # Never allow trading
end

function get_signal_lifetime(sg::SignalGenerator)
    return 0.2  # Default signal lifetime
end

function get_signal_lifetime(sg::SimpleBuySignalGenerator)
    return 0.5  # Custom lifetime
end

@testset "Signal Interface Tests" begin
    
    @testset "SignalGenerator interface compliance" begin
        # Test that all signal generators implement required methods
        generators = [
            SimpleBuySignalGenerator(),
            AlwaysBuySignalGenerator(),
            NeverTradeSignalGenerator(),
            RSISignalGenerator(),
            MovingAverageCrossoverGenerator()
        ]
        
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        for sg in generators
            # Test required methods exist and return valid values
            buy_signal = generate_buy_signal(sg, s, ai, ats)
            sell_signal = generate_sell_signal(sg, s, ai, ats)
            
            @test buy_signal isa Float64
            @test sell_signal isa Float64
            @test 0.0 <= buy_signal <= 1.0
            @test 0.0 <= sell_signal <= 1.0
            
            # Test optional methods
            @test should_trade(sg, s, ai, ats) isa Bool
            @test get_signal_lifetime(sg) isa Float64
            @test get_signal_lifetime(sg) > 0.0
        end
    end
    
    @testset "SimpleBuySignalGenerator behavior" begin
        sg = SimpleBuySignalGenerator()
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        # Test with high momentum (should favor buy)
        s.market_data[ai] = Dict(:momentum => 0.8)
        buy_signal_high = generate_buy_signal(sg, s, ai, ats)
        sell_signal_high = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_high > 0.5  # Should be high buy signal
        @test sell_signal_high < 0.5  # Should be low sell signal
        
        # Test with low momentum (should favor sell)
        s.market_data[ai] = Dict(:momentum => 0.2)
        buy_signal_low = generate_buy_signal(sg, s, ai, ats)
        sell_signal_low = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_low < 0.5   # Should be low buy signal
        @test sell_signal_low > 0.5  # Should be high sell signal
        
        # Test custom signal lifetime
        @test get_signal_lifetime(sg) == 0.5
        
        # Test should_trade (should always be true for this generator)
        @test should_trade(sg, s, ai, ats) == true
    end
    
    @testset "AlwaysBuySignalGenerator behavior" begin
        sg = AlwaysBuySignalGenerator()
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        # Should always generate buy signals, never sell
        for i in 1:10
            buy_signal = generate_buy_signal(sg, s, ai, ats)
            sell_signal = generate_sell_signal(sg, s, ai, ats)
            
            @test buy_signal == 1.0
            @test sell_signal == 0.0
            @test should_trade(sg, s, ai, ats) == true
        end
        
        # Test default signal lifetime
        @test get_signal_lifetime(sg) == 0.2
    end
    
    @testset "NeverTradeSignalGenerator behavior" begin
        sg = NeverTradeSignalGenerator()
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        # Should never generate any signals and never allow trading
        for i in 1:10
            buy_signal = generate_buy_signal(sg, s, ai, ats)
            sell_signal = generate_sell_signal(sg, s, ai, ats)
            
            @test buy_signal == 0.0
            @test sell_signal == 0.0
            @test should_trade(sg, s, ai, ats) == false
        end
    end
    
    @testset "RSISignalGenerator behavior" begin
        sg = RSISignalGenerator()
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        # Test oversold condition (should buy)
        s.market_data[ai] = Dict(:rsi => 25.0)  # Below oversold threshold
        buy_signal_oversold = generate_buy_signal(sg, s, ai, ats)
        sell_signal_oversold = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_oversold > 0.8   # Strong buy signal
        @test sell_signal_oversold < 0.2  # Weak sell signal
        
        # Test overbought condition (should sell)
        s.market_data[ai] = Dict(:rsi => 75.0)  # Above overbought threshold
        buy_signal_overbought = generate_buy_signal(sg, s, ai, ats)
        sell_signal_overbought = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_overbought < 0.2  # Weak buy signal
        @test sell_signal_overbought > 0.8 # Strong sell signal
        
        # Test neutral condition
        s.market_data[ai] = Dict(:rsi => 50.0)  # Neutral RSI
        buy_signal_neutral = generate_buy_signal(sg, s, ai, ats)
        sell_signal_neutral = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_neutral < 0.2   # Weak buy signal
        @test sell_signal_neutral < 0.2  # Weak sell signal
        
        # Test edge cases
        s.market_data[ai] = Dict(:rsi => 30.0)  # Exactly at oversold threshold
        buy_signal_edge = generate_buy_signal(sg, s, ai, ats)
        @test buy_signal_edge < 0.2  # Should not trigger (not below threshold)
        
        s.market_data[ai] = Dict(:rsi => 70.0)  # Exactly at overbought threshold
        sell_signal_edge = generate_sell_signal(sg, s, ai, ats)
        @test sell_signal_edge < 0.2  # Should not trigger (not above threshold)
    end
    
    @testset "MovingAverageCrossoverGenerator behavior" begin
        sg = MovingAverageCrossoverGenerator()
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        # Test bullish crossover (fast MA > slow MA)
        s.market_data[ai] = Dict(:fast_ma => 51000.0, :slow_ma => 50000.0)
        buy_signal_bullish = generate_buy_signal(sg, s, ai, ats)
        sell_signal_bullish = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_bullish > 0.5   # Should favor buying
        @test sell_signal_bullish < 0.5  # Should not favor selling
        
        # Test bearish crossover (fast MA < slow MA)
        s.market_data[ai] = Dict(:fast_ma => 49000.0, :slow_ma => 50000.0)
        buy_signal_bearish = generate_buy_signal(sg, s, ai, ats)
        sell_signal_bearish = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_bearish < 0.5   # Should not favor buying
        @test sell_signal_bearish > 0.5  # Should favor selling
        
        # Test equal MAs (no clear signal)
        s.market_data[ai] = Dict(:fast_ma => 50000.0, :slow_ma => 50000.0)
        buy_signal_equal = generate_buy_signal(sg, s, ai, ats)
        sell_signal_equal = generate_sell_signal(sg, s, ai, ats)
        
        @test buy_signal_equal < 0.5   # Should not favor buying
        @test sell_signal_equal < 0.5  # Should not favor selling
    end
    
    @testset "Signal state management" begin
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        
        # Mock signal state management functions
        function initialize_signal_state!(s::MockSignalStrategy, ai::MockAssetInstance, lifetime::Float64 = 0.2)
            s.signal_states[ai] = MockSignalState(lifetime)
            return true
        end
        
        function update_signal_state!(s::MockSignalStrategy, ai::MockAssetInstance, 
                                    buy_signal::Float64, sell_signal::Float64, ats::DateTime)
            if !haskey(s.signal_states, ai)
                initialize_signal_state!(s, ai)
            end
            
            state = s.signal_states[ai]
            
            # Update buy signal state
            if buy_signal > 0.5
                state.last_buy_signal = ats
                state.buy_signal_active = true
            end
            
            # Update sell signal state
            if sell_signal > 0.5
                state.last_sell_signal = ats
                state.sell_signal_active = true
            end
            
            # Check signal expiry
            current_time = ats
            if state.buy_signal_active && 
               (current_time - state.last_buy_signal).value / 1000 > state.signal_lifetime * 3600
                state.buy_signal_active = false
            end
            
            if state.sell_signal_active && 
               (current_time - state.last_sell_signal).value / 1000 > state.signal_lifetime * 3600
                state.sell_signal_active = false
            end
            
            return state
        end
        
        function is_signal_active(s::MockSignalStrategy, ai::MockAssetInstance, signal_type::Symbol)
            if !haskey(s.signal_states, ai)
                return false
            end
            
            state = s.signal_states[ai]
            if signal_type == :buy
                return state.buy_signal_active
            elseif signal_type == :sell
                return state.sell_signal_active
            else
                return false
            end
        end
        
        # Test signal state initialization
        @test initialize_signal_state!(s, ai, 0.3)
        @test haskey(s.signal_states, ai)
        @test s.signal_states[ai].signal_lifetime == 0.3
        @test !s.signal_states[ai].buy_signal_active
        @test !s.signal_states[ai].sell_signal_active
        
        # Test signal activation
        ats = now()
        state = update_signal_state!(s, ai, 0.8, 0.2, ats)  # Strong buy signal
        @test state.buy_signal_active == true
        @test state.sell_signal_active == false
        @test state.last_buy_signal == ats
        
        @test is_signal_active(s, ai, :buy) == true
        @test is_signal_active(s, ai, :sell) == false
        
        # Test sell signal activation
        state = update_signal_state!(s, ai, 0.2, 0.9, ats + Second(1))  # Strong sell signal
        @test state.sell_signal_active == true
        @test is_signal_active(s, ai, :sell) == true
        
        # Test signal expiry (mock by setting old timestamp)
        old_time = ats - Hour(2)  # 2 hours ago
        state.last_buy_signal = old_time
        state.last_sell_signal = old_time
        
        update_signal_state!(s, ai, 0.1, 0.1, ats)  # Weak signals, should expire old ones
        @test !state.buy_signal_active
        @test !state.sell_signal_active
    end
    
    @testset "Signal validation and debugging" begin
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        
        # Mock signal validation functions
        function validate_signal_output(buy_signal::Float64, sell_signal::Float64)
            errors = String[]
            
            if !(0.0 <= buy_signal <= 1.0)
                push!(errors, "Buy signal out of range: $buy_signal")
            end
            
            if !(0.0 <= sell_signal <= 1.0)
                push!(errors, "Sell signal out of range: $sell_signal")
            end
            
            if isnan(buy_signal)
                push!(errors, "Buy signal is NaN")
            end
            
            if isnan(sell_signal)
                push!(errors, "Sell signal is NaN")
            end
            
            if isinf(buy_signal)
                push!(errors, "Buy signal is infinite")
            end
            
            if isinf(sell_signal)
                push!(errors, "Sell signal is infinite")
            end
            
            return isempty(errors) ? nothing : errors
        end
        
        function debug_signal_generation(sg::SignalGenerator, s::MockSignalStrategy, 
                                       ai::MockAssetInstance, ats::DateTime)
            debug_info = Dict{String, Any}()
            
            # Capture signal generation
            start_time = time()
            buy_signal = generate_buy_signal(sg, s, ai, ats)
            sell_signal = generate_sell_signal(sg, s, ai, ats)
            end_time = time()
            
            debug_info["generation_time_ms"] = (end_time - start_time) * 1000
            debug_info["buy_signal"] = buy_signal
            debug_info["sell_signal"] = sell_signal
            debug_info["signal_generator"] = string(typeof(sg))
            debug_info["timestamp"] = ats
            debug_info["asset"] = ai.symbol
            
            # Validate signals
            validation_errors = validate_signal_output(buy_signal, sell_signal)
            debug_info["validation_errors"] = validation_errors
            debug_info["is_valid"] = validation_errors === nothing
            
            # Additional context
            debug_info["should_trade"] = should_trade(sg, s, ai, ats)
            debug_info["signal_lifetime"] = get_signal_lifetime(sg)
            debug_info["market_data"] = get(s.market_data, ai, Dict())
            
            return debug_info
        end
        
        # Test valid signals
        sg = SimpleBuySignalGenerator()
        s.market_data[ai] = Dict(:momentum => 0.8)
        
        errors = validate_signal_output(0.8, 0.2)
        @test errors === nothing
        
        # Test invalid signals
        errors_invalid = validate_signal_output(1.5, -0.2)  # Out of range
        @test errors_invalid !== nothing
        @test length(errors_invalid) == 2
        @test contains(errors_invalid[1], "out of range")
        @test contains(errors_invalid[2], "out of range")
        
        # Test NaN signals
        errors_nan = validate_signal_output(NaN, 0.5)
        @test errors_nan !== nothing
        @test contains(errors_nan[1], "NaN")
        
        # Test infinite signals
        errors_inf = validate_signal_output(Inf, 0.5)
        @test errors_inf !== nothing
        @test contains(errors_inf[1], "infinite")
        
        # Test debug information
        debug_info = debug_signal_generation(sg, s, ai, now())
        
        @test haskey(debug_info, "generation_time_ms")
        @test haskey(debug_info, "buy_signal")
        @test haskey(debug_info, "sell_signal")
        @test haskey(debug_info, "signal_generator")
        @test haskey(debug_info, "is_valid")
        @test haskey(debug_info, "should_trade")
        @test haskey(debug_info, "signal_lifetime")
        
        @test debug_info["generation_time_ms"] >= 0.0
        @test debug_info["is_valid"] == true
        @test debug_info["signal_generator"] == "SimpleBuySignalGenerator"
        @test debug_info["should_trade"] == true
        @test debug_info["signal_lifetime"] == 0.5
    end
    
    @testset "Signal generator composition and chaining" begin
        # Test combining multiple signal generators
        struct CompositeSignalGenerator <: SignalGenerator
            generators::Vector{SignalGenerator}
            weights::Vector{Float64}
            
            function CompositeSignalGenerator(generators::Vector{SignalGenerator}, weights::Vector{Float64})
                @assert length(generators) == length(weights)
                @assert sum(weights) ≈ 1.0
                new(generators, weights)
            end
        end
        
        function generate_buy_signal(sg::CompositeSignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
            weighted_signal = 0.0
            for (gen, weight) in zip(sg.generators, sg.weights)
                signal = generate_buy_signal(gen, s, ai, ats)
                weighted_signal += signal * weight
            end
            return clamp(weighted_signal, 0.0, 1.0)
        end
        
        function generate_sell_signal(sg::CompositeSignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
            weighted_signal = 0.0
            for (gen, weight) in zip(sg.generators, sg.weights)
                signal = generate_sell_signal(gen, s, ai, ats)
                weighted_signal += signal * weight
            end
            return clamp(weighted_signal, 0.0, 1.0)
        end
        
        function should_trade(sg::CompositeSignalGenerator, s::MockSignalStrategy, ai::MockAssetInstance, ats)
            # All generators must allow trading
            return all(should_trade(gen, s, ai, ats) for gen in sg.generators)
        end
        
        # Test composite signal generator
        generators = [
            AlwaysBuySignalGenerator(),
            SimpleBuySignalGenerator(),
            RSISignalGenerator()
        ]
        weights = [0.3, 0.4, 0.3]
        
        composite_sg = CompositeSignalGenerator(generators, weights)
        s = MockSignalStrategy()
        ai = MockBTCUSDT()
        ats = now()
        
        # Set up market data for testing
        s.market_data[ai] = Dict(:momentum => 0.8, :rsi => 25.0)  # Bullish conditions
        
        buy_signal = generate_buy_signal(composite_sg, s, ai, ats)
        sell_signal = generate_sell_signal(composite_sg, s, ai, ats)
        
        @test 0.0 <= buy_signal <= 1.0
        @test 0.0 <= sell_signal <= 1.0
        @test should_trade(composite_sg, s, ai, ats) == true
        
        # Test with one generator that doesn't allow trading
        generators_with_never = [
            AlwaysBuySignalGenerator(),
            NeverTradeSignalGenerator()
        ]
        weights_never = [0.5, 0.5]
        
        composite_never = CompositeSignalGenerator(generators_with_never, weights_never)
        @test should_trade(composite_never, s, ai, ats) == false  # Should be false due to NeverTradeSignalGenerator
    end
end

println("✓ Signal interface tests completed")