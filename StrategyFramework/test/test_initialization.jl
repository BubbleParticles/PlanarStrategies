# Tests for strategy initialization system
using Test
using Dates

# Mock Planar types and functions for testing
struct MockStrategy
    attrs::Dict{Symbol, Any}
    universe::Vector{MockAssetInstance}
    timeframe::Symbol
    
    MockStrategy() = new(Dict{Symbol, Any}(), MockAssetInstance[], :tf_1m)
end

struct MockAssetInstance
    symbol::String
end

struct MockSignalGenerator
    name::String
    requires_trends_flag::Bool
    warmup_period::Period
    
    MockSignalGenerator(name="test"; requires_trends=false, warmup=Day(1)) = 
        new(name, requires_trends, warmup)
end

# Mock strategy lifecycle types
struct LoadStrategy end
struct ResetStrategy end
struct StartStrategy end
struct StopStrategy end
struct WarmupPeriod end
struct StrategyMarkets end
struct WatchOHLCV end

# Mock functions
id(s::MockStrategy) = "test_strategy_$(hash(s))"
available(tf::Symbol, ts::DateTime) = ts
get_current_assets() = ["BTC/USDT", "ETH/USDT"]

# Include the types and initialization modules for testing
include("../src/core/types.jl")
include("../src/core/initialization.jl")

@testset "Strategy Initialization Tests" begin
    
    @testset "initialize_strategy! function" begin
        s = MockStrategy()
        sg = MockSignalGenerator("test_sg")
        
        # Test basic initialization
        initialize_strategy!(s, sg)
        
        @test haskey(s.attrs, :pnl)
        @test s.attrs[:pnl] isa Dict
        @test haskey(s.attrs, :def_lev)
        @test s.attrs[:def_lev] == 1.0
        @test haskey(s.attrs, :position_tracker)
        @test s.attrs[:position_tracker] isa PositionTracker
        @test haskey(s.attrs, :performance_metrics)
        @test s.attrs[:performance_metrics] isa PerformanceMetrics
        @test haskey(s.attrs, :strategy_config)
        @test s.attrs[:strategy_config] isa StrategyConfig
        
        # Test initialization with existing attributes
        s.attrs[:pnl] = Dict(:existing => "data")
        s.attrs[:def_lev] = 2.0
        
        initialize_strategy!(s, sg)
        
        # Should not overwrite existing values
        @test s.attrs[:pnl][:existing] == "data"
        @test s.attrs[:def_lev] == 2.0
        
        # Test with signal generator that requires trends
        sg_with_trends = MockSignalGenerator("trends_sg", requires_trends=true)
        
        # Mock the requires_trends function
        requires_trends(sg::MockSignalGenerator) = sg.requires_trends_flag ? [:sma, :ema] : Symbol[]
        
        s_trends = MockStrategy()
        initialize_strategy!(s_trends, sg_with_trends)
        
        @test haskey(s_trends.attrs, :trends)
        @test s_trends.attrs[:trends] isa Dict
    end
    
    @testset "reset_strategy! function" begin
        s = MockStrategy()
        sg = MockSignalGenerator("test_sg")
        
        # Set up some existing data
        s.attrs[:pnl] = Dict(:btc => 0.05, :eth => -0.02)
        s.attrs[:def_lev] = 2.0
        s.attrs[:trends] = Dict(:sma => [1, 2, 3])
        
        # Create position tracker with data
        tracker = PositionTracker()
        ai = MockAssetInstance("BTC/USDT")
        tracker.extremas[ai] = "mock_extrema"
        tracker.backoff[ai] = now()
        s.attrs[:position_tracker] = tracker
        
        # Create performance metrics with data
        metrics = PerformanceMetrics(
            peak_cash = 10000.0,
            total_trades = 50,
            winning_trades = 30
        )
        s.attrs[:performance_metrics] = metrics
        
        # Mock apply_params! function
        apply_params!(s::MockStrategy) = nothing
        
        # Test reset
        reset_strategy!(s, sg)
        
        # Check that data was reset
        @test isempty(s.attrs[:pnl])
        @test s.attrs[:def_lev] == 2.0  # Should preserve existing value
        @test isempty(s.attrs[:trends])
        
        # Check position tracker reset
        reset_tracker = s.attrs[:position_tracker]
        @test isempty(reset_tracker.extremas)
        @test isempty(reset_tracker.backoff)
        @test length(reset_tracker.uni_iter[1]) == 0
        
        # Check performance metrics reset
        reset_metrics = s.attrs[:performance_metrics]
        @test isempty(reset_metrics.pnl_history)
        @test isempty(reset_metrics.trade_history)
        @test reset_metrics.peak_cash == 0.0
        @test reset_metrics.max_drawdown == 0.0
        @test reset_metrics.total_trades == 0
        @test reset_metrics.winning_trades == 0
    end
    
    @testset "apply_params! function" begin
        s = MockStrategy()
        
        # Mock apply_configuration_to_strategy! function
        apply_configuration_to_strategy!(s::MockStrategy) = nothing
        
        # Create custom configuration
        config = StrategyConfig(
            signal_lifetime = 0.5,
            def_lev = 2.5,
            reserve_cash_pct = 0.15,
            ordertype = :market,
            ismake = false
        )
        s.attrs[:strategy_config] = config
        
        # Apply parameters
        apply_params!(s)
        
        # Check that parameters were applied
        @test s.attrs[:signal_lifetime] == 0.5
        @test s.attrs[:def_lev] == 2.5
        @test s.attrs[:reserve_cash_pct] == 0.15
        @test s.attrs[:ordertype] == :market
        @test s.attrs[:ismake] == false
        @test s.attrs[:trade_cooldown] == Minute(1)  # Default value
        @test s.attrs[:order_timeout] == Minute(2)   # Default value
        
        # Test with no configuration
        s_no_config = MockStrategy()
        apply_params!(s_no_config)
        
        # Should use default values
        @test s_no_config.attrs[:signal_lifetime] == 0.2
        @test s_no_config.attrs[:def_lev] == 1.0
        @test s_no_config.attrs[:reserve_cash_pct] == 0.1
    end
    
    @testset "convert_float_vector_to_params function" begin
        s = MockStrategy()
        
        # Mock the parameter conversion utility
        convert_float_vector_to_params(params::Vector{Float64}, names::Vector{Symbol}) = 
            Dict(zip(names, params))
        
        # Test parameter conversion
        params = [0.3, 1.5, 0.2]
        param_names = [:signal_lifetime, :def_lev, :reserve_cash_pct]
        s.attrs[:optimization_params] = param_names
        
        config = convert_float_vector_to_params(s, params)
        
        @test config isa StrategyConfig
        @test config.signal_lifetime == 0.3
        @test config.def_lev == 1.5
        @test config.reserve_cash_pct == 0.2
        
        # Check that strategy was updated
        @test s.attrs[:strategy_config] == config
        
        # Test with default parameter names
        s_default = MockStrategy()
        config_default = convert_float_vector_to_params(s_default, [0.4, 2.0, 0.25])
        
        @test config_default.signal_lifetime == 0.4
        @test config_default.def_lev == 2.0
        @test config_default.reserve_cash_pct == 0.25
    end
    
    @testset "Strategy lifecycle callbacks" begin
        # Test LoadStrategy callback
        struct MockStrategyType end
        struct MockConfig
            min_timeframe::Symbol
            timeframes::Vector{Symbol}
            signal_lifetime::Float64
            def_lev::Float64
            
            MockConfig() = new(:tf_1m, [:tf_1m], 0.2, 1.0)
        end
        
        # Mock default_load function
        default_load(module, type, config) = nothing
        
        config = MockConfig()
        call!(MockStrategyType, config, LoadStrategy())
        
        @test config.min_timeframe == :tf_1m
        @test config.timeframes == [:tf_1m]
        @test config.signal_lifetime == 0.2
        @test config.def_lev == 1.0
        
        # Test ResetStrategy callback
        s = MockStrategy()
        sg = MockSignalGenerator("test_sg")
        s.attrs[:signal_generator] = sg
        
        # Mock WatchOHLCV call
        call!(s::MockStrategy, ::WatchOHLCV) = nothing
        
        call!(s, ResetStrategy())
        
        # Should have called reset_strategy!
        @test haskey(s.attrs, :pnl)
        @test haskey(s.attrs, :position_tracker)
        
        # Test StartStrategy callback
        s_start = MockStrategy()
        s_start.attrs[:signal_generator] = sg
        
        # Mock additional functions
        call!(s::MockStrategy, ::WarmupPeriod) = Day(1)
        initialize_warmup_data!(s::MockStrategy, period::Period) = nothing
        initialize_ohlcv!(s::MockStrategy) = nothing
        
        call!(s_start, StartStrategy())
        
        @test haskey(s_start.attrs, :strategy_config)
        @test haskey(s_start.attrs, :performance_metrics)
        
        # Test StopStrategy callback
        s_stop = MockStrategy()
        s_stop.attrs[:signal_generator] = sg
        
        # Mock cleanup functions
        finalize_performance_metrics!(s::MockStrategy) = nothing
        log_final_statistics!(s::MockStrategy) = nothing
        
        call!(s_stop, StopStrategy())
        # Should complete without error
        
        # Test WarmupPeriod callback
        s_warmup = MockStrategy()
        s_warmup.attrs[:signal_generator] = sg
        
        # Mock get_warmup_period for signal generator
        get_warmup_period(sg::MockSignalGenerator) = sg.warmup_period
        
        warmup = call!(s_warmup, WarmupPeriod())
        @test warmup == Day(1)
        
        # Test with custom warmup period
        sg_custom = MockSignalGenerator("custom", warmup=Hour(12))
        s_warmup.attrs[:signal_generator] = sg_custom
        
        warmup_custom = call!(s_warmup, WarmupPeriod())
        @test warmup_custom == Hour(12)
        
        # Test StrategyMarkets callback
        markets = call!(MockStrategyType, StrategyMarkets())
        @test markets == ["BTC/USDT", "ETH/USDT"]
    end
    
    @testset "poll_strategy! function" begin
        s = MockStrategy()
        sg = MockSignalGenerator("test_sg")
        ts = now()
        
        # Set up universe
        ai1 = MockAssetInstance("BTC/USDT")
        ai2 = MockAssetInstance("ETH/USDT")
        s.universe = [ai1, ai2]
        
        # Mock required functions
        track_pnl!(s::MockStrategy, ats::DateTime) = nothing
        should_trade(sg::MockSignalGenerator, s::MockStrategy, ai::MockAssetInstance, ats::DateTime) = true
        generate_buy_signal(sg::MockSignalGenerator, s::MockStrategy, ai::MockAssetInstance, ats::DateTime) = true
        generate_sell_signal(sg::MockSignalGenerator, s::MockStrategy, ai::MockAssetInstance, ats::DateTime) = false
        handle_buy_signal!(s::MockStrategy, ai::MockAssetInstance, ats::DateTime, ts::DateTime) = nothing
        handle_sell_signal!(s::MockStrategy, ai::MockAssetInstance, ats::DateTime, ts::DateTime) = nothing
        update_asset_tracking!(s::MockStrategy, ai::MockAssetInstance, ats::DateTime) = nothing
        
        # Test polling
        poll_strategy!(s, sg, ts)
        
        # Should complete without error
        @test true
        
        # Test with signal generator that doesn't allow trading
        should_trade_false(sg::MockSignalGenerator, s::MockStrategy, ai::MockAssetInstance, ats::DateTime) = false
        
        # Temporarily replace should_trade function
        original_should_trade = should_trade
        should_trade = should_trade_false
        
        poll_strategy!(s, sg, ts)
        
        # Should still complete without error
        @test true
        
        # Restore original function
        should_trade = original_should_trade
    end
    
    @testset "Signal generator interface methods" begin
        sg = MockSignalGenerator("test_sg")
        s = MockStrategy()
        
        # Test default implementations
        @test requires_trends(sg) == Symbol[]
        @test initialize!(sg, s) === nothing
        @test reset!(sg, s) === nothing
        @test cleanup!(sg, s) === nothing
        @test get_warmup_period(sg) == Day(1)
        
        # Test custom implementations
        struct CustomSignalGenerator
            trends_required::Vector{Symbol}
            warmup::Period
            initialized::Ref{Bool}
            reset_count::Ref{Int}
            cleanup_called::Ref{Bool}
        end
        
        CustomSignalGenerator() = CustomSignalGenerator(
            [:sma, :ema], 
            Hour(6), 
            Ref(false), 
            Ref(0), 
            Ref(false)
        )
        
        requires_trends(sg::CustomSignalGenerator) = sg.trends_required
        get_warmup_period(sg::CustomSignalGenerator) = sg.warmup
        
        function initialize!(sg::CustomSignalGenerator, s::MockStrategy)
            sg.initialized[] = true
            nothing
        end
        
        function reset!(sg::CustomSignalGenerator, s::MockStrategy)
            sg.reset_count[] += 1
            nothing
        end
        
        function cleanup!(sg::CustomSignalGenerator, s::MockStrategy)
            sg.cleanup_called[] = true
            nothing
        end
        
        custom_sg = CustomSignalGenerator()
        
        @test requires_trends(custom_sg) == [:sma, :ema]
        @test get_warmup_period(custom_sg) == Hour(6)
        
        initialize!(custom_sg, s)
        @test custom_sg.initialized[] == true
        
        reset!(custom_sg, s)
        @test custom_sg.reset_count[] == 1
        
        reset!(custom_sg, s)
        @test custom_sg.reset_count[] == 2
        
        cleanup!(custom_sg, s)
        @test custom_sg.cleanup_called[] == true
    end
    
    @testset "Helper functions" begin
        s = MockStrategy()
        
        # Test basic_strategy_reset!
        s.attrs[:pnl] = Dict(:test => 0.1)
        s.attrs[:def_lev] = 2.0
        
        tracker = PositionTracker()
        ai = MockAssetInstance("BTC/USDT")
        tracker.extremas[ai] = "test_data"
        s.attrs[:position_tracker] = tracker
        
        basic_strategy_reset!(s)
        
        @test isempty(s.attrs[:pnl])
        @test s.attrs[:def_lev] == 2.0
        @test isempty(s.attrs[:position_tracker].extremas)
        
        # Test basic_strategy_initialization!
        s_init = MockStrategy()
        basic_strategy_initialization!(s_init)
        
        @test haskey(s_init.attrs, :pnl)
        @test haskey(s_init.attrs, :def_lev)
        @test haskey(s_init.attrs, :position_tracker)
        @test haskey(s_init.attrs, :performance_metrics)
        @test haskey(s_init.attrs, :strategy_config)
        
        # Test initialize_warmup_data!
        s_warmup = MockStrategy()
        s_warmup.universe = [MockAssetInstance("BTC/USDT"), MockAssetInstance("ETH/USDT")]
        
        # Mock initialize_asset_warmup_data!
        initialize_asset_warmup_data!(s::MockStrategy, ai::MockAssetInstance, start::DateTime, end_time::DateTime) = nothing
        
        warmup_period = Hour(12)
        initialize_warmup_data!(s_warmup, warmup_period)
        
        @test haskey(s_warmup.attrs, :warmup_period)
        @test s_warmup.attrs[:warmup_period] == warmup_period
        @test haskey(s_warmup.attrs, :warmup_start)
        @test haskey(s_warmup.attrs, :warmup_end)
        
        # Test finalize_performance_metrics!
        s_final = MockStrategy()
        metrics = PerformanceMetrics(
            peak_cash = 15000.0,
            max_drawdown = -0.12,
            total_trades = 75,
            winning_trades = 48
        )
        s_final.attrs[:performance_metrics] = metrics
        
        finalize_performance_metrics!(s_final)
        
        @test s_final.attrs[:final_total_trades] == 75
        @test s_final.attrs[:final_winning_trades] == 48
        @test s_final.attrs[:final_win_rate] ≈ 48/75
        @test s_final.attrs[:final_max_drawdown] == -0.12
        @test s_final.attrs[:final_peak_cash] == 15000.0
        
        # Test log_final_statistics!
        s_log = MockStrategy()
        s_log.attrs[:final_total_trades] = 100
        s_log.attrs[:final_win_rate] = 0.65
        s_log.attrs[:strategy_config] = StrategyConfig()
        s_log.attrs[:signal_generator] = MockSignalGenerator("test")
        
        # Should complete without error
        log_final_statistics!(s_log)
        @test true
    end
    
    @testset "Error handling and edge cases" begin
        # Test initialization with missing signal generator
        s = MockStrategy()
        
        # Mock WatchOHLCV call
        call!(s::MockStrategy, ::WatchOHLCV) = nothing
        
        call!(s, ResetStrategy())
        
        # Should perform basic reset
        @test haskey(s.attrs, :pnl)
        @test haskey(s.attrs, :position_tracker)
        
        # Test start without signal generator
        s_start = MockStrategy()
        
        # Mock functions
        call!(s::MockStrategy, ::WarmupPeriod) = Day(1)
        initialize_warmup_data!(s::MockStrategy, period::Period) = nothing
        initialize_ohlcv!(s::MockStrategy) = nothing
        
        call!(s_start, StartStrategy())
        
        # Should perform basic initialization
        @test haskey(s_start.attrs, :strategy_config)
        
        # Test poll with missing signal generator
        s_poll = MockStrategy()
        ts = now()
        
        # Mock track_pnl!
        track_pnl!(s::MockStrategy, ats::DateTime) = nothing
        
        call!(s_poll, ts, nothing)  # ctx parameter
        
        # Should complete without error (warning logged)
        @test true
        
        # Test with error in poll_strategy!
        s_error = MockStrategy()
        sg_error = MockSignalGenerator("error_sg")
        s_error.attrs[:signal_generator] = sg_error
        
        # Mock poll_strategy! to throw error
        function poll_strategy_error!(s::MockStrategy, sg::MockSignalGenerator, ts::DateTime)
            throw(ErrorException("Test error"))
        end
        
        # Temporarily replace poll_strategy!
        original_poll = poll_strategy!
        poll_strategy! = poll_strategy_error!
        
        call!(s_error, ts, nothing)
        
        # Should handle error gracefully
        @test true
        
        # Restore original function
        poll_strategy! = original_poll
    end
end

println("✓ Strategy initialization tests completed")