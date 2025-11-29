local M = {}

local formatter = require("consolelog.processing.formatter")
local constants = require("consolelog.core.constants")
local extmark_writer = require("consolelog.display.extmark_writer")
local vtext_builder = require("consolelog.display.virtual_text_builder")
local utils = require("consolelog.core.utils")

M.extmarks = {}
M.throttle_timers = {}
M.pending_updates = {}
M.tracked_buffers = {}
M.last_show_time = {}
M.showing_outputs = false

function M.show_outputs(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local utils = require("consolelog.core.utils")
	if not utils.is_javascript_buffer(bufnr) then
		return
	end

	if M.showing_outputs then
		return
	end

	local now = vim.loop.now()
	if M.last_show_time[bufnr] and (now - M.last_show_time[bufnr]) < constants.DISPLAY.THROTTLE_MIN_MS then
		return
	end
	M.last_show_time[bufnr] = now

	M.showing_outputs = true

	local success, err = pcall(function()
		local consolelog = require("consolelog")
		local outputs = consolelog.outputs[bufnr]

		local debug_logger = require("consolelog.core.debug_logger")
		debug_logger.log("SHOW_OUTPUTS",
			string.format("=== SHOW_OUTPUTS CALLED === buffer %d, outputs count: %d",
				bufnr, outputs and #outputs or 0))

		if not outputs or vim.tbl_isempty(outputs) then
			debug_logger.log("SHOW_OUTPUTS", "No outputs to display")
			return
		end

		for i, output in ipairs(outputs) do
			debug_logger.log("SHOW_OUTPUTS", string.format("Output %d: line=%d, type=%s",
				i, output.line, output.console_type or "log"))
			debug_logger.log("SHOW_OUTPUTS_VALUE", string.format("  Full value: %s", tostring(output.value)))
			if output.raw_value then
				debug_logger.log("SHOW_OUTPUTS_RAW", string.format("  Raw value type: %s, content: %s",
					type(output.raw_value),
					type(output.raw_value) == "table" and vim.inspect(output.raw_value) or
					tostring(output.raw_value)))
			else
				debug_logger.log("SHOW_OUTPUTS_RAW", "  No raw_value present")
			end
		end

		M.clear_buffer(bufnr)

		for _, output in ipairs(outputs) do
			M.render_output(bufnr, output)
		end
	end)

	M.showing_outputs = false

	if not success then
		local debug_logger = require("consolelog.core.debug_logger")
		debug_logger.log("SHOW_OUTPUTS_ERROR", string.format("Error in show_outputs: %s", tostring(err)))
	end
end

function M.render_output(bufnr, output)
	local line_num = output.line - 1

	local ok, line_count = pcall(vim.api.nvim_buf_line_count, bufnr)
	if not ok or line_num < 0 or line_num >= line_count then
		return
	end

	local consolelog = require("consolelog")
	local debug_logger = require("consolelog.core.debug_logger")
	
	debug_logger.log("RENDER",
		string.format("Rendering output for buffer %d, line %d (0-based: %d), line_count: %d",
			bufnr, output.line, line_num, line_count))

	local virt_lines, is_multiline = vtext_builder.build_virtual_text(output, consolelog.config)
	
	debug_logger.log("RENDER", string.format("Console type: %s, multiline: %s, lines: %d",
		tostring(output.console_type), tostring(is_multiline), #virt_lines))

	local priority = consolelog.config.display.priority or 250
	local mark_id

	if is_multiline then
		mark_id = extmark_writer.create_multiline_extmark(
			bufnr,
			consolelog.namespace,
			line_num,
			virt_lines,
			priority
		)
	else
		mark_id = extmark_writer.create_single_extmark(
			bufnr,
			consolelog.namespace,
			line_num,
			virt_lines[1],
			nil,
			priority,
			consolelog.config.display.virtual_text_pos or "eol"
		)
	end

	if mark_id then
		debug_logger.log("RENDER", string.format("Created extmark %d with namespace %d",
			mark_id, consolelog.namespace))

		if not M.extmarks[bufnr] then
			M.extmarks[bufnr] = {}
		end
		table.insert(M.extmarks[bufnr], mark_id)
	else
		debug_logger.log("RENDER_ERROR", "Failed to create extmark")
	end
end

function M.get_highlight_for_type(console_type)
	local highlights = {
		log = "ConsoleLogOutput",
		error = "ConsoleLogError",
		warn = "ConsoleLogWarning",
		info = "ConsoleLogInfo",
		debug = "ConsoleLogDebug",
	}

	local consolelog = require("consolelog")
	return highlights[console_type] or consolelog.config.display.highlight
end

function M.hide_outputs()
	local bufnr = vim.api.nvim_get_current_buf()
	M.clear_buffer(bufnr)
end

function M.clear_buffer(bufnr)
	local debug_logger = require("consolelog.core.debug_logger")
	local consolelog = require("consolelog")
	debug_logger.log("CLEAR", string.format("Clearing namespace %d for buffer %d", consolelog.namespace, bufnr))

	pcall(vim.api.nvim_buf_clear_namespace, bufnr, consolelog.namespace, 0, -1)
	M.extmarks[bufnr] = {}

	if M.throttle_timers[bufnr] then
		vim.loop.timer_stop(M.throttle_timers[bufnr])
		M.throttle_timers[bufnr] = nil
	end
	M.pending_updates[bufnr] = nil
end

function M.clear_buffer_completely(bufnr)
	M.clear_buffer(bufnr)
	M.tracked_buffers[bufnr] = nil
end

function M.clear_all()
	for bufnr, _ in pairs(M.extmarks) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			M.clear_buffer_completely(bufnr)
		end
	end
	M.extmarks = {}
	M.throttle_timers = {}
	M.pending_updates = {}
	M.tracked_buffers = {}
end

function M.is_tracked_buffer(bufnr)
	return M.tracked_buffers[bufnr] == true
end

function M.handle_buffer_switch(new_bufnr)
	if not M.is_tracked_buffer(new_bufnr) then
		return
	end

	local consolelog = require("consolelog")
	if consolelog.outputs[new_bufnr] and not vim.tbl_isempty(consolelog.outputs[new_bufnr]) then
		M.show_outputs(new_bufnr)
	end
end

function M.update_output(bufnr, line, value, console_type, raw_value)
	local utils = require("consolelog.core.utils")
	if not utils.is_javascript_buffer(bufnr) then
		return
	end

	local consolelog = require("consolelog")
	if consolelog.project_root then
		local buf_path = vim.api.nvim_buf_get_name(bufnr)
		if buf_path and buf_path ~= "" then
			if not buf_path:find(consolelog.project_root, 1, true) then
				local debug_logger = require("consolelog.core.debug_logger")
				debug_logger.log("DISPLAY",
					string.format("Buffer %d (%s) not in project %s - ignoring",
						bufnr, buf_path, consolelog.project_root))
				return
			end
		end
	end

	M.tracked_buffers[bufnr] = true

	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("UPDATE_OUTPUT",
		string.format("=== UPDATE_OUTPUT CALLED === console_type: %s, line: %d, value: %s",
			tostring(console_type), line, tostring(value):sub(1, 100)))

	if raw_value then
		local utils = require("consolelog.core.utils")
		debug_logger.log("UPDATE_OUTPUT", string.format("Raw value type: %s, islist: %s",
			type(raw_value), utils.islist(raw_value) and "yes" or "no"))
		if type(raw_value) == "table" then
			debug_logger.log("UPDATE_OUTPUT", string.format("Raw value content: %s", vim.inspect(raw_value)))
		end
	end

	if not consolelog.outputs[bufnr] then
		consolelog.outputs[bufnr] = {}
	end

	if not M.pending_updates[bufnr] then
		M.pending_updates[bufnr] = {}
	end

	local existing_output = nil
	for _, output in ipairs(consolelog.outputs[bufnr] or {}) do
		if output.line == line then
			existing_output = output
			break
		end
	end

	local execution_count = 1
	local history = {}
	if existing_output then
		execution_count = (existing_output.execution_count or 1) + 1
		history = existing_output.history or {}
	end

	local value_type = "unknown"
	if raw_value then
		if type(raw_value) == "table" then
			local utils = require("consolelog.core.utils")
			if utils.islist(raw_value) then
				value_type = "array"
			else
				value_type = "object"
			end
		elseif type(raw_value) == "string" then
			value_type = "string"
		elseif type(raw_value) == "number" then
			value_type = "number"
		elseif type(raw_value) == "boolean" then
			value_type = "boolean"
		elseif raw_value == nil then
			value_type = "null"
		end
	else
		local parser = require("consolelog.processing.parser")
		value_type = parser.detect_value_type(tostring(value))
	end

	local update = {
		line = line,
		value = value,
		raw_value = raw_value or value,
		console_type = console_type or "log",
		type = value_type,
		timestamp = require("consolelog.core.utils").get_timestamp(),
		execution_count = execution_count,
		history = history,
	}

	if consolelog.config.history and consolelog.config.history.enabled then
		local history_entry = {
			value = value,
			raw_value = raw_value or value,
			console_type = console_type or "log",
			timestamp = update.timestamp,
			execution_count = execution_count,
		}
		table.insert(update.history, 1, history_entry)

		local max_history = consolelog.config.history.max_entries or constants.DISPLAY.DEFAULT_HISTORY_MAX
		if #update.history > max_history then
			for i = #update.history, max_history + 1, -1 do
				table.remove(update.history, i)
			end
		end

		debug_logger.log("UPDATE_OUTPUT",
			string.format("Added to history: line %d, count %d", line, execution_count))
	end

	M.pending_updates[bufnr][line] = update

	debug_logger.log("UPDATE_OUTPUT", string.format("Stored console_type: %s",
		tostring(M.pending_updates[bufnr][line].console_type)))

	M.schedule_update(bufnr)
end

function M.schedule_update(bufnr)
	if M.throttle_timers[bufnr] then
		return
	end

	local consolelog = require("consolelog")
	local throttle_ms = consolelog.config.display.throttle_ms or constants.DISPLAY.DEFAULT_THROTTLE_MS

	M.throttle_timers[bufnr] = vim.defer_fn(function()
		M.throttle_timers[bufnr] = nil
		M.apply_pending_updates(bufnr)
	end, throttle_ms)
end

function M.apply_pending_updates(bufnr)
	local pending = M.pending_updates[bufnr]

	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("APPLY_UPDATES", string.format("=== APPLY_UPDATES CALLED === Buffer %d, pending count: %d",
		bufnr, pending and vim.tbl_count(pending) or 0))

	if not pending or vim.tbl_isempty(pending) then
		debug_logger.log("APPLY_UPDATES", "No pending updates to apply")
		return
	end

	local consolelog = require("consolelog")

	if not consolelog.outputs[bufnr] then
		consolelog.outputs[bufnr] = {}
		debug_logger.log("APPLY_UPDATES", "Initialized outputs table for buffer " .. bufnr)
	end

	for line, update in pairs(pending) do
		debug_logger.log("APPLY_UPDATE_ITEM", string.format("Processing line %d: value=%s, raw_value type=%s",
			line, tostring(update.value):sub(1, 50), type(update.raw_value)))
		if update.raw_value and type(update.raw_value) == "table" then
			debug_logger.log("APPLY_UPDATE_RAW",
				string.format("  Raw value: %s", vim.inspect(update.raw_value)))
		end

		local existing_index = nil
		for i, output in ipairs(consolelog.outputs[bufnr]) do
			if output.line == line then
				existing_index = i
				debug_logger.log("APPLY_UPDATE_ITEM",
					string.format("  Found existing output at index %d", i))
				break
			end
		end

		if existing_index then
			consolelog.outputs[bufnr][existing_index] = update
			debug_logger.log("APPLY_UPDATE_ITEM",
				string.format("  Updated existing output at index %d", existing_index))
		else
			local insert_index = 1
			for i, output in ipairs(consolelog.outputs[bufnr]) do
				if output.line < line then
					insert_index = i + 1
				else
					break
				end
			end
			table.insert(consolelog.outputs[bufnr], insert_index, update)
			debug_logger.log("APPLY_UPDATE_ITEM",
				string.format("  Added new output at index %d", insert_index))
		end
	end

	M.pending_updates[bufnr] = {}

	debug_logger.log("APPLY_UPDATES", string.format("=== FINAL STATE === outputs count: %d, enabled: %s",
		#consolelog.outputs[bufnr], tostring(consolelog.config.enabled)))

	if consolelog.config.enabled then
		debug_logger.log("APPLY_UPDATES", "Calling show_outputs for buffer " .. bufnr)
		M.show_outputs(bufnr)
	else
		debug_logger.log("APPLY_UPDATES", "Consolelog not enabled, skipping show_outputs")
	end
end

function M.toggle_output_window()
	local bufnr = vim.api.nvim_get_current_buf()

	local consolelog = require("consolelog")
	local outputs = consolelog.outputs[bufnr]

	if not outputs or vim.tbl_isempty(outputs) then
		vim.notify("No console outputs to display", vim.log.levels.INFO)
		return
	end

	local win_exists = false
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local win_buf = vim.api.nvim_win_get_buf(win)
		local buf_name = vim.api.nvim_buf_get_name(win_buf)
		if buf_name:match("Console Output") or vim.b[win_buf].consolelog_output then
			vim.api.nvim_win_close(win, true)
			win_exists = true
			break
		end
	end

	if win_exists then
		return
	end

	local utils = require("consolelog.core.utils")
	local lines = {}
	for _, output in ipairs(outputs) do
		local type_indicator = ""
		if output.console_type == "error" then
			type_indicator = "[ERROR] "
		elseif output.console_type == "warn" then
			type_indicator = "[WARN]  "
		elseif output.console_type == "info" then
			type_indicator = "[INFO]  "
		elseif output.console_type == "debug" then
			type_indicator = "[DEBUG] "
		else
			type_indicator = "[LOG]   "
		end

		local header = string.format("Line %d %s", output.line, type_indicator)
		table.insert(lines, header)
		table.insert(lines, string.rep("-", 60))

		local content
		if output.raw_value then
			local utils = require("consolelog.core.utils")
			if type(output.raw_value) == "table" and utils.islist(output.raw_value) then
				local parts = {}
				for _, arg in ipairs(output.raw_value) do
					if type(arg) == "string" then
						table.insert(parts, utils.strip_ansi(arg))
					elseif type(arg) == "table" then
						local ok, json = pcall(vim.json.encode, arg, { indent = 2 })
						if ok then
							table.insert(parts, json)
						else
							table.insert(parts, vim.inspect(arg))
						end
					else
						table.insert(parts, tostring(arg))
					end
				end
				content = table.concat(parts, " ")
			else
				local ok, decoded = pcall(vim.json.decode, output.raw_value)
				if ok and type(decoded) == "table" then
					content = vim.json.encode(decoded, { indent = 2 })
				else
					content = utils.strip_ansi(tostring(output.raw_value))
				end
			end
		else
			content = utils.strip_ansi(output.value or "[No output]")
		end

		for line in content:gmatch("[^\n]+") do
			table.insert(lines, "  " .. line)
		end

		table.insert(lines, "")
	end

	local width = math.min(120, math.floor(vim.o.columns * constants.DISPLAY.WINDOW_WIDTH_RATIO))
	local height = math.min(#lines + 2, math.floor(vim.o.lines * constants.DISPLAY.WINDOW_HEIGHT_RATIO))

	local output_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, lines)
	vim.bo[output_buf].filetype = "javascript"
	vim.bo[output_buf].modifiable = false
	vim.b[output_buf].consolelog_output = true

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = vim.o.lines - height - 2,
		style = "minimal",
		border = "rounded",
		title = " Console Output ",
		title_pos = "center",
	}

	vim.api.nvim_open_win(output_buf, true, win_opts)

	vim.keymap.set("n", "q", function() vim.cmd("close") end, { buffer = output_buf, silent = true })
	vim.keymap.set("n", "<Esc>", function() vim.cmd("close") end, { buffer = output_buf, silent = true })
	vim.keymap.set("n", "ya", function() vim.cmd("%y") end, { buffer = output_buf, silent = true, desc = "Yank all" })
end

return M
