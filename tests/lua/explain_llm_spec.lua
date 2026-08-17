local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

local llm = require("consolelog.explain.llm")
local constants = require("consolelog.core.constants")

local function has_header(cmd, value)
  for i, arg in ipairs(cmd) do
    if arg == value and cmd[i - 1] == "-H" then
      return true
    end
  end
  return false
end

local function max_time(cmd)
  for i, arg in ipairs(cmd) do
    if arg == "--max-time" then
      return cmd[i + 1]
    end
  end
  return nil
end

describe("Explain LLM request builder", function()
  local saved_getenv
  local fake_env = {}

  local function setup()
    saved_getenv = os.getenv
    os.getenv = function(name)
      return fake_env[name]
    end
  end

  local function teardown()
    os.getenv = saved_getenv
    fake_env = {}
  end

  it("builds an openai request with bearer auth and a stdin body", function()
    setup()
    fake_env["OPENAI_API_KEY"] = "test-key"
    local request, err = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
    }, "the prompt")
    assert.is_nil(err)
    assert.not_nil(request)
    assert.equals("https://api.openai.com/v1/chat/completions", request.cmd[5])
    assert.is_true(has_header(request.cmd, "Authorization: Bearer test-key"))
    assert.is_true(has_header(request.cmd, "Content-Type: application/json"))
    assert.is_true(vim.tbl_contains(request.cmd, "--data-binary"))
    assert.is_true(vim.tbl_contains(request.cmd, "@-"))
    assert.equals("60", max_time(request.cmd))
    teardown()
  end)

  it("encodes model, messages, max_tokens and temperature into the body", function()
    setup()
    fake_env["OPENAI_API_KEY"] = "test-key"
    local request = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
      temperature = 0.2,
    }, "explain this line")
    local decoded = vim.json.decode(request.body)
    assert.equals("gpt-4o-mini", decoded.model)
    assert.equals("explain this line", decoded.messages[1].content)
    assert.equals("user", decoded.messages[1].role)
    assert.equals(300, decoded.max_tokens)
    assert.equals(0.2, decoded.temperature)
    teardown()
  end)

  it("omits temperature when cfg.temperature is false", function()
    setup()
    fake_env["OPENAI_API_KEY"] = "test-key"
    local request = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
      temperature = false,
    }, "explain this line")
    local decoded = vim.json.decode(request.body)
    assert.is_nil(decoded.temperature)
    teardown()
  end)

  it("builds an anthropic request with x-api-key and version headers", function()
    setup()
    fake_env["ANTHROPIC_API_KEY"] = "test-key"
    local request, err = llm.build_request({
      provider = "anthropic",
      model = "claude-3-5-sonnet",
      max_tokens = 300,
    }, "the prompt")
    assert.is_nil(err)
    assert.not_nil(request)
    assert.equals("https://api.anthropic.com/v1/messages", request.cmd[5])
    assert.is_true(has_header(request.cmd, "x-api-key: test-key"))
    assert.is_true(has_header(request.cmd, "anthropic-version: 2023-06-01"))
    local decoded = vim.json.decode(request.body)
    assert.equals("the prompt", decoded.messages[1].content)
    assert.equals(300, decoded.max_tokens)
    teardown()
  end)

  it("honors a cfg.url override while keeping provider headers", function()
    setup()
    fake_env["OPENAI_API_KEY"] = "test-key"
    local request, err = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
      url = "http://localhost:11434/v1/chat/completions",
    }, "the prompt")
    assert.is_nil(err)
    assert.equals("http://localhost:11434/v1/chat/completions", request.cmd[5])
    assert.is_true(has_header(request.cmd, "Authorization: Bearer test-key"))
    teardown()
  end)

  it("skips auth when cfg.api_key_env is false", function()
    setup()
    local request, err = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
      api_key_env = false,
    }, "the prompt")
    assert.is_nil(err)
    assert.not_nil(request)
    for _, arg in ipairs(request.cmd) do
      assert.is_false(type(arg) == "string" and arg:find("Authorization") ~= nil, "no Authorization header expected")
      assert.is_false(type(arg) == "string" and arg:find("x-api-key") ~= nil, "no x-api-key header expected")
    end
    teardown()
  end)

  it("fails fast when the api key env var is missing", function()
    setup()
    local request, err = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
    }, "the prompt")
    assert.is_nil(request)
    assert.is_true(type(err) == "string" and err:find("OPENAI_API_KEY") ~= nil, "error should name the missing env var")
    teardown()
  end)

  it("uses a cfg.api_key_env override for the env var name", function()
    setup()
    fake_env["MY_CUSTOM_KEY"] = "custom-key"
    local request, err = llm.build_request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
      api_key_env = "MY_CUSTOM_KEY",
    }, "the prompt")
    assert.is_nil(err)
    assert.is_true(has_header(request.cmd, "Authorization: Bearer custom-key"))
    teardown()
  end)

  it("rejects an unknown provider", function()
    setup()
    local request, err = llm.build_request({ provider = "bogus", model = "m", max_tokens = 10 }, "p")
    assert.is_nil(request)
    assert.is_true(type(err) == "string" and err:find("bogus") ~= nil, "error should name the provider")
    teardown()
  end)

  it("returns nil plus an error for a missing config table", function()
    setup()
    local request, err = llm.build_request(nil, "p")
    assert.is_nil(request)
    assert.is_true(type(err) == "string" and err ~= "", "should have an error message")
    teardown()
  end)
end)

describe("Explain provider content extraction", function()
  it("openai extracts choices[1].message.content", function()
    local content = llm.providers.openai.extract_content({
      choices = { { message = { content = "the explanation" } } },
    })
    assert.equals("the explanation", content)
  end)

  it("anthropic skips thinking blocks to the first text block", function()
    local content = llm.providers.anthropic.extract_content({
      content = {
        { type = "thinking", thinking = "internal" },
        { type = "text", text = "the explanation" },
        { type = "text", text = "ignored" },
      },
    })
    assert.equals("the explanation", content)
  end)

  it("anthropic falls back to the first entry carrying text", function()
    local content = llm.providers.anthropic.extract_content({
      content = { { type = "tool_use", text = "odd but present" } },
    })
    assert.equals("odd but present", content)
  end)

  it("returns nil when the decoded shape does not match", function()
    assert.is_nil(llm.providers.openai.extract_content({}))
    assert.is_nil(llm.providers.openai.extract_content({ choices = {} }))
    assert.is_nil(llm.providers.anthropic.extract_content({}))
    assert.is_nil(llm.providers.anthropic.extract_content({ content = {} }))
  end)
end)

describe("Explain response handling", function()
  local function sentinel(status)
    return constants.EXPLAIN.HTTP_STATUS_SENTINEL .. status
  end

  it("splits the -w status sentinel from the body", function()
    local body, status = llm.split_response('{"choices":[]}\n' .. sentinel("200"))
    assert.equals(200, status)
    assert.deep_equals({ choices = {} }, vim.json.decode(body))
  end)

  it("preserves bodies containing braces and newlines when splitting", function()
    local body, status = llm.split_response('{"a": 1,\n"b": "}"}\n' .. sentinel("404"))
    assert.equals('{"a": 1,\n"b": "}"}\n', body)
    assert.equals(404, status)
  end)

  it("returns nil body and status when the sentinel is absent", function()
    local body, status = llm.split_response("curl: (28) timeout")
    assert.is_nil(body)
    assert.is_nil(status)
  end)

  it("extracts openai content through the decode path", function()
    local content, err = llm.extract_content("openai", '{"choices":[{"message":{"content":"hi"}}]}')
    assert.is_nil(err)
    assert.equals("hi", content)
  end)

  it("extracts anthropic content through the decode path", function()
    local content, err = llm.extract_content("anthropic", '{"content":[{"text":"hi"}]}')
    assert.is_nil(err)
    assert.equals("hi", content)
  end)

  it("skips anthropic thinking blocks during extraction", function()
    local content, err = llm.extract_content("anthropic",
      '{"content":[{"type":"thinking","thinking":"hmm {braces}"},{"type":"text","text":"hi"}]}')
    assert.is_nil(err)
    assert.equals("hi", content)
  end)

  it("ignores separate reasoning fields and reads only content", function()
    local content, err = llm.extract_content("openai",
      '{"choices":[{"message":{"reasoning_content":"let me think","content":"hi"}}]}')
    assert.is_nil(err)
    assert.equals("hi", content)
  end)

  it("returns a shape error naming the provider for a decodable but wrong response", function()
    local content, err = llm.extract_content("openai", '{"choices":[]}')
    assert.is_nil(content)
    assert.is_true(type(err) == "string" and err:find("openai") ~= nil, "error should mention the provider")
    assert.is_true(type(err) == "string" and err:find("unexpected response shape") ~= nil, "error should describe the shape failure")
  end)

  it("returns a decode error for non-JSON responses", function()
    local content, err = llm.extract_content("openai", "<html>502</html>")
    assert.is_nil(content)
    assert.is_true(type(err) == "string" and err:find("could not decode") ~= nil, "error should describe the decode failure")
    assert.is_true(type(err) == "string" and err:find("openai") ~= nil, "error should mention the provider")
  end)

  it("returns an error naming an unknown provider", function()
    local content, err = llm.extract_content("bogus", "{}")
    assert.is_nil(content)
    assert.is_true(type(err) == "string" and err:find("bogus") ~= nil, "error should name the provider")
  end)

  it("extracts the error message from a provider error envelope", function()
    assert.equals("invalid api key", llm.extract_error('{"error":{"message":"invalid api key"}}'))
  end)

  it("extracts a plain string error", function()
    assert.equals("rate limited", llm.extract_error('{"error":"rate limited"}'))
  end)

  it("falls back to a whitespace-collapsed body snippet for non-JSON errors", function()
    local err = llm.extract_error("Bad Gateway")
    assert.is_true(type(err) == "string" and err ~= "", "snippet should be non-empty")
    assert.is_true(type(err) == "string" and err:find("Bad Gateway") ~= nil, "snippet should contain the body text")
  end)

  it("never returns nil from extract_error", function()
    assert.is_true(type(llm.extract_error(nil)) == "string")
    assert.is_true(type(llm.extract_error("")) == "string")
    assert.is_true(type(llm.extract_error("not json")) == "string")
  end)
end)

describe("Explain request lifecycle", function()
  local saved_executable, saved_jobstart, saved_chansend, saved_chanclose
  local captured

  local function setup()
    captured = {
      curl_available = 1,
      jobstart_calls = {},
      chansend_calls = {},
      chanclose_calls = {},
    }
    saved_executable = vim.fn.executable
    vim.fn.executable = function(name)
      if name == "curl" then
        return captured.curl_available
      end
      return saved_executable(name)
    end
    saved_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      table.insert(captured.jobstart_calls, { cmd = cmd, opts = opts })
      return 7
    end
    saved_chansend = vim.fn.chansend
    vim.fn.chansend = function(job_id, data)
      table.insert(captured.chansend_calls, { job_id = job_id, data = data })
    end
    saved_chanclose = vim.fn.chanclose
    vim.fn.chanclose = function(job_id, what)
      table.insert(captured.chanclose_calls, { job_id = job_id, what = what })
    end
  end

  local function teardown()
    vim.fn.executable = saved_executable
    vim.fn.jobstart = saved_jobstart
    vim.fn.chansend = saved_chansend
    vim.fn.chanclose = saved_chanclose
  end

  local function cfg()
    return { provider = "openai", model = "gpt-4o-mini", max_tokens = 300, api_key_env = false }
  end

  local function sentinel(status)
    return constants.EXPLAIN.HTTP_STATUS_SENTINEL .. status
  end

  it("sends the body through stdin and delivers content on success", function()
    setup()
    local done_calls = {}
    local job_id = llm.request(cfg(), "the prompt", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    assert.equals(7, job_id)
    assert.equals(1, #captured.jobstart_calls)
    assert.equals(1, #captured.chansend_calls)
    assert.equals(7, captured.chansend_calls[1].job_id)
    local expected = llm.build_request(cfg(), "the prompt")
    assert.equals(expected.body, captured.chansend_calls[1].data, "request body should reach curl via chansend")
    assert.equals(1, #captured.chanclose_calls)
    assert.equals("stdin", captured.chanclose_calls[1].what)
    captured.jobstart_calls[1].opts.on_stdout(7, { '{"choices":[{"message":{"content":"ok"}}]}', sentinel("200") })
    captured.jobstart_calls[1].opts.on_exit(7, 0)
    helper.async.wait(50)
    assert.equals(1, #done_calls, "on_done should be invoked exactly once")
    assert.equals("ok", done_calls[1].content)
    assert.is_nil(done_calls[1].err)
    teardown()
  end)

  it("reports provider HTTP errors with the extracted message", function()
    setup()
    local done_calls = {}
    llm.request(cfg(), "the prompt", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    captured.jobstart_calls[1].opts.on_stdout(7, { '{"error":{"message":"bad key"}}', sentinel("401") })
    captured.jobstart_calls[1].opts.on_exit(7, 0)
    helper.async.wait(50)
    assert.equals(1, #done_calls, "on_done should be invoked exactly once")
    assert.is_nil(done_calls[1].content)
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("401") ~= nil, "error should contain the status code")
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("bad key") ~= nil, "error should contain the extracted message")
    teardown()
  end)

  it("reports a non-zero curl exit code with the first stderr line", function()
    setup()
    local done_calls = {}
    llm.request(cfg(), "the prompt", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    captured.jobstart_calls[1].opts.on_stderr(7, { "curl: (28) Operation timed out" })
    captured.jobstart_calls[1].opts.on_exit(7, 28)
    helper.async.wait(50)
    assert.equals(1, #done_calls, "on_done should be invoked exactly once")
    assert.is_nil(done_calls[1].content)
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("28") ~= nil, "error should mention the exit code")
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("Operation timed out") ~= nil, "error should mention the first stderr line")
    teardown()
  end)

  it("fails preflight without starting a job when curl is missing", function()
    setup()
    captured.curl_available = 0
    local done_calls = {}
    local job_id = llm.request(cfg(), "the prompt", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    assert.is_nil(job_id)
    assert.equals(0, #captured.jobstart_calls, "jobstart should never be called")
    assert.equals(1, #done_calls, "on_done should be invoked exactly once")
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("curl") ~= nil, "error should mention curl")
    teardown()
  end)

  it("fails preflight when the request cannot be built", function()
    setup()
    local done_calls = {}
    local job_id = llm.request({ provider = "bogus", model = "m", max_tokens = 10 }, "p", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    assert.is_nil(job_id)
    assert.equals(0, #captured.jobstart_calls, "jobstart should never be called")
    assert.equals(1, #done_calls, "on_done should be invoked exactly once")
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("bogus") ~= nil, "error should name the provider")
    teardown()
  end)

  it("fails when jobstart cannot start the process", function()
    setup()
    local failing_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function()
      return 0
    end
    local done_calls = {}
    local job_id = llm.request(cfg(), "the prompt", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    assert.is_nil(job_id)
    assert.equals(1, #done_calls, "on_done should be invoked exactly once")
    assert.is_true(type(done_calls[1].err) == "string" and done_calls[1].err:find("failed to start curl") ~= nil, "error should describe the start failure")
    vim.fn.jobstart = failing_jobstart
    teardown()
  end)

  it("never logs the api key, prompt or body through the debug logger", function()
    setup()
    local logged = {}
    package.loaded["consolelog.core.debug_logger"] = {
      log = function(category, message)
        table.insert(logged, { category = category, message = tostring(message) })
      end,
    }
    local saved_getenv = os.getenv
    os.getenv = function(name)
      if name == "OPENAI_API_KEY" then
        return "sk-test-secret-123"
      end
      return saved_getenv(name)
    end
    local done_calls = {}
    llm.request({
      provider = "openai",
      model = "gpt-4o-mini",
      max_tokens = 300,
      api_key_env = "OPENAI_API_KEY",
    }, "secret prompt body", function(content, err)
      table.insert(done_calls, { content = content, err = err })
    end)
    captured.jobstart_calls[1].opts.on_stdout(7, { '{"choices":[{"message":{"content":"ok"}}]}', sentinel("200") })
    captured.jobstart_calls[1].opts.on_exit(7, 0)
    helper.async.wait(50)
    os.getenv = saved_getenv
    assert.is_true(#logged > 0, "debug logger should have been called")
    for _, entry in ipairs(logged) do
      assert.is_false(entry.message:find("secret prompt body") ~= nil, "prompt/body must not be logged")
      assert.is_false(entry.message:find("sk-test-secret-123") ~= nil, "api key value must not be logged")
      assert.is_false(entry.message:find("OPENAI_API_KEY") ~= nil, "api key env name must not be logged")
      assert.is_false(entry.message:find("Authorization") ~= nil, "headers must not be logged")
    end
    package.loaded["consolelog.core.debug_logger"] = nil
    teardown()
  end)
end)
