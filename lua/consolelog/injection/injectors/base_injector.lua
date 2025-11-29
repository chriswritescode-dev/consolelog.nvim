local M = {}

local debug_logger = require("consolelog.core.debug_logger")
local constants = require("consolelog.core.constants")

-- Shared utility functions for all framework injectors

-- Find search roots including monorepo detection
function M.find_search_roots(project_root)
  local search_roots = { project_root }
  local dir = project_root
  while dir ~= "/" do
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end

    local parent_package = parent .. "/package.json"
    if vim.fn.filereadable(parent_package) == 1 then
      local content = table.concat(vim.fn.readfile(parent_package), "\n")
      if content:match('"workspaces"') then
        table.insert(search_roots, parent)
        debug_logger.log("INJECTOR_UTILS", string.format("Found monorepo root: %s", parent))
        break
      end
    end
    dir = parent
  end
  return search_roots
end

-- Get plugin directory with fallback logic
function M.get_plugin_directory()
  local current_file = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = current_file:match("(.*[/\\]consolelog%.nvim[/\\])")
  
  if not plugin_dir then
    plugin_dir = vim.fn.fnamemodify(current_file, ":p:h:h:h:h:h")
    debug_logger.log("INJECTOR_UTILS", string.format("Using fallback plugin directory: %s", plugin_dir))
    
    if not plugin_dir or plugin_dir == "" then
      debug_logger.log("INJECTOR_UTILS", "ERROR: Could not determine plugin directory")
      vim.notify("ConsoleLog: Failed to determine plugin directory", vim.log.levels.ERROR)
      return nil
    end
  end
  
  return plugin_dir
end

-- Create backup of file with consistent error handling
function M.create_backup(filepath)
  local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX
  
  if vim.fn.filereadable(backup_path) == 1 then
    debug_logger.log("INJECTOR_UTILS", string.format("Backup exists: %s", backup_path))
    return true
  end
  
  local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
  if success == 0 then
    debug_logger.log("INJECTOR_UTILS", string.format("Created backup: %s", backup_path))
    return true
  else
    debug_logger.log("INJECTOR_UTILS", string.format("Failed to create backup: %s", backup_path))
    return false
  end
end

-- Restore file from backup with consistent error handling
function M.restore_from_backup(filepath)
  local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX
  
  if vim.fn.filereadable(backup_path) == 1 then
    local success = vim.fn.writefile(vim.fn.readfile(backup_path, "b"), filepath, "b")
    if success == 0 then
      debug_logger.log("INJECTOR_UTILS", string.format("Restored from backup: %s", filepath))
      vim.fn.delete(backup_path)
      debug_logger.log("INJECTOR_UTILS", string.format("Deleted backup: %s", backup_path))
      return true
    else
      debug_logger.log("INJECTOR_UTILS", string.format("Failed to restore from backup: %s", filepath))
      return false
    end
  else
    debug_logger.log("INJECTOR_UTILS", string.format("No backup found for: %s", filepath))
    return false
  end
end

-- Check if file is patched by looking for backup and injection markers
function M.is_file_patched(filepath, check_content)
  if vim.fn.filereadable(filepath) ~= 1 then
    return false
  end
  
  local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX
  local has_backup = vim.fn.filereadable(backup_path) == 1
  
  if check_content then
    local content = table.concat(vim.fn.readfile(filepath), "\n")
    local has_markers = content:match("window%.__CONSOLELOG_WS_PORT") and
                       content:match("ConsoleLog%.nvim auto%-injection")
    return has_backup or has_markers
  end
  
  return has_backup
end

-- Generate injection script template with framework-specific parameters
function M.generate_injection_script(ws_port, project_id, framework, debug_enabled, sourcemap_content, inject_content)
  debug_enabled = debug_enabled ~= false -- default to true
  framework = framework or "unknown"
  
  return string.format([[
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = %d;
  window.__CONSOLELOG_PROJECT_ID = '%s';
  window.__CONSOLELOG_FRAMEWORK = '%s';
  window.__CONSOLELOG_DEBUG = %s;
  %s
  %s
}
]], ws_port, project_id, framework, tostring(debug_enabled), sourcemap_content, inject_content)
end

-- Load injection scripts with consistent error handling
function M.load_injection_scripts(plugin_dir)
  local inject_script_path = plugin_dir .. "js/inject-client.js"
  local sourcemap_script_path = plugin_dir .. "js/sourcemap-resolver.js"
  
  if vim.fn.filereadable(inject_script_path) ~= 1 then
    debug_logger.log("INJECTOR_UTILS", "ERROR: inject-client.js not found at: " .. inject_script_path)
    vim.notify("ConsoleLog: Failed to patch - inject script not found", vim.log.levels.ERROR)
    return nil, nil
  end
  
  local inject_content = table.concat(vim.fn.readfile(inject_script_path), "\n")
  
  local sourcemap_content = ""
  if vim.fn.filereadable(sourcemap_script_path) == 1 then
    sourcemap_content = table.concat(vim.fn.readfile(sourcemap_script_path), "\n")
    debug_logger.log("INJECTOR_UTILS", "Including source map resolver")
  else
    debug_logger.log("INJECTOR_UTILS", "Source map resolver not found, skipping")
  end
  
  return inject_content, sourcemap_content
end

-- Standardized patch file function with common patterns
function M.patch_file_with_injection(filepath, injection_script, patterns)
  patterns = patterns or {}
  
  if not M.create_backup(filepath) then
    return false
  end
  
  local content = table.concat(vim.fn.readfile(filepath), "\n")
  
  -- Remove old injection if present
  if content:match("ConsoleLog%.nvim auto%-injection") then
    local start_marker = "// ConsoleLog%.nvim auto%-injection"
    local end_marker = "\n}\n"
    local pattern = start_marker .. ".-" .. end_marker
    content = content:gsub(pattern, "", 1)
    debug_logger.log("INJECTOR_UTILS", string.format("Removed old injection from %s", filepath))
  end
  
  -- Apply injection based on patterns
  local injected = false
  
  if patterns.use_client_directive and content:match("^'use client'") then
    content = content:gsub("(\'use client'.-\n)", "%1\n" .. injection_script .. "\n")
    injected = true
  elseif patterns.use_strict_directive and content:match("^'use strict'") then
    content = content:gsub("(\'use strict'.-\n)", "%1\n" .. injection_script .. "\n")
    injected = true
  elseif patterns.window_check_pattern then
    local pattern = patterns.window_check_pattern
    local replacement = injection_script .. "\n" .. pattern
    if content:match(pattern) then
      content = content:gsub(pattern, replacement, 1)
      injected = true
    end
  end
  
  -- Fallback: prepend to file
  if not injected then
    content = injection_script .. "\n" .. content
  end
  
  vim.fn.writefile(vim.split(content, "\n"), filepath)
  debug_logger.log("INJECTOR_UTILS", string.format("Patched %s", filepath))
  return true
end

-- Standardized success notification
function M.notify_success(framework, ws_port, extra_info)
  local message = string.format("ConsoleLog: %s patched (Port %d)", framework, ws_port)
  if extra_info then
    message = message .. " - " .. extra_info
  else
    message = message .. ". Restart dev server if needed."
  end
  
  vim.notify(message, vim.log.levels.INFO)
end

-- Standardized error notification
function M.notify_error(framework, error_msg)
  local message = string.format("ConsoleLog: Failed to patch %s - %s", framework, error_msg)
  vim.notify(message, vim.log.levels.ERROR)
end

return M