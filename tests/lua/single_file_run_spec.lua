local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"
local constants = require('consolelog.core.constants')
local inspector = require('consolelog.communication.inspector')

describe("Single File Run", function()
  describe("parse_node_version", function()
    it("should parse v23.6.0 correctly", function()
      local v = inspector.parse_node_version("v23.6.0")
      assert.not_nil(v)
      assert.equals(23, v.major)
      assert.equals(6, v.minor)
      assert.equals(0, v.patch)
    end)

    it("should parse v22.6.1 with newline", function()
      local v = inspector.parse_node_version("v22.6.1\n")
      assert.not_nil(v)
      assert.equals(22, v.major)
      assert.equals(6, v.minor)
      assert.equals(1, v.patch)
    end)

    it("should return nil for garbage input", function()
      local v = inspector.parse_node_version("garbage")
      assert.is_nil(v)
    end)

    it("should return nil for empty string", function()
      local v = inspector.parse_node_version("")
      assert.is_nil(v)
    end)

    it("should return nil for nil input", function()
      local v = inspector.parse_node_version(nil)
      assert.is_nil(v)
    end)
  end)

  describe("build_run_command", function()
    it("should return plain command for .js with nil version", function()
      local cmd, err = inspector.build_run_command("/tmp/test.js", nil)
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals("node", cmd[1])
      assert.equals("--inspect=0", cmd[2])
      assert.equals("/tmp/test.js", cmd[3])
      assert.equals(3, #cmd)
    end)

    it("should return plain command for .js with any version", function()
      local cmd, err = inspector.build_run_command("/tmp/test.js", { major = 18, minor = 0, patch = 0 })
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals(3, #cmd)
    end)

    it("should return plain command for .ts with Node >= 24", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", { major = 24, minor = 0, patch = 0 })
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals("node", cmd[1])
      assert.equals("--inspect=0", cmd[2])
      assert.equals("/tmp/test.ts", cmd[3])
      assert.equals(3, #cmd)
    end)

    it("should return plain command for .ts with Node 23.6.0", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", { major = 23, minor = 6, patch = 0 })
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals(3, #cmd)
    end)

    it("should return strip-types flag for .ts with Node 23.5.0", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", { major = 23, minor = 5, patch = 0 })
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals("node", cmd[1])
      assert.equals("--inspect=0", cmd[2])
      assert.equals("--experimental-strip-types", cmd[3])
      assert.equals("/tmp/test.ts", cmd[4])
      assert.equals(4, #cmd)
    end)

    it("should return strip-types flag for .ts with Node 22.6.0", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", { major = 22, minor = 6, patch = 0 })
      assert.not_nil(cmd)
      assert.is_nil(err)
      assert.equals("--experimental-strip-types", cmd[3])
      assert.equals(4, #cmd)
    end)

    it("should return nil and error for .ts with Node < 22.6", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", { major = 22, minor = 5, patch = 0 })
      assert.is_nil(cmd)
      assert.not_nil(err)
      assert.is_true(err:find("v22.5.0") ~= nil)
    end)

    it("should return nil and error for .ts with Node 18", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", { major = 18, minor = 19, patch = 0 })
      assert.is_nil(cmd)
      assert.not_nil(err)
    end)

    it("should return nil and error for .ts with nil version", function()
      local cmd, err = inspector.build_run_command("/tmp/test.ts", nil)
      assert.is_nil(cmd)
      assert.not_nil(err)
      assert.is_true(err:find("unknown") ~= nil)
    end)

    it("should return plain command for .mjs files", function()
      local cmd, err = inspector.build_run_command("/tmp/test.mjs", nil)
      assert.not_nil(cmd)
      assert.equals(3, #cmd)
    end)

    it("should return plain command for .mts files with nil version", function()
      local cmd, err = inspector.build_run_command("/tmp/test.mts", nil)
      assert.is_nil(cmd)
      assert.not_nil(err)
      assert.is_true(err:find("unknown") ~= nil)
    end)
  end)

  describe("constants.is_single_file_runnable", function()
    it("should return true for .js files", function()
      assert.is_true(constants.is_single_file_runnable("a.js"))
    end)

    it("should return true for .mjs files", function()
      assert.is_true(constants.is_single_file_runnable("a.mjs"))
    end)

    it("should return true for .cjs files", function()
      assert.is_true(constants.is_single_file_runnable("a.cjs"))
    end)

    it("should return true for .ts files", function()
      assert.is_true(constants.is_single_file_runnable("a.ts"))
    end)

    it("should return true for .mts files", function()
      assert.is_true(constants.is_single_file_runnable("a.mts"))
    end)

    it("should return true for .cts files", function()
      assert.is_true(constants.is_single_file_runnable("a.cts"))
    end)

    it("should return false for .tsx files", function()
      assert.is_false(constants.is_single_file_runnable("a.tsx"))
    end)

    it("should return false for .jsx files", function()
      assert.is_false(constants.is_single_file_runnable("a.jsx"))
    end)

    it("should return false for .txt files", function()
      assert.is_false(constants.is_single_file_runnable("a.txt"))
    end)
  end)

  describe("constants.is_single_file_runnable with Python", function()
    it("should return true for .py files", function()
      assert.is_true(constants.is_single_file_runnable("a.py"))
    end)

    it("should return false for .pyc files", function()
      assert.is_false(constants.is_single_file_runnable("a.pyc"))
    end)
  end)

  describe("constants.is_python_file", function()
    it("should return true for .py files", function()
      assert.is_true(constants.is_python_file("a.py"))
    end)

    it("should return false for .js files", function()
      assert.is_false(constants.is_python_file("a.js"))
    end)

    it("should return false for .pyc files", function()
      assert.is_false(constants.is_python_file("a.pyc"))
    end)
  end)

  describe("constants.is_typescript_file", function()
    it("should return true for .ts files", function()
      assert.is_true(constants.is_typescript_file("a.ts"))
    end)

    it("should return true for .mts files", function()
      assert.is_true(constants.is_typescript_file("a.mts"))
    end)

    it("should return true for .cts files", function()
      assert.is_true(constants.is_typescript_file("a.cts"))
    end)

    it("should return false for .js files", function()
      assert.is_false(constants.is_typescript_file("a.js"))
    end)

    it("should return false for .mjs files", function()
      assert.is_false(constants.is_typescript_file("a.mjs"))
    end)

    it("should return false for .cjs files", function()
      assert.is_false(constants.is_typescript_file("a.cjs"))
    end)
  end)

  describe("get_node_version caching", function()
    it("should call vim.fn.system only once even for unparseable output", function()
      local saved_system = vim.fn.system
      local call_count = 0
      vim.fn.system = function(...)
        call_count = call_count + 1
        return "garbage"
      end

      inspector._version_checked = false
      inspector.node_version = nil

      local v1 = inspector.get_node_version()
      local v2 = inspector.get_node_version()

      vim.fn.system = saved_system

      assert.is_nil(v1)
      assert.is_nil(v2)
      assert.equals(1, call_count)
    end)
  end)

  describe("session lifecycle", function()
    local clear_buffer_mock

    local function setup_display_stub()
      clear_buffer_mock = helper.mock.new("clear_buffer")
      package.loaded["consolelog.display.display"] = {
        clear_buffer = clear_buffer_mock,
        update_output = function() end,
      }
    end

    local function teardown_display_stub()
      package.loaded["consolelog.display.display"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
    end

    it("should finalize completed session without calling clear_buffer", function()
      setup_display_stub()
      cleanup_sessions()

      local session = {
        filepath = "/tmp/x.js",
        bufnr = 1,
        completed = true,
        job_id = nil,
      }
      inspector.sessions["t1"] = session
      inspector.reconnect_attempts["t1"] = 0

      inspector.handle_connection_error(session)

      assert.is_nil(inspector.sessions["t1"])
      assert.is_nil(inspector.reconnect_attempts["t1"])
      assert.equals(0, clear_buffer_mock.call_count)

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should remove incomplete session with no inspector_url via cleanup path", function()
      setup_display_stub()
      cleanup_sessions()

      local session = {
        filepath = "/tmp/x.js",
        bufnr = 1,
        completed = false,
        job_id = nil,
        inspector_url = nil,
      }
      inspector.sessions["t1"] = session
      inspector.reconnect_attempts["t1"] = 0

      inspector.handle_connection_error(session)

      assert.is_nil(inspector.sessions["t1"])
      assert.is_nil(inspector.reconnect_attempts["t1"])
      assert.equals(1, clear_buffer_mock.call_count)

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should remove bookkeeping via finalize_session without calling clear_buffer", function()
      setup_display_stub()
      cleanup_sessions()

      local session = {
        filepath = "/tmp/x.js",
        bufnr = 2,
        completed = false,
        job_id = nil,
      }
      inspector.sessions["t2"] = session
      inspector.reconnect_attempts["t2"] = 0

      inspector.finalize_session(session)

      assert.is_nil(inspector.sessions["t2"])
      assert.is_nil(inspector.reconnect_attempts["t2"])
      assert.equals(0, clear_buffer_mock.call_count)

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should not reconnect via deferred callback when session completes during backoff", function()
      setup_display_stub()
      cleanup_sessions()

      local captured_fn = nil
      local saved_defer_fn = vim.defer_fn
      vim.defer_fn = function(fn, _delay)
        captured_fn = fn
      end

      local saved_notify = vim.notify
      local notify_count = 0
      vim.notify = function()
        notify_count = notify_count + 1
      end

      local session = {
        filepath = "/tmp/x.js",
        bufnr = 1,
        completed = false,
        job_id = nil,
        inspector_url = "ws://127.0.0.1:9229/session1",
        reconnecting = false,
      }
      inspector.sessions["t1"] = session
      inspector.reconnect_attempts["t1"] = 0

      inspector.handle_connection_error(session)

      assert.not_nil(captured_fn, "deferred callback should have been captured")

      session.completed = true

      captured_fn()

      assert.is_nil(inspector.sessions["t1"], "session should be finalized")
      assert.is_nil(inspector.reconnect_attempts["t1"], "reconnect bookkeeping should be removed")
      assert.equals(0, notify_count, "no reconnect notifications should fire")
      assert.equals(0, clear_buffer_mock.call_count, "clear_buffer should not be called")

      vim.defer_fn = saved_defer_fn
      vim.notify = saved_notify
      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should finalize session in reconnecting state when job exits normally", function()
      setup_display_stub()
      cleanup_sessions()

      local captured_on_exit = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(_cmd, _opts)
        captured_on_exit = _opts.on_exit
        return 42
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = inspector.start_debug_session("/tmp/x.js", 1)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.not_nil(session_id, "session should be created")

      local session = inspector.sessions[session_id]
      assert.not_nil(session)

      session.reconnecting = true
      session.completed = false

      captured_on_exit(42, 0)

      assert.is_nil(inspector.sessions[session_id], "session should be removed after exit during reconnect")
      assert.is_nil(inspector.reconnect_attempts[session_id], "reconnect bookkeeping should be removed")
      assert.equals(0, clear_buffer_mock.call_count, "clear_buffer should not be called")

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should finalize non-reconnecting session in on_exit", function()
      setup_display_stub()
      cleanup_sessions()

      local captured_on_exit = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(_cmd, _opts)
        captured_on_exit = _opts.on_exit
        return 42
      end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = inspector.start_debug_session("/tmp/x.js", 1)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.not_nil(session_id, "session should be created")

      local session = inspector.sessions[session_id]
      assert.not_nil(session)
      assert.is_false(session.reconnecting)

      captured_on_exit(42, 0)

      assert.is_nil(inspector.sessions[session_id], "non-reconnecting session should be removed on exit")
      assert.is_nil(inspector.reconnect_attempts[session_id], "reconnect bookkeeping should be removed")
      assert.equals(0, clear_buffer_mock.call_count, "clear_buffer should not be called")

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should suppress error notification for intentionally stopped jobs", function()
      setup_display_stub()
      cleanup_sessions()

      local captured_on_exit = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(_cmd, _opts)
        captured_on_exit = _opts.on_exit
        return 42
      end

      local saved_notify = vim.notify
      local notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      local session_id = inspector.start_debug_session("/tmp/x.js", 1)

      vim.fn.jobstart = saved_jobstart

      assert.not_nil(session_id, "session should be created")

      local session = inspector.sessions[session_id]
      assert.not_nil(session)

      inspector.cleanup_session(session)

      captured_on_exit(42, 143)

      local error_notifications = vim.tbl_filter(function(n)
        return n.level == vim.log.levels.ERROR
      end, notify_calls)

      assert.equals(0, #error_notifications, "no error notification should be emitted for intentionally stopped job")

      vim.notify = saved_notify
      teardown_display_stub()
      cleanup_sessions()
    end)
    it("should suppress error notification after stop_all_sessions when on_exit fires later", function()
      setup_display_stub()
      cleanup_sessions()

      local captured_on_exit = nil
      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(_cmd, _opts)
        captured_on_exit = _opts.on_exit
        return 99
      end

      local saved_notify = vim.notify
      local notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      local session_id = inspector.start_debug_session("/tmp/x.js", 1)

      vim.fn.jobstart = saved_jobstart

      assert.not_nil(session_id, "session should be created")
      assert.is_true(inspector.is_single_file_buffer(1), "buffer should be tracked")

      inspector.stop_all_sessions()

      assert.is_false(inspector.is_single_file_buffer(1), "stop_all should clear single_file_buffers")

      captured_on_exit(99, 143)

      local error_notifications = vim.tbl_filter(function(n)
        return n.level == vim.log.levels.ERROR
      end, notify_calls)

      assert.equals(0, #error_notifications, "no error notification after stop_all_sessions + late on_exit")

      vim.notify = saved_notify
      teardown_display_stub()
      cleanup_sessions()
    end)
  end)

  describe("run_buffer gating", function()
    local start_session_mock
    local saved_inspector_module

    local function setup_inspector_stub()
      saved_inspector_module = package.loaded["consolelog.communication.inspector"]
      start_session_mock = helper.mock.new("start_debug_session")
      start_session_mock:returns("fake_session_id")
      package.loaded["consolelog.communication.inspector"] = {
        start_debug_session = start_session_mock,
        get_session_for_buffer = function() return nil end,
        cleanup_session = function() end,
        single_file_buffers = {},
        is_single_file_buffer = function() return false end,
        stop_all_sessions = function() end,
      }
    end

    local function teardown_inspector_stub()
      package.loaded["consolelog.communication.inspector"] = saved_inspector_module
      saved_inspector_module = nil
    end

    local saved_display_module = nil

    local function setup_consolelog_module()
      saved_display_module = package.loaded["consolelog.display.display"]
      package.loaded["consolelog.display.display"] = {
        clear_all = function() end,
        clear_buffer = function() end,
        show_outputs = function() end,
      }
      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
      }
    end

    local function teardown_consolelog_module()
      package.loaded["consolelog.display.display"] = saved_display_module
      saved_display_module = nil
      package.loaded["consolelog"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
      inspector.single_file_buffers = {}
      inspector._intentionally_stopped_jobs = {}
    end

    it("should not call start_debug_session for non-runnable file", function()
      setup_inspector_stub()
      setup_consolelog_module()
      cleanup_sessions()

      local test_bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      vim.api.nvim_win_set_buf(winid, test_bufnr)
      local core = require("consolelog.core.init")

      vim.api.nvim_buf_get_name = function() return "/tmp/consolelog_test.txt" end
      core.run_buffer(test_bufnr, winid)

      assert.equals(0, start_session_mock.call_count)

      vim.api.nvim_buf_get_name = function() return "" end
      teardown_inspector_stub()
      teardown_consolelog_module()
      cleanup_sessions()
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)

    it("should call start_debug_session for runnable .js file", function()
      setup_inspector_stub()
      setup_consolelog_module()
      cleanup_sessions()

      local test_bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      vim.api.nvim_win_set_buf(winid, test_bufnr)

      local real_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        if path == "/tmp/consolelog_test.js" then return 1 end
        return real_filereadable(path)
      end

      local real_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function()
        return "/tmp/consolelog_test.js"
      end

      local core = require("consolelog.core.init")
      core.outputs[test_bufnr] = { { line = 1, value = "stale", execution_count = 3 } }
      core.run_buffer(test_bufnr, winid)

      assert.equals(1, start_session_mock.call_count)
      assert.is_true(vim.tbl_isempty(core.outputs[test_bufnr]),
        "outputs from the previous run must not leak into the new run")

      vim.api.nvim_buf_get_name = real_buf_get_name
      vim.fn.filereadable = real_filereadable
      teardown_inspector_stub()
      teardown_consolelog_module()
      cleanup_sessions()
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)

    it("should not run a regular buffer from a diff window", function()
      setup_inspector_stub()
      setup_consolelog_module()
      cleanup_sessions()

      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      local test_bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
      vim.api.nvim_win_set_buf(winid, test_bufnr)
      vim.api.nvim_win_set_option(winid, "diff", true)

      local real_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        if path == "/tmp/consolelog_diff_test.js" then return 1 end
        return real_filereadable(path)
      end

      local real_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function()
        return "/tmp/consolelog_diff_test.js"
      end

      local core = require("consolelog.core.init")
      core.run_buffer(test_bufnr, winid)
      local call_count = start_session_mock.call_count

      vim.api.nvim_buf_get_name = real_buf_get_name
      vim.fn.filereadable = real_filereadable
      vim.api.nvim_win_set_option(winid, "diff", false)
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
      teardown_inspector_stub()
      teardown_consolelog_module()
      cleanup_sessions()

      assert.equals(call_count, 0, "Diff windows must not start debug sessions")
    end)
  end)

  describe("run_buffer Python dispatch", function()
    local start_session_mock
    local saved_inspector_module
    local saved_python_runner_module
    local py_start_session_mock

    local function setup_inspector_stub()
      saved_inspector_module = package.loaded["consolelog.communication.inspector"]
      start_session_mock = helper.mock.new("start_debug_session")
      start_session_mock:returns("fake_session_id")
      package.loaded["consolelog.communication.inspector"] = {
        start_debug_session = start_session_mock,
        get_session_for_buffer = function() return nil end,
        cleanup_session = function() end,
        single_file_buffers = {},
        is_single_file_buffer = function() return false end,
        stop_all_sessions = function() end,
      }
    end

    local function teardown_inspector_stub()
      package.loaded["consolelog.communication.inspector"] = saved_inspector_module
      saved_inspector_module = nil
    end

    local function setup_python_runner_stub()
      saved_python_runner_module = package.loaded["consolelog.communication.python_runner"]
      py_start_session_mock = helper.mock.new("start_debug_session")
      py_start_session_mock:returns("py_session")
      package.loaded["consolelog.communication.python_runner"] = {
        start_debug_session = py_start_session_mock,
        get_session_for_buffer = function() return nil end,
        cleanup_session = function() end,
        stop_all_sessions = function() end,
      }
    end

    local function teardown_python_runner_stub()
      package.loaded["consolelog.communication.python_runner"] = saved_python_runner_module
      saved_python_runner_module = nil
    end

    local saved_display_module = nil

    local function setup_consolelog_module()
      saved_display_module = package.loaded["consolelog.display.display"]
      package.loaded["consolelog.display.display"] = {
        clear_all = function() end,
        clear_buffer = function() end,
        show_outputs = function() end,
      }
      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
      }
    end

    local function teardown_consolelog_module()
      package.loaded["consolelog.display.display"] = saved_display_module
      saved_display_module = nil
      package.loaded["consolelog"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
      inspector.single_file_buffers = {}
      inspector._intentionally_stopped_jobs = {}
    end

    it("should call python_runner.start_debug_session for .py file and not inspector", function()
      setup_inspector_stub()
      setup_python_runner_stub()
      setup_consolelog_module()
      cleanup_sessions()

      local test_bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      vim.api.nvim_win_set_buf(winid, test_bufnr)

      local real_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        if path == "/tmp/consolelog_test.py" then return 1 end
        return real_filereadable(path)
      end

      local real_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function()
        return "/tmp/consolelog_test.py"
      end

      local core = require("consolelog.core.init")
      core.run_buffer(test_bufnr, winid)

      assert.equals(1, py_start_session_mock.call_count, "python_runner.start_debug_session should be called once")
      assert.equals(0, start_session_mock.call_count, "inspector.start_debug_session should NOT be called")

      vim.api.nvim_buf_get_name = real_buf_get_name
      vim.fn.filereadable = real_filereadable
      teardown_inspector_stub()
      teardown_python_runner_stub()
      teardown_consolelog_module()
      cleanup_sessions()
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
  end)

  describe("run_buffer cross-runner session cleanup", function()
    local start_session_mock
    local saved_inspector_module
    local saved_python_runner_module
    local py_start_session_mock
    local inspector_cleanup_mock
    local py_cleanup_mock

    local function setup_inspector_stub()
      saved_inspector_module = package.loaded["consolelog.communication.inspector"]
      start_session_mock = helper.mock.new("start_debug_session")
      start_session_mock:returns("fake_session_id")
      inspector_cleanup_mock = helper.mock.new("cleanup_session")
      package.loaded["consolelog.communication.inspector"] = {
        start_debug_session = start_session_mock,
        get_session_for_buffer = function() return nil end,
        cleanup_session = inspector_cleanup_mock,
        single_file_buffers = {},
        is_single_file_buffer = function() return false end,
        stop_all_sessions = function() end,
      }
    end

    local function teardown_inspector_stub()
      package.loaded["consolelog.communication.inspector"] = saved_inspector_module
      saved_inspector_module = nil
    end

    local function setup_python_runner_stub()
      saved_python_runner_module = package.loaded["consolelog.communication.python_runner"]
      py_start_session_mock = helper.mock.new("start_debug_session")
      py_start_session_mock:returns("py_session")
      py_cleanup_mock = helper.mock.new("cleanup_session")
      package.loaded["consolelog.communication.python_runner"] = {
        start_debug_session = py_start_session_mock,
        get_session_for_buffer = function() return nil end,
        cleanup_session = py_cleanup_mock,
        stop_all_sessions = function() end,
      }
    end

    local function teardown_python_runner_stub()
      package.loaded["consolelog.communication.python_runner"] = saved_python_runner_module
      saved_python_runner_module = nil
    end

    local saved_display_module = nil

    local function setup_consolelog_module()
      saved_display_module = package.loaded["consolelog.display.display"]
      package.loaded["consolelog.display.display"] = {
        clear_all = function() end,
        clear_buffer = function() end,
        show_outputs = function() end,
      }
      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
      }
    end

    local function teardown_consolelog_module()
      package.loaded["consolelog.display.display"] = saved_display_module
      saved_display_module = nil
      package.loaded["consolelog"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
      inspector.single_file_buffers = {}
      inspector._intentionally_stopped_jobs = {}
    end

    it("should clean inspector session when running a renamed .py buffer", function()
      setup_inspector_stub()
      setup_python_runner_stub()
      setup_consolelog_module()
      cleanup_sessions()

      local test_bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      vim.api.nvim_win_set_buf(winid, test_bufnr)

      -- Simulate an existing inspector session on test buffer
      local existing_session = { filepath = "/tmp/old.js", bufnr = test_bufnr }
      local inspector_get_session = function(bufnr)
        if bufnr == test_bufnr then return existing_session end
        return nil
      end
      package.loaded["consolelog.communication.inspector"].get_session_for_buffer = inspector_get_session

      local real_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        if path == "/tmp/consolelog_test.py" then return 1 end
        return real_filereadable(path)
      end

      local real_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function()
        return "/tmp/consolelog_test.py"
      end

      local core = require("consolelog.core.init")
      core.run_buffer(test_bufnr, winid)

      assert.equals(1, inspector_cleanup_mock.call_count,
        "inspector session must be cleaned when buffer runs as .py")
      assert.equals(1, py_start_session_mock.call_count,
        "python_runner.start_debug_session should be called")
      assert.equals(0, start_session_mock.call_count,
        "inspector.start_debug_session should NOT be called")

      vim.api.nvim_buf_get_name = real_buf_get_name
      vim.fn.filereadable = real_filereadable
      teardown_inspector_stub()
      teardown_python_runner_stub()
      teardown_consolelog_module()
      cleanup_sessions()
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)

    it("should clean python_runner session when running a renamed .js buffer", function()
      setup_inspector_stub()
      setup_python_runner_stub()
      setup_consolelog_module()
      cleanup_sessions()

      local test_bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      vim.api.nvim_win_set_buf(winid, test_bufnr)

      -- Simulate an existing python_runner session on test buffer
      local existing_py_session = { filepath = "/tmp/old.py", bufnr = test_bufnr }
      local py_get_session = function(bufnr)
        if bufnr == test_bufnr then return existing_py_session end
        return nil
      end
      package.loaded["consolelog.communication.python_runner"].get_session_for_buffer = py_get_session

      local real_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        if path == "/tmp/consolelog_test.js" then return 1 end
        return real_filereadable(path)
      end

      local real_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function()
        return "/tmp/consolelog_test.js"
      end

      local core = require("consolelog.core.init")
      core.run_buffer(test_bufnr, winid)

      assert.equals(1, py_cleanup_mock.call_count,
        "python_runner session must be cleaned when buffer runs as .js")
      assert.equals(1, start_session_mock.call_count,
        "inspector.start_debug_session should be called")
      assert.equals(0, py_start_session_mock.call_count,
        "python_runner.start_debug_session should NOT be called")

      vim.api.nvim_buf_get_name = real_buf_get_name
      vim.fn.filereadable = real_filereadable
      teardown_inspector_stub()
      teardown_python_runner_stub()
      teardown_consolelog_module()
      cleanup_sessions()
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end)
  end)

  describe("rerun-on-save for Python", function()
    local run_buffer_mock

    local function setup_display_stub()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
        show_outputs = function() end,
      }
    end

    local function teardown_display_stub()
      package.loaded["consolelog.display.display"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
      inspector.single_file_buffers = {}
      inspector._intentionally_stopped_jobs = {}
    end

    it("should rerun tracked .py buffer even when filetype is unset", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      -- Track clear_buffer calls to verify output clearing
      local clear_buffer_mock = helper.mock.new("clear_buffer")
      package.loaded["consolelog.display.display"] = {
        clear_buffer = clear_buffer_mock,
        update_output = function() end,
        show_outputs = function() end,
      }

      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
        outputs = { [3] = { { text = "old output", line = 1 } } },
        run_buffer = run_buffer_mock,
      }

      -- Simulate unset filetype: is_javascript_buffer and is_supported_buffer both return false
      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return false end,
        is_supported_buffer = function() return false end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.py"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.py" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      vim.api.nvim_buf_is_loaded = function() return true end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = nil
      vim.defer_fn = function(fn, _delay)
        captured_deferred = fn
      end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      bufwritepost_cb({buf = 3})

      -- Verify stale outputs are cleared before the deferred re-run
      assert.equals(1, clear_buffer_mock.call_count,
        "clear_buffer must be called for tracked Python buffer even when should_process_buffer is false")
      assert.is_true(vim.tbl_isempty(package.loaded["consolelog"].outputs[3]),
        "outputs for buffer 3 must be cleared on save")

      assert.not_nil(captured_deferred, "vim.defer_fn should have been called")

      captured_deferred()

      assert.equals(1, run_buffer_mock.call_count,
        "tracked .py buffer must rerun even when should_process_buffer is false")

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)
  end)

  describe("single_file_buffers tracking", function()
    local function setup_display_stub()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
      }
    end

    local function teardown_display_stub()
      package.loaded["consolelog.display.display"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
      inspector.single_file_buffers = {}
      inspector._intentionally_stopped_jobs = {}
    end

    it("should not track buffer when jobstart returns -1", function()
      setup_display_stub()
      cleanup_sessions()

      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return -1 end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = inspector.start_debug_session("/tmp/x.js", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.is_nil(session_id, "session should not be created for failed jobstart")
      assert.is_false(inspector.is_single_file_buffer(7), "buffer should not be tracked after failed jobstart")

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should not track buffer when jobstart returns 0", function()
      setup_display_stub()
      cleanup_sessions()

      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 0 end

      local saved_notify = vim.notify
      vim.notify = function() end

      local session_id = inspector.start_debug_session("/tmp/x.js", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.is_nil(session_id, "session should not be created for jobstart returning 0")
      assert.is_false(inspector.is_single_file_buffer(7), "buffer should not be tracked after jobstart returning 0")

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should track buffer after start_debug_session", function()
      setup_display_stub()
      cleanup_sessions()

      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 123 end

      local saved_notify = vim.notify
      vim.notify = function() end

      inspector.start_debug_session("/tmp/x.js", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.is_true(inspector.is_single_file_buffer(7))

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should clear tracking after stop_all_sessions", function()
      setup_display_stub()
      cleanup_sessions()

      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 123 end

      local saved_notify = vim.notify
      vim.notify = function() end

      inspector.start_debug_session("/tmp/x.js", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.is_true(inspector.is_single_file_buffer(7))

      inspector.stop_all_sessions()

      assert.is_false(inspector.is_single_file_buffer(7))

      teardown_display_stub()
      cleanup_sessions()
    end)

    it("should not clear tracking on finalize_session", function()
      setup_display_stub()
      cleanup_sessions()

      local saved_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 123 end

      local saved_notify = vim.notify
      vim.notify = function() end

      inspector.start_debug_session("/tmp/x.js", 7)

      vim.fn.jobstart = saved_jobstart
      vim.notify = saved_notify

      assert.is_true(inspector.is_single_file_buffer(7))

      local session = inspector.get_session_for_buffer(7)
      assert.not_nil(session)
      inspector.finalize_session(session)

      assert.is_true(inspector.is_single_file_buffer(7), "single_file_buffers must survive finalize_session")

      teardown_display_stub()
      cleanup_sessions()
    end)
  end)

  describe("rerun-on-save wiring", function()
    local run_buffer_mock

    local function setup_display_stub()
      package.loaded["consolelog.display.display"] = {
        clear_buffer = function() end,
        update_output = function() end,
        show_outputs = function() end,
      }
    end

    local function teardown_display_stub()
      package.loaded["consolelog.display.display"] = nil
    end

    local function cleanup_sessions()
      inspector.sessions = {}
      inspector.reconnect_attempts = {}
      inspector.single_file_buffers = {}
      inspector._intentionally_stopped_jobs = {}
    end

    it("should debounce reruns on rapid saves for tracked buffer", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.js" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      vim.api.nvim_buf_is_loaded = function() return true end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = {}
      vim.defer_fn = function(fn, _delay)
        table.insert(captured_deferred, fn)
      end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      bufwritepost_cb({buf = 3})
      bufwritepost_cb({buf = 3})

      assert.equals(2, #captured_deferred, "each save should queue a deferred callback")

      captured_deferred[1]()
      captured_deferred[2]()

      assert.equals(1, run_buffer_mock.call_count)

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should not call run_buffer when rerun_on_save is false", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = false } },
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.js" end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb)

      bufwritepost_cb({buf = 3})

      assert.equals(0, run_buffer_mock.call_count)

      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should not call run_buffer after toggle-off disables the plugin", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      local config = { enabled = true, runner = { rerun_on_save = true } }
      package.loaded["consolelog"] = {
        config = config,
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.js" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      vim.api.nvim_buf_is_loaded = function() return true end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = nil
      vim.defer_fn = function(fn, _delay)
        captured_deferred = fn
      end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      bufwritepost_cb({buf = 3})

      assert.not_nil(captured_deferred, "vim.defer_fn should have been called")

      config.enabled = false

      captured_deferred()

      assert.equals(0, run_buffer_mock.call_count, "run_buffer should not be called after toggle-off")

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should not fire stale deferred rerun after toggle-off/on lifecycle", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      local config = { enabled = true, runner = { rerun_on_save = true } }
      package.loaded["consolelog"] = {
        config = config,
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.js" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      vim.api.nvim_buf_is_loaded = function() return true end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = nil
      vim.defer_fn = function(fn, _delay)
        captured_deferred = fn
      end

      package.loaded["consolelog.core.autocmds"] = nil
      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      -- Step 1: save triggers deferred callback
      bufwritepost_cb({buf = 3})
      assert.not_nil(captured_deferred, "deferred callback should be captured")

      -- Step 2: toggle-off invalidates the generation
      autocmds.invalidate_reruns()

      -- Step 3: toggle-on and manual run re-track the buffer
      config.enabled = true
      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      -- Step 4: stale deferred callback fires
      captured_deferred()

      assert.equals(0, run_buffer_mock.call_count, "stale deferred rerun must not fire after invalidate_reruns")

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should call run_buffer after deferred rerun with real BufWritePost", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")
      run_buffer_mock:returns(nil)

      local config = { enabled = true, runner = { rerun_on_save = true } }
      package.loaded["consolelog"] = {
        config = config,
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      -- Create a real temp file so filereadable passes
      local tmpfile = "/tmp/consolelog_rerun_real_test.js"
      local f = io.open(tmpfile, "w")
      f:write("console.log('hello')")
      f:close()

      -- Open the file in a real buffer
      vim.cmd("edit " .. tmpfile)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Track the buffer as if it was previously run
      inspector.single_file_buffers[bufnr] = tmpfile

      -- Set up autocmds with REAL registration (not mocked)
      package.loaded["consolelog.core.autocmds"] = nil
      local autocmds = require("consolelog.core.autocmds")
      autocmds.setup()

      -- Write the buffer (triggers BufWritePost)
      vim.cmd("write")

      -- Wait for the deferred callback (50ms defer + margin)
      helper.async.wait(200)

      assert.equals(1, run_buffer_mock.call_count,
        "run_buffer should be called once after real BufWritePost (got " .. run_buffer_mock.call_count .. ")")

      -- Cleanup
      vim.cmd("bdelete! " .. bufnr)
      os.remove(tmpfile)
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should use args.buf not nvim_get_current_buf for rerun target", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")
      run_buffer_mock:returns(nil)

      local config = { enabled = true, runner = { rerun_on_save = true } }
      package.loaded["consolelog"] = {
        config = config,
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.js" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      vim.api.nvim_buf_is_loaded = function() return true end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = nil
      vim.defer_fn = function(fn, _delay)
        captured_deferred = fn
      end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      bufwritepost_cb({buf = 3})

      assert.not_nil(captured_deferred, "vim.defer_fn should have been called")

      captured_deferred()

      assert.equals(1, run_buffer_mock.call_count, "run_buffer should target saved buffer 3, not current buffer")

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should rerun tracked .mts buffer even when filetype is unset", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      -- Track clear_buffer calls to verify output clearing
      local clear_buffer_mock = helper.mock.new("clear_buffer")
      package.loaded["consolelog.display.display"] = {
        clear_buffer = clear_buffer_mock,
        update_output = function() end,
        show_outputs = function() end,
      }

      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
        outputs = { [3] = { { text = "old output", line = 1 } } },
        run_buffer = run_buffer_mock,
      }

      -- Simulate unset filetype: is_javascript_buffer returns false
      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return false end,
        is_supported_buffer = function() return false end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.mts"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.mts" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      vim.api.nvim_buf_is_loaded = function() return true end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = nil
      vim.defer_fn = function(fn, _delay)
        captured_deferred = fn
      end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      bufwritepost_cb({buf = 3})

      -- Verify stale outputs are cleared before the deferred re-run
      assert.equals(1, clear_buffer_mock.call_count,
        "clear_buffer must be called for tracked buffer even when should_process_buffer is false")
      assert.is_true(vim.tbl_isempty(package.loaded["consolelog"].outputs[3]),
        "outputs for buffer 3 must be cleared on save")

      assert.not_nil(captured_deferred, "vim.defer_fn should have been called")

      captured_deferred()

      assert.equals(1, run_buffer_mock.call_count,
        "tracked .mts buffer must rerun even when should_process_buffer is false")

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)

    it("should discard deferred rerun when buffer is deleted before callback fires", function()
      setup_display_stub()
      cleanup_sessions()

      run_buffer_mock = helper.mock.new("run_buffer")

      package.loaded["consolelog"] = {
        config = { enabled = true, runner = { rerun_on_save = true } },
        enable = function() end,
        notify = function() end,
        outputs = {},
        run_buffer = run_buffer_mock,
      }

      package.loaded["consolelog.core.utils"] = {
        is_javascript_buffer = function() return true end,
        is_supported_buffer = function() return true end,
        find_regular_buffer_window = function(_, winid) return winid end,
      }

      package.loaded["consolelog.communication.inspector"] = inspector

      inspector.single_file_buffers[3] = "/tmp/tracked.js"

      local saved_buf_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function() return "/tmp/tracked.js" end

      local saved_buf_is_valid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function() return true end

      local saved_buf_is_loaded = vim.api.nvim_buf_is_loaded
      -- Buffer is valid but NOT loaded (simulates :bdelete within 50ms)
      vim.api.nvim_buf_is_loaded = function() return false end

      local saved_defer_fn = vim.defer_fn
      local captured_deferred = nil
      vim.defer_fn = function(fn, _delay)
        captured_deferred = fn
      end

      local autocmds = require("consolelog.core.autocmds")

      local captured_callbacks = {}
      local saved_create_autocmd = vim.api.nvim_create_autocmd
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(captured_callbacks, { event = event, callback = opts.callback })
        return 1
      end

      local saved_create_augroup = vim.api.nvim_create_augroup
      vim.api.nvim_create_augroup = function() return 1 end

      autocmds.setup()

      vim.api.nvim_create_autocmd = saved_create_autocmd
      vim.api.nvim_create_augroup = saved_create_augroup

      local bufwritepost_cb = nil
      for _, entry in ipairs(captured_callbacks) do
        if entry.event == "BufWritePost" then
          bufwritepost_cb = entry.callback
          break
        end
      end

      assert.not_nil(bufwritepost_cb, "BufWritePost autocmd should have been registered")

      -- At the time of BufWritePost, buffer is loaded (is_loaded = true for the outer check)
      -- but we simulate it becoming unloaded before the deferred callback fires
      vim.api.nvim_buf_is_loaded = function() return true end

      bufwritepost_cb({buf = 3})

      assert.not_nil(captured_deferred, "vim.defer_fn should have been called")

      -- Simulate :bdelete between BufWritePost and deferred callback
      vim.api.nvim_buf_is_loaded = function() return false end

      captured_deferred()

      assert.equals(0, run_buffer_mock.call_count,
        "run_buffer should NOT be called when buffer is unloaded at deferred callback time")

      vim.defer_fn = saved_defer_fn
      vim.api.nvim_buf_is_loaded = saved_buf_is_loaded
      vim.api.nvim_buf_is_valid = saved_buf_is_valid
      vim.api.nvim_buf_get_name = saved_buf_get_name
      teardown_display_stub()
      package.loaded["consolelog"] = nil
      package.loaded["consolelog.core.utils"] = nil
      package.loaded["consolelog.core.autocmds"] = nil
      package.loaded["consolelog.communication.inspector"] = nil
      cleanup_sessions()
    end)
  end)
end)
