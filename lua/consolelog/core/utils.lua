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

	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
	if filetype == "javascript" or filetype == "typescript" or filetype == "javascriptreact" or filetype == "typescriptreact" then
		return true
	end

	local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
	if buftype ~= "" then
		return false
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

	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
	if filetype == "python" then
		return true
	end

	local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
	if buftype ~= "" then
		return false
	end

	local file = vim.api.nvim_buf_get_name(bufnr)
	return M.is_python_file(file)
end

function M.is_supported_buffer(bufnr)
	return M.is_javascript_buffer(bufnr) or M.is_python_buffer(bufnr)
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
