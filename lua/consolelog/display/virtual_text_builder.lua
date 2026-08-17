local M = {}

local formatter = require("consolelog.processing.formatter")
local constants = require("consolelog.core.constants")
local utils = require("consolelog.core.utils")

function M.get_highlight_groups(console_type)
  local highlight_map = {
    log = {
      main = "ConsoleLogOutput",
      left = "ConsoleLogOutputLeft",
      right = "ConsoleLogOutputRight",
    },
    error = {
      main = "ConsoleLogError",
      left = "ConsoleLogErrorLeft",
      right = "ConsoleLogErrorRight",
    },
    warn = {
      main = "ConsoleLogWarning",
      left = "ConsoleLogWarningLeft",
      right = "ConsoleLogWarningRight",
    },
    info = {
      main = "ConsoleLogInfo",
      left = "ConsoleLogInfoLeft",
      right = "ConsoleLogInfoRight",
    },
    debug = {
      main = "ConsoleLogDebug",
      left = "ConsoleLogDebugLeft",
      right = "ConsoleLogDebugRight",
    },
  }

  return highlight_map[console_type] or highlight_map.log
end

function M.collect_inline_values(output, config)
  -- Always use `value` for inline virtual text.  `raw_value` carries the
  -- full representation (parsed table or multiline exception stack) that the
  -- float inspector should show; forcing it inline would flatten exception
  -- stacks into a single display line.
  local values = {}
  for _, entry in ipairs(utils.ordered_output_entries(output, config)) do
    table.insert(values, entry.value)
  end

  return values
end

function M.format_value_for_display(output, config)
  return formatter.format_values_for_inline(
    M.collect_inline_values(output, config),
    config,
    constants.DISPLAY.MAX_INLINE_VALUES
  )
end

function M.add_execution_count(text, count, config)
  if not config.history or not config.history.enabled then
    return text
  end

  if not config.history.show_indicator then
    return text
  end

  if count and count > 1 then
    return text .. string.format(" [×%d]", count)
  end

  return text
end

function M.split_into_lines(text, max_width)
  if not max_width or max_width <= 0 then
    return { text }
  end

  local lines = {}
  local current_line = ""
  
  for word in text:gmatch("%S+") do
    local test_line = current_line == "" and word or (current_line .. " " .. word)
    
    if vim.fn.strdisplaywidth(test_line) <= max_width then
      current_line = test_line
    else
      if current_line ~= "" then
        table.insert(lines, current_line)
      end
      current_line = word
    end
  end
  
  if current_line ~= "" then
    table.insert(lines, current_line)
  end

  return #lines > 0 and lines or { text }
end

function M.build_virtual_text(output, config)
  local console_type = output.console_type or "log"
  local highlights = M.get_highlight_groups(console_type)
  
  local formatted = M.format_value_for_display(output, config)
  formatted = M.add_execution_count(formatted, output.execution_count, config)

  local max_width = config.display.max_width or 0
  
  if max_width > 0 and vim.fn.strdisplaywidth(formatted) > max_width then
    local lines = M.split_into_lines(formatted, max_width)
    local virt_lines = {}
    
    for i, line in ipairs(lines) do
      if i == 1 then
        table.insert(virt_lines, {
          { "", highlights.left },
          { " " .. line .. " ", highlights.main },
          { "", highlights.right }
        })
      else
        table.insert(virt_lines, {
          { "", highlights.left },
          { " " .. line .. " ", highlights.main },
          { "", highlights.right }
        })
      end
    end
    
    return virt_lines, true
  else
    return { {
      { "", highlights.left },
      { " " .. formatted .. " ", highlights.main },
      { "", highlights.right }
    } }, false
  end
end

function M.get_highlight_for_type(console_type, config)
  local highlights = {
    log = "ConsoleLogOutput",
    error = "ConsoleLogError",
    warn = "ConsoleLogWarning",
    info = "ConsoleLogInfo",
    debug = "ConsoleLogDebug",
  }

  return highlights[console_type] or config.display.highlight
end

return M
