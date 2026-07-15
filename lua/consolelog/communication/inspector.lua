local M = {}
local constants = require("consolelog.core.constants")

M.sessions = {}
M.message_id = 1
M.reconnect_attempts = {}
M.max_reconnect_attempts = 5
M.reconnect_delay = constants.TIMING.RECONNECT_BASE_DELAY_MS
M.auto_attach_timer = nil

function M.start_debug_session(filepath, bufnr)
	local session = {
		filepath = filepath,
		bufnr = bufnr,
		ws_id = nil,
		inspector_url = nil,
		job_id = nil,
		ready = false,
		reconnecting = false,
	}

	session.job_id = M.start_node_inspect(filepath, function(url)
		session.inspector_url = url
		M.connect_to_inspector(session)
	end)

	if not session.job_id then
		return nil
	end

	local session_id = tostring(session.job_id)
	M.sessions[session_id] = session
	M.reconnect_attempts[session_id] = 0

	-- Timeout to clean up if inspector URL is never found
	vim.defer_fn(function()
		if M.sessions[session_id] and not session.inspector_url then
			vim.notify("ConsoleLog: Inspector URL not found (timeout)", vim.log.levels.ERROR)
			M.cleanup_session(session)
		end
	end, 10000)

	return session_id
end

function M.start_node_inspect(filepath, on_url_found)
	local cmd = { "node", "--inspect=0", filepath }
	local inspector_url_found = false

	return vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stderr = function(_, data)
			if not inspector_url_found then
				for _, line in ipairs(data) do
					local url = M.extract_inspector_url(line)
					if url then
						inspector_url_found = true
						on_url_found(url)
						break
					end
				end
			end
		end,
		on_exit = function(job_id, exit_code)
			local session_id = tostring(job_id)
			local session = M.sessions[session_id]

			if session then
				session.job_id = nil
			end

			if exit_code ~= 0 then
				vim.notify("Process exited with code " .. exit_code, vim.log.levels.ERROR)
			end
		end,
	})
end

function M.extract_inspector_url(line)
	local ws_url = line:match("ws://([^%s]+)")
	if ws_url then
		ws_url = ws_url:gsub("localhost", constants.NETWORK.LOCALHOST_IP)
		return "ws://" .. ws_url
	end
	return nil
end

function M.connect_to_inspector(session, is_reconnect)
	local session_id = M.get_session_id(session)

	if is_reconnect then
		session.reconnecting = true
		vim.notify("Reconnecting to debugger...", vim.log.levels.INFO)
	end

	-- Parse WebSocket URL
	local ws_url = session.inspector_url
	if not ws_url then
		M.handle_connection_error(session)
		return
	end

	-- Extract port and path from WebSocket URL
	local port, path = ws_url:match("ws://[^:]+:(%d+)(/.*)")
	if not port or not path then
		M.handle_connection_error(session)
		return
	end

	local host = constants.NETWORK.LOCALHOST_IP

	-- Create WebSocket client
	local ws_client = require("consolelog.communication.ws_server").create_client(host, port, path)

	if not ws_client then
		M.handle_connection_error(session)
		return
	end

	session.ws_id = ws_client.id

	-- Set up WebSocket callbacks
	ws_client.on_connect = function()
		M.initialize_runtime(session)
	end

	ws_client.on_message = function(message)
		M.handle_inspector_message(session, message)
	end

	ws_client.on_close = function()
		if not session.reconnecting then
			M.handle_connection_error(session)
		end
	end

	ws_client.on_error = function()
		M.handle_connection_error(session)
	end
end

function M.handle_connection_error(session)
	if session.reconnecting then
		return
	end

	local session_id = M.get_session_id(session)
	if not session_id then
		-- Session was already cleaned up, don't try to reconnect
		return
	end

	local attempts = M.reconnect_attempts[session_id] or 0

	if attempts < M.max_reconnect_attempts and session.inspector_url then
		attempts = attempts + 1
		M.reconnect_attempts[session_id] = attempts

		local delay = M.reconnect_delay * math.pow(2, attempts - 1)

		vim.defer_fn(function()
			if M.sessions[session_id] and not session.reconnecting then
				vim.notify(
					string.format("Reconnection attempt %d/%d", attempts, M.max_reconnect_attempts),
					vim.log.levels.INFO)
				M.connect_to_inspector(session, true)
			end
		end, delay)
	else
		vim.notify("Failed to maintain debugger connection", vim.log.levels.ERROR)
		M.cleanup_session(session)
	end
end

function M.get_session_id(session)
	for id, s in pairs(M.sessions) do
		if s == session then
			return id
		end
	end
	return nil
end

function M.initialize_runtime(session)
	local debug_logger = require("consolelog.core.debug_logger")
	vim.schedule(function()
		local runtime_ok = M.send_command(session, "Runtime.enable", {})
		local debugger_ok = M.send_command(session, "Debugger.enable", {})

		if not runtime_ok or not debugger_ok then
			debug_logger.log("INSPECTOR", "Failed to initialize runtime or debugger")
			return
		end

		vim.defer_fn(function()
			local run_ok = M.send_command(session, "Runtime.runIfWaitingForDebugger", {})
			if run_ok then
				session.ready = true
				debug_logger.log("INSPECTOR", "Session initialized and ready")
			else
				debug_logger.log("INSPECTOR", "Failed to start debugger execution")
			end
		end, constants.TIMING.INSPECTOR_INIT_DELAY_MS)
	end)
end

function M.handle_inspector_message(session, message)
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("INSPECTOR", "Received message: " .. message:sub(1, 200))

	local data = vim.json.decode(message)

	if not data then
		debug_logger.log("INSPECTOR", "Failed to decode JSON message")
		return
	end

	debug_logger.log("INSPECTOR", "Decoded method: " .. (data.method or "nil"))

	-- Handle console messages
	if data.method == "Runtime.consoleAPICalled" then
		local console_data = data.params
		if console_data and console_data.args then
			debug_logger.log("INSPECTOR", "Console API called with " .. #console_data.args .. " args")

			-- Schedule processing to avoid fast event context
			vim.schedule(function()
				-- Format all arguments into a single console text
				local console_parts = {}
				for _, arg in ipairs(console_data.args) do
					debug_logger.log("INSPECTOR",
						"Arg type: " ..
						(arg.type or "nil") .. ", value: " .. tostring(arg.value or "nil"))
					if arg.type == "string" then
						table.insert(console_parts, arg.value or "")
					elseif arg.type == "number" then
						table.insert(console_parts, tostring(arg.value))
					elseif arg.type == "boolean" then
						table.insert(console_parts, tostring(arg.value))
					elseif arg.type == "object" and arg.className then
						table.insert(console_parts, "[" .. arg.className .. "]")
					elseif arg.type == "undefined" then
						table.insert(console_parts, "undefined")
					elseif arg.type == "null" then
						table.insert(console_parts, "null")
					else
						table.insert(console_parts, tostring(arg.value or arg.type))
					end
				end

				local console_text = table.concat(console_parts, " ")
				local location = console_data.stackTrace and console_data.stackTrace.callFrames[1]

				if location then
					debug_logger.log("INSPECTOR",
						string.format(
							"Location found: URL: %s | Line: %d | Column: %d | Func: %s | Text: %s",
							location.url or "nil",
							location.lineNumber or 0,
							location.columnNumber or 0,
							location.functionName or "nil",
							console_text:sub(1, 50)))
					local location_data = {
						lineNumber = location.lineNumber,
						columnNumber = location.columnNumber,
						url = location.url,
						functionName = location.functionName
					}

					-- Process the console message using the new line matching
					local line_matching = require("consolelog.processing.line_matching")
					line_matching.process_console_message(session.bufnr, console_text, location_data)
				else
					debug_logger.log("INSPECTOR", "No location found in stack trace")
				end
			end)
		else
			debug_logger.log("INSPECTOR", "No console data or args found")
		end
	elseif data.method then
		debug_logger.log("INSPECTOR", "Unhandled method: " .. data.method)
	end
end

function M.send_command(session, method, params)
	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("INSPECTOR", "Sending command: " .. method .. ", session.ws_id: " .. tostring(session.ws_id))

	if not session.ws_id then
		debug_logger.log("INSPECTOR", "No WebSocket connection for command: " .. method)
		return false, "No WebSocket connection"
	end

	local ws_server = require("consolelog.communication.ws_server")
	local ws_client = ws_server.get_client(session.ws_id)
	if not ws_client then
		debug_logger.log("INSPECTOR", "WebSocket client not found for command: " .. method)
		return false, "WebSocket client not found"
	end

	local message = {
		id = M.message_id,
		method = method,
		params = params or {}
	}
	local json_message = vim.json.encode(message)
	debug_logger.log("INSPECTOR", "Command JSON: " .. json_message:sub(1, 100))
	M.message_id = M.message_id + 1

	local result = ws_server.send_client_message(session.ws_id, json_message)
	debug_logger.log("INSPECTOR", "Send result: " .. tostring(result))
	return result
end

function M.cleanup_session(session)
	if session.bufnr then
		local display = require("consolelog.display.display")
		display.clear_buffer(session.bufnr)
	end

	if session.job_id then
		vim.fn.jobstop(session.job_id)
		session.job_id = nil
	end

	local session_id = M.get_session_id(session)
	if session_id then
		M.sessions[session_id] = nil
		M.reconnect_attempts[session_id] = nil
	end
end

function M.stop_all_sessions()
	for _, session in pairs(M.sessions) do
		M.cleanup_session(session)
	end
	M.sessions = {}
	M.reconnect_attempts = {}
end

function M.get_session_for_buffer(bufnr)
	for _, session in pairs(M.sessions) do
		if session.bufnr == bufnr then
			return session
		end
	end
	return nil
end

function M.is_session_ready(session_id)
	local session = M.sessions[session_id]
	if not session then
		return false
	end

	return session.ready and session.ws_id ~= nil
end

function M.get_active_sessions()
	local active = {}
	for id, session in pairs(M.sessions) do
		if M.is_session_ready(id) then
			table.insert(active, {
				id = id,
				filepath = session.filepath,
				bufnr = session.bufnr,
			})
		end
	end
	return active
end

function M.setup_auto_attach()
	if M.auto_attach_timer then
		vim.fn.timer_stop(M.auto_attach_timer)
	end

	M.auto_attach_timer = vim.fn.timer_start(2000, function()
		local found_process = false
		local result = vim.fn.system("pgrep -f 'node.*--inspect'")

		if vim.v.shell_error == 0 and result ~= "" then
			found_process = true

			-- Try to connect to the default inspector port
			local inspector_url = "ws://127.0.0.1:9229"
			local bufnr = vim.api.nvim_get_current_buf()
			local session = {
				filepath = vim.api.nvim_buf_get_name(bufnr),
				bufnr = bufnr,
				ws_id = nil,
				inspector_url = inspector_url,
				job_id = nil,
				ready = false,
				reconnecting = false,
			}

			M.connect_to_inspector(session)
			local session_id = "auto_" .. bufnr
			M.sessions[session_id] = session
		end

		return found_process and 0 or 1 -- Stop timer if process found
	end, { ["repeat"] = -1 })
end

return M
