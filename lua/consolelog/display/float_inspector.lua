local M = {}

local formatter = require("consolelog.processing.formatter")

-- Create a floating window with the content
function M.open_inspector(content, opts)
	opts = opts or {}

	-- Format the content
	local formatted_lines = {}
	local formatted = formatter.format_for_inspector(content)

	-- Split into lines
	for line in formatted:gmatch("[^\n]+") do
		table.insert(formatted_lines, line)
	end

	-- Calculate window dimensions
	local max_width = math.min(opts.max_width or 100, vim.o.columns - 4)
	local max_height = math.min(opts.max_height or 30, vim.o.lines - 4)

	-- Adjust width based on content
	local content_width = 0
	for _, line in ipairs(formatted_lines) do
		content_width = math.max(content_width, #line)
	end
	local width = math.min(content_width + 4, max_width)
	local height = math.min(#formatted_lines + 3, max_height)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted_lines)

	vim.bo[buf].filetype = "lua"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	-- Calculate position (centered)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Create window
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = opts.title or " Console Output Inspector ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Store navigation state if provided
	if opts.bufnr and opts.line then
		vim.w[win].inspector_bufnr = opts.bufnr
		vim.w[win].inspector_line = opts.line
	end

	-- Set window options
	vim.wo[win].wrap = true
	vim.wo[win].cursorline = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false

	-- Add keymaps for the floating window
	local function close_window()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	-- Keymaps
	vim.keymap.set("n", "q", close_window, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_window, { buffer = buf, nowait = true })

	return win, buf
end

-- Inspect the output at the current cursor position with history support
function M.inspect_at_cursor(outputs, use_split)
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1]

	if not outputs or vim.tbl_isempty(outputs) then
		vim.notify("No console outputs in this buffer", vim.log.levels.INFO)
		return
	end

	local found_output = nil
	local found_line = nil
	for _, output in ipairs(outputs) do
		if output.line == line then
			found_output = output
			found_line = line
			break
		end
	end

	if not found_output then
		for offset = 1, 5 do
			for _, output in ipairs(outputs) do
				if output.line == line - offset or output.line == line + offset then
					found_output = output
					found_line = output.line
					break
				end
			end
			if found_output then break end
		end
	end

	if found_output then
		M.open_inspector_with_history(outputs, bufnr, found_line, use_split)
	else
		vim.notify("No console output near cursor position", vim.log.levels.INFO)
	end
end

-- Open inspector with history navigation support
function M.open_inspector_with_history(outputs, bufnr, line, use_split)
	local output = nil
	for _, o in ipairs(outputs or {}) do
		if o.line == line then
			output = o
			break
		end
	end

	if not output then
		vim.notify("No output at line " .. line, vim.log.levels.INFO)
		return
	end

	local history_index = 1
	local entry = output
	local pos = history_index
	local total = #(output.history or {})
	if total == 0 then
		total = 1
	end

	-- Format the content
	local content = entry.raw_value or entry.value
	local formatted_lines = {}
	local formatted = formatter.format_for_inspector(content)

	-- Split into lines
	for content_line in formatted:gmatch("[^\n]+") do
		table.insert(formatted_lines, content_line)
	end

	-- Calculate window dimensions - make it much larger
	local max_width = math.min(120, math.floor(vim.o.columns * 0.8))
	local max_height = math.min(40, math.floor(vim.o.lines * 0.8))

	-- Adjust width based on content - ensure minimum size
	local content_width = 0
	for _, content_line in ipairs(formatted_lines) do
		content_width = math.max(content_width, #content_line)
	end
	local width = math.max(60, math.min(content_width + 4, max_width))
	local height = math.max(10, math.min(#formatted_lines + 4, max_height))

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Function to refresh content
	local function refresh_content()
		local current_entry = output.history and output.history[history_index] or output
		if not current_entry then
			return
		end

		local current_pos = history_index
		local current_total = #(output.history or {})
		if current_total == 0 then
			current_total = 1
		end
		local current_content = current_entry.raw_value or current_entry.value
		local current_formatted = formatter.format_for_inspector(current_content)

		local lines_to_set = {}
		for content_line in current_formatted:gmatch("[^\n]+") do
			table.insert(lines_to_set, content_line)
		end

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_to_set)
		vim.bo[buf].modifiable = false
	end

	-- Set initial content
	refresh_content()

	-- Set buffer options
	vim.bo[buf].filetype = "lua"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	-- Create window (float or split based on parameter)
	local win
	if use_split then
		-- Open in a split window
		vim.cmd("botright split")
		win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_win_set_height(win, math.min(15, #formatted_lines + 3))

		-- Set split-specific title
		local title = string.format("Console Output - Line %d", line)
		if total > 1 then
			title = string.format("Console Output - Line %d [%d/%d]", line, pos, total)
		end
		vim.wo[win].statusline = title
	else
		-- Calculate position (centered) for float
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		-- Create window with position indicator in title
		local title = string.format(" Line %d: console.%s ", line, entry.console_type or "log")
		if total > 1 then
			title = string.format(" Line %d [%d/%d]: console.%s ", line, pos, total,
				entry.console_type or "log")
		end

		local win_opts = {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = title,
			title_pos = "center",
		}

		win = vim.api.nvim_open_win(buf, true, win_opts)
	end

	-- Set window options
	vim.wo[win].wrap = true
	vim.wo[win].cursorline = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false

	-- Add keymaps for the floating window
	local function close_window()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	-- Navigation functions
	local function navigate_history(direction)
		local total_history = #(output.history or {})
		if total_history == 0 then
			return
		end

		local current = history_index
		if direction == "older" or direction == "j" then
			current = math.min(current + 1, total_history)
		elseif direction == "newer" or direction == "k" then
			current = math.max(current - 1, 1)
		elseif direction == "latest" or direction == "g" then
			current = 1
		elseif direction == "oldest" or direction == "G" then
			current = total_history
		end

		history_index = current
		local new_entry = output.history[history_index]
		if new_entry then
			refresh_content()
			if use_split then
				local new_title = string.format("Console Output - Line %d [%d/%d]", line, history_index,
					total_history)
				vim.wo[win].statusline = new_title
			else
				local new_title = string.format(" Line %d [%d/%d]: console.%s ",
					line, history_index, total_history, new_entry.console_type or "log")
				vim.api.nvim_win_set_config(win, { title = new_title })
			end
		end
	end

	-- Keymaps
	vim.keymap.set("n", "q", close_window, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_window, { buffer = buf, nowait = true })

	-- History navigation (only if there's history)
	if total > 1 then
		vim.keymap.set("n", "j", function() navigate_history("older") end,
			{ buffer = buf, nowait = true, desc = "Navigate to older output" })
		vim.keymap.set("n", "k", function() navigate_history("newer") end,
			{ buffer = buf, nowait = true, desc = "Navigate to newer output" })
		vim.keymap.set("n", "gg", function() navigate_history("latest") end,
			{ buffer = buf, nowait = true, desc = "Jump to latest output" })
		vim.keymap.set("n", "G", function() navigate_history("oldest") end,
			{ buffer = buf, nowait = true, desc = "Jump to oldest output" })
	end

	return win, buf
end

function M.build_output_lines(output, config)
	local utils = require("consolelog.core.utils")
	config = config or require("consolelog").config

	local entries = utils.ordered_output_entries(output, config)
	local numbered = #entries > 1
	local lines = {}

	for i, entry in ipairs(entries) do
		local prefix = numbered and string.format("[%d] ", i) or ""
		local continuation = string.rep(" ", #prefix)
		local content = entry.raw_value or entry.value

		local ok, formatted = pcall(formatter.format_for_inspector, content)
		if not ok then
			formatted = tostring(content or "[nil]")
		elseif formatted == nil or formatted == "" then
			formatted = "[Empty]"
		end

		local is_first = true
		for content_line in tostring(formatted):gmatch("[^\n]+") do
			table.insert(lines, "  " .. (is_first and prefix or continuation) .. content_line)
			is_first = false
		end

		if is_first then
			table.insert(lines, "  " .. prefix .. "[Empty]")
		end
	end

	return lines
end

-- Inspect all outputs across ALL buffers
function M.inspect_all(all_outputs, all_unmatched_outputs)
	local success, err = pcall(function()
		local debug_logger = require("consolelog.core.debug_logger")
		debug_logger.log("INSPECT_ALL", "Starting inspect_all for ALL buffers")

		if not all_outputs then
			debug_logger.log("INSPECT_ALL_ERROR", "all_outputs is nil")
			vim.notify("all_outputs is nil", vim.log.levels.ERROR)
			return
		end

		-- Collect outputs from ALL buffers (both matched for inline and unmatched)
		local collected_outputs = {}
		local total_count = 0
		local matched_count = 0
		local unmatched_count = 0

		for bufnr, outputs in pairs(all_outputs) do
			if outputs and not vim.tbl_isempty(outputs) then
				-- Get buffer name for context
				local bufname = vim.api.nvim_buf_get_name(bufnr)
				local short_name = vim.fn.fnamemodify(bufname, ":t") -- Just filename
				if short_name == "" then short_name = "[No Name]" end

				for _, output in ipairs(outputs) do
					-- Add buffer info to each output
					local enriched = vim.tbl_extend("force", output, {
						bufnr = bufnr,
					bufname = short_name,
					full_path = bufname,
					display_status = "inline"
				})
				table.insert(collected_outputs, enriched)
				total_count = total_count + 1
				matched_count = matched_count + 1
			end
		end
	end

	for bufnr, outputs in pairs(all_unmatched_outputs or {}) do
		if outputs and not vim.tbl_isempty(outputs) then
			local bufname = vim.api.nvim_buf_get_name(bufnr)
			local short_name = vim.fn.fnamemodify(bufname, ":t")
			if short_name == "" then short_name = "[No Name]" end

			for _, output in ipairs(outputs) do
				local enriched = vim.tbl_extend("force", output, {
					bufnr = bufnr,
					bufname = short_name,
					full_path = bufname,
					display_status = output.matched and "matched" or "unmatched",
					line = output.matched_line or output.reported_line
				})
				table.insert(collected_outputs, enriched)
				total_count = total_count + 1
				if not output.matched then
					unmatched_count = unmatched_count + 1
				end
			end
		end
	end

		debug_logger.log("INSPECT_ALL", string.format("Found %d total outputs across all buffers", total_count))

		if total_count == 0 then
			vim.notify("No console outputs in any buffer", vim.log.levels.INFO)
			return
		end

		-- Sort by timestamp if available, or by buffer/line
		table.sort(collected_outputs, function(a, b)
			if a.timestamp and b.timestamp then
				return a.timestamp > b.timestamp -- Most recent first
			elseif a.bufnr == b.bufnr then
				return a.line < b.line
			else
				return a.bufnr < b.bufnr
			end
		end)

		-- Combine all outputs with file context
		local lines = {}
		local line_map = {}
		local current_line = 1
		local current_buf = nil

		for i, output in ipairs(collected_outputs) do
			debug_logger.log("INSPECT_ALL", string.format("Processing output %d from %s", i, output.bufname))

			-- Add file separator when buffer changes
			if current_buf ~= output.bufnr then
				if current_buf then
					table.insert(lines, "")
					current_line = current_line + 1
					table.insert(lines, "────────────────────────────────────────")
					current_line = current_line + 1
				end
				table.insert(lines, string.format("══════ %s ══════", output.bufname))
				current_line = current_line + 1
				current_buf = output.bufnr
			end

			-- Show match status in the header
			local status_indicator = ""
			if output.display_status == "unmatched" then
				status_indicator = " [UNMATCHED - browser line " .. (output.reported_line or "?") .. "]"
			elseif output.matched_line and output.reported_line and output.matched_line ~= output.reported_line then
				status_indicator = string.format(" [browser: %d → actual: %d]", output.reported_line,
					output.matched_line)
			end

			local line_display = output.line or (output.reported_line and tostring(output.reported_line)) or
			    "?"
			local ok, line_header = pcall(string.format, "→ Line %s: console.%s%s",
				line_display,
				output.console_type or "log",
				status_indicator)
			if ok then
				table.insert(lines, line_header)
				line_map[current_line] = {
					bufnr = output.bufnr,
					line = output.line,
					filepath = output.full_path,
					type = "header"
				}
				current_line = current_line + 1
			else
				debug_logger.log("INSPECT_ALL_ERROR", "Failed to format header for output " .. i)
				table.insert(lines, "=== Output " .. i .. " ===")
				current_line = current_line + 1
			end

			for _, content_line in ipairs(M.build_output_lines(output)) do
				table.insert(lines, content_line)
				line_map[#lines] = {
					bufnr = output.bufnr,
					line = output.line,
					type = "content"
				}
			end
			current_line = #lines + 1

			table.insert(lines, "")
			current_line = current_line + 1
		end

		-- Add summary at the top
		local buffer_count = vim.tbl_count(all_outputs) +
		    vim.tbl_count(all_unmatched_outputs or {})
		local summary_lines = {
			string.format("═══════ Console Output Summary ═══════"),
			string.format("Total: %d outputs from %d buffer(s)", total_count, buffer_count),
			string.format("Matched (inline): %d | Unmatched: %d", matched_count, unmatched_count),
			"",
			"[UNMATCHED] = couldn't find matching console.log line",
			"[browser: X → actual: Y] = line number mapping",
			"════════════════════════════════════",
			""
		}

		-- Prepend summary to lines
		for i = #summary_lines, 1, -1 do
			table.insert(lines, 1, summary_lines[i])
		end

		-- Adjust line_map indices after prepending summary
		local summary_offset = #summary_lines
		local adjusted_line_map = {}
		for line_num, mapping in pairs(line_map) do
			adjusted_line_map[line_num + summary_offset] = mapping
		end
		line_map = adjusted_line_map

		debug_logger.log("INSPECT_ALL", string.format("Created %d lines of output", #lines))

		-- Create buffer with all outputs
		debug_logger.log("INSPECT_ALL", "Creating buffer")

		local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
		if not ok then
			debug_logger.log("INSPECT_ALL_ERROR", "Failed to create buffer: " .. tostring(buf))
			vim.notify("Failed to create buffer: " .. tostring(buf), vim.log.levels.ERROR)
			return
		end

		debug_logger.log("INSPECT_ALL", string.format("Buffer created: %d", buf))

		local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
		if not ok then
			debug_logger.log("INSPECT_ALL_ERROR", "Failed to set buffer lines: " .. tostring(err))
			vim.notify("Failed to set buffer lines: " .. tostring(err), vim.log.levels.ERROR)
			return
		end

		vim.bo[buf].filetype = "javascript"
		vim.bo[buf].modifiable = false
		vim.b[buf].consolelog_line_map = line_map

		local function jump_to_source()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line_num = cursor[1]
			local mapping = vim.b[buf].consolelog_line_map[line_num]

			if not mapping or not mapping.line then
				vim.notify("No source location for this line", vim.log.levels.INFO)
				return
			end

			vim.cmd("close")

			local target_bufnr = mapping.bufnr
			local is_loaded = vim.api.nvim_buf_is_loaded(target_bufnr)

			if not is_loaded then
				local filepath = vim.api.nvim_buf_get_name(target_bufnr)
				if filepath == "" then
					vim.notify("Cannot open file: buffer has no path", vim.log.levels.WARN)
					return
				end

				vim.cmd("tabnew " .. vim.fn.fnameescape(filepath))
				vim.api.nvim_win_set_cursor(0, { mapping.line, 0 })
				vim.cmd("normal! zz")
				return
			end

			local source_win = nil
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(win) == target_bufnr then
					source_win = win
					break
				end
			end

			if source_win then
				vim.api.nvim_set_current_win(source_win)
			else
				vim.cmd("tabnew")
				vim.api.nvim_set_current_buf(target_bufnr)
			end

			vim.api.nvim_win_set_cursor(0, { mapping.line, 0 })
			vim.cmd("normal! zz")
		end

		-- Open in a split instead of floating window for better navigation
		debug_logger.log("INSPECT_ALL", "Attempting to create window")

		local ok, result = pcall(vim.cmd, "botright split")
		if not ok then
			debug_logger.log("INSPECT_ALL", "Split failed, trying floating window: " .. tostring(result))

			-- If split fails, try using a floating window instead
			local width = math.min(120, math.floor(vim.o.columns * 0.8))
			local height = math.min(30, math.floor(vim.o.lines * 0.8))
			local opts = {
				relative = "editor",
				width = width,
				height = height,
				col = math.floor((vim.o.columns - width) / 2),
				row = math.floor((vim.o.lines - height) / 2),
				border = "rounded",
				title = string.format(" All Console Outputs (%d total) - Press Enter to jump ", total_count),
				title_pos = "center",
			}

			local ok2, win = pcall(vim.api.nvim_open_win, buf, true, opts)
			if not ok2 then
				debug_logger.log("INSPECT_ALL_ERROR",
					"Failed to create floating window: " .. tostring(win))
				vim.notify("Failed to create window: " .. tostring(win), vim.log.levels.ERROR)
				return
			end

			vim.wo[win].wrap = true
			vim.wo[win].cursorline = true
		else
			debug_logger.log("INSPECT_ALL", "Split created successfully")
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(win, buf)
			vim.api.nvim_win_set_height(win, math.min(20, #lines))
		end

		debug_logger.log("INSPECT_ALL", "Window created successfully")

		-- Add keymaps using functions instead of command strings
		vim.keymap.set("n", "q", function() vim.cmd("close") end, { buffer = buf, nowait = true, silent = true })
		vim.keymap.set("n", "<CR>", jump_to_source, { buffer = buf, nowait = true, silent = true, desc = "Jump to source" })
	end) -- End of pcall function

	if not success then
		local debug_logger = require("consolelog.core.debug_logger")
		debug_logger.log("INSPECT_ALL_ERROR", "Uncaught error: " .. tostring(err))
		vim.notify("Error in inspect_all: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.inspect_buffer(buffer_outputs, buffer_unmatched_outputs)
	local success, err = pcall(function()
		local debug_logger = require("consolelog.core.debug_logger")
		debug_logger.log("INSPECT_BUFFER", "Starting inspect_buffer for current buffer")

		local bufnr = vim.api.nvim_get_current_buf()
		local bufname = vim.api.nvim_buf_get_name(bufnr)
		local short_name = vim.fn.fnamemodify(bufname, ":t")
		if short_name == "" then short_name = "[No Name]" end

		local all_outputs = {}
		local total_count = 0

		if buffer_outputs and not vim.tbl_isempty(buffer_outputs) then
			for _, output in ipairs(buffer_outputs) do
				local enriched = vim.tbl_extend("force", output, {
					bufnr = bufnr,
					bufname = short_name,
					full_path = bufname,
					display_status = "inline"
				})
				table.insert(all_outputs, enriched)
				total_count = total_count + 1
			end
		end

		if buffer_unmatched_outputs and not vim.tbl_isempty(buffer_unmatched_outputs) then
			for _, output in ipairs(buffer_unmatched_outputs) do
				local enriched = vim.tbl_extend("force", output, {
					bufnr = bufnr,
					bufname = short_name,
					full_path = bufname,
					display_status = output.matched and "matched" or "unmatched",
					line = output.matched_line or output.reported_line
				})
				table.insert(all_outputs, enriched)
				total_count = total_count + 1
			end
		end

		debug_logger.log("INSPECT_BUFFER",
			string.format("Found %d outputs in buffer %s", total_count, short_name))

		if total_count == 0 then
			vim.notify("No console outputs in any buffer", vim.log.levels.INFO)
			return
		end

		table.sort(all_outputs, function(a, b)
			if a.timestamp and b.timestamp then
				return a.timestamp > b.timestamp
			elseif a.bufnr == b.bufnr then
				return a.line < b.line
			else
				return a.bufnr < b.bufnr
			end
		end)

		local lines = {}
		local line_map = {}
		local current_line = 1

		for i, output in ipairs(all_outputs) do
			local status_indicator = ""
			if output.display_status == "unmatched" then
				status_indicator = " [UNMATCHED - browser line " .. (output.reported_line or "?") .. "]"
			elseif output.matched_line and output.reported_line and output.matched_line ~= output.reported_line then
				status_indicator = string.format(" [browser: %d → actual: %d]", output.reported_line,
					output.matched_line)
			end

			local line_display = output.line or (output.reported_line and tostring(output.reported_line)) or
			    "?"
			local ok, line_header = pcall(string.format, "→ Line %s: console.%s%s",
				line_display,
				output.method or output.console_type or "log",
				status_indicator)
			if ok then
				table.insert(lines, line_header)
				line_map[current_line] = {
					bufnr = output.bufnr,
					line = output.line,
					type = "header"
				}
				current_line = current_line + 1
			else
				table.insert(lines, "=== Output " .. i .. " ===")
				current_line = current_line + 1
			end

			for _, content_line in ipairs(M.build_output_lines(output)) do
				table.insert(lines, content_line)
				line_map[#lines] = {
					bufnr = output.bufnr,
					line = output.line,
					type = "content"
				}
			end
			current_line = #lines + 1

			table.insert(lines, "")
			current_line = current_line + 1
		end

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = "javascript"
		vim.bo[buf].bufhidden = "wipe"
		vim.b[buf].consolelog_line_map = line_map

		local function jump_to_source()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line_num = cursor[1]
			local mapping = vim.b[buf].consolelog_line_map[line_num]

			if not mapping or not mapping.line then
				vim.notify("No source location for this line", vim.log.levels.INFO)
				return
			end

			if not vim.api.nvim_buf_is_valid(mapping.bufnr) then
				vim.notify("Source buffer no longer valid", vim.log.levels.WARN)
				return
			end

			vim.cmd("close")

			local source_win = nil
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(win) == mapping.bufnr then
					source_win = win
					break
				end
			end

			if source_win then
				vim.api.nvim_set_current_win(source_win)
			else
				vim.api.nvim_set_current_buf(mapping.bufnr)
			end

			vim.api.nvim_win_set_cursor(0, { mapping.line, 0 })
			vim.cmd("normal! zz")
		end

		local width = math.min(120, math.floor(vim.o.columns * 0.8))
		local height = math.min(30, math.floor(vim.o.lines * 0.8))
		local opts = {
			relative = "editor",
			width = width,
			height = height,
			col = math.floor((vim.o.columns - width) / 2),
			row = math.floor((vim.o.lines - height) / 2),
			border = "rounded",
			title = string.format(" %s Outputs (%d) - Press Enter to jump ", short_name, total_count),
			title_pos = "center",
		}

		local ok, win = pcall(vim.api.nvim_open_win, buf, true, opts)
		if not ok then
			vim.notify("Failed to create window: " .. tostring(win), vim.log.levels.ERROR)
			return
		end

		vim.wo[win].wrap = true
		vim.wo[win].cursorline = true

		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
		vim.keymap.set("n", "<CR>", jump_to_source, { buffer = buf, silent = true, desc = "Jump to source" })
	end)

	if not success then
		vim.notify("Error in inspect_buffer: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.inspect_at_cursor_split(outputs)
	M.inspect_at_cursor(outputs, true)
end

return M
