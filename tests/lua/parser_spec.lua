local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"
local parser = require('consolelog.processing.parser')
local formatter = require('consolelog.processing.formatter')

describe("Parser Module", function()
  local mock_config = {
    display = {
      prefix = " ▸ ",
      max_width = 80,
      truncate_marker = "..."
    },
    
  }
  
  describe("Value type detection", function()
    it("should detect arrays", function()
      local test_cases = {
        '[]',
        '[1, 2, 3]',
        '["a", "b"]',
        '[{"key": "value"}]'
      }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "array", "Should detect array: " .. value)
      end
    end)
    
    it("should detect objects", function()
      local test_cases = {
        '{}',
        '{"key": "value"}',
        '{"a": 1, "b": 2}',
        '{"nested": {"key": "value"}}'
      }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "object", "Should detect object: " .. value)
      end
    end)
    
    it("should detect strings", function()
      local test_cases = {
        '"hello"',
        "'world'",
        '"test string"',
        '""'
      }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "string", "Should detect string: " .. value)
      end
    end)
    
    it("should detect numbers", function()
      local test_cases = {
        '42',
        '-10',
        '3.14',
        '0',
        '-0.5'
      }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "number", "Should detect number: " .. value)
      end
    end)
    
    it("should detect booleans", function()
      assert.equals(parser.detect_value_type("true"), "boolean", "Should detect true")
      assert.equals(parser.detect_value_type("false"), "boolean", "Should detect false")
    end)
    
    it("should detect null values", function()
      local test_cases = { "null", "nil", "undefined" }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "null", "Should detect null: " .. value)
      end
    end)
    
    it("should return unknown for unrecognized types", function()
      local test_cases = {
        "random text",
        "not-a-type",
        "123abc",
        "true123"
      }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "unknown", "Should return unknown: " .. value)
      end
    end)
  end)
  
  describe("Output formatting", function()
    it("should format output with prefix", function()
      local value = "test"
      
      local formatted = formatter.format_values_for_inline({ value }, mock_config)
      assert.not_nil(formatted, "Should format output")
      assert.is_true(formatted:find(mock_config.display.prefix) ~= nil, "Should have prefix")
      assert.is_true(formatted:find("test") ~= nil, "Should have value")
    end)
    
    it("should handle JSON objects", function()
      local value = '{"key": "value", "num": 42}'
      
      local formatted = formatter.format_values_for_inline({ value }, mock_config)
      assert.not_nil(formatted, "Should format JSON object")
    end)
    
    it("should truncate long values", function()
      local long_value = string.rep("a", 200)
      
      local formatted = formatter.format_values_for_inline({ long_value }, mock_config)
      assert.is_true(#formatted < #long_value + 20, "Should truncate long value")
    end)
    
    it("should not truncate when max_width is unset", function()
      local unlimited_config = { display = { prefix = "", max_width = 0 } }

      local formatted = formatter.format_values_for_inline({ "42" }, unlimited_config)
      assert.equals(formatted, "42", "max_width 0 means no configured limit, not a zero-width limit")
    end)

    it("should handle arrays with preview", function()
      local value = '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]'
      
      local formatted = formatter.format_values_for_inline({ value }, mock_config)
      assert.not_nil(formatted, "Should format array")
      assert.is_true(formatted:find("%[") ~= nil, "Should have opening bracket")
      assert.is_true(formatted:find("%]") ~= nil, "Should have closing bracket")
    end)
  end)
  
  describe("Error handling", function()
    it("should handle very large objects", function()
      local large_obj = '{"data": "' .. string.rep("x", 500) .. '"}'
      
      local formatted = formatter.format_values_for_inline({ large_obj }, mock_config)
      assert.not_nil(formatted, "Should format large object")
      assert.is_true(#formatted <= mock_config.display.max_width + 50, "Should respect max width")
    end)
    
    it("should handle special characters in strings", function()
      local test_cases = {
        '"string with \\"quotes\\""',
        '"string with \\n newline"',
        '"string with \\t tab"',
        '"string with \\\\ backslash"',
        '"string with / forward slash"'
      }
      
      for _, value in ipairs(test_cases) do
        local type = parser.detect_value_type(value)
        assert.equals(type, "string", "Should detect as string: " .. value)
      end
    end)
    
    it("should handle deeply nested objects", function()
      local nested = '{"a":{"b":{"c":{"d":{"e":{"f":{"g":"deep"}}}}}}}'
      
      local type = parser.detect_value_type(nested)
      assert.equals(type, "object", "Should detect deeply nested as object")
      
      local formatted = formatter.format_values_for_inline({ nested }, mock_config)
      assert.not_nil(formatted, "Should format deeply nested object")
    end)
    
    it("should handle extremely long arrays", function()
      local items = {}
      for i = 1, 100 do
        table.insert(items, tostring(i))
      end
      local long_array = "[" .. table.concat(items, ",") .. "]"
      
      local formatted = formatter.format_values_for_inline({ long_array }, mock_config)
      assert.not_nil(formatted, "Should format long array")
      assert.is_true(#formatted <= mock_config.display.max_width + 50, "Should truncate long array")
    end)
    
    it("should handle mixed type arrays", function()
      local mixed = '[1, "string", true, null, {"key": "value"}]'
      
      local type = parser.detect_value_type(mixed)
      assert.equals(type, "array", "Should detect mixed array")
      
      local formatted = formatter.format_values_for_inline({ mixed }, mock_config)
      assert.not_nil(formatted, "Should format mixed array")
    end)
  end)
end)