local constants = require("consolelog.core.constants")

local M = {}

function M.build(source_lines, start_line, filetype)
	if not source_lines or #source_lines == 0 then
		return nil
	end

	local language = filetype
	if type(language) ~= "string" or language == "" then
		language = "source code"
	end

	local lines = {
		string.format("Explain the following %s line by line.", language),
		"",
		"Rules:",
		string.format('- Reply with JSON only in the shape {"%s":[{"line":<number>,"text":"<explanation>"}]}', constants.EXPLAIN.RESPONSE_KEY),
		"- Use exactly the line numbers shown below.",
		string.format("- At most %d words per explanation.", constants.EXPLAIN.MAX_WORDS),
		"- No trailing period.",
		"- Describe behavior/intent, not syntax names.",
		"- Skip blank lines, comment-only lines and lines that are only closing brackets.",
		"",
		"Source:",
	}

	for i, source_line in ipairs(source_lines) do
		table.insert(lines, string.format("%d: %s", start_line + i - 1, source_line))
	end

	return table.concat(lines, "\n")
end

function M.parse(content, min_line, max_line)
	if type(content) ~= "string" or content == "" then
		return nil, "empty response from model"
	end

	content = content:gsub("<[Tt]hinking>.-</[Tt]hinking>", "")
	content = content:gsub("<[Tt]hink>.-</[Tt]hink>", "")

	local payload = content
	local fenced = payload:match("```json%s*(.-)%s*```")
	if not fenced then
		fenced = payload:match("```%s*(.-)%s*```")
	end
	if fenced then
		payload = fenced
	else
		local first = payload:find("[%[{]")
		local last = payload:reverse():find("[%]}]")
		if not first or not last or #payload - last + 1 < first then
			return nil, "no JSON object in model response"
		end
		payload = payload:sub(first, #payload - last + 1)
	end

	local ok, decoded = pcall(vim.json.decode, payload)
	if not ok or type(decoded) ~= "table" then
		return nil, "could not decode model response as JSON"
	end

	local entries
	if type(decoded[constants.EXPLAIN.RESPONSE_KEY]) == "table" then
		entries = decoded[constants.EXPLAIN.RESPONSE_KEY]
	elseif vim.islist(decoded) then
		entries = decoded
	else
		return nil, "unexpected JSON shape in model response"
	end

	local annotations = {}
	local seen_lines = {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" then
			local line = tonumber(entry.line)
			if line and line >= min_line and line <= max_line and not seen_lines[line] then
				local text = entry.text
				if type(text) == "string" then
					text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
					if text ~= "" then
						table.insert(annotations, { line = line, text = text })
						seen_lines[line] = true
					end
				end
			end
		end
	end

	if #annotations == 0 then
		return nil, "model returned no usable line explanations"
	end

	table.sort(annotations, function(a, b) return a.line < b.line end)

	return annotations, nil
end

return M
