local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.loaded["consolelog.core.debug_logger"] = { log = function() end }

package.path = package.path .. ";./lua/?.lua;./tests/lua/?.lua"
local formatter = require('consolelog.processing.formatter')
local float_inspector = require('consolelog.display.float_inspector')

describe("Value rendering", function()
	describe("render_json", function()
		it("should keep short containers on one line", function()
			assert.equals(formatter.render_json({ 1, 2, 3 }), "[ 1, 2, 3 ]")
			assert.equals(formatter.render_json({ { 1, 0 }, { 3, 1 } }), "[ [ 1, 0 ], [ 3, 1 ] ]")
		end)

		it("should render empty containers compactly", function()
			assert.equals(formatter.render_json({}), "[]")
			assert.equals(formatter.render_json(vim.empty_dict()), "{}")
		end)

		it("should render object keys sorted and unquoted when identifiers", function()
			assert.equals(formatter.render_json({ name = "chris", active = true }),
				'{ active: true, name: "chris" }')
		end)

		it("should quote keys that are not identifiers", function()
			assert.equals(formatter.render_json({ ["a-b"] = 1 }), '{ "a-b": 1 }')
		end)

		it("should break long containers across lines with trailing commas", function()
			local items = {}
			for i = 1, 10 do
				table.insert(items, { i, i * 2 })
			end

			local rendered = formatter.render_json(items)
			local lines = vim.split(rendered, "\n")

			assert.equals(lines[1], "[")
			assert.equals(lines[2], "  [ 1, 2 ],")
			assert.equals(lines[#lines], "]")
			assert.is_true(rendered:find(",\n") ~= nil, "commas belong at end of line, not on their own")
		end)

		it("should render null for JSON null values", function()
			assert.equals(formatter.render_json({ vim.NIL }), "[ null ]")
		end)
	end)

	describe("format_for_inspector", function()
		it("should keep runtime-formatted values verbatim", function()
			local value = "[Map Iterator] { 0, 1, 2 } Map(3) { 1 => 0 }"
			assert.equals(formatter.format_for_inspector(value), value)
		end)

		it("should keep multiline runtime output verbatim", function()
			local value = "{\n  a: {\n    b: { c: [ 1, 2 ] }\n  }\n}"
			assert.equals(formatter.format_for_inspector(value), value)
		end)

		it("should re-render serialized JSON payloads", function()
			assert.equals(formatter.format_for_inspector('{"b":2,"a":1}'), "{ a: 1, b: 2 }")
		end)

		it("should expand nested values instead of collapsing them", function()
			local rendered = formatter.format_for_inspector('[[1,0],[3,1]]')
			assert.equals(rendered, "[ [ 1, 0 ], [ 3, 1 ] ]")
			assert.is_true(rendered:find("%.%.%.") == nil, "nested values must not be elided")
		end)
	end)

	describe("format_values_for_inline", function()
		local config = { display = { prefix = "", max_width = 40 } }

		it("should render structured values in the same syntax as the inspector", function()
			assert.equals(formatter.format_values_for_inline({ '[[1,0],[3,1]]' }, config),
				"[ [ 1, 0 ], [ 3, 1 ] ]")
		end)

		it("should truncate and point at the inspector when too wide", function()
			local wide = {}
			for i = 1, 30 do
				table.insert(wide, i)
			end

			local formatted = formatter.format_values_for_inline({ wide }, config)
			assert.is_true(formatted:find("%[→ li%]") ~= nil, "should hint the inspector: " .. formatted)
			assert.is_true(#formatted <= config.display.max_width + 10, "should respect max_width")
		end)
	end)

	describe("compare_by_source_position", function()
		it("should order outputs by ascending line within a buffer", function()
			local outputs = {
				{ bufnr = 1, bufname = "a.ts", line = 16, timestamp = 300 },
				{ bufnr = 1, bufname = "a.ts", line = 5, timestamp = 100 },
				{ bufnr = 1, bufname = "a.ts", line = 10, timestamp = 200 },
			}

			table.sort(outputs, float_inspector.compare_by_source_position)

			assert.equals(outputs[1].line, 5, "first source line comes first")
			assert.equals(outputs[2].line, 10)
			assert.equals(outputs[3].line, 16)
		end)

		it("should group outputs per file", function()
			local outputs = {
				{ bufnr = 2, bufname = "b.ts", line = 1 },
				{ bufnr = 1, bufname = "a.ts", line = 9 },
				{ bufnr = 2, bufname = "b.ts", line = 4 },
				{ bufnr = 1, bufname = "a.ts", line = 2 },
			}

			table.sort(outputs, float_inspector.compare_by_source_position)

			assert.equals(outputs[1].bufname .. ":" .. outputs[1].line, "a.ts:2")
			assert.equals(outputs[2].bufname .. ":" .. outputs[2].line, "a.ts:9")
			assert.equals(outputs[3].bufname .. ":" .. outputs[3].line, "b.ts:1")
			assert.equals(outputs[4].bufname .. ":" .. outputs[4].line, "b.ts:4")
		end)
	end)
end)
