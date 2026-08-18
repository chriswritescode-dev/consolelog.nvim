local constants = require("consolelog.core.constants")
local vtext_builder = require("consolelog.display.virtual_text_builder")
local extmark_writer = require("consolelog.display.extmark_writer")
local prompt = require("consolelog.explain.prompt")

local M = {}

M.namespace = vim.api.nvim_create_namespace("consolelog_explain")
M.pending = {}
M.annotations = {}
M.hidden = {}
M.loading = {}

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_INTERVAL_MS = 100

local function toast_opts(bufnr, loading)
	return {
		id = "consolelog_explain_" .. bufnr,
		title = "ConsoleLog",
		replace = loading and loading.notif or nil,
		timeout = false,
		hide_from_history = true,
	}
end

local function notify_toast(msg, level, opts)
	local ok, result = pcall(vim.notify, msg, level, opts)
	if ok then
		return result
	end
	if opts and opts.replace ~= nil then
		opts.replace = nil
		local retry_ok, retry_result = pcall(vim.notify, msg, level, opts)
		if retry_ok then
			return retry_result
		end
	end
	return nil
end

local function spin(bufnr)
	local loading = M.loading[bufnr]
	if not loading then
		return
	end
	local frame = SPINNER_FRAMES[loading.frame]
	loading.frame = loading.frame % #SPINNER_FRAMES + 1
	loading.notif = notify_toast(frame .. " " .. loading.msg, vim.log.levels.INFO, toast_opts(bufnr, loading))
end

local function hide_loading(bufnr)
	local loading = M.loading[bufnr]
	M.loading[bufnr] = nil
	if not loading then
		return nil
	end
	if loading.timer then
		loading.timer:stop()
		if not loading.timer:is_closing() then
			loading.timer:close()
		end
	end
	return loading
end

local function stop_loading(bufnr, msg, level)
	local loading = hide_loading(bufnr)
	local opts = toast_opts(bufnr, loading)
	opts.timeout = nil
	notify_toast(msg, level, opts)
end

local function show_loading(bufnr, state)
	local chunk = state.chunks[state.index]
	local msg
	if #state.chunks == 1 then
		local requested = chunk.e - chunk.s + 1
		msg = string.format("Explaining %d line%s", requested, requested == 1 and "" or "s")
	else
		msg = string.format("Explaining lines %d-%d (%d/%d)", chunk.s, chunk.e, state.index, #state.chunks)
	end

	local loading = M.loading[bufnr]
	if loading then
		loading.msg = msg
		return
	end

	loading = { frame = 1, msg = msg }
	M.loading[bufnr] = loading
	spin(bufnr)

	local uv = vim.uv or vim.loop
	local timer = uv.new_timer()
	if timer then
		loading.timer = timer
		timer:start(SPINNER_INTERVAL_MS, SPINNER_INTERVAL_MS, vim.schedule_wrap(function()
			spin(bufnr)
		end))
	end
end

function M.sync_lines(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if M.hidden[bufnr] then
		return
	end

	local ok, extmarks = pcall(vim.api.nvim_buf_get_extmarks, bufnr, M.namespace, 0, -1, {})
	if not ok then
		return
	end
	local rows_by_id = {}
	for _, mark in ipairs(extmarks) do
		rows_by_id[mark[1]] = mark[2] + 1
	end

	local entries = M.annotations[bufnr]
	if not entries then
		return
	end

	local synced = {}
	for _, entry in ipairs(entries) do
		local row = rows_by_id[entry.id]
		if row then
			entry.line = row
			table.insert(synced, entry)
		end
	end
	M.annotations[bufnr] = synced
end

function M.clear(bufnr, start_line, end_line)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if start_line == nil then
		M.hidden[bufnr] = nil
	end

	M.sync_lines(bufnr)

	local entries = M.annotations[bufnr]
	if entries then
		local remaining = {}
		for _, entry in ipairs(entries) do
			local in_range = start_line == nil
				or (end_line == nil and entry.line >= start_line)
				or (entry.line >= start_line and entry.line <= end_line)
			if not in_range then
				table.insert(remaining, entry)
			end
		end
		M.annotations[bufnr] = remaining
	end

	pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, (start_line or 1) - 1, end_line or -1)
end

function M.cancel(bufnr)
	local state = M.pending[bufnr]
	if state and state.job_id then
		vim.fn.jobstop(state.job_id)
	end
	M.pending[bufnr] = nil
	hide_loading(bufnr)
end

local function render_entry(bufnr, entry, line_count, config)
	if entry.line < 1 or entry.line > line_count then
		return false
	end

	local virt_lines, is_multiline = vtext_builder.build_annotation_virtual_text(entry.text, config)
	local mark_id = extmark_writer.write_virt_lines(
		bufnr,
		M.namespace,
		entry.line - 1,
		virt_lines,
		is_multiline,
		constants.EXPLAIN.EXTMARK_PRIORITY,
		"eol"
	)
	if not mark_id then
		return false
	end

	if not M.annotations[bufnr] then
		M.annotations[bufnr] = {}
	end
	table.insert(M.annotations[bufnr], { id = mark_id, line = entry.line, text = entry.text })
	return true
end

function M.restore(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if M.hidden[bufnr] then
		return
	end

	local cached = M.annotations[bufnr]
	if not cached or #cached == 0 then
		return
	end

	M.annotations[bufnr] = {}
	pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local config = require("consolelog").config
	for _, entry in ipairs(cached) do
		render_entry(bufnr, entry, line_count, config)
	end
end

function M.toggle(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No explanations to toggle", vim.log.levels.INFO)
		return
	end
	local entries = M.annotations[bufnr]
	if not entries or #entries == 0 then
		vim.notify("No explanations to toggle", vim.log.levels.INFO)
		return
	end

	if M.hidden[bufnr] then
		M.hidden[bufnr] = nil
		M.restore(bufnr)
	else
		M.sync_lines(bufnr)
		pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
		M.hidden[bufnr] = true
	end
end

function M.chunk_ranges(start_line, end_line, size, anchor)
	if type(size) ~= "number" or size < 1 then
		size = constants.EXPLAIN.DEFAULT_MAX_LINES
	end
	if type(anchor) ~= "number" or anchor <= start_line or anchor > end_line then
		anchor = start_line
	end
	local chunks = {}
	local s = anchor
	while s <= end_line do
		table.insert(chunks, { s = s, e = math.min(s + size - 1, end_line) })
		s = chunks[#chunks].e + 1
	end
	s = start_line
	while s < anchor do
		table.insert(chunks, { s = s, e = math.min(s + size - 1, anchor - 1) })
		s = chunks[#chunks].e + 1
	end
	return chunks
end

local function cursor_line_in(bufnr)
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= bufnr then
		return nil
	end
	return vim.api.nvim_win_get_cursor(win)[1]
end

local run_chunk
local request_chunk
request_chunk = function(bufnr, state, chunk, prompt_text)
	local llm = require("consolelog.explain.llm")
	local on_done = function(content, err)
		if M.pending[bufnr] ~= state then
			return
		end
		if err then
			M.pending[bufnr] = nil
			stop_loading(bufnr, "ConsoleLog explain: " .. err, vim.log.levels.ERROR)
			return
		end
		if not vim.api.nvim_buf_is_valid(bufnr) then
			M.pending[bufnr] = nil
			stop_loading(bufnr, "Explain aborted: buffer is gone", vim.log.levels.WARN)
			return
		end
		if vim.api.nvim_buf_get_changedtick(bufnr) ~= state.tick then
			M.pending[bufnr] = nil
			stop_loading(bufnr, "Buffer changed while explaining; run :ConsoleLogExplain again", vim.log.levels.WARN)
			return
		end
		local annotations, parse_err = prompt.parse(content, chunk.s, chunk.e)
		if not annotations then
			if state.attempts < state.max_retries then
				state.attempts = state.attempts + 1
				local loading = M.loading[bufnr]
				if loading then
					loading.msg = string.format("Retrying lines %d-%d (%d/%d)", chunk.s, chunk.e, state.attempts, state.max_retries)
					spin(bufnr)
				end
				request_chunk(bufnr, state, chunk, prompt_text .. constants.EXPLAIN.RETRY_HINT)
				return
			end
			M.pending[bufnr] = nil
			stop_loading(bufnr, "ConsoleLog explain: " .. parse_err, vim.log.levels.ERROR)
			return
		end
		if M.hidden[bufnr] then
			M.hidden[bufnr] = nil
			M.restore(bufnr)
		end
		state.attempts = 0
		state.rendered = state.rendered + M.render_annotations(bufnr, chunk.s, chunk.e, annotations)
		state.index = state.index + 1
		run_chunk(bufnr, state)
	end
	state.job_id = llm.request(state.cfg, prompt_text, on_done)
end

run_chunk = function(bufnr, state)
	local chunk = state.chunks[state.index]
	if not chunk then
		M.pending[bufnr] = nil
		stop_loading(bufnr, string.format("Explained %d lines", state.rendered), vim.log.levels.INFO)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, chunk.s - 1, chunk.e, false)
	local has_code = false
	for _, line in ipairs(lines) do
		if not line:match("^%s*$") then
			has_code = true
			break
		end
	end
	if not has_code then
		state.index = state.index + 1
		return run_chunk(bufnr, state)
	end

	show_loading(bufnr, state)

	local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local total = #buffer_lines
	local limit = state.cfg.max_context_lines or constants.EXPLAIN.DEFAULT_MAX_CONTEXT_LINES
	local ctx_s, ctx_e = 1, total
	if total > limit then
		ctx_e = chunk.e
		ctx_s = math.min(chunk.s, math.max(1, chunk.e - limit + 1))
	end
	local context = {}
	for i = ctx_s, ctx_e do
		table.insert(context, buffer_lines[i])
	end

	local prompt_text = prompt.build(context, ctx_s, chunk.s, chunk.e, vim.bo[bufnr].filetype)
	request_chunk(bufnr, state, chunk, prompt_text)
end

function M.inspect(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No explanation on this line", vim.log.levels.INFO)
		return nil
	end

	M.sync_lines(bufnr)

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local entry
	for _, candidate in ipairs(M.annotations[bufnr] or {}) do
		if candidate.line == line then
			entry = candidate
			break
		end
	end
	if not entry then
		vim.notify("No explanation on this line", vim.log.levels.INFO)
		return nil
	end

	local max_width = math.min(80, vim.o.columns - 4)
	local lines = vtext_builder.split_into_lines(entry.text, max_width)
	local width = 1
	for _, text_line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(text_line))
	end
	width = math.min(width + 2, max_width + 2)
	local height = math.min(#lines, math.max(1, vim.o.lines - 4))

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		width = width,
		height = height,
		row = 1,
		col = 0,
		style = "minimal",
		border = "rounded",
		title = string.format(" Explanation - line %d ", line),
		title_pos = "center",
	})
	vim.wo[win].wrap = true

	local function close_window()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	vim.keymap.set("n", "q", close_window, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_window, { buffer = buf, nowait = true })

	return win
end

function M.explain_range(bufnr, start_line, end_line)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local utils = require("consolelog.core.utils")
	if not vim.api.nvim_buf_is_valid(bufnr) or not utils.is_regular_buffer(bufnr) then
		vim.notify(":ConsoleLogExplain needs a regular file buffer", vim.log.levels.ERROR)
		return nil
	end

	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	start_line = math.max(1, math.min(start_line, line_count))
	end_line = math.max(1, math.min(end_line, line_count))

	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	local all_blank = true
	for _, line in ipairs(lines) do
		if not line:match("^%s*$") then
			all_blank = false
			break
		end
	end
	if all_blank then
		vim.notify("Nothing to explain in that range", vim.log.levels.INFO)
		return nil
	end

	M.cancel(bufnr)

	local cfg = require("consolelog").config.explain or {}
	local max_retries = cfg.max_retries
	if type(max_retries) ~= "number" or max_retries < 0 then
		max_retries = constants.EXPLAIN.DEFAULT_MAX_RETRIES
	end
	local state = {
		cfg = cfg,
		tick = vim.api.nvim_buf_get_changedtick(bufnr),
		chunks = M.chunk_ranges(
			start_line,
			end_line,
			cfg.max_lines or constants.EXPLAIN.DEFAULT_MAX_LINES,
			cursor_line_in(bufnr)
		),
		index = 1,
		rendered = 0,
		max_retries = max_retries,
		attempts = 0,
	}
	M.pending[bufnr] = state
	run_chunk(bufnr, state)
	return state
end

function M.render_annotations(bufnr, start_line, end_line, annotations)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return 0
	end

	M.clear(bufnr, start_line, end_line)

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local config = require("consolelog").config

	local rendered = 0
	for _, annotation in ipairs(annotations or {}) do
		if render_entry(bufnr, annotation, line_count, config) then
			rendered = rendered + 1
		end
	end

	return rendered
end

return M
