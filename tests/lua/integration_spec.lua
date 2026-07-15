local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("Integration Tests", function()
  local consolelog
  local test_bufnr
  local test_counter = 0
  
  -- Setup before each test
  local function setup()
    -- Load the main module
    consolelog = require('consolelog.core.init')
    
    -- Set project root to /tmp so test buffers are considered in-project.
    -- Resolve symlinks (e.g. /tmp -> /private/tmp on macOS) so the root
    -- matches the buffer name that nvim_buf_set_name normalises.
    consolelog.project_root = vim.fn.resolve("/tmp")

    -- Create test buffer with unique name
    test_counter = test_counter + 1
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(test_bufnr, string.format("/tmp/test_%d.js", test_counter))
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'console.log("test1");',
      'console.log("test2");',
      'console.error("error");',
      'console.warn("warning");'
    })
    vim.bo[test_bufnr].filetype = "javascript"
  end
  
  describe("Module initialization", function()
    it("should load consolelog module", function()
      setup()
      assert.not_nil(consolelog, "Should load consolelog module")
      assert.equals(type(consolelog), "table", "Module should be a table")
    end)
    
    it("should have core functions", function()
      setup()
      assert.not_nil(consolelog.setup, "Should have setup function")
      assert.not_nil(consolelog.enable, "Should have enable function")
      assert.not_nil(consolelog.disable, "Should have disable function")
      assert.not_nil(consolelog.toggle, "Should have toggle function")
      assert.not_nil(consolelog.clear, "Should have clear function")
    end)
    
    it("should have configuration", function()
      setup()
      assert.not_nil(consolelog.config, "Should have config")
      assert.equals(type(consolelog.config), "table", "Config should be a table")
    end)
  end)
  
  describe("Enable/Disable functionality", function()
    it("should enable and disable", function()
      setup()
      
      -- Enable
      consolelog.enable()
      assert.is_true(consolelog.config.enabled, "Should be enabled")
      
      -- Disable
      consolelog.disable()
      assert.is_false(consolelog.config.enabled, "Should be disabled")
    end)
    
    it("should toggle state", function()
      setup()
      
      local initial = consolelog.config.enabled
      consolelog.toggle()
      assert.not_equals(consolelog.config.enabled, initial, "Should toggle state")
      
      consolelog.toggle()
      assert.equals(consolelog.config.enabled, initial, "Should toggle back")
    end)
  end)
  
  describe("Output management", function()
    it("should initialize outputs table", function()
      setup()
      assert.not_nil(consolelog.outputs, "Should have outputs table")
      assert.equals(type(consolelog.outputs), "table", "Outputs should be a table")
    end)
    
    it("should clear outputs", function()
      setup()
      
      -- Add some outputs
      consolelog.outputs[test_bufnr] = {
        { line = 1, value = "test" }
      }
      
      -- Clear
      consolelog.clear()
      
      -- Check cleared
      assert.equals(vim.tbl_count(consolelog.outputs), 0, "Should clear all outputs")
    end)
  end)
  
  describe("Commands", function()
    it("should have setup function", function()
      setup()
      
      local commands = require('consolelog.core.commands')
      assert.not_nil(commands.setup, "Should have setup function")
    end)
  end)
  
  describe("Utils", function()
    it("should have utility functions", function()
      local utils = require('consolelog.core.utils')
      
      assert.not_nil(utils.is_javascript_file, "Should have is_javascript_file")
      assert.not_nil(utils.is_javascript_buffer, "Should have is_javascript_buffer")
      assert.not_nil(utils.strip_ansi, "Should have strip_ansi")
    end)
    
    it("should detect JavaScript files", function()
      local utils = require('consolelog.core.utils')
      
      local js_files = {
        "test.js",
        "test.jsx",
        "test.ts",
        "test.tsx",
        "test.mts",
        "test.cts",
        "test.mjs",
        "test.cjs"
      }
      
      for _, file in ipairs(js_files) do
        assert.is_true(utils.is_javascript_file(file), file .. " should be detected as JS")
      end
      
      local non_js_files = {
        "test.py",
        "test.lua",
        "test.rb",
        "test.txt"
      }
      
      for _, file in ipairs(non_js_files) do
        assert.is_false(utils.is_javascript_file(file), file .. " should not be detected as JS")
      end
    end)
  end)
  
  describe("Display integration", function()
    it("should update display when output added", function()
      setup()
      
      local display = require('consolelog.display.display')
      
      -- Update output
      display.update_output(test_bufnr, 1, "test value", "log")
      
      -- Check pending updates
      assert.not_nil(display.pending_updates[test_bufnr], "Should have pending updates")
    end)
  end)
  
  describe("History integration", function()
    it("should track history when enabled", function()
      setup()
      
      -- Enable history
      consolelog.config.history = { enabled = true }
      
      -- Add output via display which now tracks history inline
      local display = require('consolelog.display.display')
      display.update_output(test_bufnr, 1, "test value", "log", "test value")
      
      -- Apply pending updates to move them to outputs
      display.apply_pending_updates(test_bufnr)

      -- Check output has history with execution count
      local outputs = consolelog.outputs[test_bufnr]
      assert.not_nil(outputs, "Should have outputs")
      assert.is_true(#outputs > 0, "Should have at least one output")
      assert.equals(outputs[1].execution_count, 1, "First execution should have count 1")
      assert.not_nil(outputs[1].history, "Should have history table")
      assert.is_true(#outputs[1].history > 0, "History should have at least one entry")
    end)
  end)
  
  describe("WebSocket to Display pipeline", function()
    it("should process console message through message_processor", function()
      setup()
      
      local message_processor = require('consolelog.processing.message_processor_impl')
      
      local message = {
        type = "console",
        method = "log",
        location = {
          file = string.format("test_%d.js", test_counter),
          line = 1
        },
        args = {"test output"}
      }
      
      -- process_message returns true when message matches a buffer
      local result = message_processor.process_message(message)
      assert.is_true(result, "Should process message and match buffer")
      
      -- Verify the output was queued
      local display = require('consolelog.display.display')
      assert.not_nil(display.pending_updates[test_bufnr],
        "Should have pending updates for the buffer")
    end)
    
    it("should handle batch messages", function()
      setup()
      vim.bo[test_bufnr].filetype = "javascript"
      
      local ws_server = require('consolelog.communication.ws_server')
      
      local batch_message = {
        type = "batch",
        messages = {
          {
            type = "console",
            method = "log",
            location = { file = string.format("test_%d.js", test_counter), line = 1 },
            args = {"message 1"}
          },
          {
            type = "console",
            method = "log",
            location = { file = string.format("test_%d.js", test_counter), line = 2 },
            args = {"message 2"}
          }
        }
      }
      
      local ok = pcall(ws_server.handle_message, vim.json.encode(batch_message))
      assert.is_true(ok, "Should handle batch message without error")
    end)
    
    it("should handle ping/pong messages", function()
      setup()
      
      local ws_server = require('consolelog.communication.ws_server')
      
      local ping_message = {
        type = "ping",
        timestamp = vim.loop.now()
      }
      
      local ok = pcall(ws_server.handle_message, vim.json.encode(ping_message))
      assert.is_true(ok, "Should handle ping message")
    end)
    
    it("should handle identify messages", function()
      setup()
      
      local ws_server = require('consolelog.communication.ws_server')
      
      local identify_message = {
        type = "identify",
        projectId = "test-project-123"
      }
      
      local ok = pcall(ws_server.handle_message, vim.json.encode(identify_message))
      assert.is_true(ok, "Should handle identify message")
    end)
  end)
  
  describe("Multi-buffer scenarios", function()
    it("should track outputs for multiple buffers", function()
      setup()
      
      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf2, "/tmp/test2.js")
      vim.api.nvim_buf_set_lines(buf2, 0, -1, false, {
        'console.log("buf2");'
      })
      vim.bo[buf2].filetype = "javascript"
      
      local display = require('consolelog.display.display')
      
      -- Both calls should not error
      display.update_output(test_bufnr, 1, "buffer 1 output", "log")
      display.update_output(buf2, 1, "buffer 2 output", "log")
      
      display.apply_pending_updates(test_bufnr)
      display.apply_pending_updates(buf2)
      
      -- Check that both buffers are tracked
      assert.is_true(display.tracked_buffers[test_bufnr] == true,
        "Should track first buffer")
      assert.is_true(display.tracked_buffers[buf2] == true,
        "Should track second buffer")

      -- Check that both buffers have outputs
      assert.not_nil(consolelog.outputs[test_bufnr],
        "Should have outputs for first buffer")
      assert.not_nil(consolelog.outputs[buf2],
        "Should have outputs for second buffer")
      assert.equals(consolelog.outputs[test_bufnr][1].value, "buffer 1 output",
        "Should retain first buffer output")
      assert.equals(consolelog.outputs[buf2][1].value, "buffer 2 output",
        "Should retain second buffer output")
      
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
    
    it("should clear specific buffer without affecting others", function()
      setup()
      
      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf2, "/tmp/test3.js")
      vim.bo[buf2].filetype = "javascript"
      
      local display = require('consolelog.display.display')
      
      consolelog.outputs[test_bufnr] = { { line = 1, value = "buf1" } }
      consolelog.outputs[buf2] = { { line = 1, value = "buf2" } }
      
      display.clear_buffer(test_bufnr)
      
      assert.not_nil(consolelog.outputs[buf2], "Should preserve buf2 outputs")
      assert.equals(#consolelog.outputs[buf2], 1, "Buf2 should still have 1 output")
      
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)
end)
