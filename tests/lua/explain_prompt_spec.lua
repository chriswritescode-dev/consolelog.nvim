local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

local constants = require("consolelog.core.constants")
local prompt = require("consolelog.explain.prompt")

describe("Explain prompt", function()
  it("builds numbered rows with absolute line numbers", function()
    local result = prompt.build({ "const a = 1", "return a" }, 12, "javascript")
    assert.is_true(result:find("12: const a = 1", 1, true) ~= nil, "Should use absolute line 12")
    assert.is_true(result:find("13: return a", 1, true) ~= nil, "Should use absolute line 13")
  end)

  it("names the filetype and uses the response key constant", function()
    local result = prompt.build({ "const a = 1" }, 12, "javascript")
    assert.is_true(result:find("javascript", 1, true) ~= nil, "Should name the filetype")
    assert.is_true(result:find(constants.EXPLAIN.RESPONSE_KEY, 1, true) ~= nil, "Should reference the response key")
  end)

  it("returns nil for an empty source", function()
    assert.is_nil(prompt.build({}, 1, "lua"))
  end)
end)

describe("Explain response parsing", function()
  it("parses an object root with the response key", function()
    local annotations = prompt.parse('{"explanations":[{"line":12,"text":"adds the two totals"}]}', 12, 13)
    assert.not_nil(annotations, "Should parse object root")
    assert.equals(1, #annotations)
    assert.deep_equals({ line = 12, text = "adds the two totals" }, annotations[1])
  end)

  it("parses a fenced json block identically", function()
    local content = "```json\n{\"explanations\":[{\"line\":12,\"text\":\"adds the two totals\"}]}\n```"
    local annotations = prompt.parse(content, 12, 13)
    assert.not_nil(annotations, "Should parse fenced json")
    assert.deep_equals({ line = 12, text = "adds the two totals" }, annotations[1])

    local plain = "```\n{\"explanations\":[{\"line\":12,\"text\":\"adds the two totals\"}]}\n```"
    local annotations_plain = prompt.parse(plain, 12, 13)
    assert.not_nil(annotations_plain, "Should parse plain fence")
    assert.deep_equals({ line = 12, text = "adds the two totals" }, annotations_plain[1])
  end)

  it("parses a bare array root identically", function()
    local annotations = prompt.parse('[{"line":12,"text":"adds the two totals"}]', 12, 13)
    assert.not_nil(annotations, "Should parse bare array")
    assert.deep_equals({ line = 12, text = "adds the two totals" }, annotations[1])
  end)

  it("strips DeepSeek-R1-style thinking prose before extraction", function()
    local content = "\60think\62we should map {line: 12} carefully\nmaybe [1,2] \60/think\62\n{\"explanations\":[{\"line\":12,\"text\":\"adds the totals\"}]}"
    local annotations = prompt.parse(content, 12, 13)
    assert.not_nil(annotations, "Should ignore braces inside thinking prose")
    assert.equals(1, #annotations)
    assert.deep_equals({ line = 12, text = "adds the totals" }, annotations[1])
  end)

  it("keeps texts that mention thinking or response untouched", function()
    local content = '{"explanations":[{"line":1,"text":"logs thinking state"},{"line":2,"text":"awaits fetch response"}]}\nLet me know if you need another response\n'
    local annotations = prompt.parse(content, 1, 5)
    assert.not_nil(annotations)
    assert.equals(2, #annotations)
    assert.deep_equals({ line = 1, text = "logs thinking state" }, annotations[1])
    assert.deep_equals({ line = 2, text = "awaits fetch response" }, annotations[2])
  end)

  it("strips <thinking> blocks around a fenced payload", function()
    local content = "Here you go:\n<thinking>we should consider [1,2] and {x:1}</thinking>\n```json\n{\"explanations\":[{\"line\":12,\"text\":\"maps the payload\"}]}\n```\nHope that helps"
    local annotations = prompt.parse(content, 12, 13)
    assert.not_nil(annotations, "Should strip thinking block")
    assert.equals(1, #annotations)
    assert.deep_equals({ line = 12, text = "maps the payload" }, annotations[1])
  end)

  it("drops out-of-range entries and keeps in-range ones", function()
    local content = '{"explanations":[{"line":5,"text":"out"},{"line":13,"text":"in"},{"line":20,"text":"out"}]}'
    local annotations = prompt.parse(content, 12, 13)
    assert.not_nil(annotations)
    assert.equals(1, #annotations)
    assert.deep_equals({ line = 13, text = "in" }, annotations[1])
  end)

  it("accepts string line numbers and drops empty or missing text", function()
    local content = '{"explanations":[{"line":"12","text":"x"},{"line":13,"text":""},{"line":14}]}'
    local annotations = prompt.parse(content, 12, 14)
    assert.not_nil(annotations)
    assert.equals(1, #annotations)
    assert.deep_equals({ line = 12, text = "x" }, annotations[1])
  end)

  it("collapses multiline text to a single line", function()
    local content = '{"explanations":[{"line":12,"text":"first line\nsecond\tline  third"}]}'
    local annotations = prompt.parse(content, 12, 13)
    assert.not_nil(annotations)
    assert.equals(1, #annotations)
    assert.deep_equals({ line = 12, text = "first line second line third" }, annotations[1])
  end)

  it("keeps the first entry per line and sorts ascending", function()
    local content = '{"explanations":[{"line":13,"text":"second"},{"line":12,"text":"first"},{"line":13,"text":"duplicate dropped"}]}'
    local annotations = prompt.parse(content, 12, 13)
    assert.not_nil(annotations)
    assert.equals(2, #annotations)
    assert.deep_equals({ line = 12, text = "first" }, annotations[1])
    assert.deep_equals({ line = 13, text = "second" }, annotations[2])
  end)

  it("returns nil plus an error message for unusable responses", function()
    local annotations, err = prompt.parse("not json at all", 1, 10)
    assert.is_nil(annotations)
    assert.is_true(type(err) == "string" and err ~= "", "Should have an error message")

    local annotations_empty, err_empty = prompt.parse('{"explanations":[]}', 1, 10)
    assert.is_nil(annotations_empty)
    assert.is_true(type(err_empty) == "string" and err_empty ~= "", "Should have an error message")

    local annotations_nil, err_nil = prompt.parse(nil, 1, 10)
    assert.is_nil(annotations_nil)
    assert.is_true(type(err_nil) == "string" and err_nil ~= "", "Should have an error message")

    local annotations_blank, err_blank = prompt.parse("", 1, 10)
    assert.is_nil(annotations_blank)
    assert.is_true(type(err_blank) == "string" and err_blank ~= "", "Should have an error message")
  end)
end)
