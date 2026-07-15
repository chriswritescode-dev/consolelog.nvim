local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

-- Stub display before requiring protocol
local update_output_mock = helper.mock.new("update_output")
package.loaded["consolelog.display.display"] = {
	update_output = update_output_mock,
}
package.loaded["consolelog"] = {
	config = {
		websocket = { display_methods = { "log", "error" } },
	},
}
-- Stub line_matching and debug_logger so real message_processor_impl can load
package.loaded["consolelog.processing.line_matching"] = {
	match_by_file_and_command = function() return nil, nil, nil end,
	reset = function() end,
	get_state_info = function() return {} end,
}
package.loaded["consolelog.core.debug_logger"] = {
	log = function() end,
}

package.path = package.path .. ";./lua/?.lua;./tests/lua/?.lua"
local protocol = require('consolelog.communication.protocol')

local function setup()
	update_output_mock:reset()
end

describe("Protocol Module", function()
	describe("remote_object_to_arg", function()
		it("should pass through strings", function()
			assert.equals(protocol.remote_object_to_arg({ type = "string", value = "hello" }), "hello")
		end)

		it("should pass through numbers", function()
			local result = protocol.remote_object_to_arg({ type = "number", value = 42 })
			assert.equals(result, 42)
		end)

		it("should handle NaN via unserializableValue", function()
			local result = protocol.remote_object_to_arg({ type = "number", unserializableValue = "NaN" })
			assert.equals(result, "NaN")
		end)

		it("should handle Infinity via unserializableValue", function()
			local result = protocol.remote_object_to_arg({ type = "number", unserializableValue = "Infinity" })
			assert.equals(result, "Infinity")
		end)

		it("should handle -Infinity via unserializableValue", function()
			local result = protocol.remote_object_to_arg({ type = "number", unserializableValue = "-Infinity" })
			assert.equals(result, "-Infinity")
		end)

		it("should handle -0 via unserializableValue", function()
			local result = protocol.remote_object_to_arg({ type = "number", unserializableValue = "-0" })
			assert.equals(result, "-0")
		end)

		it("should prefer unserializableValue over value for numbers", function()
			local result = protocol.remote_object_to_arg({ type = "number", value = "42", unserializableValue = "NaN" })
			assert.equals(result, "NaN")
		end)

		it("should pass through booleans", function()
			local result = protocol.remote_object_to_arg({ type = "boolean", value = true })
			assert.equals(result, true)
		end)

		it("should convert undefined to string", function()
			assert.equals(protocol.remote_object_to_arg({ type = "undefined" }), "undefined")
		end)

		it("should convert null object to string", function()
			assert.equals(protocol.remote_object_to_arg({ type = "object", subtype = "null" }), "null")
		end)

		it("should use unserializableValue for bigint", function()
			assert.equals(
				protocol.remote_object_to_arg({ type = "bigint", unserializableValue = "123n" }),
				"123n"
			)
		end)

		it("should use description for symbol", function()
			assert.equals(
				protocol.remote_object_to_arg({ type = "symbol", description = "Symbol(foo)" }),
				"Symbol(foo)"
			)
		end)

		it("should fallback for symbol without description", function()
			assert.equals(protocol.remote_object_to_arg({ type = "symbol" }), "Symbol()")
		end)

		it("should format function description", function()
			assert.equals(
				protocol.remote_object_to_arg({ type = "function", description = "function foo() {}" }),
				"[Function: foo]"
			)
		end)

		it("should return description for error subtype", function()
			assert.equals(
				protocol.remote_object_to_arg({ type = "object", subtype = "error", description = "Error: boom" }),
				"Error: boom"
			)
		end)

		it("should format map preview", function()
			local result = protocol.remote_object_to_arg({
				type = "object",
				subtype = "map",
				preview = {
					entries = {
						{ key = { value = "a" }, value = { value = "1" } },
					},
				},
			})
			assert.is_true(result:match("Map") ~= nil, "Should contain Map: " .. result)
			assert.is_true(result:match("a") ~= nil, "Should contain key: " .. result)
		end)

		it("should format map preview with real CDP descriptions", function()
			local result = protocol.remote_object_to_arg({
				type = "object",
				subtype = "map",
				preview = {
					entries = {
						{ key = { type = "string", description = "name" }, value = { type = "string", description = "Alice" } },
						{ key = { type = "number", description = "42" }, value = { type = "boolean", description = "true" } },
					},
				},
			})
			assert.is_true(result:match("Map") ~= nil, "Should contain Map: " .. result)
			assert.is_true(result:match("name") ~= nil, "Should contain key: " .. result)
			assert.is_true(result:match("Alice") ~= nil, "Should contain value: " .. result)
			assert.is_true(result:match("42") ~= nil, "Should contain numeric key: " .. result)
			assert.is_true(result:match("true") ~= nil, "Should contain boolean value: " .. result)
		end)

		it("should format set preview", function()
			local result = protocol.remote_object_to_arg({
				type = "object",
				subtype = "set",
				preview = {
					entries = {
						{ value = { value = "x" } },
					},
				},
			})
			assert.is_true(result:match("Set") ~= nil, "Should contain Set: " .. result)
		end)

		it("should format set preview with real CDP descriptions", function()
			local result = protocol.remote_object_to_arg({
				type = "object",
				subtype = "set",
				preview = {
					entries = {
						{ value = { type = "string", description = "foo" } },
						{ value = { type = "number", description = "99" } },
					},
				},
			})
			assert.is_true(result:match("Set") ~= nil, "Should contain Set: " .. result)
			assert.is_true(result:match("foo") ~= nil, "Should contain value: " .. result)
			assert.is_true(result:match("99") ~= nil, "Should contain numeric value: " .. result)
		end)

		it("should return description for date subtype", function()
			assert.equals(
				protocol.remote_object_to_arg({ type = "object", subtype = "date", description = "2024-01-01" }),
				"2024-01-01"
			)
		end)

		it("should return description for regexp subtype", function()
			assert.equals(
				protocol.remote_object_to_arg({ type = "object", subtype = "regexp", description = "/abc/g" }),
				"/abc/g"
			)
		end)

		it("should return JSON string for array with preview", function()
			local result = protocol.remote_object_to_arg({
				type = "object",
				subtype = "array",
				preview = {
					subtype = "array",
					properties = {
						{ name = "0", type = "number", value = "1" },
						{ name = "1", type = "number", value = "2" },
					},
				},
			})
			local ok, decoded = pcall(vim.json.decode, result)
			assert.is_true(ok, "Should be valid JSON: " .. result)
			assert.is_true(vim.islist(decoded), "Should be a list")
			assert.equals(#decoded, 2)
			assert.equals(decoded[1], 1)
			assert.equals(decoded[2], 2)
		end)

		it("should return JSON string for object with preview", function()
			local result = protocol.remote_object_to_arg({
				type = "object",
				preview = {
					properties = {
						{ name = "a", type = "number", value = "1" },
						{ name = "b", type = "string", value = "x" },
					},
				},
			})
			local ok, decoded = pcall(vim.json.decode, result)
			assert.is_true(ok, "Should be valid JSON: " .. result)
			assert.equals(decoded.a, 1)
			assert.equals(decoded.b, "x")
		end)
	end)

	describe("preview_to_table", function()
		it("should build array from array preview", function()
			local result = protocol.preview_to_table({
				subtype = "array",
				properties = {
					{ name = "0", type = "number", value = "1" },
					{ name = "1", type = "number", value = "2" },
				},
			})
			assert.is_true(vim.islist(result))
			assert.equals(#result, 2)
			assert.equals(result[1], 1)
			assert.equals(result[2], 2)
		end)

		it("should build map from object preview", function()
			local result = protocol.preview_to_table({
				properties = {
					{ name = "a", type = "number", value = "1" },
					{ name = "b", type = "string", value = "x" },
				},
			})
			assert.equals(result.a, 1)
			assert.equals(result.b, "x")
		end)

		it("should add overflow indicator for arrays", function()
			local result = protocol.preview_to_table({
				subtype = "array",
				overflow = true,
				properties = {
					{ name = "0", type = "number", value = "1" },
				},
			})
			assert.equals(#result, 2)
			assert.equals(result[2], "...")
		end)

		it("should add overflow key for maps", function()
			local result = protocol.preview_to_table({
				overflow = true,
				properties = {
					{ name = "a", type = "number", value = "1" },
				},
			})
			assert.equals(result.a, 1)
			assert.equals(result["..."], "...")
		end)

		it("should handle nested objects as placeholders", function()
			local result = protocol.preview_to_table({
				properties = {
					{ name = "inner", type = "object", subtype = "array" },
				},
			})
			assert.equals(result.inner, "[...]")
		end)

		it("should handle nested objects as map placeholders", function()
			local result = protocol.preview_to_table({
				properties = {
					{ name = "inner", type = "object" },
				},
			})
			assert.equals(result.inner, "{...}")
		end)

		it("should handle valuePreview in array as nested placeholder", function()
			local result = protocol.preview_to_table({
				subtype = "array",
				properties = {
					{ name = "0", type = "string", value = "a" },
					{ name = "1", valuePreview = { subtype = "array", properties = {} } },
				},
			})
			assert.equals(result[1], "a")
			assert.equals(result[2], "[...]")
		end)

		it("should handle valuePreview in map as nested placeholder", function()
			local result = protocol.preview_to_table({
				properties = {
					{ name = "fn", valuePreview = { properties = {} } },
				},
			})
			assert.equals(result.fn, "{...}")
		end)

		it("should handle boolean properties", function()
			local result = protocol.preview_to_table({
				properties = {
					{ name = "flag", type = "boolean", value = "true" },
					{ name = "off", type = "boolean", value = "false" },
				},
			})
			assert.equals(result.flag, true)
			assert.equals(result.off, false)
		end)

		it("should sort array properties by numeric name", function()
			local result = protocol.preview_to_table({
				subtype = "array",
				properties = {
					{ name = "1", type = "number", value = "2" },
					{ name = "0", type = "number", value = "1" },
				},
			})
			assert.is_true(vim.islist(result))
			assert.equals(#result, 2)
			assert.equals(result[1], 1)
			assert.equals(result[2], 2)
		end)
	end)

	describe("handle_console_event", function()
		it("should convert CDP args and format via real format_args", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {
				type = "warning",
				args = { { type = "string", value = "hi" } },
				stackTrace = {
					callFrames = {
						{ url = "file:///tmp/t.js", lineNumber = 4 },
					},
				},
			}

			protocol.handle_console_event(session, params)
			helper.async.wait(50)

			assert.is_true(update_output_mock:was_called(), "update_output should be called")
			local upd_args = update_output_mock.calls[1]
			assert.equals(upd_args[1], 1, "bufnr")
			assert.equals(upd_args[2], 5, "line (lineNumber 4 + 1)")
			local out = type(upd_args[3]) == "table" and upd_args[3][1] or tostring(upd_args[3])
			assert.is_true(out:match("hi") ~= nil, "output should contain 'hi', got: " .. tostring(out))
			assert.equals(upd_args[4], "warn", "console_type")
		end)

		it("should default unknown types to log", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {
				type = "verbose",
				args = { { type = "string", value = "msg" } },
				stackTrace = {
					callFrames = {
						{ url = "file:///tmp/t.js", lineNumber = 0 },
					},
				},
			}

			protocol.handle_console_event(session, params)
			helper.async.wait(50)

			assert.is_true(update_output_mock:was_called(), "update_output should be called")
			local upd_args = update_output_mock.calls[1]
			assert.equals(upd_args[4], "log", "unknown type should default to log")
		end)

		it("should skip when no stackTrace matches", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {
				type = "log",
				args = { { type = "string", value = "msg" } },
			}

			protocol.handle_console_event(session, params)
			helper.async.wait(50)

			assert.is_false(update_output_mock:was_called(), "update_output should not be called")
		end)

		it("should render empty args with correct type", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {
				type = "log",
				args = {},
				stackTrace = {
					callFrames = {
						{ url = "file:///tmp/t.js", lineNumber = 4 },
					},
				},
			}

			protocol.handle_console_event(session, params)
			helper.async.wait(50)

			assert.is_true(update_output_mock:was_called(), "update_output should be called for empty args")
			local upd_args = update_output_mock.calls[1]
			assert.equals(upd_args[1], 1, "bufnr")
			assert.equals(upd_args[2], 5, "line")
			assert.equals(upd_args[4], "log", "console_type")
		end)
	end)

	describe("handle_exception_event", function()
		it("should render first line inline and full desc as raw_value", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {
				exceptionDetails = {
					exception = {
						description = "Error: boom\n    at foo (/tmp/t.js:3:1)",
					},
					stackTrace = {
						callFrames = {
							{ url = "file:///tmp/t.js", lineNumber = 2 },
						},
					},
				},
			}

			protocol.handle_exception_event(session, params)
			helper.async.wait(50)

			assert.is_true(update_output_mock:was_called(), "update_output should be called")
			local args = update_output_mock.calls[1]
			assert.equals(args[1], 1, "bufnr")
			assert.equals(args[2], 3, "line (lineNumber 2 + 1)")
			assert.equals(args[3], "Error: boom", "inline text should be first line only")
			assert.equals(args[4], "error", "console_type")
			assert.is_true(
				tostring(args[5]):match("Error: boom") ~= nil,
				"raw_value should contain full description"
			)
		end)

		it("should handle missing stackTrace via lineNumber fallback", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {
				exceptionDetails = {
					exception = {
						description = "TypeError: cannot read property",
					},
					lineNumber = 9,
				},
			}

			protocol.handle_exception_event(session, params)
			helper.async.wait(50)

			assert.is_true(update_output_mock:was_called())
			local args = update_output_mock.calls[1]
			assert.equals(args[2], 10, "lineNumber 9 + 1")
			assert.equals(args[4], "error")
		end)

		it("should skip when no exceptionDetails", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local params = {}

			protocol.handle_exception_event(session, params)
			helper.async.wait(50)

			assert.is_false(update_output_mock:was_called())
		end)

		it("should render only first line in virtual text, not full stack", function()
			-- This tests the integration with virtual_text_builder to ensure
			-- the full multiline stack is NOT shown inline.
			local vtext = require("consolelog.display.virtual_text_builder")
			local config = {
				display = { prefix = "", max_width = 200 },
				history = { enabled = false },
			}

			local output = {
				value = "Error: boom",
				raw_value = "Error: boom\n    at foo (/tmp/t.js:3:1)\n    at bar (/tmp/t.js:5:1)",
				console_type = "error",
			}

			local virt_lines = vtext.build_virtual_text(output, config)
			-- The first (and only) virtual text line should contain "Error: boom"
			-- but NOT the stack frames (at foo, at bar).
			local first_line_text = ""
			for _, segment in ipairs(virt_lines[1]) do
				first_line_text = first_line_text .. segment[1]
			end
			assert.is_true(first_line_text:find("Error: boom") ~= nil,
				"inline should contain first line, got: " .. first_line_text)
			assert.is_true(first_line_text:find("at foo") == nil,
				"inline should NOT contain stack frames, got: " .. first_line_text)
			assert.is_true(first_line_text:find("at bar") == nil,
				"inline should NOT contain stack frames, got: " .. first_line_text)
		end)
	end)

	describe("handle_message routing", function()
		it("should not error on valid consoleAPICalled JSON", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local msg = vim.json.encode({
				method = "Runtime.consoleAPICalled",
				params = {
					type = "log",
					args = { { type = "string", value = "test" } },
					stackTrace = {
						callFrames = {
							{ url = "file:///tmp/t.js", lineNumber = 0 },
						},
					},
				},
			})

			local ok = pcall(protocol.handle_message, session, msg)
			assert.is_true(ok, "Should not error on valid message")
		end)

		it("should not error on invalid JSON", function()
			setup()

			local session = { bufnr = 1, filepath = "/tmp/t.js" }
			local ok = pcall(protocol.handle_message, session, "not json{{{")
			assert.is_true(ok, "Should not error on invalid JSON")
		end)
	end)
end)