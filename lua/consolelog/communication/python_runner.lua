local M = {}
local constants = require("consolelog.core.constants")

M.sessions = {}
M._intentionally_stopped_jobs = {}

local _run_counter = 0

function M._generate_run_id()
	_run_counter = _run_counter + 1
	return string.format("cl_%d_%d", os.time(), _run_counter)
end

function M.get_plugin_root()
	local current_file = debug.getinfo(1, "S").source:sub(2)
	return vim.fn.fnamemodify(current_file, ":p:h:h:h:h") .. "/"
end

function M.get_runner_script()
	local script = M.get_plugin_root() .. "py/consolelog_runner.py"
	if vim.fn.filereadable(script) ~= 1 then
		return nil
	end
	return script
end

function M.resolve_python_executable(filepath)
	-- (1) Config override
	local ok, cfg = pcall(function() return require("consolelog").config.runner.python_executable end)
	if ok and cfg and vim.fn.executable(cfg) == 1 then
		return cfg
	end

	-- (2) VIRTUAL_ENV
	local venv = os.getenv("VIRTUAL_ENV")
	if venv then
		local venv_exe = venv .. "/bin/python"
		if vim.fn.executable(venv_exe) == 1 then
			return venv_exe
		end
	end

	-- (3) Walk up from file directory looking for .venv/bin/python or venv/bin/python
	local dir = vim.fn.fnamemodify(filepath, ":h")
	for _ = 1, constants.FILES.MAX_PATH_DEPTH do
		for _, venv_dir in ipairs({ ".venv", "venv" }) do
			local candidate = dir .. "/" .. venv_dir .. "/bin/python"
			if vim.fn.executable(candidate) == 1 then
				return candidate
			end
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then break end
		dir = parent
	end

	-- (4) Fallback to python3
	if vim.fn.executable("python3") == 1 then
		return "python3"
	end

	return nil, "No Python interpreter found (need python3 or a virtualenv)"
end

function M.build_run_command(filepath)
	local exe, err = M.resolve_python_executable(filepath)
	if not exe then
		return nil, err
	end

	local script = M.get_runner_script()
	if not script then
		return nil, "Python runner script not found at " .. M.get_plugin_root() .. "py/consolelog_runner.py"
	end

	return { exe, script, filepath }
end

function M.parse_event(line)
	local sentinel = "__CONSOLELOG_EVENT__"
	local search_from = 1

	while search_from <= #line do
		local sentinel_pos = line:find(sentinel, search_from, true)
		if not sentinel_pos then
			return nil
		end

		local payload = line:sub(sentinel_pos + #sentinel)
		local ok, result = pcall(vim.json.decode, payload)
		if ok and type(result) == "table" and result.event ~= nil then
			return result
		end

		-- Invalid event at this sentinel; try the next occurrence
		search_from = sentinel_pos + #sentinel
	end

	return nil
end

function M.handle_event(session, event)
	if session.cancelled then
		return
	end

	if event.event == "console" then
		if vim.fn.fnamemodify(event.file, ":p") ~= vim.fn.fnamemodify(session.filepath, ":p") then
			return
		end

		local args = {}
		for _, arg in ipairs(event.args or {}) do
			if arg == vim.NIL then
				table.insert(args, "None")
			else
				table.insert(args, arg)
			end
		end

		local message_processor = require("consolelog.processing.message_processor_impl")
		local display = require("consolelog.display.display")

		vim.schedule(function()
			if session.cancelled then
				return
			end
			local output, raw_value = message_processor.format_args(args, event.method, true)
			display.update_output(session.bufnr, event.line, output, event.method, raw_value)
		end)
	elseif event.event == "exception" then
		if vim.fn.fnamemodify(event.file, ":p") ~= vim.fn.fnamemodify(session.filepath, ":p") then
			return
		end

		local text = (event.text or ""):match("[^\n]+") or event.text or ""
		local display = require("consolelog.display.display")

		vim.schedule(function()
			if session.cancelled then
				return
			end
			display.update_output(session.bufnr, event.line, text, "error", event.text)
		end)
	end
end

function M.start_debug_session(filepath, bufnr)
	local cmd, err = M.build_run_command(filepath)
	if not cmd then
		vim.notify("ConsoleLog: " .. err, vim.log.levels.ERROR)
		return nil
	end

	local run_id = M._generate_run_id()

	local session = {
		filepath = filepath,
		bufnr = bufnr,
		job_id = nil,
		run_id = run_id,
		_stdout_buffer = "",
	}

	local session_id = nil

	session.job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		env = { CONSOLELOG_RUN_ID = run_id },
		on_stdout = function(_, data)
			session._stdout_buffer = session._stdout_buffer .. table.concat(data, "\n")
			while true do
				local newline_pos = session._stdout_buffer:find("\n")
				if not newline_pos then break end
				local line = session._stdout_buffer:sub(1, newline_pos - 1)
				session._stdout_buffer = session._stdout_buffer:sub(newline_pos + 1)
				local event = M.parse_event(line)
				if event and event.run_id == session.run_id then
					M.handle_event(session, event)
				end
			end
		end,
		on_exit = function(job_id, exit_code)
			local was_intentional = M._intentionally_stopped_jobs[job_id]
			M._intentionally_stopped_jobs[job_id] = nil

			local sid = tostring(job_id)
			M.sessions[sid] = nil

			if exit_code ~= 0 and not was_intentional then
				vim.notify("Process exited with code " .. exit_code, vim.log.levels.ERROR)
			end
		end,
	})

	if session.job_id == nil or session.job_id <= 0 then
		return nil
	end

	session_id = tostring(session.job_id)
	M.sessions[session_id] = session
	require("consolelog.communication.inspector").single_file_buffers[bufnr] = filepath

	return session_id
end

function M.get_session_for_buffer(bufnr)
	for _, session in pairs(M.sessions) do
		if session.bufnr == bufnr then
			return session
		end
	end
	return nil
end

function M.cleanup_session(session)
	session.cancelled = true

	if session.bufnr then
		local display = require("consolelog.display.display")
		display.clear_buffer(session.bufnr)
	end

	if session.job_id then
		M._intentionally_stopped_jobs[session.job_id] = true
		vim.fn.jobstop(session.job_id)
		session.job_id = nil
	end

	for id, s in pairs(M.sessions) do
		if s == session then
			M.sessions[id] = nil
			break
		end
	end
end

function M.stop_all_sessions()
	local inspector = require("consolelog.communication.inspector")
	for _, session in pairs(M.sessions) do
		M.cleanup_session(session)
		if session.bufnr and inspector.single_file_buffers then
			inspector.single_file_buffers[session.bufnr] = nil
		end
	end
	M.sessions = {}
end

return M