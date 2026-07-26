local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

-- Skip if python3 is not available
if vim.fn.executable("python3") == 0 then
  print("SKIP: python3 not available, skipping python_capture_spec")
  return
end

local SENTINEL = "__CONSOLELOG_EVENT__"
local SPEC_TARGET = "/tmp/consolelog_py_spec_target.py"

local function write_target(content)
  local f = io.open(SPEC_TARGET, "w")
  f:write(content)
  f:close()
end

local function parse_events(output)
  local events = {}
  for line in output:gmatch("[^\n]+") do
    -- Find sentinel anywhere in the line (not just at start) because
    -- vim.fn.system merges stderr and stdout, so real stderr content
    -- may precede the sentinel on the same line.
    local sentinel_pos = line:find(SENTINEL, 1, true)
    if sentinel_pos then
      local json_str = line:sub(sentinel_pos + #SENTINEL)
      local ok, event = pcall(vim.json.decode, json_str)
      if ok and event then
        table.insert(events, event)
      end
    end
  end
  return events
end

local function find_event(events, matcher)
  for _, event in ipairs(events) do
    if matcher(event) then
      return event
    end
  end
  return nil
end

describe("Python Capture Spec", function()
  it("should capture print, logging, stderr, and exception events", function()
    write_target([[
import logging, sys
print("hello", 42)
print({"a": 1, "b": 2})
logging.warning("warned")
sys.stderr.write("raw stderr\n")
x = 1 / 0
]])

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    -- console/log event from print("hello", 42) on line 2
    local print_hello = find_event(events, function(e)
      return e.event == "console" and e.method == "log" and e.line == 2
    end)
    assert.not_nil(print_hello, "Should capture print('hello', 42) event")
    assert.equals(print_hello.args[1], "hello", "First arg should be 'hello'")
    assert.equals(print_hello.args[2], 42, "Second arg should be 42")
    assert.is_true(print_hello.file:find("consolelog_py_spec_target%.py$") ~= nil,
      "File should end with 'consolelog_py_spec_target.py'")

    -- console/log event from print({"a": 1, "b": 2}) on line 3
    local print_dict = find_event(events, function(e)
      return e.event == "console" and e.method == "log" and e.line == 3
    end)
    assert.not_nil(print_dict, "Should capture print(dict) event")
    assert.is_true(type(print_dict.args[1]) == "table", "Dict arg should be a table")
    assert.equals(print_dict.args[1].a, 1, "Dict key 'a' should be 1")
    assert.equals(print_dict.args[1].b, 2, "Dict key 'b' should be 2")

    -- console/warn event from logging.warning on line 4
    local log_warn = find_event(events, function(e)
      return e.event == "console" and e.method == "warn" and e.line == 4
    end)
    assert.not_nil(log_warn, "Should capture logging.warning event")
    assert.equals(log_warn.args[1], "warned", "Warning message should be 'warned'")

    -- console/error event from stderr.write on line 5
    local stderr_event = find_event(events, function(e)
      return e.event == "console" and e.method == "error" and e.line == 5
    end)
    assert.not_nil(stderr_event, "Should capture stderr.write event")
    assert.equals(stderr_event.args[1], "raw stderr", "Stderr content should be 'raw stderr'")

    -- exception event from ZeroDivisionError on line 6
    local exc_event = find_event(events, function(e)
      return e.event == "exception" and e.line == 6
    end)
    assert.not_nil(exc_event, "Should capture ZeroDivisionError exception event")
    assert.is_true(exc_event.text:find("ZeroDivisionError") ~= nil,
      "Exception text should contain ZeroDivisionError")
  end)

  it("should exit cleanly for programs without exceptions", function()
    write_target('print("ok")\n')

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    -- No exception event
    local exc = find_event(events, function(e)
      return e.event == "exception"
    end)
    assert.is_nil(exc, "Should not emit exception event for clean exit")

    assert.equals(vim.v.shell_error, 0, "Shell error should be 0 for clean exit")
  end)

  it("should preserve raw stdout output alongside events", function()
    write_target('print("hello", 42)\n')

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })

    -- The raw "hello 42" text should still be in the output
    assert.is_true(out:find("hello 42") ~= nil,
      "Raw stdout 'hello 42' should be preserved in output")
  end)

  it("should preserve %s literals in print events", function()
    write_target('print("rate: 100%s")\n')

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    local print_event = find_event(events, function(e)
      return e.event == "console" and e.method == "log"
    end)
    assert.not_nil(print_event, "Should capture print event")
    assert.equals(print_event.args[1], "rate: 100%s",
      "Percent-s literal should be preserved in Python print output")
  end)

  it("should not suppress buffered stderr when logging writes after", function()
    write_target([[
import sys, logging
sys.stderr.write("prefix")
logging.warning("logged")
]])

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    -- The "prefix" write has no newline, so it buffers.  Then logging writes.
    -- The buffered "prefix" must still be emitted as an error event.
    local prefix_event = find_event(events, function(e)
      return e.event == "console" and e.method == "error" and e.args[1] == "prefix"
    end)
    assert.not_nil(prefix_event,
      "Should capture 'prefix' stderr event even when logging writes after it")

    -- The logging warn event should also be present
    local warn_event = find_event(events, function(e)
      return e.event == "console" and e.method == "warn"
    end)
    assert.not_nil(warn_event, "Should capture logging.warning event")
  end)

  it("should attribute partial stderr to target line, not runner", function()
    write_target([[
import sys
sys.stderr.write("partial")
x = 1 / 0
]])

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    -- "partial" is written on line 2 of the target — the error event must
    -- carry that line number, not a line from the runner's exception handler.
    local partial_event = find_event(events, function(e)
      return e.event == "console" and e.method == "error" and e.args[1] == "partial"
    end)
    assert.not_nil(partial_event, "Should capture 'partial' stderr event")
    assert.equals(partial_event.line, 2,
      "Partial stderr should be attributed to target line 2, not runner")

    -- Exception should also be present
    local exc_event = find_event(events, function(e)
      return e.event == "exception"
    end)
    assert.not_nil(exc_event, "Should capture exception event")
  end)

  it("should attribute both fragments of complete\\npartial stderr to target line", function()
    write_target([[
import sys
sys.stderr.write("complete\npartial")
x = 1 / 0
]])

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    -- The "complete" fragment should be attributed to line 2
    local complete_event = find_event(events, function(e)
      return e.event == "console" and e.method == "error" and e.args[1] == "complete"
    end)
    assert.not_nil(complete_event, "Should capture 'complete' stderr event")
    assert.equals(complete_event.line, 2,
      "Complete stderr should be attributed to target line 2")

    -- The "partial" fragment (flushed by exception handler) should also be
    -- attributed to line 2 — the original write line — not the runner.
    local partial_event = find_event(events, function(e)
      return e.event == "console" and e.method == "error" and e.args[1] == "partial"
    end)
    assert.not_nil(partial_event, "Should capture 'partial' stderr event")
    assert.equals(partial_event.line, 2,
      "Partial stderr should be attributed to target line 2, not runner")

    -- Exception should be present
    local exc_event = find_event(events, function(e)
      return e.event == "exception"
    end)
    assert.not_nil(exc_event, "Should capture exception event")
  end)

  it("should attribute imported-module exceptions to the deepest traceback frame", function()
    -- Create an imported module that raises at a specific line
    local mod_path = "/tmp/consolelog_py_spec_failing_mod.py"
    local mf = io.open(mod_path, "w")
    mf:write("x = 1\ny = 2\nz = 1 / 0\n")
    mf:close()

    -- Target imports the module — exception originates in the module, not target
    write_target(string.format("import %s\n", mod_path:match("([^/]+)%.py$")))

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    local exc = find_event(events, function(e)
      return e.event == "exception"
    end)
    assert.not_nil(exc, "Should capture exception from imported module")
    assert.is_true(exc.text:find("ZeroDivisionError") ~= nil,
      "Exception text should contain ZeroDivisionError")
    -- The traceback includes the target's import line, so the exception should
    -- point to the target file (the import line), not the imported module.
    assert.is_true(exc.file:find("consolelog_py_spec_target%.py") ~= nil,
      "Exception file should reference the target file's import line")
    assert.equals(exc.line, 1, "Exception line should be the import line in the target")

    os.remove(mod_path)
  end)

  it("should attribute imported-module SyntaxError to the target import line", function()
    -- Create a module with a syntax error
    local mod_path = "/tmp/consolelog_py_spec_syntax_mod.py"
    local mf = io.open(mod_path, "w")
    mf:write("def foo(\n  pass\n")
    mf:close()

    local mod_name = mod_path:match("([^/]+)%.py$")
    write_target("import " .. mod_name .. "\n")

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    local exc = find_event(events, function(e)
      return e.event == "exception"
    end)
    assert.not_nil(exc, "Should capture SyntaxError from imported module")
    assert.is_true(exc.text:find("SyntaxError") ~= nil,
      "Exception text should contain SyntaxError")
    -- The traceback includes the target's import line, so the exception should
    -- point to the target file (the import line), not the imported module.
    assert.is_true(exc.file:find("consolelog_py_spec_target%.py") ~= nil,
      "Exception file should reference the target file's import line")
    assert.equals(exc.line, 1, "Exception line should be the import line in the target")

    os.remove(mod_name)
    os.remove(mod_path)
  end)

it("should not prevent basicConfig when named logger logs first", function()
    -- A target that uses a named logger with propagate=False, then calls basicConfig.
    -- The callHandlers patch must not pre-install root's default handler,
    -- which would make basicConfig a no op.
    -- Note: with propagate=False, the named logger's records never reach root,
    -- so they won't produce console events. The key test is that basicConfig
    -- still takes effect (its format appears on stderr for root logger output).
    write_target([[
import logging

logger = logging.getLogger("myns")
logger.propagate = False
logger.warning("before config")

logging.basicConfig(format="CUSTOM:%(message)s")
# Log through root logger to verify basicConfig took effect
logging.warning("after config")
]])

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    -- The root logger warning after basicConfig should produce a console event
    local root_warn = find_event(events, function(e)
      return e.event == "console" and e.method == "warn" and e.args[1] == "after config"
    end)
    assert.not_nil(root_warn, "Should capture root logger warning event")

    -- The raw stderr should contain the custom format from basicConfig,
    -- proving that basicConfig was NOT silenced by our handler bootstrap.
    assert.is_true(out:find("CUSTOM:after config") ~= nil,
      "basicConfig format should be applied — callHandlers must not pre-install root handler")
  end)

  it("should attribute target-file compile-time SyntaxError to the target line", function()
    -- The target itself has a syntax error (unmatched parenthesis on line 1)
    write_target("def foo(\n  pass\n")

    local out = vim.fn.system({ "python3", "py/consolelog_runner.py", SPEC_TARGET })
    local events = parse_events(out)

    local exc = find_event(events, function(e)
      return e.event == "exception"
    end)
    assert.not_nil(exc, "Should capture compile-time SyntaxError")
    assert.is_true(exc.text:find("SyntaxError") ~= nil,
      "Exception text should contain SyntaxError")
    assert.is_true(exc.file:find("consolelog_py_spec_target%.py") ~= nil,
      "Exception file should reference the target file")
    assert.equals(exc.line, 1,
      "Exception line should be line 1 of the target (the def with unclosed paren)")
  end)

  -- Cleanup
  os.remove(SPEC_TARGET)
end)

describe("format_args preserve_literals", function()
  local message_processor

  local function setup()
    -- Stub dependencies for real message_processor_impl
    package.loaded["consolelog.processing.line_matching"] = {
      match_by_file_and_command = function() return nil, nil, nil end,
      reset = function() end,
      get_state_info = function() return {} end,
    }
    package.loaded["consolelog.core.debug_logger"] = {
      log = function() end,
    }
    package.loaded["consolelog"] = {
      config = { websocket = { display_methods = { "log", "error", "warn" } } },
    }
    package.loaded["consolelog.display.display"] = {
      update_output = function() end,
    }
    -- Clear cached module to force fresh require
    package.loaded["consolelog.processing.message_processor_impl"] = nil
    message_processor = require("consolelog.processing.message_processor_impl")
  end

  local function teardown()
    package.loaded["consolelog.processing.line_matching"] = nil
    package.loaded["consolelog.core.debug_logger"] = nil
    package.loaded["consolelog"] = nil
    package.loaded["consolelog.display.display"] = nil
    package.loaded["consolelog.processing.message_processor_impl"] = nil
  end

  it("should strip %s from browser format strings by default", function()
    setup()
    local output = message_processor.format_args({ "rate: 100%s" }, "log")
    assert.is_true(output:find("%%s") == nil,
      "Default format_args should strip %s from browser format strings")
    teardown()
  end)

  it("should preserve %s literals when preserve_literals is true", function()
    setup()
    local output = message_processor.format_args({ "rate: 100%s" }, "log", true)
    assert.is_true(output:find("100%%s") ~= nil,
      "format_args with preserve_literals=true should keep %s in Python output")
    teardown()
  end)
end)