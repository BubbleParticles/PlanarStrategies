# Tests for Telegram integration functions
using Test
using Planar.Engine.TimeTicks
using Planar.Engine.TimeTicks: Dates
using Statistics

# Mock types for testing
abstract type MockInstrumentInstance end

struct MockBTCUSDT <: MockInstrumentInstance
    symbol::String
    MockBTCUSDT() = new("BTC/USDT")
end

# Mock Telegram configuration
mutable struct MockTelegramConfig
    bot_token::String
    chat_id::String
    username::String
    enabled::Bool
    
    function MockTelegramConfig()
        new("mock_token_123", "mock_chat_456", "mock_bot", false)
    end
end

# Mock strategy with Telegram integration
mutable struct MockTelegramStrategy
    config::NamedTuple
    telegram_config::MockTelegramConfig
    message_history::Vector{Dict{String, Any}}
    notification_settings::Dict{Symbol, Bool}
    
    function MockTelegramStrategy()
        config = (
            strategy_id = "test_strategy",
            enable_notifications = true,
            notification_cooldown = Minute(5)
        )
        new(
            config,
            MockTelegramConfig(),
            Dict{String, Any}[],
            Dict(:trades => true, :errors => true, :performance => true, :startup => true)
        )
    end
end

# Mock HTTP response for Telegram API
struct MockHTTPResponse
    status::Int
    body::String
    
    MockHTTPResponse(status::Int, body::String = "{}") = new(status, body)
end

# Mock Telegram API functions
function mock_send_telegram_message(token::String, chat_id::String, message::String; parse_mode::String = "Markdown")
    # Simulate API call
    if token == "invalid_token"
        return MockHTTPResponse(401, """{"ok": false, "error_code": 401, "description": "Unauthorized"}""")
    elseif chat_id == "invalid_chat"
        return MockHTTPResponse(400, """{"ok": false, "error_code": 400, "description": "Bad Request: chat not found"}""")
    else
        return MockHTTPResponse(200, """{"ok": true, "result": {"message_id": 123, "date": $(Int(time())), "text": "$message"}}""")
    end
end

function mock_get_telegram_bot_info(token::String)
    if token == "invalid_token"
        return MockHTTPResponse(401, """{"ok": false, "error_code": 401, "description": "Unauthorized"}""")
    else
        return MockHTTPResponse(200, """{"ok": true, "result": {"id": 123456789, "is_bot": true, "first_name": "TestBot", "username": "test_bot"}}""")
    end
end

@testset "Telegram Integration Tests" begin
    
    @testset "start_telegram function" begin
        s = MockTelegramStrategy()
        
        # Mock the start_telegram function
        function start_telegram(s::MockTelegramStrategy)
            # Check if environment variables are set
            token = get(ENV, "TELEGRAM_BOT_TOKEN", "")
            chat_id = get(ENV, "TELEGRAM_BOT_CHAT_ID", "")
            username = get(ENV, "TELEGRAM_BOT_USERNAME", "")
            
            if isempty(token) || isempty(chat_id)
                @warn "Telegram credentials not configured"
                return false
            end
            
            # Test bot connection
            response = mock_get_telegram_bot_info(token)
            if response.status != 200
                @warn "Failed to connect to Telegram bot" status=response.status
                return false
            end
            
            # Update configuration
            s.telegram_config.bot_token = token
            s.telegram_config.chat_id = chat_id
            s.telegram_config.username = username
            s.telegram_config.enabled = true
            
            # Send startup message
            startup_msg = "🚀 Strategy $(s.config.strategy_id) started successfully"
            send_result = mock_send_telegram_message(token, chat_id, startup_msg)
            
            if send_result.status == 200
                push!(s.message_history, Dict(
                    "type" => "startup",
                    "message" => startup_msg,
                    "timestamp" => now(),
                    "status" => "sent"
                ))
                return true
            else
                @warn "Failed to send startup message" status=send_result.status
                return false
            end
        end
        
        # Test without credentials
        result_no_creds = start_telegram(s)
        @test result_no_creds == false
        @test s.telegram_config.enabled == false
        
        # Test with valid credentials
        ENV["TELEGRAM_BOT_TOKEN"] = "valid_token_123"
        ENV["TELEGRAM_BOT_CHAT_ID"] = "valid_chat_456"
        ENV["TELEGRAM_BOT_USERNAME"] = "test_bot"
        
        result_valid = start_telegram(s)
        @test result_valid == true
        @test s.telegram_config.enabled == true
        @test s.telegram_config.bot_token == "valid_token_123"
        @test s.telegram_config.chat_id == "valid_chat_456"
        @test length(s.message_history) == 1
        @test s.message_history[1]["type"] == "startup"
        
        # Test with invalid token
        ENV["TELEGRAM_BOT_TOKEN"] = "invalid_token"
        s_invalid = MockTelegramStrategy()
        result_invalid = start_telegram(s_invalid)
        @test result_invalid == false
        
        # Clean up environment
        delete!(ENV, "TELEGRAM_BOT_TOKEN")
        delete!(ENV, "TELEGRAM_BOT_CHAT_ID")
        delete!(ENV, "TELEGRAM_BOT_USERNAME")
    end
    
    @testset "send_telegram_notification function" begin
        s = MockTelegramStrategy()
        s.telegram_config.enabled = true
        s.telegram_config.bot_token = "valid_token"
        s.telegram_config.chat_id = "valid_chat"
        
        # Mock the send_telegram_notification function
        function send_telegram_notification(s::MockTelegramStrategy, message::String, 
                                          notification_type::Symbol = :general; 
                                          parse_mode::String = "Markdown")
            
            if !s.telegram_config.enabled
                return false
            end
            
            # Check if notification type is enabled
            if haskey(s.notification_settings, notification_type) && 
               !s.notification_settings[notification_type]
                return false
            end
            
            # Send message
            response = mock_send_telegram_message(
                s.telegram_config.bot_token,
                s.telegram_config.chat_id,
                message;
                parse_mode = parse_mode
            )
            
            # Record message
            push!(s.message_history, Dict(
                "type" => string(notification_type),
                "message" => message,
                "timestamp" => now(),
                "status" => response.status == 200 ? "sent" : "failed",
                "response_code" => response.status
            ))
            
            return response.status == 200
        end
        
        # Test successful notification
        result = send_telegram_notification(s, "Test message", :general)
        @test result == true
        @test length(s.message_history) == 1
        @test s.message_history[1]["status"] == "sent"
        
        # Test with disabled Telegram
        s.telegram_config.enabled = false
        result_disabled = send_telegram_notification(s, "Test message", :general)
        @test result_disabled == false
        @test length(s.message_history) == 1  # No new message added
        
        # Test with disabled notification type
        s.telegram_config.enabled = true
        s.notification_settings[:trades] = false
        result_disabled_type = send_telegram_notification(s, "Trade message", :trades)
        @test result_disabled_type == false
        
        # Test with enabled notification type
        s.notification_settings[:errors] = true
        result_enabled_type = send_telegram_notification(s, "Error message", :errors)
        @test result_enabled_type == true
        @test length(s.message_history) == 2
        
        # Test with invalid credentials
        s.telegram_config.chat_id = "invalid_chat"
        result_invalid = send_telegram_notification(s, "Test message", :general)
        @test result_invalid == false
        @test s.message_history[end]["status"] == "failed"
        @test s.message_history[end]["response_code"] == 400
    end
    
    @testset "send_trade_notification function" begin
        s = MockTelegramStrategy()
        s.telegram_config.enabled = true
        s.telegram_config.bot_token = "valid_token"
        s.telegram_config.chat_id = "valid_chat"
        
        ii = MockBTCUSDT()
        
        # Mock trade data
        trade_data = Dict(
            "side" => "BUY",
            "amount" => 0.1,
            "price" => 50000.0,
            "timestamp" => now(),
            "order_id" => "order_123"
        )
        
        # Mock the send_trade_notification function
        function send_trade_notification(s::MockTelegramStrategy, ii::MockInstrumentInstance, trade_data::Dict)
            if !s.notification_settings[:trades]
                return false
            end
            
            side_emoji = trade_data["side"] == "BUY" ? "🟢" : "🔴"
            
            message = """
            $side_emoji **Trade Executed**
            
            **Instrument:** $(ii.symbol)
            **Side:** $(trade_data["side"])
            **Amount:** $(trade_data["amount"])
            **Price:** \$$(trade_data["price"])
            **Value:** \$$(trade_data["amount"] * trade_data["price"])
            **Time:** $(trade_data["timestamp"])
            **Order ID:** $(trade_data["order_id"])
            """
            
            return send_telegram_notification(s, message, :trades)
        end
        
        # Test trade notification
        result = send_trade_notification(s, ii, trade_data)
        @test result == true
        @test length(s.message_history) == 1
        @test contains(s.message_history[1]["message"], "Trade Executed")
        @test contains(s.message_history[1]["message"], "BTC/USDT")
        @test contains(s.message_history[1]["message"], "BUY")
        @test contains(s.message_history[1]["message"], "0.1")
        @test contains(s.message_history[1]["message"], "50000.0")
        
        # Test with disabled trade notifications
        s.notification_settings[:trades] = false
        result_disabled = send_trade_notification(s, ii, trade_data)
        @test result_disabled == false
        @test length(s.message_history) == 1  # No new message
        
        # Test sell trade
        s.notification_settings[:trades] = true
        sell_trade_data = merge(trade_data, Dict("side" => "SELL"))
        result_sell = send_trade_notification(s, ii, sell_trade_data)
        @test result_sell == true
        @test contains(s.message_history[end]["message"], "🔴")
        @test contains(s.message_history[end]["message"], "SELL")
    end
    
    @testset "send_error_notification function" begin
        s = MockTelegramStrategy()
        s.telegram_config.enabled = true
        s.telegram_config.bot_token = "valid_token"
        s.telegram_config.chat_id = "valid_chat"
        
        # Mock the send_error_notification function
        function send_error_notification(s::MockTelegramStrategy, error_msg::String, 
                                       error_type::String = "ERROR", 
                                       context::Dict = Dict())
            
            if !s.notification_settings[:errors]
                return false
            end
            
            severity_emoji = if error_type == "CRITICAL"
                "🚨"
            elseif error_type == "WARNING"
                "⚠️"
            else
                "❌"
            end
            
            message = """
            $severity_emoji **$(error_type)**
            
            **Strategy:** $(s.config.strategy_id)
            **Error:** $error_msg
            **Time:** $(now())
            """
            
            if !isempty(context)
                message *= "\n**Context:**\n"
                for (key, value) in context
                    message *= "• $key: $value\n"
                end
            end
            
            return send_telegram_notification(s, message, :errors)
        end
        
        # Test error notification
        result = send_error_notification(s, "Connection timeout", "ERROR")
        @test result == true
        @test length(s.message_history) == 1
        @test contains(s.message_history[1]["message"], "❌")
        @test contains(s.message_history[1]["message"], "Connection timeout")
        @test contains(s.message_history[1]["message"], "test_strategy")
        
        # Test critical error
        context = Dict("exchange" => "binance", "asset" => "BTC/USDT")
        result_critical = send_error_notification(s, "Exchange connection lost", "CRITICAL", context)
        @test result_critical == true
        @test contains(s.message_history[end]["message"], "🚨")
        @test contains(s.message_history[end]["message"], "CRITICAL")
        @test contains(s.message_history[end]["message"], "exchange: binance")
        @test contains(s.message_history[end]["message"], "asset: BTC/USDT")
        
        # Test warning
        result_warning = send_error_notification(s, "High latency detected", "WARNING")
        @test result_warning == true
        @test contains(s.message_history[end]["message"], "⚠️")
        @test contains(s.message_history[end]["message"], "WARNING")
        
        # Test with disabled error notifications
        s.notification_settings[:errors] = false
        result_disabled = send_error_notification(s, "Test error", "ERROR")
        @test result_disabled == false
    end
    
    @testset "send_performance_update function" begin
        s = MockTelegramStrategy()
        s.telegram_config.enabled = true
        s.telegram_config.bot_token = "valid_token"
        s.telegram_config.chat_id = "valid_chat"
        
        # Mock performance data
        performance_data = Dict(
            "total_return" => 0.15,
            "daily_return" => 0.02,
            "win_rate" => 0.65,
            "total_trades" => 45,
            "winning_trades" => 29,
            "max_drawdown" => -0.08,
            "sharpe_ratio" => 1.25,
            "current_balance" => 11500.0,
            "period" => "24h"
        )
        
        # Mock the send_performance_update function
        function send_performance_update(s::MockTelegramStrategy, performance_data::Dict)
            if !s.notification_settings[:performance]
                return false
            end
            
            total_return_pct = performance_data["total_return"] * 100
            daily_return_pct = performance_data["daily_return"] * 100
            win_rate_pct = performance_data["win_rate"] * 100
            max_drawdown_pct = abs(performance_data["max_drawdown"]) * 100
            
            return_emoji = total_return_pct >= 0 ? "📈" : "📉"
            
            message = """
            $return_emoji **Performance Update ($(performance_data["period"]))**
            
            **Strategy:** $(s.config.strategy_id)
            **Total Return:** $(round(total_return_pct, digits=2))%
            **Daily Return:** $(round(daily_return_pct, digits=2))%
            **Current Balance:** \$$(performance_data["current_balance"])
            
            **Trading Stats:**
            • Win Rate: $(round(win_rate_pct, digits=1))%
            • Total Trades: $(performance_data["total_trades"])
            • Winning Trades: $(performance_data["winning_trades"])
            • Max Drawdown: $(round(max_drawdown_pct, digits=2))%
            • Sharpe Ratio: $(round(performance_data["sharpe_ratio"], digits=2))
            
            **Time:** $(now())
            """
            
            return send_telegram_notification(s, message, :performance)
        end
        
        # Test performance update
        result = send_performance_update(s, performance_data)
        @test result == true
        @test length(s.message_history) == 1
        @test contains(s.message_history[1]["message"], "📈")  # Positive return
        @test contains(s.message_history[1]["message"], "Performance Update")
        @test contains(s.message_history[1]["message"], "15.0%")  # Total return
        @test contains(s.message_history[1]["message"], "2.0%")   # Daily return
        @test contains(s.message_history[1]["message"], "65.0%")  # Win rate
        @test contains(s.message_history[1]["message"], "45")     # Total trades
        @test contains(s.message_history[1]["message"], "8.0%")   # Max drawdown
        @test contains(s.message_history[1]["message"], "1.25")   # Sharpe ratio
        
        # Test with negative performance
        negative_performance = merge(performance_data, Dict(
            "total_return" => -0.05,
            "daily_return" => -0.01
        ))
        
        result_negative = send_performance_update(s, negative_performance)
        @test result_negative == true
        @test contains(s.message_history[end]["message"], "📉")  # Negative return
        @test contains(s.message_history[end]["message"], "-5.0%")
        
        # Test with disabled performance notifications
        s.notification_settings[:performance] = false
        result_disabled = send_performance_update(s, performance_data)
        @test result_disabled == false
    end
    
    @testset "Telegram status and configuration" begin
        s = MockTelegramStrategy()
        
        # Mock status functions
        function is_telegram_available(s::MockTelegramStrategy)
            return s.telegram_config.enabled && 
                   !isempty(s.telegram_config.bot_token) && 
                   !isempty(s.telegram_config.chat_id)
        end
        
        function get_telegram_status(s::MockTelegramStrategy)
            return Dict(
                "enabled" => s.telegram_config.enabled,
                "configured" => !isempty(s.telegram_config.bot_token) && !isempty(s.telegram_config.chat_id),
                "bot_username" => s.telegram_config.username,
                "messages_sent" => length(s.message_history),
                "last_message" => isempty(s.message_history) ? nothing : s.message_history[end]["timestamp"]
            )
        end
        
        function stop_telegram(s::MockTelegramStrategy)
            if s.telegram_config.enabled
                # Send shutdown message
                shutdown_msg = "🛑 Strategy $(s.config.strategy_id) shutting down"
                send_telegram_notification(s, shutdown_msg, :general)
                
                s.telegram_config.enabled = false
                return true
            end
            return false
        end
        
        # Test initial status
        @test !is_telegram_available(s)
        
        status = get_telegram_status(s)
        @test status["enabled"] == false
        @test status["configured"] == false
        @test status["messages_sent"] == 0
        @test status["last_message"] === nothing
        
        # Test after configuration
        s.telegram_config.enabled = true
        s.telegram_config.bot_token = "test_token"
        s.telegram_config.chat_id = "test_chat"
        s.telegram_config.username = "test_bot"
        
        @test is_telegram_available(s)
        
        status_configured = get_telegram_status(s)
        @test status_configured["enabled"] == true
        @test status_configured["configured"] == true
        @test status_configured["bot_username"] == "test_bot"
        
        # Send a test message
        send_telegram_notification(s, "Test message", :general)
        
        status_with_message = get_telegram_status(s)
        @test status_with_message["messages_sent"] == 1
        @test status_with_message["last_message"] !== nothing
        
        # Test stop
        result_stop = stop_telegram(s)
        @test result_stop == true
        @test !s.telegram_config.enabled
        @test length(s.message_history) == 2  # Test message + shutdown message
        @test contains(s.message_history[end]["message"], "shutting down")
        
        # Test stop when already stopped
        result_stop_again = stop_telegram(s)
        @test result_stop_again == false
    end
    
    @testset "Notification cooldown and rate limiting" begin
        s = MockTelegramStrategy()
        s.telegram_config.enabled = true
        s.telegram_config.bot_token = "valid_token"
        s.telegram_config.chat_id = "valid_chat"
        
        # Mock rate limiting
        last_notification_times = Dict{Symbol, DateTime}()
        
        function send_telegram_notification_with_cooldown(s::MockTelegramStrategy, message::String, 
                                                        notification_type::Symbol = :general)
            
            cooldown = s.config.notification_cooldown
            current_time = now()
            
            # Check cooldown
            if haskey(last_notification_times, notification_type)
                time_since_last = current_time - last_notification_times[notification_type]
                if time_since_last < cooldown
                    return false  # Still in cooldown
                end
            end
            
            # Send notification
            result = send_telegram_notification(s, message, notification_type)
            
            if result
                last_notification_times[notification_type] = current_time
            end
            
            return result
        end
        
        # Test first message (should succeed)
        result1 = send_telegram_notification_with_cooldown(s, "First message", :errors)
        @test result1 == true
        
        # Test immediate second message (should fail due to cooldown)
        result2 = send_telegram_notification_with_cooldown(s, "Second message", :errors)
        @test result2 == false
        @test length(s.message_history) == 1  # Only first message sent
        
        # Test different notification type (should succeed)
        result3 = send_telegram_notification_with_cooldown(s, "Trade message", :trades)
        @test result3 == true
        @test length(s.message_history) == 2
        
        # Test after cooldown period (mock by updating last notification time)
        last_notification_times[:errors] = now() - Minute(10)  # Simulate time passing
        result4 = send_telegram_notification_with_cooldown(s, "After cooldown", :errors)
        @test result4 == true
        @test length(s.message_history) == 3
    end
end

println("✓ Telegram integration tests completed")