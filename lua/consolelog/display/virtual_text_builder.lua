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
    explain = {
      main = "ConsoleLogExplain",
      left = "ConsoleLogExplainLeft",
      right = "ConsoleLogExplainRight",
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

function M.build_chunks(text, highlights, max_width)
  if max_width > 0 and vim.fn.strdisplaywidth(text) > max_width then
    local lines = M.split_into_lines(text, max_width)
    local virt_lines = {}

    for _, line in ipairs(lines) do
      table.insert(virt_lines, {
        { "", highlights.left },
        { " " .. line .. " ", highlights.main },
        { "", highlights.right }
      })
    end

    return virt_lines, true
  end

  return { {
    { "", highlights.left },
    { " " .. text .. " ", highlights.main },
    { "", highlights.right }
  } }, false
end

function M.build_virtual_text(output, config)
  local console_type = output.console_type or "log"
  local highlights = M.get_highlight_groups(console_type)

  local formatted = M.format_value_for_display(output, config)
  formatted = M.add_execution_count(formatted, output.execution_count, config)

  return M.build_chunks(formatted, highlights, config.display.max_width or 0)
end

function M.build_annotation_virtual_text(text, config)
  local explain = config.explain or {}
  local highlights = M.get_highlight_groups("explain")

  local prefixed = (explain.prefix or constants.EXPLAIN.DEFAULT_PREFIX) .. text
  local max_width = explain.max_width or 0

  return M.build_chunks(prefixed, highlights, max_width)
end

return M
