local M = {}

function M.get_timestamp()
	return vim.loop.hrtime() / 1000000
end

function M.is_javascript_file(file)
	if not file or file == "" then
		return false
	end

	return file:match("%.jsx?$") or file:match("%.tsx?$") or file:match("%.mts$") or file:match("%.cts$") or file:match("%.mjs$") or file:match("%.cjs$")
end

function M.is_javascript_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if not M.is_regular_buffer(bufnr) then
		return false
	end

	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
	if filetype == "javascript" or filetype == "typescript" or filetype == "javascriptreact" or filetype == "typescriptreact" then
		return true
	end

	local file = vim.api.nvim_buf_get_name(bufnr)
	return M.is_javascript_file(file)
end

function M.is_python_file(file)
	if not file or file == "" then
		return false
	end
	return file:match("%.py$")
end

function M.is_python_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if not M.is_regular_buffer(bufnr) then
		return false
	end

	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
	if filetype == "python" then
		return true
	end

	local file = vim.api.nvim_buf_get_name(bufnr)
	return M.is_python_file(file)
end

function M.is_supported_buffer(bufnr)
	return M.is_javascript_buffer(bufnr) or M.is_python_buffer(bufnr)
end

function M.is_regular_buffer(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr)
		and vim.api.nvim_buf_get_option(bufnr, "buftype") == ""
		and not vim.api.nvim_buf_get_name(bufnr):match("^[%w+.-]+://")
end

function M.find_regular_buffer_window(bufnr, winid)
	if not M.is_regular_buffer(bufnr) then
		return nil
	end

	local windows = winid and { winid } or vim.fn.win_findbuf(bufnr)
	for _, candidate in ipairs(windows) do
		if vim.api.nvim_win_is_valid(candidate)
			and vim.api.nvim_win_get_buf(candidate) == bufnr
			and vim.api.nvim_win_get_config(candidate).relative == ""
			and not vim.api.nvim_win_get_option(candidate, "diff") then
			return candidate
		end
	end

	return nil
end

function M.strip_ansi(text)
	if not text or type(text) ~= "string" then
		return text
	end
	text = text:gsub("\27%[[0-9;]*m", "")
	text = text:gsub("\27%[%d+[A-Z]", "")
	text = text:gsub("\27%[[0-9;]*[HfJ]", "")
	return text
end

return M
