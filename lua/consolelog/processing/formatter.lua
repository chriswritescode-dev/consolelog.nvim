local M = {}

local utils = require("consolelog.core.utils")

local function prettify_json(json_str)
	local ok, parsed = pcall(vim.json.decode, json_str)
	if ok and parsed then
		local ok2, formatted = pcall(vim.fn.json_encode, parsed)
		if ok2 and formatted then
			local lines = {}
			local indent_level = 0
			local in_string = false
			local escape_next = false
			local line = ""

			for i = 1, #formatted do
				local char = formatted:sub(i, i)

				if escape_next then
					line = line .. char
					escape_next = false
				elseif char == "\\" and in_string then
					line = line .. char
					escape_next = true
				elseif char == '"' then
					in_string = not in_string
					line = line .. char
				elseif not in_string then
					if char == "{" or char == "[" then
						line = line .. char
						table.insert(lines, string.rep("  ", indent_level) .. line)
						indent_level = indent_level + 1
						line = ""
					elseif char == "}" or char == "]" then
						if line:match("%S") then
							table.insert(lines, string.rep("  ", indent_level) .. line)
							line = ""
						end
						indent_level = indent_level - 1
						table.insert(lines, string.rep("  ", indent_level) .. char)
					elseif char == "," then
						line = line .. char
						table.insert(lines, string.rep("  ", indent_level) .. line)
						line = ""
					else
						line = line .. char
					end
				else
					line = line .. char
				end
			end

			if line:match("%S") then
				table.insert(lines, string.rep("  ", indent_level) .. line)
			end

			return table.concat(lines, "\n")
		end
	end
	return json_str
end

local function format_table_preview(tbl, max_items)
	max_items = max_items or 2
	local is_array = utils.islist(tbl)
	local count = vim.tbl_count(tbl)
	local preview_parts = {}
	local i = 0

	for k, v in pairs(tbl) do
		if i >= max_items then break end
		i = i + 1

		if is_array then
			local item_str = type(v) == "table" and "{...}" or tostring(v)
			if type(v) == "string" then
				item_str = '"' .. (v:sub(1, 10)) .. (#v > 10 and "..." or "") .. '"'
			end
			table.insert(preview_parts, item_str)
		else
			local val_preview = type(v) == "table" and "{...}" or tostring(v)
			if type(v) == "string" then
				val_preview = '"' .. (v:sub(1, 10)) .. (#v > 10 and "..." or "") .. '"'
			elseif type(v) == "boolean" or type(v) == "number" then
				val_preview = tostring(v)
			end
			table.insert(preview_parts, tostring(k) .. ": " .. val_preview)
		end
	end

	local preview = table.concat(preview_parts, ", ")
	if count > max_items then
		preview = preview .. ", ..." .. (count - max_items) .. " more"
	end

	if is_array then
		return "[" .. preview .. "]"
	else
		return "{" .. preview .. "}"
	end
end

function M.format_value(value, opts)
	opts = opts or {}
	local mode = opts.mode or "inline"
	local max_width = opts.max_width or (mode == "inline" and 60 or 1000)
	local depth = opts.depth
	local utils = require("consolelog.core.utils")

	if value == nil then
		return "nil"
	end

	value = type(value) == "string" and utils.strip_ansi(value) or value

	if mode == "inspector" then
		if type(value) == "string" then
			if (value:match("^%[") or value:match("^{")) then
				return prettify_json(value)
			end
			local ok, parsed = pcall(vim.json.decode, value)
			if ok and parsed ~= nil then
				local json = vim.fn.json_encode(parsed)
				return prettify_json(json)
			end
			return value
		elseif type(value) == "table" then
			local ok, json = pcall(vim.fn.json_encode, value)
			if ok and json then
				return prettify_json(json)
			end
			return vim.inspect(value, { indent = "  ", depth = depth })
		else
			return tostring(value or "")
		end
	elseif mode == "detailed" then
		if type(value) == "string" then
			local ok, parsed = pcall(vim.json.decode, value)
			if ok and type(parsed) == "table" then
				return vim.inspect(parsed, { depth = depth or 3 })
			end
			return value
		elseif type(value) == "table" then
			return vim.inspect(value, { depth = depth or 3 })
		else
			return tostring(value or "")
		end
	else
		if type(value) == "table" then
			local count = vim.tbl_count(value)
			if count <= 3 then
				return vim.inspect(value, { indent = "", newline = " " })
			else
				return format_table_preview(value, 2) .. " [→ li]"
			end
		elseif type(value) == "string" then
			local is_json = false
			local json_obj = nil
			if value:match("^%s*{") or value:match("^%s*%[") then
				local ok, parsed = pcall(vim.json.decode, value)
				if ok then
					is_json = true
					json_obj = parsed
				end
			end

			if is_json and type(json_obj) == "table" then
				local count = vim.tbl_count(json_obj)
				local json_str = vim.json.encode(json_obj)
				if #json_str <= max_width and count <= 3 then
					return json_str
				else
					return format_table_preview(json_obj, 2) .. " [→ li]"
				end
			elseif #value > max_width then
				return value:sub(1, max_width - 3) .. "..."
			end
			return value
		else
			return tostring(value or "")
		end
	end
end

function M.format_for_inline(value, config)
	local formatted = M.format_value(value, {
		mode = "inline",
		max_width = config.display.max_width
	})
	formatted = formatted:gsub("\n", " ")
	return string.format("%s%s", config.display.prefix, formatted)
end

function M.format_for_hover(value)
	return M.format_value(value, { mode = "detailed", depth = 3 })
end

function M.format_for_inspector(value)
	return M.format_value(value, { mode = "inspector", depth = nil })
end

return M
