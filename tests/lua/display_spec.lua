local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"
local display = require('consolelog.display.display')
local parser = require('consolelog.processing.parser')
local formatter = require('consolelog.processing.formatter')
local constants = require('consolelog.core.constants')

describe("Display Module", function()
  local test_bufnr
  local consolelog_mock

  local function setup()
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'console.log("test1");',
      'console.log("test2");',
      'console.log("test3");',
      'console.log("test4");',
      'console.log("test5");'
    })
    vim.bo[test_bufnr].filetype = "javascript"

    consolelog_mock = {
      namespace = vim.api.nvim_create_namespace("consolelog_test"),
      outputs = {},
      config = {
        enabled = true,
        display = {
          virtual_text_pos = "eol",
          highlight = "ConsoleLogOutput",
          throttle_ms = 50,
          max_width = 120,
          truncate_marker = "..."
        },
        history = {
          enabled = false
        }
      }
    }
    package.loaded['consolelog'] = consolelog_mock
    display.extmarks = {}
    display.pending_updates = {}
    display.throttle_timers = {}
    display.tracked_buffers = {}
  end

  describe("Core functions", function()
    it("should have show_outputs function", function()
      assert.not_nil(display.show_outputs, "show_outputs should exist")
      assert.equals(type(display.show_outputs), "function", "show_outputs should be a function")
    end)

    it("should have clear_buffer function", function()
      assert.not_nil(display.clear_buffer, "clear_buffer should exist")
      assert.equals(type(display.clear_buffer), "function", "clear_buffer should be a function")
    end)

    it("should have update_output function", function()
      assert.not_nil(display.update_output, "update_output should exist")
      assert.equals(type(display.update_output), "function", "update_output should be a function")
    end)

    it("should have render_output function", function()
      assert.not_nil(display.render_output, "render_output should exist")
      assert.equals(type(display.render_output), "function", "render_output should be a function")
    end)

    it("should have toggle_output_window function", function()
      assert.not_nil(display.toggle_output_window, "toggle_output_window should exist")
      assert.equals(type(display.toggle_output_window), "function", "toggle_output_window should be a function")
    end)
  end)

  describe("Constants usage", function()
    it("should use constants from core/constants.lua", function()
      assert.not_nil(constants.DISPLAY, "DISPLAY constants should exist")
      assert.equals(constants.DISPLAY.THROTTLE_MIN_MS, 100, "THROTTLE_MIN_MS should be 100")
      assert.equals(constants.DISPLAY.EXTMARK_PRIORITY, 100, "EXTMARK_PRIORITY should be 100")
      assert.equals(constants.DISPLAY.DEFAULT_THROTTLE_MS, 50, "DEFAULT_THROTTLE_MS should be 50")
      assert.equals(constants.DISPLAY.WINDOW_WIDTH_RATIO, 0.8, "WINDOW_WIDTH_RATIO should be 0.8")
      assert.equals(constants.DISPLAY.WINDOW_HEIGHT_RATIO, 0.6, "WINDOW_HEIGHT_RATIO should be 0.6")
      assert.equals(constants.DISPLAY.DEFAULT_HISTORY_MAX, 100, "DEFAULT_HISTORY_MAX should be 100")
    end)
  end)

  describe("Output rendering", function()
    it("should render output with correct highlight", function()
      setup()

      local output = {
        line = 1,
        value = "test",
        console_type = "log",
        type = "string"
      }

      display.render_output(test_bufnr, output)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 1, "Should create one extmark")
    end)

    it("should get correct highlight for console type", function()
      setup()

      local test_cases = {
        { type = "log", expected = "ConsoleLogOutput" },
        { type = "error", expected = "ConsoleLogError" },
        { type = "warn", expected = "ConsoleLogWarning" },
        { type = "info", expected = "ConsoleLogInfo" },
        { type = "debug", expected = "ConsoleLogDebug" },
      }

      for _, test in ipairs(test_cases) do
        local highlight = display.get_highlight_for_type(test.type)
        assert.equals(highlight, test.expected, "Should get correct highlight for " .. test.type)
      end
    end)

    it("should handle invalid line numbers gracefully", function()
      setup()

      local output = {
        line = 999,
        value = "test",
        console_type = "log",
        type = "string"
      }

      display.render_output(test_bufnr, output)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 0, "Should not create extmark for invalid line")
    end)

    it("should handle negative line numbers gracefully", function()
      setup()

      local output = {
        line = -1,
        value = "test",
        console_type = "log",
        type = "string"
      }

      display.render_output(test_bufnr, output)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 0, "Should not create extmark for negative line")
    end)

    it("should use correct priority from config", function()
      setup()

      consolelog_mock.config.display.priority = 250

      local output = {
        line = 1,
        value = "test",
        console_type = "log",
        type = "string"
      }

      display.render_output(test_bufnr, output)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        { details = true }
      )
      assert.equals(#extmarks, 1, "Should create one extmark")
      assert.equals(extmarks[1][4].priority, 250, "Should use priority from config")
    end)
  end)

  describe("Buffer management", function()
    it("should clear buffer", function()
      setup()

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test1" },
        { line = 2, value = "test2" }
      }

      display.clear_buffer(test_bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 0, "Should clear all extmarks")
    end)

    it("should clear tracked buffers completely", function()
      setup()

      display.tracked_buffers[test_bufnr] = true
      display.clear_buffer_completely(test_bufnr)

      assert.is_nil(display.tracked_buffers[test_bufnr], "Should clear tracked buffer")
    end)

    it("should clear all buffers", function()
      setup()
      local buf2 = vim.api.nvim_create_buf(false, true)

      display.tracked_buffers[test_bufnr] = true
      display.tracked_buffers[buf2] = true
      display.extmarks[test_bufnr] = {1, 2}
      display.extmarks[buf2] = {3, 4}

      display.clear_all()

      assert.equals(vim.tbl_count(display.tracked_buffers), 0, "Should clear all tracked buffers")
      assert.equals(vim.tbl_count(display.extmarks), 0, "Should clear all extmarks")
    end)

    it("should track buffers with outputs", function()
      setup()

      assert.is_false(display.is_tracked_buffer(test_bufnr), "Should not be tracked initially")

      display.update_output(test_bufnr, 1, "test", "log")

      assert.is_true(display.is_tracked_buffer(test_bufnr), "Should be tracked after update")
    end)

    it("should accept output for python buffers via update_output", function()
      setup()
      vim.bo[test_bufnr].filetype = "python"
      consolelog_mock.outputs[test_bufnr] = {}

      display.update_output(test_bufnr, 1, "hello from python", "log")

      assert.is_true(display.is_tracked_buffer(test_bufnr), "Python buffer should be tracked")
    end)

    it("should allow tracked single-file buffers outside project root", function()
      setup()
      -- Set a project root that does NOT contain the buffer path
      consolelog_mock.project_root = "/home/user/my-js-project"
      vim.api.nvim_buf_set_name(test_bufnr, "/tmp/standalone.py")
      vim.bo[test_bufnr].filetype = "python"
      consolelog_mock.outputs[test_bufnr] = {}

      -- Register the buffer as an explicitly run single-file session
      local inspector_mock = {
        single_file_buffers = { [test_bufnr] = "/tmp/standalone.py" },
      }
      package.loaded["consolelog.communication.inspector"] = inspector_mock

      display.update_output(test_bufnr, 1, "output from standalone", "log")

      assert.is_true(display.is_tracked_buffer(test_bufnr),
        "Tracked single-file buffer should receive output despite being outside project root")

      -- Cleanup
      package.loaded["consolelog.communication.inspector"] = nil
      consolelog_mock.project_root = nil
    end)

    it("should discard non-tracked buffers outside project root", function()
      setup()
      consolelog_mock.project_root = "/home/user/my-js-project"
      local bufnr2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr2, "/tmp/untracked.py")
      vim.bo[bufnr2].filetype = "python"
      consolelog_mock.outputs[bufnr2] = {}

      -- NOT registered in single_file_buffers — should be discarded
      local inspector_mock = {
        single_file_buffers = {},
      }
      package.loaded["consolelog.communication.inspector"] = inspector_mock

      display.update_output(bufnr2, 1, "should be discarded", "log")

      assert.is_false(display.is_tracked_buffer(bufnr2),
        "Non-tracked buffer outside project root should not receive output")

      -- Cleanup
      package.loaded["consolelog.communication.inspector"] = nil
      consolelog_mock.project_root = nil
    end)
  end)

  describe("History management", function()
    it("should add to history when enabled", function()
      setup()
      consolelog_mock.config.history.enabled = true
      consolelog_mock.outputs[test_bufnr] = {}

      display.update_output(test_bufnr, 1, "test1", "log")
      display.apply_pending_updates(test_bufnr)

      display.update_output(test_bufnr, 1, "test2", "log")
      display.apply_pending_updates(test_bufnr)

      local output = consolelog_mock.outputs[test_bufnr][1]
      assert.equals(output.execution_count, 2, "Should increment execution count")
      assert.not_nil(output.history, "Should have history")
      assert.equals(#output.history, 2, "Should have 2 history entries")
    end)

    it("should limit history size", function()
      setup()
      consolelog_mock.config.history.enabled = true
      consolelog_mock.config.history.max_entries = 3
      consolelog_mock.outputs[test_bufnr] = {}

      for i = 1, 10 do
        display.update_output(test_bufnr, 1, "test" .. i, "log")
        display.apply_pending_updates(test_bufnr)
      end

      local output = consolelog_mock.outputs[test_bufnr][1]
      assert.equals(#output.history, 3, "Should limit history to max_entries")
    end)

    it("should use default history max when not configured", function()
      setup()
      consolelog_mock.config.history.enabled = true
      consolelog_mock.outputs[test_bufnr] = {}

      for i = 1, 150 do
        display.update_output(test_bufnr, 1, "test" .. i, "log")
        display.apply_pending_updates(test_bufnr)
      end

      local output = consolelog_mock.outputs[test_bufnr][1]
      assert.equals(#output.history, constants.DISPLAY.DEFAULT_HISTORY_MAX, "Should use default max")
    end)
  end)

  describe("Sorted insertion", function()
    it("should maintain sorted order when inserting outputs", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      display.update_output(test_bufnr, 5, "test5", "log")
      display.apply_pending_updates(test_bufnr)

      display.update_output(test_bufnr, 2, "test2", "log")
      display.apply_pending_updates(test_bufnr)

      display.update_output(test_bufnr, 8, "test8", "log")
      display.apply_pending_updates(test_bufnr)

      display.update_output(test_bufnr, 1, "test1", "log")
      display.apply_pending_updates(test_bufnr)

      local outputs = consolelog_mock.outputs[test_bufnr]
      assert.equals(#outputs, 4, "Should have 4 outputs")
      assert.equals(outputs[1].line, 1, "First output should be line 1")
      assert.equals(outputs[2].line, 2, "Second output should be line 2")
      assert.equals(outputs[3].line, 5, "Third output should be line 5")
      assert.equals(outputs[4].line, 8, "Fourth output should be line 8")
    end)

    it("should update existing output at same line", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      display.update_output(test_bufnr, 5, "test5_v1", "log")
      display.apply_pending_updates(test_bufnr)

      display.update_output(test_bufnr, 5, "test5_v2", "log")
      display.apply_pending_updates(test_bufnr)

      local outputs = consolelog_mock.outputs[test_bufnr]
      assert.equals(#outputs, 1, "Should have only 1 output")
      assert.equals(outputs[1].value, "test5_v2", "Should update to new value")
    end)
  end)

  describe("Update output", function()
    it("should handle pending updates", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      display.update_output(test_bufnr, 1, "test value", "log")

      assert.not_nil(display.pending_updates, "Should have pending updates table")

      display.apply_pending_updates(test_bufnr)

      assert.not_nil(consolelog_mock.outputs[test_bufnr], "Should create outputs for buffer")
      assert.equals(#consolelog_mock.outputs[test_bufnr], 1, "Should have one output")
    end)

    it("should store console type correctly", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      display.update_output(test_bufnr, 1, "error message", "error")
      display.apply_pending_updates(test_bufnr)

      local output = consolelog_mock.outputs[test_bufnr][1]
      assert.equals(output.console_type, "error", "Should store error type")
    end)

    it("should handle raw_value parameter", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      local raw_obj = {foo = "bar", baz = 123}
      display.update_output(test_bufnr, 1, "formatted", "log", raw_obj)
      display.apply_pending_updates(test_bufnr)

      local output = consolelog_mock.outputs[test_bufnr][1]
      assert.not_nil(output.raw_value, "Should have raw_value")
      assert.equals(output.raw_value.foo, "bar", "Should preserve raw_value")
    end)

    it("should handle array raw_value", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      local raw_array = {"a", "b", "c"}
      display.update_output(test_bufnr, 1, "formatted", "log", raw_array)
      display.apply_pending_updates(test_bufnr)

      local output = consolelog_mock.outputs[test_bufnr][1]
      assert.not_nil(output.raw_value, "Should have raw_value")
      assert.equals(output.type, "array", "Should detect array type")
    end)
  end)

  describe("Show outputs", function()
    it("should show outputs for buffer", function()
      setup()
      consolelog_mock.config.enabled = true

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test1", console_type = "log", type = "string" },
        { line = 2, value = "test2", console_type = "error", type = "string" }
      }

      display.show_outputs(test_bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 2, "Should create extmarks for all outputs")
    end)

    it("should handle empty outputs", function()
      setup()
      consolelog_mock.outputs[test_bufnr] = {}

      display.show_outputs(test_bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 0, "Should not create extmarks for empty outputs")
    end)

    it("should handle non-supported buffers", function()
      setup()
      vim.bo[test_bufnr].filetype = "markdown"

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test", console_type = "log", type = "string" }
      }

      display.show_outputs(test_bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 0, "Should not show outputs for unsupported buffer")
    end)

    it("should show outputs for python buffers", function()
      setup()
      vim.bo[test_bufnr].filetype = "python"

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test", console_type = "log", type = "string" }
      }

      display.show_outputs(test_bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 1, "Should show outputs for python buffer")
    end)

    it("should prevent recursive calls with flag", function()
      setup()
      consolelog_mock.config.enabled = true

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test", console_type = "log", type = "string" }
      }

      display.showing_outputs = true
      display.show_outputs(test_bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(
        test_bufnr,
        consolelog_mock.namespace,
        0,
        -1,
        {}
      )
      assert.equals(#extmarks, 0, "Should prevent recursive calls")

      display.showing_outputs = false
    end)
  end)

  describe("Parser integration", function()
    it("should format output using formatter", function()
      setup()

      local value = "test"
      local formatted = formatter.format_for_inline(value, consolelog_mock.config)
      assert.not_nil(formatted, "Should format output")
      assert.is_true(formatted:find("test") ~= nil, "Should contain the value")
    end)

    it("should detect value types", function()
      local test_cases = {
        { value = '["a", "b"]', expected = "array" },
        { value = '{"key": "value"}', expected = "object" },
        { value = '"string"', expected = "string" },
        { value = '123', expected = "number" },
        { value = 'true', expected = "boolean" },
        { value = 'null', expected = "null" },
      }

      for _, test in ipairs(test_cases) do
        local type = parser.detect_value_type(test.value)
        assert.equals(type, test.expected, "Should detect " .. test.expected)
      end
    end)
  end)

  describe("Error handling", function()
    it("should handle invalid buffer gracefully", function()
      setup()
      local invalid_buf = 99999

      local output = {
        line = 1,
        value = "test",
        console_type = "log",
        type = "string"
      }

      display.render_output(invalid_buf, output)
    end)

    it("should reset showing_outputs flag on error", function()
      setup()
      vim.bo[test_bufnr].filetype = "javascript"

      local original_config = consolelog_mock.config.enabled
      consolelog_mock.config.enabled = true

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test", console_type = "log", type = "string" }
      }

      display.showing_outputs = false
      display.show_outputs(test_bufnr)

      assert.is_false(display.showing_outputs, "Flag should be reset after show_outputs completes")

      consolelog_mock.config.enabled = original_config
    end)
  end)

  describe("Throttling", function()
    it("should throttle rapid show_outputs calls", function()
      setup()
      vim.bo[test_bufnr].filetype = "javascript"

      consolelog_mock.outputs[test_bufnr] = {
        { line = 1, value = "test", console_type = "log", type = "string" }
      }

      display.show_outputs(test_bufnr)

      local first_time = display.last_show_time[test_bufnr]
      assert.not_nil(first_time, "Should record show time")

      display.show_outputs(test_bufnr)

      assert.equals(display.last_show_time[test_bufnr], first_time, "Should throttle rapid calls")
    end)
  end)
end)
