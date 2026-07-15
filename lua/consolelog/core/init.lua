local M = {}

-- Log level utilities
local log_levels = {
	debug = 0,
	info = 1,
	warn = 2,
	error = 3,
	silent = 4,
}

function M.notify(msg, level)
	level = level or vim.log.levels.INFO

	-- Map vim.log.levels to our log levels
	local level_map = {
		[vim.log.levels.DEBUG] = "debug",
		[vim.log.levels.INFO] = "info",
		[vim.log.levels.WARN] = "warn",
		[vim.log.levels.ERROR] = "error",
	}

	local msg_level = level_map[level] or "info"
	local config_level = M.config.log_level or "warn"

	-- Only show if message level is >= config level
	if log_levels[msg_level] >= log_levels[config_level] then
		vim.notify(msg, level)
	end
end

M.config = {
	enabled = false,
	auto_enable = true,
	auto_inject = true, -- Automatically inject console capture for Next.js/React
	log_level = "silent", -- "debug", "info", "warn", "error", "silent"
	display = {
		virtual_text = true,
		virtual_text_pos = "eol",
		highlight = "ConsoleLogOutput",
		prefix = " ▸ ",
		truncate_marker = "...",
		throttle_ms = 50,
		priority = 250,
		max_width = 0,
	},
	history = {
		enabled = true,
		show_indicator = true,
	},
	websocket = {
		ping_interval = 15000,
		close_timeout = 30000,
		display_methods = { "log", "error" },
		reconnect = {
			enabled = true,
			max_attempts = 5,
			delay = 1000,
		},
	},
	inspector = {
		auto_resume = true,
		capture_exceptions = true,
		console_methods = { "log", "error", "warn", "info", "debug" },
	},

	production_check = true,
	clear_cache_on_disable = true,
	allowed_hosts = { "localhost", "127.0.0.1" },
	debug_logger = {
		enabled = false,
		log_file = "/tmp/consolelog_debug.log"
	},
	runner = {
		command = nil,
		use_inspector = true,
		rerun_on_save = true,
		python_executable = nil,
	},
	keymaps = {
		enabled = true,
		toggle = "<leader>lt",
		run = "<leader>lr",
		clear = "<leader>lx",
		inspect = "<leader>li",
		inspect_all = "<leader>la",
		inspect_buffer = "<leader>lb",
		reload = "<leader>lR",
		debug_toggle = "<leader>ld",
	},
}




M.namespace = vim.api.nvim_create_namespace("consolelog")
M.outputs = {}
M.unmatched_outputs = {}
M.active_buf = nil
M.is_patched = false
M.project_root = nil
M.project_id = nil

function M.setup_project_context()
	local port_manager = require("consolelog.communication.port_manager")
	M.project_root = port_manager.find_project_root()
	if M.project_root then
		M.project_id = vim.fn.fnamemodify(M.project_root, ":t")
	end
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Cleanup stale locks and registry entries on startup
	local port_manager = require("consolelog.communication.port_manager")
	port_manager.cleanup_stale_locks()

	require("consolelog.display.highlights").setup()
	require("consolelog.core.autocmds").setup()
	require("consolelog.core.commands").setup()
	require("consolelog.core.keymaps").setup(M.config)

	if M.config.auto_enable then
		vim.defer_fn(function()
			M.enable()
		end, 100)
	end
end

function M.enable()
	if M.config.enabled then
		M.notify("ConsoleLog is already enabled", vim.log.levels.INFO)
		return
	end

	M.clear()

	M.config.enabled = true

	local ws_server = require("consolelog.communication.ws_server")
	if ws_server.server then
		ws_server.enable_clients()
	end

	-- Setup project context for multi-instance isolation
	M.setup_project_context()

	-- First try to find project root from current buffer or cwd
	local port_manager = require("consolelog.communication.port_manager")
	local project_root = port_manager.find_project_root()

	-- If no project root found from current buffer, search from cwd
	if not project_root then
		local cwd = vim.fn.getcwd()
		local dir = cwd
		while dir ~= "/" do
			if vim.fn.filereadable(dir .. "/package.json") == 1 then
				project_root = dir
				break
			end
			local parent = vim.fn.fnamemodify(dir, ":h")
			if parent == dir then break end
			dir = parent
		end
	end

	if project_root then
		-- Use framework detector to properly identify the framework
		local framework_detector = require("consolelog.injection.framework_detector")
		local framework = framework_detector.detect_framework(project_root)
		local config = framework_detector.get_framework_config(framework)

		if config and config.inject_client then
			-- Browser project (Next.js/React/Vue/etc)
			local auto_inject = require("consolelog.injection.auto_inject")
			local ports = auto_inject.setup_project(project_root, true)

			if ports then
				M.notify(string.format("ConsoleLog enabled for %s (Port %d)",
						config.name or framework, ports.ws_port or 9999), vim.log.levels.INFO)
			else
				M.notify("ConsoleLog: Failed to setup browser console capture", vim.log.levels.ERROR)
			end
			return
		end
	end

	-- Fallback: just enable for current buffer
	M.notify("ConsoleLog enabled", vim.log.levels.INFO)
end

function M.disable()
	if not M.config.enabled then
		M.notify("ConsoleLog is not enabled", vim.log.levels.INFO)
		return
	end

	M.config.enabled = false

	local ws_server = require("consolelog.communication.ws_server")
	if ws_server.server then
		ws_server.disable_clients()
	end

	local port_manager = require("consolelog.communication.port_manager")
	local project_root = port_manager.find_project_root()

	if project_root then
		local auto_inject = require("consolelog.injection.auto_inject")
		auto_inject.stop_all()

		local injector_manager = require("consolelog.injection.injectors.manager")
		injector_manager.unpatch(project_root)
	end

	vim.defer_fn(function()
		ws_server.stop()
	end, 300)

	local inspector = require("consolelog.communication.inspector")
	inspector.stop_all_sessions()

	require("consolelog.communication.python_runner").stop_all_sessions()

	-- Invalidate any deferred rerun callbacks queued before this disable
	require("consolelog.core.autocmds").invalidate_reruns()

	M.clear()

	M.notify("ConsoleLog disabled", vim.log.levels.INFO)
end

function M.toggle()
	if M.config.enabled then
		M.disable()
	else
		M.enable()
	end
end

function M.show()
	if not M.config.enabled then return end
	require("consolelog.display.display").show_outputs()
end

function M.hide()
	require("consolelog.display.display").hide_outputs()
end

function M.clear()
	M.outputs = {}
	require("consolelog.display.display").clear_all()
	require("consolelog.processing.message_processor_impl").reset_matched_lines()
end

function M.clear_cache()
	-- Clear any cached module configurations
	local port_manager = require("consolelog.communication.port_manager")
	local project_root = port_manager.find_project_root()

	if project_root then
		local consolelog_dir = project_root .. "/node_modules/.consolelog"
		if vim.fn.isdirectory(consolelog_dir) == 1 then
			vim.fn.system("rm -rf " .. vim.fn.shellescape(consolelog_dir))
		end
	end

	vim.notify("Build tool caches cleared", vim.log.levels.INFO)
end

function M.run_buffer(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local constants = require("consolelog.core.constants")

	if not constants.is_single_file_runnable(filepath) then
		M.notify("ConsoleLogRun supports .js/.mjs/.cjs/.ts/.mts/.cts/.py files.", vim.log.levels.ERROR)
		return
	end

	if vim.fn.filereadable(filepath) == 0 then
		M.notify("File not found: " .. filepath, vim.log.levels.ERROR)
		return
	end

	if not M.config.enabled then
		M.enable()
	end

	-- Dispatch to the appropriate runner based on file type
	local runner
	if constants.is_python_file(filepath) then
		runner = require("consolelog.communication.python_runner")
	else
		runner = require("consolelog.communication.inspector")
	end

	-- Clear any stale outputs from previous runs (including completed sessions)
	require("consolelog.display.display").clear_buffer(bufnr)

	-- Clean any existing session from BOTH runners (handles buffer renamed between JS and Python)
	local inspector = require("consolelog.communication.inspector")
	local py_runner = require("consolelog.communication.python_runner")
	for _, r in ipairs({ inspector, py_runner }) do
		local existing = r.get_session_for_buffer(bufnr)
		if existing then
			r.cleanup_session(existing)
		end
	end

	local session_id = runner.start_debug_session(filepath, bufnr)

	if session_id then
		M.notify("Running " .. vim.fn.fnamemodify(filepath, ":t") .. " with console capture", vim.log.levels.INFO)
	else
		M.notify("Failed to start debug session", vim.log.levels.ERROR)
	end
end

function M.run()
	M.run_buffer(vim.api.nvim_get_current_buf())
end

function M.toggle_output_window()
	require("consolelog.display.display").toggle_output_window()
end

function M.get_session_info()
	local inspector = require("consolelog.communication.inspector")
	local sessions = inspector.get_active_sessions()

	if #sessions == 0 then
		vim.notify("No active debug sessions", vim.log.levels.INFO)
		return
	end

	local lines = { "Active Debug Sessions:" }
	for _, session in ipairs(sessions) do
		table.insert(lines, string.format("  • [%s] %s (buf: %d)",
			session.id,
			vim.fn.fnamemodify(session.filepath, ":t"),
			session.bufnr
		))
	end

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
