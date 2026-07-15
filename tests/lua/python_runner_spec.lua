local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("Python Runner", function()
  describe("parse_event", function()
    local python_runner

    local function setup()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
    end

    it("should return decoded table for valid event line", function()
      setup()
      local line = '__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":2,"args":["hi"]}'
      local result = python_runner.parse_event(line)
      assert.not_nil(result)
      assert.equals("console", result.event)
      assert.equals("log", result.method)
      assert.equals("/tmp/a.py", result.file)
      assert.equals(2, result.line)
      assert.equals("hi", result.args[1])
      teardown()
    end)

    it("should return nil for plain text line", function()
      setup()
      local result = python_runner.parse_event("just some output")
      assert.is_nil(result)
      teardown()
    end)

    it("should return nil for sentinel with malformed JSON", function()
      setup()
      local result = python_runner.parse_event('__CONSOLELOG_EVENT__{bad json')
      assert.is_nil(result)
      teardown()
    end)

    it("should return nil for sentinel with JSON missing event field", function()
      setup()
      local result = python_runner.parse_event('__CONSOLELOG_EVENT__{"method":"log"}')
      assert.is_nil(result)
      teardown()
    end)

    it("should return decoded table when raw text precedes sentinel", function()
      setup()
      local line = 'raw output__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":2,"args":["hi"]}'
      local result = python_runner.parse_event(line)
      assert.not_nil(result)
      assert.equals("console", result.event)
      assert.equals("log", result.method)
      assert.equals(2, result.line)
      teardown()
    end)
  end)

  describe("resolve_python_executable", function()
    local python_runner
    local saved_executable
    local executable_results = {}

    local function setup()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      saved_executable = vim.fn.executable
      vim.fn.executable = function(name)
        return executable_results[name] or 0
      end
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      vim.fn.executable = saved_executable
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      executable_results = {}
    end

    it("should return config override when set and executable", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = "/custom/python3" } },
      }
      executable_results["/custom/python3"] = 1
      local exe = python_runner.resolve_python_executable("/tmp/x.py")
      assert.equals("/custom/python3", exe)
      teardown()
    end)

    it("should return nil when config override not executable", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = "/nonexistent/python" } },
      }
      executable_results["/nonexistent/python"] = 0
      -- Set up VIRTUAL_ENV so it can fall through
      local saved_env = os.getenv("VIRTUAL_ENV")
      vim.env.VIRTUAL_ENV = nil
      executable_results["python3"] = 1
      local exe = python_runner.resolve_python_executable("/tmp/x.py")
      assert.equals("python3", exe)
      vim.env.VIRTUAL_ENV = saved_env
      teardown()
    end)

    it("should use VIRTUAL_ENV when set and python is executable", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      local saved_env = os.getenv("VIRTUAL_ENV")
      vim.env.VIRTUAL_ENV = "/home/user/.venv"
      executable_results["/home/user/.venv/bin/python"] = 1
      local exe = python_runner.resolve_python_executable("/tmp/x.py")
      assert.equals("/home/user/.venv/bin/python", exe)
      vim.env.VIRTUAL_ENV = saved_env
      teardown()
    end)

    it("should resolve ancestor .venv/bin/python over python3 fallback", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      local saved_env = os.getenv("VIRTUAL_ENV")
      vim.env.VIRTUAL_ENV = nil
      -- File is in /tmp/projects/src/a.py; ancestor .venv is at /tmp/projects/.venv
      executable_results["/tmp/projects/.venv/bin/python"] = 1
      executable_results["python3"] = 1
      local exe = python_runner.resolve_python_executable("/tmp/projects/src/a.py")
      assert.equals("/tmp/projects/.venv/bin/python", exe)
      vim.env.VIRTUAL_ENV = saved_env
      teardown()
    end)

    it("should fall back to python3", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      local saved_env = os.getenv("VIRTUAL_ENV")
      vim.env.VIRTUAL_ENV = nil
      executable_results["python3"] = 1
      local exe = python_runner.resolve_python_executable("/tmp/x.py")
      assert.equals("python3", exe)
      vim.env.VIRTUAL_ENV = saved_env
      teardown()
    end)

    it("should return nil error when no interpreter found", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      local saved_env = os.getenv("VIRTUAL_ENV")
      vim.env.VIRTUAL_ENV = nil
      executable_results["python3"] = 0
      local exe, err = python_runner.resolve_python_executable("/tmp/x.py")
      assert.is_nil(exe)
      assert.not_nil(err)
      assert.is_true(err:find("No Python interpreter") ~= nil)
      vim.env.VIRTUAL_ENV = saved_env
      teardown()
    end)
  end)

  describe("build_run_command", function()
    local python_runner
    local saved_executable
    local executable_results = {}
    local saved_filereadable
    local filereadable_results = {}

    local function setup()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      saved_executable = vim.fn.executable
      vim.fn.executable = function(name)
        return executable_results[name] or 0
      end
      saved_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        return filereadable_results[path] or 0
      end
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      executable_results = {}
      filereadable_results = {}
    end

    it("should return command with runner script path", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      executable_results["python3"] = 1

      -- Make the runner script path filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      filereadable_results[runner_path] = 1

      local cmd, err = python_runner.build_run_command("/tmp/x.py")
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals(3, #cmd)
      assert.equals("python3", cmd[1])
      assert.is_true(cmd[2]:match("py/consolelog_runner%.py$") ~= nil)
      assert.equals("/tmp/x.py", cmd[3])
      teardown()
    end)

    it("should find the real runner script without stubbing filereadable", function()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      local real_filereadable = vim.fn.filereadable
      local runner = require("consolelog.communication.python_runner")
      local script = runner.get_runner_script()
      vim.fn.filereadable = real_filereadable
      assert.not_nil(script, "get_runner_script() should find the real py/consolelog_runner.py")
      assert.is_true(script:match("py/consolelog_runner%.py$") ~= nil, "script path should end with py/consolelog_runner.py")
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
    end)

    it("should return nil and error when no interpreter found", function()
      setup()
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      local saved_env = os.getenv("VIRTUAL_ENV")
      vim.env.VIRTUAL_ENV = nil
      executable_results["python3"] = 0

      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      filereadable_results[runner_path] = 1

      local cmd, err = python_runner.build_run_command("/tmp/x.py")
      assert.is_nil(cmd)
      assert.not_nil(err)
      vim.env.VIRTUAL_ENV = saved_env
      teardown()
    end)
  end)

  describe("start_debug_session", function()
    local python_runner

    local function setup()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      python_runner.sessions = {}
      python_runner._intentionally_stopped_jobs = {}
    end

    it("should register session when jobstart returns positive id", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local saved_jobstart = vim.fn.jobstart
      local saved_notify = vim.notify
      vim.notify = function() end
      vim.fn.jobstart = function(cmd, opts)
        return 123
      end

      -- Make build_run_command succeed
      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local session_id = python_runner.start_debug_session("/tmp/x.py", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable

      assert.not_nil(session_id)
      assert.not_nil(python_runner.sessions[session_id])
      assert.equals("/tmp/x.py", python_runner.sessions[session_id].filepath)
      assert.equals(7, python_runner.sessions[session_id].bufnr)
      assert.equals("/tmp/x.py", inspector.single_file_buffers[7])
      teardown()
    end)

    it("should return nil when jobstart returns -1", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local saved_jobstart = vim.fn.jobstart
      local saved_notify = vim.notify
      vim.notify = function() end
      vim.fn.jobstart = function(cmd, opts)
        return -1
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local session_id = python_runner.start_debug_session("/tmp/x.py", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable

      assert.is_nil(session_id)
      assert.is_nil(inspector.single_file_buffers[7])
      teardown()
    end)
  end)

  describe("handle_event", function()
    local python_runner
    local update_output_calls

    local function setup()
      update_output_calls = {}
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function(bufnr, line, output, method, raw_value)
          table.insert(update_output_calls, {
            bufnr = bufnr,
            line = line,
            output = output,
            method = method,
            raw_value = raw_value,
          })
        end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      package.loaded["consolelog.communication.python_runner"] = nil
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.communication.python_runner"] = nil
      update_output_calls = {}
    end

    it("should call update_output for console event matching session filepath", function()
      setup()
      local session = { filepath = "/tmp/a.py", bufnr = 5 }
      local event = {
        event = "console",
        method = "log",
        file = "/tmp/a.py",
        line = 3,
        args = {"hello"},
      }
      python_runner.handle_event(session, event)
      helper.async.wait(50)
      assert.equals(1, #update_output_calls)
      assert.equals(5, update_output_calls[1].bufnr)
      assert.equals(3, update_output_calls[1].line)
      assert.equals("log", update_output_calls[1].method)
      assert.equals("hello", update_output_calls[1].output, "rendered console text should match format_args output")
      assert.equals("hello", update_output_calls[1].raw_value, "raw_value should match format_args raw_value")
      teardown()
    end)

    it("should not call update_output for event with different filepath", function()
      setup()
      local session = { filepath = "/tmp/a.py", bufnr = 5 }
      local event = {
        event = "console",
        method = "log",
        file = "/tmp/b.py",
        line = 3,
        args = {"hello"},
      }
      python_runner.handle_event(session, event)
      assert.equals(0, #update_output_calls)
      teardown()
    end)

    it("should call update_output with error method for exception event", function()
      setup()
      local session = { filepath = "/tmp/a.py", bufnr = 5 }
      local event = {
        event = "exception",
        file = "/tmp/a.py",
        line = 10,
        text = "Traceback (most recent call last):\n  File \"/tmp/a.py\", line 10\nNameError: name 'x' is not defined",
      }
      python_runner.handle_event(session, event)
      helper.async.wait(50)
      assert.equals(1, #update_output_calls)
      assert.equals(10, update_output_calls[1].line)
      assert.equals("error", update_output_calls[1].method)
      assert.equals("Traceback (most recent call last):", update_output_calls[1].output, "output should be first line of exception text")
      assert.equals("Traceback (most recent call last):\n  File \"/tmp/a.py\", line 10\nNameError: name 'x' is not defined", update_output_calls[1].raw_value, "raw_value should be full exception text")
      teardown()
    end)
  end)

  describe("intentional stop", function()
    local python_runner

    local function setup()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      python_runner.sessions = {}
      python_runner._intentionally_stopped_jobs = {}
    end

    it("should not produce ERROR notify for intentionally stopped job", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local captured_on_exit = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        captured_on_exit = opts.on_exit
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      local notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      local session_id = python_runner.start_debug_session("/tmp/x.py", 7)

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable

      assert.not_nil(session_id)

      local session = python_runner.sessions[session_id]
      assert.not_nil(session)

      python_runner.cleanup_session(session)

      captured_on_exit(123, 143)

      local error_notifications = vim.tbl_filter(function(n)
        return n.level == vim.log.levels.ERROR
      end, notify_calls)

      assert.equals(0, #error_notifications, "no error notification should be emitted for intentionally stopped job")

      vim.notify = saved_notify
      teardown()
    end)

    it("should clear Python-owned buffers from inspector.single_file_buffers on stop_all_sessions", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      python_runner.start_debug_session("/tmp/x.py", 7)
      -- Also add an unrelated inspector entry
      inspector.single_file_buffers[99] = "/tmp/other.lua"

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      vim.notify = saved_notify

      assert.equals("/tmp/x.py", inspector.single_file_buffers[7])
      assert.equals("/tmp/other.lua", inspector.single_file_buffers[99])

      python_runner.stop_all_sessions()

      assert.is_nil(inspector.single_file_buffers[7], "Python buffer should be cleared")
      assert.equals("/tmp/other.lua", inspector.single_file_buffers[99], "Unrelated inspector entry should remain")

      teardown()
    end)
  end)

  describe("stdout reassembly", function()
    local python_runner
    local update_output_calls

    local function setup()
      update_output_calls = {}
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function(bufnr, line, output, method, raw_value)
          table.insert(update_output_calls, {
            bufnr = bufnr,
            line = line,
            output = output,
            method = method,
            raw_value = raw_value,
          })
        end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      package.loaded["consolelog.communication.python_runner"] = nil
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.communication.python_runner"] = nil
      update_output_calls = {}
    end

    it("should dispatch event split across two on_stdout callbacks exactly once", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local captured_on_stdout = nil
      local captured_session = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        captured_on_stdout = opts.on_stdout
        -- Capture the run_id from the env option
        local run_id = opts.env and opts.env.CONSOLELOG_RUN_ID or "test_run"
        captured_session = { run_id = run_id }
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = python_runner.start_debug_session("/tmp/a.py", 5)

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      vim.notify = saved_notify

      assert.not_nil(session_id)
      assert.not_nil(captured_on_stdout)
      assert.not_nil(captured_session)

      -- Send one event split across two callbacks with correct run_id
      local full_event = '__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":2,"args":["hi"],"run_id":"' .. captured_session.run_id .. '"}\n'
      local mid = math.floor(#full_event / 2)
      local chunk1 = full_event:sub(1, mid)
      local chunk2 = full_event:sub(mid + 1)

      captured_on_stdout(123, { chunk1 })
      captured_on_stdout(123, { chunk2 })

      helper.async.wait(50)

      assert.equals(1, #update_output_calls, "split event should produce exactly one update_output call")
      assert.equals(5, update_output_calls[1].bufnr)
      assert.equals(2, update_output_calls[1].line)
      assert.equals("log", update_output_calls[1].method)

      teardown()
    end)

    it("should parse event when raw stdout precedes sentinel", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local captured_on_stdout = nil
      local captured_session = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        captured_on_stdout = opts.on_stdout
        local run_id = opts.env and opts.env.CONSOLELOG_RUN_ID or "test_run"
        captured_session = { run_id = run_id }
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = python_runner.start_debug_session("/tmp/a.py", 5)

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      vim.notify = saved_notify

      assert.not_nil(session_id)
      assert.not_nil(captured_on_stdout)

      -- Simulate: raw stdout ("first") written without newline, then an event
      -- (e.g. print("first", end=""); print("second"))
      local event_line = '__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":3,"args":["second"],"run_id":"' .. captured_session.run_id .. '"}\n'
      captured_on_stdout(123, { "first" .. event_line })

      helper.async.wait(50)

      assert.equals(1, #update_output_calls, "event preceded by raw stdout should be parsed")
      assert.equals(3, update_output_calls[1].line)
      assert.equals("second", update_output_calls[1].output)

      teardown()
    end)
  end)

  describe("run_id gating", function()
    local python_runner
    local update_output_calls

    local function setup()
      update_output_calls = {}
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function(bufnr, line, output, method, raw_value)
          table.insert(update_output_calls, {
            bufnr = bufnr,
            line = line,
            output = output,
            method = method,
            raw_value = raw_value,
          })
        end,
      }
      package.loaded["consolelog.communication.inspector"] = {
        sessions = {},
        single_file_buffers = {},
        _intentionally_stopped_jobs = {},
      }
      package.loaded["consolelog.processing.message_processor_impl"] = {
        format_args = function(args, method)
          return table.concat(args, " "), args[1]
        end,
      }
      package.loaded["consolelog"] = {
        config = { runner = { python_executable = nil } },
      }
      package.loaded["consolelog.communication.python_runner"] = nil
      python_runner = require("consolelog.communication.python_runner")
    end

    local function teardown()
      package.loaded["consolelog.display.display"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      package.loaded["consolelog.processing.message_processor_impl"] = nil
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.communication.python_runner"] = nil
      update_output_calls = {}
    end

    it("should ignore event without run_id", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local captured_on_stdout = nil
      local captured_session = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        captured_on_stdout = opts.on_stdout
        local run_id = opts.env and opts.env.CONSOLELOG_RUN_ID or "test_run"
        captured_session = { run_id = run_id }
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = python_runner.start_debug_session("/tmp/a.py", 5)

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      vim.notify = saved_notify

      assert.not_nil(session_id)
      assert.not_nil(captured_on_stdout)

      -- Send event WITHOUT run_id (forged target output)
      captured_on_stdout(123, {
        '__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":2,"args":["forged"]}\n'
      })

      assert.equals(0, #update_output_calls, "event without run_id should be ignored")

      teardown()
    end)

    it("should ignore event with wrong run_id", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local captured_on_stdout = nil
      local captured_session = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        captured_on_stdout = opts.on_stdout
        local run_id = opts.env and opts.env.CONSOLELOG_RUN_ID or "test_run"
        captured_session = { run_id = run_id }
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = python_runner.start_debug_session("/tmp/a.py", 5)

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      vim.notify = saved_notify

      assert.not_nil(session_id)
      assert.not_nil(captured_on_stdout)

      -- Send event WITH a DIFFERENT run_id
      captured_on_stdout(123, {
        '__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":2,"args":["wrong"],"run_id":"cl_0000_999"}\n'
      })

      assert.equals(0, #update_output_calls, "event with wrong run_id should be ignored")

      teardown()
    end)

    it("should process event with correct run_id", function()
      setup()
      local inspector = package.loaded["consolelog.communication.inspector"]

      local captured_on_stdout = nil
      local captured_session = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        captured_on_stdout = opts.on_stdout
        local run_id = opts.env and opts.env.CONSOLELOG_RUN_ID or "test_run"
        captured_session = { run_id = run_id }
        return 123
      end

      local saved_executable = vim.fn.executable
      vim.fn.executable = function(name) return name == "python3" and 1 or 0 end
      local saved_filereadable = vim.fn.filereadable
      local runner_path = python_runner.get_plugin_root() .. "py/consolelog_runner.py"
      vim.fn.filereadable = function(path)
        if path == runner_path then return 1 end
        return 0
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = python_runner.start_debug_session("/tmp/a.py", 5)

      vim.fn.jobstart = saved_jobstart
      vim.fn.executable = saved_executable
      vim.fn.filereadable = saved_filereadable
      vim.notify = saved_notify

      assert.not_nil(session_id)
      assert.not_nil(captured_on_stdout)

      -- Send event with correct run_id
      captured_on_stdout(123, {
        '__CONSOLELOG_EVENT__{"event":"console","method":"log","file":"/tmp/a.py","line":2,"args":["valid"],"run_id":"' .. captured_session.run_id .. '"}\n'
      })

      helper.async.wait(50)

      assert.equals(1, #update_output_calls, "event with correct run_id should be processed")
      assert.equals("valid", update_output_calls[1].output)

      teardown()
    end)
  end)
end)