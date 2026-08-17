local M = {}

local INITIAL_UID = 1
local MAX_UID = 2 ^ 32 - 1

local state = {
  uid_counter = INITIAL_UID,
}

local function generate_uid()
  state.uid_counter = (state.uid_counter % MAX_UID) + 1
  return state.uid_counter
end

function M.create_single_extmark(buf, namespace, line, virt_text, win_col, priority, pos)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local extmark_opts = {
    id = generate_uid(),
    virt_text = virt_text,
    virt_text_pos = pos or "eol",
    virt_text_win_col = win_col,
    priority = priority,
    strict = false,
    right_gravity = true,
  }

  local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, buf, namespace, line, 0, extmark_opts)
  return ok and mark_id or nil
end

function M.create_multiline_extmark(buf, namespace, curline, virt_lines, priority)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if not virt_lines or #virt_lines == 0 then
    return
  end

  local first_line = virt_lines[1]
  local remaining_lines = {}
  for i = 2, #virt_lines do
    table.insert(remaining_lines, virt_lines[i])
  end

  local extmark_opts = {
    id = generate_uid(),
    virt_text_pos = "eol",
    virt_text = first_line,
    priority = priority,
    strict = false,
    right_gravity = true,
  }

  if #remaining_lines > 0 then
    extmark_opts.virt_lines = remaining_lines
  end

  local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, buf, namespace, curline, 0, extmark_opts)
  return ok and mark_id or nil
end

function M.write_virt_lines(buf, namespace, line, virt_lines, is_multiline, priority, pos)
  if not virt_lines or #virt_lines == 0 then
    return
  end

  if is_multiline and #virt_lines > 1 then
    return M.create_multiline_extmark(buf, namespace, line, virt_lines, priority)
  end

  return M.create_single_extmark(buf, namespace, line, virt_lines[1], nil, priority, pos or "eol")
end

function M.create_overflow_extmarks(buf, namespace, params)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local curline = params.curline
  local virt_lines = params.virt_lines
  local priority = params.priority
  local buf_lines_count = params.buf_lines_count

  local existing_lines = buf_lines_count - curline
  
  for i = 1, math.min(#virt_lines, existing_lines) do
    local line_to_place = curline + i - 1
    if i == 1 then
      M.create_single_extmark(buf, namespace, line_to_place, virt_lines[i], nil, priority, "eol")
    else
      M.create_single_extmark(buf, namespace, line_to_place, virt_lines[i], 0, priority, "overlay")
    end
  end

  if #virt_lines > existing_lines then
    local overflow_lines = {}
    for i = existing_lines + 1, #virt_lines do
      table.insert(overflow_lines, virt_lines[i])
    end

    if #overflow_lines > 0 then
      local ok, _ = pcall(vim.api.nvim_buf_set_extmark, buf, namespace, buf_lines_count - 1, 0, {
        id = generate_uid(),
        virt_lines_above = false,
        virt_lines = overflow_lines,
        priority = priority,
        strict = false,
      })
      return ok
    end
  end

  return true
end

return M
