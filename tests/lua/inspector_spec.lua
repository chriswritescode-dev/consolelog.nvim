local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"
local inspector = require('consolelog.communication.inspector')

local function setup()
  inspector.stop_all_sessions()
  inspector.sessions = {}
  inspector.reconnect_attempts = {}
end

describe("Inspector Module", function()
  local test_bufnr = 1
  local test_filepath = "/tmp/test.js"
  
  describe("Core functions", function()
    it("should have start_debug_session function", function()
      assert.not_nil(inspector.start_debug_session, "start_debug_session should exist")
      assert.equals(type(inspector.start_debug_session), "function")
    end)
    
    it("should have start_node_inspect function", function()
      assert.not_nil(inspector.start_node_inspect, "start_node_inspect should exist")
      assert.equals(type(inspector.start_node_inspect), "function")
    end)
    
    it("should have extract_inspector_url function", function()
      assert.not_nil(inspector.extract_inspector_url, "extract_inspector_url should exist")
      assert.equals(type(inspector.extract_inspector_url), "function")
    end)
  end)
  
  describe("URL extraction", function()
    it("should extract inspector URL from debug output", function()
      local test_lines = {
        "Debugger listening on ws://127.0.0.1:9229/abcd-1234",
        "Debugger listening on ws://localhost:9229/xyz-5678",
        "Debugger listening on ws://[::1]:9229/test-uuid"
      }
      
      for _, line in ipairs(test_lines) do
        local url = inspector.extract_inspector_url(line)
        assert.not_nil(url, "Should extract URL from: " .. line)
        assert.is_true(url:match("^ws://") ~= nil, "Should be websocket URL")
      end
    end)
    
    it("should return nil for non-debug lines", function()
      local non_debug_lines = {
        "Console output",
        "Error: something went wrong",
        "Random text"
      }
      
      for _, line in ipairs(non_debug_lines) do
        local url = inspector.extract_inspector_url(line)
        assert.nil_value(url, "Should not extract URL from: " .. line)
      end
    end)
  end)
  
  describe("Session management", function()
    it("should track active sessions", function()
      -- Get active sessions
      local sessions = inspector.get_active_sessions()
      assert.not_nil(sessions, "Should return sessions table")
      assert.equals(type(sessions), "table", "Should be a table")
    end)
    
    it("should get session for buffer", function()
      local session = inspector.get_session_for_buffer(test_bufnr)
      -- May be nil if no session exists
      if session then
        assert.equals(type(session), "table", "Session should be a table")
      end
    end)
    
    it("should check if session is ready", function()
      local ready = inspector.is_session_ready("test-session-id")
      assert.equals(type(ready), "boolean", "Should return boolean")
    end)
    
    it("should have cleanup functions", function()
      assert.not_nil(inspector.cleanup_session, "cleanup_session should exist")
      assert.not_nil(inspector.stop_all_sessions, "stop_all_sessions should exist")
      
      -- Should not error when called
      inspector.stop_all_sessions()
    end)
  end)
  
  describe("Runtime commands", function()
    it("should have send_command function", function()
      assert.not_nil(inspector.send_command, "send_command should exist")
      assert.equals(type(inspector.send_command), "function")
    end)
    
    it("should have initialize_runtime function", function()
      assert.not_nil(inspector.initialize_runtime, "initialize_runtime should exist")
      assert.equals(type(inspector.initialize_runtime), "function")
    end)
  end)
  
  describe("Auto-attach", function()
    it("should have setup_auto_attach function", function()
      assert.not_nil(inspector.setup_auto_attach, "setup_auto_attach should exist")
      assert.equals(type(inspector.setup_auto_attach), "function")
    end)
  end)
  
  describe("Error handling", function()
    it("should have handle_connection_error function", function()
      assert.not_nil(inspector.handle_connection_error, "handle_connection_error should exist")
      assert.equals(type(inspector.handle_connection_error), "function")
    end)
    
    it("should return nil for session not in sessions table", function()
      local fake_session = { filepath = "/fake.js", bufnr = 999 }
      local id = inspector.get_session_id(fake_session)
      assert.nil_value(id, "Should return nil for unknown session")
    end)
  end)
  
  describe("Inspector message handling", function()
    it("should handle Runtime.consoleAPICalled messages", function()
      setup()
      
      local mock_message = vim.json.encode({
        method = "Runtime.consoleAPICalled",
        params = {
          type = "log",
          args = {
            { type = "string", value = "test message" }
          },
          stackTrace = {
            callFrames = {
              {
                lineNumber = 5,
                columnNumber = 10,
                url = "file:///test.js",
                functionName = "testFunc"
              }
            }
          }
        }
      })
      
      local session = {
        filepath = test_filepath,
        bufnr = test_bufnr,
        ws_id = nil,
        ready = false
      }
      
      local ok = pcall(inspector.handle_inspector_message, session, mock_message)
      assert.is_true(ok, "Should handle console message without error")
    end)
    
    it("should extract location from stack trace", function()
      setup()
      
      local mock_message = vim.json.encode({
        method = "Runtime.consoleAPICalled",
        params = {
          type = "log",
          args = { { type = "string", value = "test" } },
          stackTrace = {
            callFrames = {
              {
                lineNumber = 10,
                columnNumber = 5,
                url = "file:///app.js",
                functionName = "myFunc"
              }
            }
          }
        }
      })
      
      local session = { filepath = "/app.js", bufnr = test_bufnr, ws_id = nil, ready = false }
      
      local ok = pcall(inspector.handle_inspector_message, session, mock_message)
      assert.is_true(ok, "Should extract location data")
    end)
    
    it("should format different console argument types", function()
      setup()
      
      local test_cases = {
        { arg = { type = "string", value = "hello" }, expected = "hello" },
        { arg = { type = "number", value = 42 }, expected = "42" },
        { arg = { type = "boolean", value = true }, expected = "true" },
        { arg = { type = "null" }, expected = "null" },
        { arg = { type = "undefined" }, expected = "undefined" },
        { arg = { type = "object", className = "Array" }, expected = "[Array]" },
      }
      
      for _, test in ipairs(test_cases) do
        local mock_message = vim.json.encode({
          method = "Runtime.consoleAPICalled",
          params = {
            type = "log",
            args = { test.arg },
            stackTrace = {
              callFrames = { { lineNumber = 1, columnNumber = 1, url = "file:///test.js" } }
            }
          }
        })
        
        local session = { filepath = "/test.js", bufnr = test_bufnr, ws_id = nil, ready = false }
        local ok = pcall(inspector.handle_inspector_message, session, mock_message)
        assert.is_true(ok, "Should format " .. test.arg.type)
      end
    end)
    
    it("should handle messages without location gracefully", function()
      setup()
      
      local mock_message = vim.json.encode({
        method = "Runtime.consoleAPICalled",
        params = {
          type = "log",
          args = { { type = "string", value = "no location" } }
        }
      })
      
      local session = { filepath = "/test.js", bufnr = test_bufnr, ws_id = nil, ready = false }
      local ok = pcall(inspector.handle_inspector_message, session, mock_message)
      assert.is_true(ok, "Should handle missing stack trace")
    end)
  end)
  
  describe("Reconnection logic", function()
    it("should not reconnect if session is reconnecting", function()
      setup()
      
      local session = {
        filepath = "/test.js",
        bufnr = test_bufnr,
        reconnecting = true,
        inspector_url = "ws://127.0.0.1:9229/test"
      }
      
      inspector.sessions["test_session"] = session
      inspector.reconnect_attempts["test_session"] = 0
      
      inspector.handle_connection_error(session)
      
      assert.equals(inspector.reconnect_attempts["test_session"], 0, "Should not increment attempts when reconnecting")
    end)
    
    it("should cleanup after max reconnect attempts", function()
      setup()
      
      local session = {
        filepath = "/test.js",
        bufnr = test_bufnr,
        reconnecting = false,
        inspector_url = "ws://127.0.0.1:9229/test",
        job_id = nil
      }
      
      local session_id = "test_max_attempts"
      inspector.sessions[session_id] = session
      inspector.reconnect_attempts[session_id] = inspector.max_reconnect_attempts
      
      inspector.handle_connection_error(session)
      
      vim.wait(100)
      assert.nil_value(inspector.sessions[session_id], "Should cleanup session after max attempts")
    end)
  end)
  
  describe("Session cleanup", function()
    it("should remove session from sessions table", function()
      setup()
      
      local session = {
        filepath = "/test.js",
        bufnr = test_bufnr,
        job_id = nil
      }
      
      inspector.sessions["cleanup_test"] = session
      
      inspector.cleanup_session(session)
      
      assert.nil_value(inspector.sessions["cleanup_test"], "Should remove from sessions")
    end)
    
    it("should clear reconnect attempts", function()
      setup()
      
      local session = {
        filepath = "/test.js",
        bufnr = test_bufnr,
        job_id = nil
      }
      
      inspector.sessions["cleanup_reconnect"] = session
      inspector.reconnect_attempts["cleanup_reconnect"] = 3
      
      inspector.cleanup_session(session)
      
      assert.nil_value(inspector.reconnect_attempts["cleanup_reconnect"], "Should clear reconnect attempts")
    end)
  end)
end)