local constants = require("consolelog.core.constants")

local M = {}

local function build_body(cfg, prompt, provider)
	local body = {
		model = cfg.model,
		messages = { { role = "user", content = prompt } },
		max_tokens = cfg.max_tokens,
	}
	if provider.supports_response_format and cfg.response_format == "json_schema" then
		body.response_format = { type = "json_schema", json_schema = constants.EXPLAIN.JSON_SCHEMA }
	elseif provider.supports_response_format and cfg.response_format == "json_object" then
		body.response_format = { type = "json_object" }
	end
	if type(cfg.temperature) == "number" then
		body.temperature = cfg.temperature
	end
	if type(cfg.extra_body) == "table" then
		for key, value in pairs(cfg.extra_body) do
			body[key] = value
		end
	end
	return body
end

M.providers = {
	openai = {
		url = "https://api.openai.com/v1/chat/completions",
		api_key_env = "OPENAI_API_KEY",
		supports_response_format = true,
		build_headers = function(api_key)
			return { "Authorization: Bearer " .. api_key }
		end,
		build_body = build_body,
		extract_content = function(decoded)
			if type(decoded) ~= "table" or type(decoded.choices) ~= "table" then
				return nil
			end
			local choice = decoded.choices[1]
			if type(choice) ~= "table" or type(choice.message) ~= "table" then
				return nil
			end
			local content = choice.message.content
			if type(content) ~= "string" then
				return ""
			end
			return content
		end,
		finish_reason = function(decoded)
			if type(decoded) ~= "table" or type(decoded.choices) ~= "table" then
				return nil
			end
			local choice = decoded.choices[1]
			if type(choice) ~= "table" then
				return nil
			end
			return choice.finish_reason
		end,
	},
	anthropic = {
		url = "https://api.anthropic.com/v1/messages",
		api_key_env = "ANTHROPIC_API_KEY",
		build_headers = function(api_key)
			return { "x-api-key: " .. api_key, "anthropic-version: 2023-06-01" }
		end,
		build_body = build_body,
		extract_content = function(decoded)
			if type(decoded) ~= "table" or type(decoded.content) ~= "table" then
				return nil
			end
			local fallback
			for _, entry in ipairs(decoded.content) do
				if type(entry) == "table" and entry.text ~= nil then
					if entry.type == "text" then
						return entry.text
					end
					if not fallback then
						fallback = entry.text
					end
				end
			end
			return fallback
		end,
		finish_reason = function(decoded)
			if type(decoded) ~= "table" then
				return nil
			end
			return decoded.stop_reason
		end,
	},
}

function M.build_request(cfg, prompt)
	if type(cfg) ~= "table" then
		return nil, "explain config missing"
	end

	local provider = M.providers[cfg.provider]
	if not provider then
		return nil, string.format("unknown explain provider '%s' (expected openai or anthropic)", tostring(cfg.provider))
	end

	local header_args = { "-H", "Content-Type: application/json" }
	if cfg.api_key_env ~= false then
		local env_name = cfg.api_key_env or provider.api_key_env
		local api_key = os.getenv(env_name)
		if not api_key or api_key == "" then
			return nil, string.format("explain provider needs $%s to be set (or set explain.api_key_env = false)", env_name)
		end
		for _, header in ipairs(provider.build_headers(api_key)) do
			table.insert(header_args, "-H")
			table.insert(header_args, header)
		end
	end

	local body = vim.json.encode(provider.build_body(cfg, prompt, provider))

	local cmd = { "curl", "-sS", "-X", "POST", cfg.url or provider.url }
	for _, arg in ipairs(header_args) do
		table.insert(cmd, arg)
	end
	table.insert(cmd, "--max-time")
	table.insert(cmd, tostring(math.max(1, math.ceil((cfg.timeout_ms or constants.EXPLAIN.DEFAULT_TIMEOUT_MS) / 1000))))
	table.insert(cmd, "-w")
	table.insert(cmd, "\n" .. constants.EXPLAIN.HTTP_STATUS_SENTINEL .. "%{http_code}")
	table.insert(cmd, "--data-binary")
	table.insert(cmd, "@-")

	return { cmd = cmd, body = body }, nil
end

function M.split_response(stdout)
	if type(stdout) ~= "string" then
		return nil, nil
	end
	local sentinel = constants.EXPLAIN.HTTP_STATUS_SENTINEL
	local pos = stdout:find(sentinel, 1, true)
	if not pos then
		return nil, nil
	end
	return stdout:sub(1, pos - 1), tonumber(stdout:sub(pos + #sentinel))
end

function M.extract_content(provider_name, body)
	local provider = M.providers[provider_name]
	if not provider then
		return nil, string.format("unknown explain provider '%s'", tostring(provider_name))
	end
	local ok, decoded = pcall(vim.json.decode, body)
	if not ok then
		return nil, string.format("could not decode %s response", provider_name)
	end
	local content = provider.extract_content(decoded)
	if type(content) ~= "string" then
		return nil, string.format("unexpected response shape from %s", provider_name)
	end
	if content == "" then
		local reason = provider.finish_reason and provider.finish_reason(decoded)
		if type(reason) ~= "string" then
			reason = nil
		end
		if reason == "length" or reason == "max_tokens" then
			return nil, string.format("%s stopped at max_tokens before answering; raise explain.max_tokens", provider_name)
		end
		return nil, string.format("%s returned empty content (finish reason: %s)", provider_name, reason or "unknown")
	end
	return content, nil
end

function M.extract_error(body)
	if type(body) ~= "string" then
		body = ""
	end
	local ok, decoded = pcall(vim.json.decode, body)
	if ok and type(decoded) == "table" then
		local err = decoded.error
		if type(err) == "table" and type(err.message) == "string" and err.message ~= "" then
			return err.message
		end
		if type(err) == "string" and err ~= "" then
			return err
		end
	end
	return (body:sub(1, 200):gsub("%s+", " "))
end

function M.request(cfg, prompt, on_done)
	if vim.fn.executable("curl") ~= 1 then
		on_done(nil, "curl is required for :ConsoleLogExplain")
		return nil
	end

	local request, err = M.build_request(cfg, prompt)
	if not request then
		on_done(nil, err)
		return nil
	end

	local stdout_buffer = ""
	local stderr_buffer = ""

	local job_id = vim.fn.jobstart(request.cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			stdout_buffer = stdout_buffer .. table.concat(data, "\n")
		end,
		on_stderr = function(_, data)
			stderr_buffer = stderr_buffer .. table.concat(data, "\n")
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if code ~= 0 then
					on_done(nil, string.format("curl exited with code %d: %s", code, stderr_buffer:match("[^\n]+") or ""))
					return
				end
				local body, status = M.split_response(stdout_buffer)
				if not status then
					on_done(nil, "no HTTP status in curl response")
					return
				end
				local debug_logger = require("consolelog.core.debug_logger")
				debug_logger.log("EXPLAIN", string.format("%s returned HTTP %d", cfg.provider, status))
				if status ~= 200 then
					on_done(nil, string.format("%s returned HTTP %d: %s", cfg.provider, status, M.extract_error(body)))
					return
				end
				local content, content_err = M.extract_content(cfg.provider, body)
				on_done(content, content_err)
			end)
		end,
	})

	if job_id == nil or job_id <= 0 then
		on_done(nil, "failed to start curl")
		return nil
	end

	local debug_logger = require("consolelog.core.debug_logger")
	debug_logger.log("EXPLAIN", string.format("requesting %s via %s (model %s)",
		cfg.provider, cfg.url or M.providers[cfg.provider].url, cfg.model))

	vim.fn.chansend(job_id, request.body)
	vim.fn.chanclose(job_id, "stdin")
	return job_id
end

return M
