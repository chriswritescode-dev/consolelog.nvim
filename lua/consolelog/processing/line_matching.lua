local M = {}

M.state = {
  file_mappings = {},
  last_execution_id = 0
}

local debug_logger = require("consolelog.core.debug_logger")

function M.get_next_execution_id()
  M.state.last_execution_id = M.state.last_execution_id + 1
  return M.state.last_execution_id
end

function M.match_by_file_and_command(msg, project_root)
  local filename = msg.location and msg.location.file or "unknown"
  local line_num = msg.location and msg.location.line or "none"

  debug_logger.log("NEW_LINE_MATCHING", string.format("=== MATCHING MESSAGE === file=%s, method=%s, line=%s, project_root=%s",
    filename, msg.method or "log", line_num, project_root or "nil"))

  local bufnr = M.find_buffer_by_filename(filename, project_root)
  if not bufnr then
    local error_msg = "No buffer found for file: " .. filename
    debug_logger.log("NEW_LINE_MATCHING", error_msg)

    if debug_logger.is_enabled() then
      local buffer_list = {}
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local buf_name = vim.api.nvim_buf_get_name(buf)
          table.insert(buffer_list, string.format("Buffer %d: %s", buf, buf_name))
        end
      end
      debug_logger.log("NEW_LINE_MATCHING", "Available buffers:\n" .. table.concat(buffer_list, "\n"))
    end

    return nil, nil, "no_buffer_for_file"
  end

  debug_logger.log("NEW_LINE_MATCHING", string.format("Found buffer %d for file %s", bufnr, msg.location.file))

  if msg.location and msg.location.line then
    local resolved_line = msg.location.line
    local column = msg.location.column or 0
    local method = msg.method or "log"

    local source_mapped = msg.location.sourceMapped or false
    
    debug_logger.log("NEW_LINE_MATCHING", string.format("Raw line: %d, column: %d, method: %s, framework: %s, sourceMapped: %s", 
      resolved_line, column, method, msg.framework or "nil", tostring(source_mapped)))

    if not source_mapped and msg.framework and (msg.framework:match("React") or msg.framework:match("Vue") or 
                          msg.framework:match("Svelte") or msg.framework:match("Preact")) then
      local adjustment = 0
      
      if column < 13 then
        if method == "error" then
          adjustment = 0
        else
          adjustment = -1
        end
      else
        adjustment = 1
      end
      
      resolved_line = math.max(1, resolved_line + adjustment)
      debug_logger.log("NEW_LINE_MATCHING", string.format("Applied Vite adjustment %+d: %d -> %d (column: %d, method: %s)", 
        adjustment, msg.location.line, resolved_line, column, method))
    elseif source_mapped then
      debug_logger.log("NEW_LINE_MATCHING", "Skipping adjustment - sourcemap already resolved line number")
    end

    debug_logger.log("NEW_LINE_MATCHING", string.format("Using line number from location: %d", resolved_line))

    local buf_lines = vim.api.nvim_buf_line_count(bufnr)
    if resolved_line > 0 and resolved_line <= buf_lines then
      debug_logger.log("NEW_LINE_MATCHING", string.format("Matched to line %d", resolved_line))
      return bufnr, resolved_line, "exact_line_match"
    else
      debug_logger.log("NEW_LINE_MATCHING", string.format("Line %d out of range (buffer has %d lines)", resolved_line, buf_lines))
    end
  end

  debug_logger.log("NEW_LINE_MATCHING", "No line number provided")
  return nil, nil, "no_line_number"
end

function M.extract_relative_path(full_path, project_root)
  if not project_root or project_root == "" then
    return vim.fn.fnamemodify(full_path, ":t")
  end

  local normalized_root = project_root:gsub("/$", "")
  local normalized_path = full_path:gsub("/$", "")

  if normalized_path:sub(1, #normalized_root) == normalized_root then
    local relative = normalized_path:sub(#normalized_root + 2)
    return relative
  end

  return vim.fn.fnamemodify(full_path, ":t")
end

function M.find_buffer_by_filename(filename, project_root)
  if not filename or filename == "" or filename == "unknown" then
    debug_logger.log("NEW_LINE_MATCHING", "Invalid filename: " .. tostring(filename))
    return nil
  end

  local cache_key = filename .. "|" .. (project_root or "")
  if M.state.file_mappings[cache_key] then
    local bufnr = M.state.file_mappings[cache_key]
    if vim.api.nvim_buf_is_valid(bufnr) then
      debug_logger.log("NEW_LINE_MATCHING", string.format("Found cached mapping: %s -> buffer %d", filename, bufnr))
      return bufnr
    else
      M.state.file_mappings[cache_key] = nil
      debug_logger.log("NEW_LINE_MATCHING", "Removed invalid mapping for: " .. filename)
    end
  end

  local best_match = nil
  local best_score = 0
  local message_basename = vim.fn.fnamemodify(filename, ":t")
  local message_has_path = filename:find("/") ~= nil

  debug_logger.log("NEW_LINE_MATCHING", string.format("Searching for filename: '%s' (basename: '%s', has_path: %s) in project: '%s'",
    filename, message_basename, tostring(message_has_path), project_root or "any"))

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local bufName = vim.api.nvim_buf_get_name(buf)
      if bufName and bufName ~= "" then
        if project_root then
          local is_in_project = bufName:find(project_root, 1, true) == 1
          if not is_in_project then
            debug_logger.log("NEW_LINE_MATCHING", string.format("Buffer %d (%s) not in project %s - skipping", buf, bufName, project_root))
            goto continue
          end
        end

        local bufBasename = vim.fn.fnamemodify(bufName, ":t")
        local bufRelPath = M.extract_relative_path(bufName, project_root)

        debug_logger.log("NEW_LINE_MATCHING", string.format("Buffer %d: basename='%s', relPath='%s'", buf, bufBasename, bufRelPath))

        local score = 0

        if bufRelPath == filename then
          score = 1000
          debug_logger.log("NEW_LINE_MATCHING", string.format("Exact relative path match: '%s' == '%s'", bufRelPath, filename))
        elseif message_has_path and bufRelPath:match(vim.pesc(filename) .. "$") then
          score = 500
          debug_logger.log("NEW_LINE_MATCHING", string.format("Path suffix match: '%s' ends with '%s'", bufRelPath, filename))
        elseif bufBasename == message_basename then
          score = 100
          debug_logger.log("NEW_LINE_MATCHING", string.format("Exact basename match: '%s' == '%s'", bufBasename, message_basename))
        elseif bufBasename:find(message_basename, 1, true) or message_basename:find(bufBasename, 1, true) then
          score = 50
          debug_logger.log("NEW_LINE_MATCHING", string.format("Partial basename match: '%s' ~= '%s'", bufBasename, message_basename))
        elseif bufRelPath:find(message_basename, 1, true) then
          score = 25
          debug_logger.log("NEW_LINE_MATCHING", string.format("Path contains basename: '%s' contains '%s'", bufRelPath, message_basename))
        end

        if score > best_score then
          best_score = score
          best_match = buf
          debug_logger.log("NEW_LINE_MATCHING", string.format("New best match: buffer %d, score %d", buf, score))
        end
        ::continue::
      end
    end
  end

  if best_match and best_score >= 25 then
    M.state.file_mappings[cache_key] = best_match
    debug_logger.log("NEW_LINE_MATCHING", string.format("Selected best match: %s -> buffer %d (score: %d)", filename, best_match, best_score))
    return best_match
  end

  debug_logger.log("NEW_LINE_MATCHING", "No buffer found for filename: " .. filename)
  return nil
end

function M.find_console_lines(bufnr, method)
  method = method or "log"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local consoleLines = {}
  local searchPattern = "console%." .. method

  for i, lineText in ipairs(lines) do
    if lineText:match(searchPattern) then
      table.insert(consoleLines, i)
    end
  end

  debug_logger.log("NEW_LINE_MATCHING", string.format("Found %d console.%s lines in buffer %d", #consoleLines, method, bufnr))
  return consoleLines
end

function M.reset()
  M.state.file_mappings = {}
  M.state.last_execution_id = 0
  debug_logger.log("NEW_LINE_MATCHING", "Reset line matching state")
end

function M.get_state_info()
  return {
    file_mappings_count = vim.tbl_count(M.state.file_mappings),
    last_execution_id = M.state.last_execution_id
  }
end

return M
