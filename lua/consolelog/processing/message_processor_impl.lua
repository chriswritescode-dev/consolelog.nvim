local M = {}

local line_matching = require("consolelog.processing.line_matching")
local display = require("consolelog.display.display")
local debug_logger = require("consolelog.core.debug_logger")
local utils = require("consolelog.core.utils")

function M.format_args(args, method)
	if not args or #args == 0 then
		return "[console." .. (method or "log") .. "]", nil
	end

	debug_logger.log("NEW_PROCESSOR", string.format("Processing %d args: %s", #args, vim.inspect(args)))

	-- Handle ANSI format strings from browser console
	if #args >= 1 and type(args[1]) == "string" then
		local first = args[1]
		if first:match("%%s") then
			first = first:gsub("\27%[[^m]*m", "")
			first = first:gsub("%%s%s*", "")
			args[1] = first
			debug_logger.log("NEW_PROCESSOR", "Stripped ANSI codes and %%s from first arg")
		end
	end

	local formatted_args = {}
	local raw_args = {}

	for _, arg in ipairs(args) do
		if type(arg) == "string" then
			if arg:match("^%s*[{%[]") and arg:match("[}%]]%s*$") then
				local ok, parsed = pcall(vim.fn.json_decode, arg)
				if ok and type(parsed) == "table" then
					local count = 0
					local is_array = utils.islist(parsed)

					if is_array then
						count = #parsed
					else
						for _ in pairs(parsed) do
							count = count + 1
						end
					end

					if count <= 3 then
						table.insert(formatted_args,
							vim.inspect(parsed, { indent = "", newline = " " }))
						table.insert(raw_args, parsed)
					else
						local preview
						if is_array then
							preview = string.format("[%d items]", count)
						else
							local keys = {}
							local i = 0
							for k, _ in pairs(parsed) do
								if i < 3 then
									table.insert(keys, k)
									i = i + 1
								else
									break
								end
							end
							preview = "{" .. table.concat(keys, ", ")
							if count > 3 then
								preview = preview .. ", ..."
							end
							preview = preview .. "}"
						end
						preview = preview .. " [→ li]"
						table.insert(formatted_args, preview)
						table.insert(raw_args, parsed)
					end
				else
					table.insert(formatted_args, arg)
					table.insert(raw_args, arg)
				end
			else
				table.insert(formatted_args, arg)
				table.insert(raw_args, arg)
			end
		elseif type(arg) == "table" then
			table.insert(raw_args, arg)
			local formatted = vim.inspect(arg, { indent = "", newline = " " })
			table.insert(formatted_args, formatted)
		else
			table.insert(formatted_args, tostring(arg))
			table.insert(raw_args, arg)
		end
	end

	local output = table.concat(formatted_args, " ")
	local raw_value = #raw_args > 1 and raw_args or (raw_args[1] or output)

	debug_logger.log("NEW_PROCESSOR", string.format("Output: %s, Raw value type: %s, Raw args count: %d",
		output:sub(1, 50), type(raw_value), #raw_args))

	return output, raw_value
end

function M.process_message(msg)
	if not msg.method then
		debug_logger.log("NEW_PROCESSOR", "Missing method in message")
		return false
	end

	local consolelog = require("consolelog")

	-- Validate projectId if provided (multi-instance isolation)
	if msg.projectId and consolelog.project_id then
		if msg.projectId ~= consolelog.project_id then
			debug_logger.log("NEW_PROCESSOR",
				string.format("Project mismatch: expected %s, got %s - ignoring message",
					consolelog.project_id, msg.projectId))
			return false
		end
		debug_logger.log("NEW_PROCESSOR", string.format("Project ID validated: %s", msg.projectId))
	end

	local display_methods = consolelog.config and consolelog.config.websocket and
	consolelog.config.websocket.display_methods
	if display_methods then
		local should_display = false
		for _, method in ipairs(display_methods) do
			if method == msg.method then
				should_display = true
				break
			end
		end
		if not should_display then
			debug_logger.log("NEW_PROCESSOR",
				string.format("Skipping method '%s' (not in display_methods)", msg.method))
			return false
		end
	end

	-- Convert message format: message (string) -> args (array)
	local args = msg.args or {}
	if msg.message and #args == 0 then
		args = { msg.message }
	end

	debug_logger.log("NEW_PROCESSOR",
		string.format("=== PROCESSING MESSAGE (NEW) === method=%s, file=%s, line=%d, projectId=%s",
			msg.method,
			msg.location and msg.location.file or "unknown",
			msg.location and msg.location.line or 0,
			msg.projectId or "none"))

	-- 1. Format arguments
	local output, raw_value = M.format_args(args, msg.method)

	-- 2. Use new line matching method with project scoping
	local bufnr, line, match_type = line_matching.match_by_file_and_command(msg, consolelog.project_root)

	if bufnr and line then
		-- 3. Update display
		display.update_output(bufnr, line, output, msg.method, raw_value)

		-- 4. Log success
		debug_logger.log("NEW_PROCESSOR", string.format(
			"SUCCESS: %s -> buffer %d, line %d (%s)",
			msg.location and msg.location.file or "unknown", bufnr, line, match_type
		))

		return true
	else
		-- 5. Handle no match
		M.handle_no_match(msg, output, raw_value, match_type)
		return false
	end
end

function M.handle_no_match(msg, output, raw_value, reason)
	debug_logger.log("NEW_PROCESSOR", string.format(
		"NO MATCH: %s (%s)", msg.location and msg.location.file or "unknown", reason
	))
end

function M.get_matching_stats()
	local line_matching = require("consolelog.processing.line_matching")
	return line_matching.get_state_info()
end

function M.reset()
	local line_matching = require("consolelog.processing.line_matching")
	line_matching.reset()
	debug_logger.log("NEW_PROCESSOR", "Reset new message processor state")
end

function M.reset_matched_lines()
	M.reset()
end

return M

