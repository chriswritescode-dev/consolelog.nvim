local M = {}

M.pending_responses = {}

-- Must match the sourceURL comment in js/node-console-format.js: frames from
-- the injected console hook are never the origin of a log.
M.CONSOLE_FORMAT_SOURCE_URL = "consolelog-node-format.js"

local CONSOLE_TYPE_MAP = {
	error = "error",
	warning = "warn",
	warn = "warn",
	info = "info",
	debug = "debug",
	log = "log",
}

function M.handle_message(session, raw_message)
	local ok, message = pcall(vim.json.decode, raw_message)
	if not ok then
		return
	end

	if message.method then
		M.handle_event(session, message)
	elseif message.id then
		M.handle_response(session, message)
	end
end

function M.handle_event(session, message)
	if message.method == "Runtime.consoleAPICalled" then
		M.handle_console_event(session, message.params)
	elseif message.method == "Runtime.exceptionThrown" then
		M.handle_exception_event(session, message.params)
	elseif message.method == "Debugger.paused" then
		require("consolelog.communication.inspector").send_command(session, "Debugger.resume", {})
	elseif message.method == "Inspector.detached" then
		vim.schedule(function()
			vim.notify("Debugger detached: " .. (message.params.reason or "unknown"), vim.log.levels.WARN)
		end)
	end
end

function M.remote_object_to_arg(arg)
	if arg.type == "string" then
		return arg.value
	elseif arg.type == "number" then
		return arg.unserializableValue or arg.value
	elseif arg.type == "boolean" then
		return arg.value
	elseif arg.type == "undefined" then
		return "undefined"
	elseif arg.type == "bigint" then
		return arg.unserializableValue or arg.description or tostring(arg.value)
	elseif arg.type == "symbol" then
		return arg.description or "Symbol()"
	elseif arg.type == "function" then
		return M.format_function_preview(arg)
	elseif arg.type == "object" then
		if arg.subtype == "null" then
			return "null"
		elseif arg.subtype == "map" then
			return M.format_map_preview(arg)
		elseif arg.subtype == "set" then
			return M.format_set_preview(arg)
		elseif arg.subtype == "regexp" or arg.subtype == "date" or arg.subtype == "error" then
			return arg.description or ("[" .. (arg.subtype or "Object") .. "]")
		elseif arg.subtype == "array" or arg.preview then
			if arg.preview then
				return vim.json.encode(M.preview_to_table(arg.preview))
			end
			return arg.description or "[Object]"
		else
			return arg.description or "[Object]"
		end
	else
		return arg.description or arg.value or tostring(arg.type)
	end
end

function M.preview_to_table(preview)
	if not preview or not preview.properties then
		return {}
	end

	local is_array = preview.subtype == "array"
	local result = {}

	if is_array then
		-- Sort by numeric name to ensure correct array order (CDP may send
		-- properties in any order). CDP uses 0-based indexing.
		local sorted = {}
		for _, prop in ipairs(preview.properties) do
			local idx = tonumber(prop.name)
			if idx then
				table.insert(sorted, { idx = idx, prop = prop })
			end
		end
		table.sort(sorted, function(a, b) return a.idx < b.idx end)
		for _, entry in ipairs(sorted) do
			local prop = entry.prop
			local val
			if prop.valuePreview then
				val = prop.valuePreview.subtype == "array" and "[...]" or "{...}"
			elseif prop.type == "number" then
				val = tonumber(prop.value)
			elseif prop.type == "string" then
				val = prop.value
			elseif prop.type == "boolean" then
				val = prop.value == "true"
			elseif prop.type == "object" then
				if prop.subtype == "array" then
					val = "[...]"
				else
					val = "{...}"
				end
			else
				val = prop.value
			end
			table.insert(result, val)
		end
		if preview.overflow then
			table.insert(result, "...")
		end
	else
		for _, prop in ipairs(preview.properties) do
			if prop.valuePreview then
				result[prop.name] = prop.valuePreview.subtype == "array" and "[...]" or "{...}"
			elseif prop.type == "number" then
				result[prop.name] = tonumber(prop.value)
			elseif prop.type == "string" then
				result[prop.name] = prop.value
			elseif prop.type == "boolean" then
				result[prop.name] = prop.value == "true"
			elseif prop.type == "object" then
				if prop.subtype == "array" then
					result[prop.name] = "[...]"
				else
					result[prop.name] = "{...}"
				end
			else
				result[prop.name] = prop.value
			end
		end
		if preview.overflow then
			result["..."] = "..."
		end
	end

	return result
end

function M.handle_console_event(session, params)
	local args = params.args or {}

	local method = CONSOLE_TYPE_MAP[params.type] or "log"
	local line = M.extract_line_number(params.stackTrace, session.filepath)
	if not line then
		return
	end

	local converted = {}
	for _, arg in ipairs(args) do
		table.insert(converted, tostring(M.remote_object_to_arg(arg)))
	end

	-- Arguments are already rendered by the debuggee (see
	-- js/node-console-format.js), so they are displayed verbatim rather than
	-- re-serialized.
	local output = table.concat(converted, " ")
	local display = require("consolelog.display.display")

	vim.schedule(function()
		display.update_output(session.bufnr, line, output, method, output)
	end)
end

function M.handle_exception_event(session, params)
	local exception = params.exceptionDetails
	if not exception then
		return
	end

	local desc = exception.exception and exception.exception.description
		or exception.text
		or "Uncaught exception"

	local line = nil
	if exception.stackTrace then
		line = M.extract_line_number(exception.stackTrace, session.filepath)
	end
	if not line and exception.lineNumber then
		line = exception.lineNumber + 1
	end

	if not line then
		return
	end

	local text = desc:match("[^\n]+") or desc

	local display = require("consolelog.display.display")

	vim.schedule(function()
		display.update_output(session.bufnr, line, text, "error", desc)
	end)
end

function M.extract_line_number(stackTrace, filepath)
	if not stackTrace or not stackTrace.callFrames then
		return nil
	end

	local filename = vim.fn.fnamemodify(filepath, ":t")
	local full_path = vim.fn.fnamemodify(filepath, ":p")

	for _, frame in ipairs(stackTrace.callFrames) do
		if frame.url then
			local frame_file = frame.url:match("([^/]+)$")
			local frame_path = frame.url:match("file://(.+)$")

			if frame_file == filename or frame_path == full_path then
				return frame.lineNumber + 1
			end
		end
	end

	for _, frame in ipairs(stackTrace.callFrames) do
		if frame.lineNumber and frame.url ~= M.CONSOLE_FORMAT_SOURCE_URL then
			return frame.lineNumber + 1
		end
	end

	return nil
end

function M.format_function_preview(arg)
	local name = arg.description or "anonymous"
	name = name:match("^function%s+(%w+)") or name:match("^(%w+)") or "anonymous"
	return "[Function: " .. name .. "]"
end

function M.format_map_preview(arg)
	if arg.preview and arg.preview.entries then
		local entries = {}
		for i, entry in ipairs(arg.preview.entries) do
			if i <= 3 then
				local key = entry.key and (entry.key.description or entry.key.value) or "?"
				local value = entry.value and (entry.value.description or entry.value.value) or "?"
				table.insert(entries, key .. " => " .. value)
			end
		end
		if #arg.preview.entries > 3 then
			table.insert(entries, "...")
		end
		return "Map { " .. table.concat(entries, ", ") .. " }"
	end
	return arg.description or "Map {}"
end

function M.format_set_preview(arg)
	if arg.preview and arg.preview.entries then
		local values = {}
		for i, entry in ipairs(arg.preview.entries) do
			if i <= 5 then
				table.insert(values, entry.value and (entry.value.description or entry.value.value) or "?")
			end
		end
		if #arg.preview.entries > 5 then
			table.insert(values, "...")
		end
		return "Set { " .. table.concat(values, ", ") .. " }"
	end
	return arg.description or "Set {}"
end

function M.handle_response(session, message)
	if M.pending_responses[message.id] then
		local callback = M.pending_responses[message.id]
		M.pending_responses[message.id] = nil

		if message.error then
			vim.notify("Inspector error: " .. (message.error.message or "Unknown error"),
				vim.log.levels.ERROR)
		elseif callback then
			callback(message.result)
		end
	end
end

function M.register_response_callback(id, callback)
	M.pending_responses[id] = callback
end

return M
