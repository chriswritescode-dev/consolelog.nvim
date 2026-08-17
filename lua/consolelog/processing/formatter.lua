local M = {}



local INLINE_LIMIT = 80
local MAX_RENDER_DEPTH = 8

local function render_scalar(value)
	if value == nil or value == vim.NIL then
		return "null"
	end
	if type(value) == "string" then
		local ok, encoded = pcall(vim.json.encode, value)
		return ok and encoded or ('"' .. value .. '"')
	end
	return tostring(value)
end

local function render_key(key)
	if type(key) == "string" and key:match("^[%a_][%w_]*$") then
		return key
	end
	return render_scalar(tostring(key))
end

-- Renders a decoded JSON value the way a JS developer expects to read it:
-- short containers stay on one line, longer ones break with stable key order.
local function render_value(value, indent, depth)
	if type(value) ~= "table" then
		return render_scalar(value)
	end

	local is_list = vim.islist(value)
	local open, close = is_list and "[" or "{", is_list and "]" or "}"

	if vim.tbl_isempty(value) then
		return open .. close
	end

	if depth >= MAX_RENDER_DEPTH then
		return open .. "..." .. close
	end

	local child_indent = indent .. "  "
	local parts = {}

	if is_list then
		for _, item in ipairs(value) do
			table.insert(parts, render_value(item, child_indent, depth + 1))
		end
	else
		local keys = vim.tbl_keys(value)
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, key in ipairs(keys) do
			table.insert(parts, render_key(key) .. ": " .. render_value(value[key], child_indent, depth + 1))
		end
	end

	local single_line = open .. " " .. table.concat(parts, ", ") .. " " .. close
	if #single_line + #indent <= INLINE_LIMIT and not single_line:find("\n") then
		return single_line
	end

	local lines = { open }
	for i, part in ipairs(parts) do
		table.insert(lines, child_indent .. part .. (i < #parts and "," or ""))
	end
	table.insert(lines, indent .. close)

	return table.concat(lines, "\n")
end

function M.render_json(value)
	return render_value(value, "", 0)
end

function M.format_value(value, opts)
	opts = opts or {}
	local mode = opts.mode or "inline"
	local max_width = opts.max_width
	if not max_width or max_width <= 0 then
		max_width = mode == "inline" and 60 or 1000
	end
	local depth = opts.depth
	local utils = require("consolelog.core.utils")

	if value == nil then
		return "nil"
	end

	value = type(value) == "string" and utils.strip_ansi(value) or value

	if mode == "inspector" then
		if type(value) == "string" then
			-- Values already formatted by the runtime (util.inspect, tracebacks)
			-- are kept verbatim; only serialized payloads get re-rendered.
			local ok, parsed = pcall(vim.json.decode, value)
			if ok and type(parsed) == "table" then
				return M.render_json(parsed)
			end
			return value
		elseif type(value) == "table" then
			return M.render_json(value)
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
		local rendered
		if type(value) == "table" then
			rendered = M.render_json(value)
		elseif type(value) == "string" then
			local ok, parsed = pcall(vim.json.decode, value)
			rendered = (ok and type(parsed) == "table") and M.render_json(parsed) or value
		else
			return tostring(value or "")
		end

		rendered = rendered:gsub("%s+", " ")
		if #rendered > max_width then
			return rendered:sub(1, max_width - 3) .. "... [→ li]"
		end
		return rendered
	end
end

local function inline_value(value, config)
	local formatted = M.format_value(value, {
		mode = "inline",
		max_width = config.display.max_width
	})
	return (formatted:gsub("%s+", " "))
end

function M.format_values_for_inline(values, config, max_values)
	local constants = require("consolelog.core.constants")
	local shown = math.min(#values, max_values or #values)
	local parts = {}

	for i = 1, shown do
		table.insert(parts, inline_value(values[i], config))
	end

	if #values > shown then
		table.insert(parts, config.display.truncate_marker or constants.DISPLAY.TRUNCATE_MARKER)
	end

	return string.format("%s%s", config.display.prefix, table.concat(parts, ", "))
end

function M.format_for_hover(value)
	return M.format_value(value, { mode = "detailed", depth = 3 })
end

function M.format_for_inspector(value)
	return M.format_value(value, { mode = "inspector", depth = nil })
end

return M
