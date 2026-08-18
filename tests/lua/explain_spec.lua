local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

local explain = require("consolelog.explain")
local display = require("consolelog.display.display")

describe("Explain annotation layer", function()
  local test_bufnr
  local consolelog_mock

  local function setup()
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;'
    })
    vim.bo[test_bufnr].filetype = "javascript"

    consolelog_mock = {
      namespace = vim.api.nvim_create_namespace("consolelog_test"),
      outputs = {},
      config = {
        display = { max_width = 0, prefix = " ▸ " },
        history = { enabled = false },
        explain = { prefix = " ⟩ ", max_width = 0 },
      },
    }
    package.loaded['consolelog'] = consolelog_mock
    explain.annotations = {}
    explain.pending = {}
    explain.loading = {}
    display.extmarks = {}
  end

  it("renders annotations only into the explain namespace", function()
    setup()

    local rendered = explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "declares a" },
      { line = 3, text = "declares c" },
    })

    assert.equals(2, rendered, "Both in-range annotations should render")
    local explain_marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #explain_marks, "Two extmarks in the explain namespace")
    local console_marks = vim.api.nvim_buf_get_extmarks(test_bufnr, consolelog_mock.namespace, 0, -1, {})
    assert.equals(0, #console_marks, "No extmarks in the console namespace")
  end)

  it("keeps a console-output extmark on the same line", function()
    setup()

    display.render_output(test_bufnr, { line = 2, value = "test", console_type = "log", type = "string" })
    local before = vim.api.nvim_buf_get_extmarks(test_bufnr, consolelog_mock.namespace, 0, -1, {})
    assert.equals(1, #before, "Console output should render one mark first")

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "holds the value" },
    })

    local console_marks = vim.api.nvim_buf_get_extmarks(test_bufnr, consolelog_mock.namespace, 0, -1, {})
    assert.equals(1, #console_marks, "Console mark should survive rendering")
    assert.equals(1, console_marks[1][2], "Console mark should stay on line 2")
    local explain_marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #explain_marks, "Explain mark should render on the same line")
    assert.equals(1, explain_marks[1][2], "Explain mark should sit on line 2")
  end)

  it("skips annotations outside the buffer and counts only rendered ones", function()
    setup()

    local rendered = explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "holds 2" },
      { line = 9, text = "past the last line" },
      { line = 0, text = "before the first line" },
    })

    assert.equals(1, rendered, "Only the in-buffer annotation should render")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks)
    assert.equals(1, marks[1][2], "The surviving mark should be on line 2")
  end)

  it("records one store entry per created extmark with id, line and text", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "first" },
      { line = 5, text = "last" },
    })

    local entries = explain.annotations[test_bufnr]
    assert.not_nil(entries, "Store should be initialized")
    assert.equals(2, #entries, "One entry per extmark")

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks)
    for _, mark in ipairs(marks) do
      local matched = false
      for _, entry in ipairs(entries) do
        assert.is_true(type(entry.id) == "number", "Entry carries the mark id")
        assert.is_true(type(entry.line) == "number", "Entry carries the 1-based line")
        assert.is_true(type(entry.text) == "string" and entry.text ~= "", "Entry carries the text")
        if entry.id == mark[1] and entry.line == mark[2] + 1 then
          matched = true
        end
      end
      assert.is_true(matched, "Every extmark should have exactly one store entry")
    end
  end)

  it("clears only the requested line range", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "two" },
      { line = 3, text = "three" },
      { line = 5, text = "five" },
    })

    explain.clear(test_bufnr, 2, 3)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "Only the line 5 mark should survive")
    assert.equals(4, marks[1][2], "Surviving mark should be on line 5 (row 4)")
    local entries = explain.annotations[test_bufnr]
    assert.equals(1, #entries)
    assert.equals(5, entries[1].line)
    assert.equals("five", entries[1].text)
  end)

  it("clears the whole buffer when no range is given", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
      { line = 4, text = "four" },
    })

    explain.clear(test_bufnr)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "No marks should remain")
    assert.deep_equals({}, explain.annotations[test_bufnr], "Store should be empty")
  end)

  it("syncs stored lines with moved extmarks after an edit", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
    })

    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { "new1", "new2" })
    explain.sync_lines(test_bufnr)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, marks[1][2], "Extmark should move to row 2")
    local entries = explain.annotations[test_bufnr]
    assert.equals(1, #entries)
    assert.equals(3, entries[1].line, "Stored line should shift by 2")
  end)

  it("re-rendering a sub-range replaces only the store entries inside it", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "old two" },
      { line = 5, text = "five" },
    })

    local rendered = explain.render_annotations(test_bufnr, 2, 2, {
      { line = 2, text = "new two" },
    })
    assert.equals(1, rendered)

    local entries = explain.annotations[test_bufnr]
    assert.equals(2, #entries, "Entries outside the range should survive")
    local entry_two, entry_five
    for _, entry in ipairs(entries) do
      if entry.line == 2 then entry_two = entry end
      if entry.line == 5 then entry_five = entry end
    end
    assert.not_nil(entry_two, "Line 2 entry should exist")
    assert.equals("new two", entry_two.text)
    assert.not_nil(entry_five, "Line 5 entry should survive")
    assert.equals("five", entry_five.text)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "One mark per line outside the re-rendered range")
  end)

  it("opens a cursor-anchored float with the full explanation for the current line", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "a very long explanation of what the second line really does" },
    })

    local prev_buf = vim.api.nvim_win_get_buf(0)
    vim.api.nvim_win_set_buf(0, test_bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local win = explain.inspect(test_bufnr)
    assert.not_nil(win, "float opens for an annotated line")
    assert.is_true(vim.api.nvim_win_is_valid(win))
    local float_buf = vim.api.nvim_win_get_buf(win)
    local text = table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), " ")
    assert.is_true(text:find("a very long explanation", 1, true) ~= nil, "float carries the full text")
    vim.api.nvim_win_close(win, true)

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    assert.is_nil(explain.inspect(test_bufnr), "no float without an annotation on the line")

    vim.api.nvim_win_set_buf(0, prev_buf)
  end)

  it("does not raise on an invalid buffer", function()
    setup()

    assert.no_throw(function()
      explain.clear(99999)
    end, "clear should not raise")
    assert.no_throw(function()
      explain.render_annotations(99999, 1, 5, { { line = 1, text = "x" } })
    end, "render should not raise")
    assert.equals(0, explain.render_annotations(99999, 1, 5, { { line = 1, text = "x" } }))
  end)
end)

describe("Explain range orchestration", function()
  local test_bufnr
  local consolelog_mock
  local llm_calls
  local notify_calls
  local jobstop_calls
  local saved_notify
  local saved_jobstop

  local function setup()
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;'
    })
    vim.bo[test_bufnr].filetype = "javascript"

    consolelog_mock = {
      namespace = vim.api.nvim_create_namespace("consolelog_test"),
      outputs = {},
      config = {
        display = { max_width = 0, prefix = " ▸ " },
        history = { enabled = false },
        explain = { prefix = " ⟩ ", max_width = 0 },
      },
    }
    package.loaded['consolelog'] = consolelog_mock
    explain.annotations = {}
    explain.pending = {}
    explain.loading = {}
    display.extmarks = {}

    llm_calls = {}
    package.loaded["consolelog.explain.llm"] = {
      request = function(cfg, prompt, on_done)
        table.insert(llm_calls, { cfg = cfg, prompt = prompt, on_done = on_done })
        return #llm_calls
      end,
    }

    notify_calls = {}
    saved_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    jobstop_calls = {}
    saved_jobstop = vim.fn.jobstop
    vim.fn.jobstop = function(job_id)
      table.insert(jobstop_calls, job_id)
      return 0
    end
  end

  local function teardown()
    vim.notify = saved_notify
    vim.fn.jobstop = saved_jobstop
    package.loaded["consolelog.explain.llm"] = nil
    explain.cancel(test_bufnr)
  end

  local function notify_at(level, pattern)
    for _, call in ipairs(notify_calls) do
      if call.level == level and (not pattern or call.msg:find(pattern, 1, true)) then
        return call
      end
    end
    return nil
  end

  it("sends the whole buffer and renders one annotation per returned entry", function()
    setup()

    local state = explain.explain_range(test_bufnr, 1, 5)
    assert.equals(1, state.job_id)
    assert.equals(1, #llm_calls, "exactly one request")
    assert.is_true(llm_calls[1].prompt:find("1: const a = 1;") ~= nil, "prompt carries the first line with its absolute number")
    assert.is_true(llm_calls[1].prompt:find("5: const e = 5;") ~= nil, "prompt carries the last line with its absolute number")

    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"},{"line":5,"text":"five"}]}', nil)

    assert.is_nil(explain.pending[test_bufnr], "pending entry is cleared on completion")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "one extmark per returned entry")
    local info = notify_at(vim.log.levels.INFO, "Explained")
    assert.not_nil(info)
    assert.equals("Explained 2 lines", info.msg)
    teardown()
  end)

  it("shows an animated toast while the request is pending and resolves it on completion", function()
    setup()

    explain.explain_range(test_bufnr, 1, 5)
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "no extmarks while the request is pending")
    assert.not_nil(explain.loading[test_bufnr], "loading toast is tracked while pending")
    local toast = notify_at(vim.log.levels.INFO, "Explaining 5 lines")
    assert.not_nil(toast, "spinner toast announces the pending request")

    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)

    marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "the rendered annotation replaces the pending state")
    assert.is_nil(explain.loading[test_bufnr], "loading toast is cleared on completion")
    assert.not_nil(notify_at(vim.log.levels.INFO, "Explained 1 line"), "final toast replaces the spinner")
    teardown()
  end)

  it("clears the loading toast when the request fails", function()
    setup()

    explain.explain_range(test_bufnr, 1, 5)
    assert.not_nil(explain.loading[test_bufnr], "loading is tracked while pending")

    llm_calls[1].on_done(nil, "boom")

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "no marks remain after an error")
    assert.is_nil(explain.loading[test_bufnr], "loading toast is cleared on error")
    teardown()
  end)

  it("sends the whole file as context but explains only the requested sub-range", function()
    setup()

    local state = explain.explain_range(test_bufnr, 3, 4)
    assert.equals(1, state.job_id)
    assert.equals(1, #llm_calls)
    assert.is_true(llm_calls[1].prompt:find("3: const c = 3;") ~= nil, "prompt carries the sub-range start")
    assert.is_true(llm_calls[1].prompt:find("4: const d = 4;") ~= nil, "prompt carries the sub-range end")
    assert.is_true(llm_calls[1].prompt:find("1: const a = 1;") ~= nil, "the rest of the file rides along as context")
    assert.is_true(llm_calls[1].prompt:find("Explain only lines 3-4", 1, true) ~= nil, "instruction bounds the explained range")

    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"outside"},{"line":3,"text":"three"},{"line":4,"text":"four"}]}', nil)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "only in-range entries render")
    assert.equals(2, marks[1][2])
    assert.equals(3, marks[2][2])
    teardown()
  end)

  it("truncates context to the lines above the chunk when the file exceeds max_context_lines", function()
    setup()
    consolelog_mock.config.explain.max_lines = 2
    consolelog_mock.config.explain.max_context_lines = 3

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)

    local second = llm_calls[2].prompt
    assert.is_true(second:find("Explain only lines 3-4", 1, true) ~= nil)
    assert.is_true(second:find("2: const b = 2;") ~= nil, "one line above the chunk fits the budget")
    assert.is_false(second:find("1: const a = 1;") ~= nil, "lines beyond the context budget are dropped")
    assert.is_false(second:find("5: const e = 5;") ~= nil, "lines below the chunk are not sent when truncating")
    teardown()
  end)

  it("splits a range larger than max_lines into sequential chunk requests", function()
    setup()
    consolelog_mock.config.explain.max_lines = 2

    explain.explain_range(test_bufnr, 1, 5)
    assert.equals(1, #llm_calls, "only the first chunk is requested up front")
    assert.is_true(llm_calls[1].prompt:find("1: const a = 1;") ~= nil, "first chunk starts at line 1")
    assert.is_true(llm_calls[1].prompt:find("Explain only lines 1-2", 1, true) ~= nil, "first request explains the first chunk")

    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)

    assert.equals(2, #llm_calls, "next chunk starts after the first completes")
    assert.is_true(llm_calls[2].prompt:find("Explain only lines 3-4", 1, true) ~= nil, "second request explains the next chunk")
    assert.equals(1, #explain.annotations[test_bufnr], "first chunk renders before the second completes")
    assert.not_nil(explain.loading[test_bufnr], "loading indicator moves to the pending chunk")

    llm_calls[2].on_done('{"explanations":[{"line":3,"text":"three"},{"line":4,"text":"four"}]}', nil)
    assert.equals(3, #llm_calls, "third chunk follows")
    llm_calls[3].on_done('{"explanations":[{"line":5,"text":"five"}]}', nil)

    assert.is_nil(explain.pending[test_bufnr], "pipeline is finished")
    assert.is_nil(explain.loading[test_bufnr], "loading indicator is gone")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(4, #marks, "annotations from every chunk stay rendered")
    local info = notify_at(vim.log.levels.INFO, "Explained")
    assert.not_nil(info)
    assert.equals("Explained 4 lines", info.msg)
    teardown()
  end)

  it("anchors the first chunk exactly at the cursor line and wraps to cover the top", function()
    local chunks = explain.chunk_ranges(1, 10, 4, 6)
    assert.equals(4, #chunks)
    assert.deep_equals({ s = 6, e = 9 }, chunks[1], "first chunk starts at the cursor line")
    assert.deep_equals({ s = 10, e = 10 }, chunks[2], "following chunk continues downward")
    assert.deep_equals({ s = 1, e = 4 }, chunks[3], "the top is covered after the wrap")
    assert.deep_equals({ s = 5, e = 5 }, chunks[4], "the wrap stops just before the anchor")

    local no_cursor = explain.chunk_ranges(1, 10, 4, nil)
    assert.deep_equals({ s = 1, e = 4 }, no_cursor[1], "no cursor info starts at the top")

    local outside = explain.chunk_ranges(1, 10, 4, 99)
    assert.deep_equals({ s = 1, e = 4 }, outside[1], "a cursor outside the range starts at the top")
  end)

  it("survives a notifier that raises and still completes the pipeline", function()
    setup()
    vim.notify = function()
      error("notifier exploded")
    end

    local state = explain.explain_range(test_bufnr, 1, 5)
    assert.not_nil(state, "the pipeline starts despite the notifier raising")

    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)

    assert.is_nil(explain.pending[test_bufnr], "pipeline completes despite notifier errors")
    assert.is_nil(explain.loading[test_bufnr], "loading state is cleaned up")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "annotations render even when the notifier is broken")
    teardown()
  end)

  it("aborts the remaining chunks when one chunk fails", function()
    setup()
    consolelog_mock.config.explain.max_lines = 2

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)
    llm_calls[2].on_done(nil, "boom")

    assert.equals(2, #llm_calls, "no further chunk is requested after a failure")
    assert.is_nil(explain.pending[test_bufnr], "pipeline is dropped on error")
    assert.is_nil(explain.loading[test_bufnr], "loading indicator is cleared on error")
    assert.equals(1, #explain.annotations[test_bufnr], "annotations from completed chunks survive")
    local err = notify_at(vim.log.levels.ERROR)
    assert.not_nil(err)
    assert.is_true(err.msg:find("boom") ~= nil)
    teardown()
  end)

  it("skips a blank-only range with an info notification", function()
    setup()
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, { "", "  ", "\t" })

    local result = explain.explain_range(test_bufnr, 1, 3)
    assert.is_nil(result)
    assert.equals(0, #llm_calls)
    local info = notify_at(vim.log.levels.INFO)
    assert.not_nil(info)
    assert.equals("Nothing to explain in that range", info.msg)
    teardown()
  end)

  it("rejects a non-regular buffer with an error notification", function()
    setup()
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "nofile")

    local result = explain.explain_range(test_bufnr, 1, 5)
    assert.is_nil(result)
    assert.equals(0, #llm_calls)
    local err = notify_at(vim.log.levels.ERROR)
    assert.not_nil(err)
    assert.equals(":ConsoleLogExplain needs a regular file buffer", err.msg)
    teardown()
  end)

  it("stops the previous in-flight job when a new range is requested", function()
    setup()

    local first = explain.explain_range(test_bufnr, 1, 5)
    assert.equals(1, first.job_id)
    local second = explain.explain_range(test_bufnr, 2, 3)
    assert.equals(2, second.job_id)
    assert.deep_equals({ 1 }, jobstop_calls, "the first job is stopped")
    assert.equals(2, explain.pending[test_bufnr].job_id, "only the newest job stays pending")
    teardown()
  end)

  it("stops an in-flight request on demand and clears the loading toast", function()
    setup()

    explain.explain_range(test_bufnr, 1, 5)
    assert.not_nil(explain.loading[test_bufnr], "loading is tracked while pending")

    explain.stop(test_bufnr)

    assert.is_nil(explain.pending[test_bufnr], "pending state is cleared on stop")
    assert.is_nil(explain.loading[test_bufnr], "loading toast is cleared on stop")
    assert.deep_equals({ 1 }, jobstop_calls, "the in-flight job is stopped")
    assert.not_nil(notify_at(vim.log.levels.INFO, "Explain stopped"), "stop is announced")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "no annotations render after a stop")
    teardown()
  end)

  it("keeps completed chunk annotations when stopping mid-pipeline", function()
    setup()
    consolelog_mock.config.explain.max_lines = 2

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)
    assert.equals(2, #llm_calls, "second chunk is in flight")

    explain.stop(test_bufnr)

    assert.equals(2, #llm_calls, "no further chunk is requested after a stop")
    assert.deep_equals({ 2 }, jobstop_calls, "only the in-flight job is stopped")
    assert.equals(1, #explain.annotations[test_bufnr], "annotations from the completed chunk survive")
    assert.not_nil(explain.annotations[test_bufnr][1], "the surviving entry is line 1")
    teardown()
  end)

  it("notifies when there is nothing to stop", function()
    setup()

    explain.stop(test_bufnr)

    assert.equals("Nothing to stop", notify_at(vim.log.levels.INFO).msg)
    assert.equals(0, #jobstop_calls)
    teardown()
  end)

  it("surfaces request errors without touching the annotation layer", function()
    setup()

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done(nil, "boom")

    assert.is_nil(explain.pending[test_bufnr], "pending is cleared on error")
    local err = notify_at(vim.log.levels.ERROR)
    assert.not_nil(err)
    assert.is_true(err.msg:find("boom") ~= nil, "error message is surfaced")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "no extmarks rendered on error")
    teardown()
  end)

  it("discards a response when the buffer changed since the request", function()
    setup()

    explain.explain_range(test_bufnr, 1, 5)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { "const z = 0;" })
    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"stale"}]}', nil)

    local warn = notify_at(vim.log.levels.WARN)
    assert.not_nil(warn)
    assert.equals("Buffer changed while explaining; run :ConsoleLogExplain again", warn.msg)
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "stale annotations must never render")
    teardown()
  end)

  it("reports a model response that fails parsing without rendering", function()
    setup()
    consolelog_mock.config.explain.max_retries = 0

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done('{"explanations": [{"line": 1, "text": "x"}', nil)

    local err = notify_at(vim.log.levels.ERROR)
    assert.not_nil(err)
    assert.is_true(err.msg:find("could not decode model response as JSON") ~= nil, "error carries the parser message")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks)
    teardown()
  end)

  it("retries a chunk whose response fails JSON parsing and succeeds on retry", function()
    setup()
    consolelog_mock.config.explain.max_retries = 2

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done('{"explanations": [{"line": 1, "text": "x"}', nil)

    assert.equals(2, #llm_calls, "a parse failure triggers a retry request")
    assert.is_true(llm_calls[2].prompt:find("could not be parsed as JSON") ~= nil, "retry prompt carries a corrective hint")
    assert.not_nil(explain.pending[test_bufnr], "the run stays pending across retries")
    assert.not_nil(notify_at(vim.log.levels.INFO, "Retrying"), "the spinner announces the retry")

    llm_calls[2].on_done('{"explanations":[{"line":1,"text":"one"}]}', nil)

    assert.is_nil(explain.pending[test_bufnr], "pending is cleared once the retry succeeds")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "the retried response renders its annotations")
    teardown()
  end)

  it("gives up after max_retries parse failures and surfaces the error", function()
    setup()
    consolelog_mock.config.explain.max_retries = 2

    explain.explain_range(test_bufnr, 1, 5)
    llm_calls[1].on_done('{"explanations": [{"line": 1, "text": "x"}', nil)
    llm_calls[2].on_done('{"explanations": [{"line": 2, "text": "y"}', nil)
    llm_calls[3].on_done('{"explanations": [{"line": 3, "text": "z"}', nil)

    assert.equals(3, #llm_calls, "the initial request plus two retries")
    local err = notify_at(vim.log.levels.ERROR)
    assert.not_nil(err)
    assert.is_true(err.msg:find("could not decode model response as JSON") ~= nil, "the final parse error is surfaced")
    assert.is_nil(explain.pending[test_bufnr], "pending is cleared after retries are exhausted")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "nothing renders after retries are exhausted")
    teardown()
  end)
end)

describe("Explain command surface", function()
  local test_bufnr
  local recorder

  local function setup()
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;'
    })
    vim.bo[test_bufnr].filetype = "javascript"
    vim.api.nvim_set_current_buf(test_bufnr)

    recorder = { calls = {} }
    package.loaded["consolelog.explain"] = {
      explain_range = function(bufnr, start_line, end_line)
        table.insert(recorder.calls, { fn = "explain_range", bufnr = bufnr, start_line = start_line, end_line = end_line })
      end,
      clear = function(bufnr)
        table.insert(recorder.calls, { fn = "clear", bufnr = bufnr })
      end,
    }
  end

  local function teardown()
    package.loaded["consolelog.explain"] = nil
    vim.api.nvim_buf_delete(test_bufnr, { force = true })
  end

  it("registers ConsoleLogExplain with a range and ConsoleLogExplainClear", function()
    require("consolelog.core.commands").setup()

    local commands = vim.api.nvim_get_commands({})
    assert.not_nil(commands["ConsoleLogExplain"], "ConsoleLogExplain should be registered")
    assert.not_nil(commands["ConsoleLogExplain"].range, "ConsoleLogExplain should accept a range")
    assert.not_nil(commands["ConsoleLogExplainClear"], "ConsoleLogExplainClear should be registered")
  end)

  it("explains the whole buffer bare and the selection with a range", function()
    setup()
    require("consolelog.core.commands").setup()

    vim.cmd("ConsoleLogExplain")
    assert.equals(1, #recorder.calls, "bare invocation records one call")
    assert.equals("explain_range", recorder.calls[1].fn)
    assert.equals(test_bufnr, recorder.calls[1].bufnr)
    assert.equals(1, recorder.calls[1].start_line, "bare invocation falls back to line 1")
    assert.equals(5, recorder.calls[1].end_line, "bare invocation falls back to the whole buffer")

    vim.cmd("2,3ConsoleLogExplain")
    assert.equals(2, #recorder.calls, "range invocation records a second call")
    assert.equals(2, recorder.calls[2].start_line)
    assert.equals(3, recorder.calls[2].end_line)
    teardown()
  end)

  it("clears the current buffer on ConsoleLogExplainClear", function()
    setup()
    require("consolelog.core.commands").setup()

    vim.cmd("ConsoleLogExplainClear")
    assert.equals(1, #recorder.calls)
    assert.equals("clear", recorder.calls[1].fn)
    assert.equals(test_bufnr, recorder.calls[1].bufnr)
    teardown()
  end)

  it("exposes explain defaults and merges user overrides after setup", function()
    package.loaded['consolelog'] = nil
    require("consolelog.core.init").setup()

    local config = require("consolelog").config
    assert.equals("openai", config.explain.provider)
    assert.equals("gpt-4o-mini", config.explain.model)
    assert.equals(32768, config.explain.max_tokens)
    assert.is_nil(config.explain.temperature, "temperature stays unset so the server default applies")
    assert.equals(25, config.explain.max_lines)
    assert.equals(120000, config.explain.timeout_ms)
    assert.equals(80, config.explain.max_width)
    assert.equals("", config.explain.prefix)
    assert.equals(2, config.explain.max_retries)
    assert.equals("json_schema", config.explain.response_format)
    assert.is_nil(config.explain.url, "url stays absent so it can be overridden")
    assert.is_nil(config.explain.api_key_env, "api_key_env stays absent so it can be overridden")
    assert.equals("<leader>le", config.keymaps.explain)
    assert.equals("<leader>lE", config.keymaps.explain_clear)
    assert.equals("<leader>lI", config.keymaps.explain_inspect)

    require("consolelog.core.init").setup({ explain = { provider = "anthropic", url = "https://custom.example" } })
    assert.equals("anthropic", require("consolelog").config.explain.provider, "user provider override wins")
    assert.equals("https://custom.example", require("consolelog").config.explain.url, "user url override wins")
    assert.equals(32768, require("consolelog").config.explain.max_tokens, "unset fields keep defaults")
  end)

  it("maps explain to both normal and visual mode and clear to normal", function()
    local config = { keymaps = { enabled = true, explain = "<leader>le", explain_clear = "<leader>lE" } }
    require("consolelog.core.keymaps").setup(config)

    assert.is_true(vim.fn.maparg("<leader>le", "n") ~= "", "normal-mode explain mapping exists")
    assert.is_true(vim.fn.maparg("<leader>le", "x") ~= "", "visual-mode explain mapping exists")
    assert.is_true(vim.fn.maparg("<leader>lE", "n") ~= "", "normal-mode clear mapping exists")
  end)
end)

describe("Explain persistence", function()
  local test_bufnr
  local consolelog_mock

  local function setup()
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;'
    })
    vim.bo[test_bufnr].filetype = "javascript"

    consolelog_mock = {
      namespace = vim.api.nvim_create_namespace("consolelog_test"),
      outputs = {},
      config = {
        enabled = false,
        auto_enable = false,
        runner = { rerun_on_save = false },
        display = { max_width = 0, prefix = " ▸ " },
        history = { enabled = false },
        explain = { prefix = " ⟩ ", max_width = 0 },
      },
    }
    package.loaded['consolelog'] = consolelog_mock
    package.loaded["consolelog.communication.inspector"] = {
      is_single_file_buffer = function() return false end,
    }
    package.loaded["consolelog.explain"] = explain
    explain.annotations = {}
    explain.pending = {}
    explain.loading = {}
    display.extmarks = {}

    require("consolelog.core.autocmds").setup()
  end

  local function teardown()
    package.loaded['consolelog'] = nil
    package.loaded["consolelog.communication.inspector"] = nil
    vim.api.nvim_buf_delete(test_bufnr, { force = true })
  end

  it("keeps annotations when the buffer is saved", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "two" },
      { line = 4, text = "four" },
    })

    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = test_bufnr })

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "both extmarks survive a save")
    assert.equals(1, marks[1][2], "first mark stays on line 2")
    assert.equals(3, marks[2][2], "second mark stays on line 4")
    local entries = explain.annotations[test_bufnr]
    assert.equals(2, #entries, "store keeps both entries")
    teardown()
  end)

  it("snapshots moved extmark positions into the store on save", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
    })

    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { "const z = 0;", "const y = 0;" })
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = test_bufnr })

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, marks[1][2], "extmark moved to row 2")
    local entries = explain.annotations[test_bufnr]
    assert.equals(1, #entries)
    assert.equals(3, entries[1].line, "stored line shifts by 2 after save")
    teardown()
  end)

  it("re-renders cached annotations after a reload for any filetype", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "first" },
      { line = 3, text = "third" },
    })

    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;',
      'const f = 6;',
    })
    vim.api.nvim_buf_clear_namespace(test_bufnr, explain.namespace, 0, -1)
    vim.bo[test_bufnr].filetype = "markdown"
    vim.api.nvim_set_current_buf(test_bufnr)

    vim.api.nvim_exec_autocmds("BufReadPost", {})

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "annotations re-render at their stored lines")
    assert.equals(0, marks[1][2], "first annotation back on line 1")
    assert.equals(2, marks[2][2], "second annotation back on line 3")
    local entries = explain.annotations[test_bufnr]
    assert.equals(2, #entries)
    assert.equals("first", entries[1].text)
    assert.equals("third", entries[2].text)
    teardown()
  end)

  it("drops cached annotations beyond the reloaded buffer's line count", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "first" },
      { line = 5, text = "fifth" },
    })

    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
    })
    vim.api.nvim_buf_clear_namespace(test_bufnr, explain.namespace, 0, -1)
    vim.bo[test_bufnr].filetype = "markdown"
    vim.api.nvim_set_current_buf(test_bufnr)

    vim.api.nvim_exec_autocmds("BufReadPost", {})

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "only the in-bounds annotation re-renders")
    assert.equals(0, marks[1][2], "surviving annotation sits on line 1")
    local entries = explain.annotations[test_bufnr]
    assert.equals(1, #entries, "out-of-bounds entry is dropped from the store")
    teardown()
  end)

  it("renders nothing after an explicit clear followed by a reload", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "two" },
    })

    explain.clear(test_bufnr)
    vim.bo[test_bufnr].filetype = "markdown"
    vim.api.nvim_set_current_buf(test_bufnr)

    vim.api.nvim_exec_autocmds("BufReadPost", {})

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "cleared annotations never come back on reload")
    assert.deep_equals({}, explain.annotations[test_bufnr], "store stays empty after reload")
    teardown()
  end)
end)

describe("Explain visibility toggle", function()
  local test_bufnr
  local consolelog_mock
  local llm_calls
  local notify_calls
  local saved_notify
  local saved_jobstop

  local function setup()
    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_bufnr, "buftype", "")
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'const a = 1;',
      'const b = 2;',
      'const c = 3;',
      'const d = 4;',
      'const e = 5;'
    })
    vim.bo[test_bufnr].filetype = "javascript"

    consolelog_mock = {
      namespace = vim.api.nvim_create_namespace("consolelog_test"),
      outputs = {},
      config = {
        enabled = false,
        auto_enable = false,
        runner = { rerun_on_save = false },
        display = { max_width = 0, prefix = " ▸ " },
        history = { enabled = false },
        explain = { prefix = " ⟩ ", max_width = 0 },
      },
    }
    package.loaded['consolelog'] = consolelog_mock
    package.loaded["consolelog.communication.inspector"] = {
      is_single_file_buffer = function() return false end,
    }
    package.loaded["consolelog.explain"] = explain
    explain.annotations = {}
    explain.pending = {}
    explain.loading = {}
    explain.hidden = {}
    display.extmarks = {}

    llm_calls = {}
    package.loaded["consolelog.explain.llm"] = {
      request = function(cfg, prompt, on_done)
        table.insert(llm_calls, { cfg = cfg, prompt = prompt, on_done = on_done })
        return #llm_calls
      end,
    }

    notify_calls = {}
    saved_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    saved_jobstop = vim.fn.jobstop
    vim.fn.jobstop = function()
      return 0
    end

    require("consolelog.core.autocmds").setup()
  end

  local function teardown()
    vim.notify = saved_notify
    vim.fn.jobstop = saved_jobstop
    package.loaded["consolelog.explain.llm"] = nil
    package.loaded["consolelog.explain"] = nil
    package.loaded['consolelog'] = nil
    package.loaded["consolelog.communication.inspector"] = nil
    vim.api.nvim_buf_delete(test_bufnr, { force = true })
  end

  local function mark_texts()
    local texts = {}
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      local parts = {}
      for _, chunk in ipairs(mark[4].virt_text) do
        table.insert(parts, chunk[1])
      end
      table.insert(texts, table.concat(parts))
    end
    return texts
  end

  local function notify_at(level)
    for _, call in ipairs(notify_calls) do
      if call.level == level then
        return call
      end
    end
    return nil
  end

  it("hides extmarks while keeping the store intact", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "two" },
      { line = 4, text = "four" },
    })

    explain.toggle(test_bufnr)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "no extmarks while hidden")
    local entries = explain.annotations[test_bufnr]
    assert.equals(2, #entries, "store keeps both entries")
    assert.equals("two", entries[1].text)
    assert.equals("four", entries[2].text)
    assert.is_true(explain.hidden[test_bufnr] == true, "hidden flag is set")
    teardown()
  end)

  it("re-renders cached annotations with identical text on a second toggle", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "two" },
      { line = 4, text = "four" },
    })
    local before = mark_texts()

    explain.toggle(test_bufnr)
    explain.toggle(test_bufnr)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "both annotations re-render")
    assert.deep_equals(before, mark_texts(), "re-rendered texts match the originals")
    assert.is_nil(explain.hidden[test_bufnr], "hidden flag cleared on show")
    teardown()
  end)

  it("keeps the cache through a save while hidden", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
      { line = 3, text = "three" },
    })

    explain.toggle(test_bufnr)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { "const z = 0;", "const y = 0;" })
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = test_bufnr })

    local entries = explain.annotations[test_bufnr]
    assert.equals(2, #entries, "a save while hidden must not empty the store")

    explain.toggle(test_bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "annotations reappear after un-hiding")
    assert.equals(2, #explain.annotations[test_bufnr], "store still holds both entries")
    teardown()
  end)

  it("snapshots moved extmark positions before hiding", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
    })

    vim.api.nvim_buf_set_lines(test_bufnr, 0, 0, false, { "const z = 0;", "const y = 0;" })
    explain.toggle(test_bufnr)
    explain.toggle(test_bufnr)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks)
    assert.equals(2, marks[1][2], "annotation reappears at the shifted row")
    assert.equals(3, explain.annotations[test_bufnr][1].line, "store line shifted by the edit")
    teardown()
  end)

  it("keeps hidden annotations hidden across a reload", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 2, text = "two" },
    })

    explain.toggle(test_bufnr)
    vim.bo[test_bufnr].filetype = "markdown"
    vim.api.nvim_set_current_buf(test_bufnr)
    vim.api.nvim_exec_autocmds("BufReadPost", {})

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(0, #marks, "a reload must not resurrect hidden annotations")
    assert.equals(1, #explain.annotations[test_bufnr], "cache is kept while hidden")

    explain.toggle(test_bufnr)
    marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "un-hiding renders the cached annotation")
    assert.is_nil(explain.hidden[test_bufnr], "hidden flag cleared on show")
    teardown()
  end)

  it("re-explain clears the hidden flag and shows its result", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "old" },
    })
    explain.toggle(test_bufnr)
    assert.is_true(explain.hidden[test_bufnr] == true, "hidden before re-explain")

    local state = explain.explain_range(test_bufnr, 1, 5)
    assert.equals(1, state.job_id)
    llm_calls[1].on_done('{"explanations":[{"line":1,"text":"new"}]}', nil)

    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(1, #marks, "re-explain result renders immediately")
    assert.is_nil(explain.hidden[test_bufnr], "hidden flag cleared on re-explain")
    teardown()
  end)

  it("re-explain while hidden keeps out-of-range cached annotations", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
      { line = 4, text = "four" },
    })
    explain.toggle(test_bufnr)
    assert.is_true(explain.hidden[test_bufnr] == true, "hidden before re-explain")

    local state = explain.explain_range(test_bufnr, 3, 4)
    assert.equals(1, state.job_id)
    llm_calls[1].on_done('{"explanations":[{"line":3,"text":"three-new"}]}', nil)

    local entries = explain.annotations[test_bufnr]
    assert.equals(2, #entries, "out-of-range entry survives a re-explain while hidden")
    assert.equals("one", entries[1].text, "line-1 entry keeps its text")
    local marks = vim.api.nvim_buf_get_extmarks(test_bufnr, explain.namespace, 0, -1, {})
    assert.equals(2, #marks, "out-of-range annotation re-renders alongside the new one")
    assert.is_nil(explain.hidden[test_bufnr], "hidden flag cleared on re-explain")
    teardown()
  end)

  it("notifies when there is nothing to toggle", function()
    setup()

    assert.no_throw(function()
      explain.toggle(test_bufnr)
    end, "toggle on an empty buffer must not raise")
    local info = notify_at(vim.log.levels.INFO)
    assert.not_nil(info)
    assert.equals("No explanations to toggle", info.msg)
    assert.is_nil(explain.hidden[test_bufnr], "hidden flag untouched")
    teardown()
  end)

  it("clear fully resets the explain state for the buffer", function()
    setup()

    explain.render_annotations(test_bufnr, 1, 5, {
      { line = 1, text = "one" },
    })
    explain.toggle(test_bufnr)
    assert.is_true(explain.hidden[test_bufnr] == true, "hidden before clear")

    explain.clear(test_bufnr)

    assert.deep_equals({}, explain.annotations[test_bufnr], "store emptied")
    assert.is_nil(explain.hidden[test_bufnr], "hidden flag cleared")

    explain.toggle(test_bufnr)
    local info = notify_at(vim.log.levels.INFO)
    assert.not_nil(info)
    assert.equals("No explanations to toggle", info.msg)
    teardown()
  end)
end)
