local constants = require("consolelog.core.constants")
local vtext_builder = require("consolelog.display.virtual_text_builder")
local extmark_writer = require("consolelog.display.extmark_writer")

local M = {}

M.namespace = vim.api.nvim_create_namespace("consolelog_explain")
M.pending = {}
M.annotations = {}
M.hidden = {}

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
	local job_id = M.pending[bufnr]
	if job_id then
		vim.fn.jobstop(job_id)
		M.pending[bufnr] = nil
	end
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

	local cfg = require("consolelog").config.explain or {}
	local limit = cfg.max_lines or constants.EXPLAIN.DEFAULT_MAX_LINES
	local requested = end_line - start_line + 1
	if requested > limit then
		vim.notify(
			string.format(":ConsoleLogExplain range is %d lines, maximum is %d", requested, limit),
			vim.log.levels.ERROR
		)
		return nil
	end

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

	local prompt = require("consolelog.explain.prompt")
	local prompt_text = prompt.build(lines, start_line, vim.bo[bufnr].filetype)
	local tick = vim.api.nvim_buf_get_changedtick(bufnr)

	local job_id
	local on_done = function(content, err)
		if M.pending[bufnr] == job_id then
			M.pending[bufnr] = nil
		end
		if err then
			vim.notify("ConsoleLog explain: " .. err, vim.log.levels.ERROR)
			return
		end
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		if vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
			vim.notify("Buffer changed while explaining; run :ConsoleLogExplain again", vim.log.levels.WARN)
			return
		end
		local annotations, parse_err = prompt.parse(content, start_line, end_line)
		if not annotations then
			vim.notify("ConsoleLog explain: " .. parse_err, vim.log.levels.ERROR)
			return
		end
		if M.hidden[bufnr] then
			M.hidden[bufnr] = nil
			M.restore(bufnr)
		end
		local rendered = M.render_annotations(bufnr, start_line, end_line, annotations)
		vim.notify(string.format("Explained %d lines", rendered), vim.log.levels.INFO)
	end

	local llm = require("consolelog.explain.llm")
	job_id = llm.request(cfg, prompt_text, on_done)
	M.pending[bufnr] = job_id
	return job_id
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
