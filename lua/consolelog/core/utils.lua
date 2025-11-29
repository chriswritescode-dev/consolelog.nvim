local M = {}

function M.get_timestamp()
	return vim.loop.hrtime() / 1000000
end

function M.is_javascript_file(file)
	if not file or file == "" then
		return false
	end

	return file:match("%.jsx?$") or file:match("%.tsx?$") or file:match("%.mjs$") or file:match("%.cjs$")
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

function M.strip_ansi(text)
	if not text or type(text) ~= "string" then
		return text
	end
	text = text:gsub("\27%[[0-9;]*m", "")
	text = text:gsub("\27%[%d+[A-Z]", "")
	text = text:gsub("\27%[[0-9;]*[HfJ]", "")
	return text
end

function M.find_buffer_for_file(filepath)
	if not filepath or filepath == "" then
		return nil
	end
	
	-- Normalize the file path
	local normalized_path = vim.fn.fnamemodify(filepath, ":p")
	
	-- Iterate through all buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local buf_name = vim.api.nvim_buf_get_name(bufnr)
			if buf_name and buf_name ~= "" then
				local normalized_buf_name = vim.fn.fnamemodify(buf_name, ":p")
				if normalized_buf_name == normalized_path then
					return bufnr
				end
			end
		end
	end
	
	return nil
end

-- Compatibility shim for vim.islist (available in newer Neovim versions)
function M.islist(tbl)
	if vim.islist then
		return vim.islist(tbl)
	end
	
	-- Fallback implementation for older Neovim versions
	if type(tbl) ~= "table" then
		return false
	end
	
	-- Check if it's an array-like table (sequential integer keys)
	local max_index = 0
	local count = 0
	for k, _ in pairs(tbl) do
		if type(k) == "number" and k > 0 and k == math.floor(k) then
			max_index = math.max(max_index, k)
			count = count + 1
		else
			-- Has non-numeric key, not a list
			return false
		end
	end
	
	-- If all keys are sequential integers starting from 1, it's a list
	return count == max_index and max_index > 0
end

return M
