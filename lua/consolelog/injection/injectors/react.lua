local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local constants = require("consolelog.core.constants")

local REACT_FILES = {
  "/node_modules/react-dom/index.js",
  "/node_modules/react-dom/client.js",
  "/node_modules/react-scripts/config/webpack.config.js",
  "/node_modules/@vitejs/plugin-react/dist/index.js",
}

local function find_search_roots(project_root)
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
        debug_logger.log("REACT_PATCH", string.format("Found monorepo root: %s", parent))
        break
      end
    end
    dir = parent
  end
  return search_roots
end

function M.detect(project_root)
  local package_json = project_root .. "/package.json"
  if vim.fn.filereadable(package_json) == 1 then
    local content = table.concat(vim.fn.readfile(package_json), "\n")
    return content:match('"react"') ~= nil and 
           not content:match('"react%-native"') and
           not content:match('"next"') and 
           not content:match('"vite"') and 
           not content:match('"@vitejs"')
  end
  return false
end

function M.is_patched(project_root)
  local search_roots = find_search_roots(project_root)
  local patched_files = 0

  for _, file in ipairs(REACT_FILES) do
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if vim.fn.filereadable(filepath) == 1 then
        local content = table.concat(vim.fn.readfile(filepath), "\n")
        if content:find("window.__CONSOLELOG_WS_PORT", 1, true) then
          patched_files = patched_files + 1
          debug_logger.log("REACT_PATCH", string.format("Found patched file: %s", filepath))
        end
        break
      end
    end
  end

  return patched_files > 0, patched_files
end

function M.patch(project_root, ws_port)
  debug_logger.log("REACT_PATCH", string.format("Patching React for port %d", ws_port))

  local search_roots = find_search_roots(project_root)
  local patched = false
  local project_id = vim.fn.fnamemodify(project_root, ":t")

  local current_file = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(current_file, ":p"):match("(.*[/\\]consolelog%.nvim[/\\])")
  if not plugin_dir then
    plugin_dir = vim.fn.fnamemodify(current_file, ":p:h:h:h:h:h")
    debug_logger.log("REACT_PATCH", string.format("Using fallback plugin directory: %s", plugin_dir))

    if not plugin_dir or plugin_dir == "" then
      debug_logger.log("REACT_PATCH", "ERROR: Could not determine plugin directory")
      vim.notify("ConsoleLog: Failed to determine plugin directory", vim.log.levels.ERROR)
      return false
    end
  end

  local inject_script_path = plugin_dir .. "js/inject-client.js"
  local sourcemap_script_path = plugin_dir .. "js/sourcemap-resolver.js"

  if vim.fn.filereadable(inject_script_path) ~= 1 then
    debug_logger.log("REACT_PATCH", "ERROR: inject-client.js not found at: " .. inject_script_path)
    vim.notify("ConsoleLog: Failed to patch - inject script not found", vim.log.levels.ERROR)
    return false
  end

  local inject_content = table.concat(vim.fn.readfile(inject_script_path), "\n")

  local sourcemap_content = ""
  if vim.fn.filereadable(sourcemap_script_path) == 1 then
    sourcemap_content = table.concat(vim.fn.readfile(sourcemap_script_path), "\n")
    debug_logger.log("REACT_PATCH", "Including source map resolver")
  else
    debug_logger.log("REACT_PATCH", "Source map resolver not found, skipping")
  end

  local inject_script = constants.INJECTION.START_MARKER .. "\n" .. string.format([[
%s
  window.__CONSOLELOG_WS_PORT = %d;
  window.__CONSOLELOG_PROJECT_ID = '%s';
  window.__CONSOLELOG_FRAMEWORK = 'React';
  window.__CONSOLELOG_DEBUG = true;
  %s
  %s
}
]], constants.INJECTION.BROWSER_GUARD, ws_port, project_id, sourcemap_content, inject_content) .. constants.INJECTION.END_MARKER

  for _, file in ipairs(REACT_FILES) do
    local found_file = false
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if vim.fn.filereadable(filepath) == 1 then
        found_file = true
        local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX

        if vim.fn.filereadable(backup_path) ~= 1 then
          local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
          if success == 0 then
            debug_logger.log("REACT_PATCH", string.format("Created backup: %s", backup_path))
          else
            debug_logger.log("REACT_PATCH", string.format("Failed to create backup: %s", backup_path))
            break
          end
        else
          debug_logger.log("REACT_PATCH", string.format("Backup exists: %s", backup_path))
        end

        local content = table.concat(vim.fn.readfile(filepath), "\n")
        if not content:find("window.__CONSOLELOG_WS_PORT", 1, true) then
          local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
          if success ~= 0 then
            debug_logger.log("REACT_PATCH", string.format("Failed to refresh backup: %s", backup_path))
            break
          end
        end
        if not content:find(constants.INJECTION.START_MARKER, 1, true)
            and content:find("window.__CONSOLELOG_WS_PORT", 1, true) then
          content = table.concat(vim.fn.readfile(backup_path), "\n")
        end

        if content:find(constants.INJECTION.START_MARKER, 1, true) then
          content = content:gsub(constants.INJECTION.BLOCK_PATTERN, "", 1)
          debug_logger.log("REACT_PATCH", string.format("Removed old injection from %s", filepath))
        end

        local pattern = "if %(typeof window !== 'undefined'%)"
        local replacement = inject_script .. "\n" .. pattern

        if content:match(pattern) then
          content = content:gsub(pattern, replacement, 1)
        else
          if content:match("^'use strict'") then
            content = content:gsub("('use strict'.-\n)", "%1\n" .. inject_script .. "\n")
          else
            content = inject_script .. "\n" .. content
          end
        end

        vim.fn.writefile(vim.split(content, "\n"), filepath)
        patched = true
        debug_logger.log("REACT_PATCH", string.format("Patched %s in %s", file, root))
        break
      end
    end
    if not found_file then
      debug_logger.log("REACT_PATCH", string.format("File not found in any search root: %s", file))
    end
  end

  if patched then
    vim.notify("ConsoleLog: React patched. Restart dev server.", vim.log.levels.INFO)
  else
    debug_logger.log("REACT_PATCH", "No React files found to patch")
    vim.notify("ConsoleLog: No React files found to patch", vim.log.levels.WARN)
  end

  return patched
end

function M.unpatch(project_root)
  debug_logger.log("REACT_PATCH", "Removing React patches")

  local search_roots = find_search_roots(project_root)
  local unpatched_count = 0

  for _, file in ipairs(REACT_FILES) do
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX

      if vim.fn.filereadable(backup_path) == 1 then
        local has_injection = vim.fn.filereadable(filepath) ~= 1
            or table.concat(vim.fn.readfile(filepath), "\n"):find("window.__CONSOLELOG_WS_PORT", 1, true)
        if not has_injection then
          vim.fn.delete(backup_path)
          break
        end
        local success = vim.fn.writefile(vim.fn.readfile(backup_path, "b"), filepath, "b")
        if success == 0 then
          unpatched_count = unpatched_count + 1
          debug_logger.log("REACT_PATCH", string.format("Restored from backup: %s", filepath))

          vim.fn.delete(backup_path)
          debug_logger.log("REACT_PATCH", string.format("Deleted backup: %s", backup_path))
        else
          debug_logger.log("REACT_PATCH", string.format("Failed to restore from backup: %s", filepath))
        end
        break
      elseif vim.fn.filereadable(filepath) == 1 then
        local content = table.concat(vim.fn.readfile(filepath), "\n")
        local restored, removed = content:gsub(constants.INJECTION.BLOCK_PATTERN, "", 1)
        if removed > 0 and vim.fn.writefile(vim.split(restored, "\n"), filepath) == 0 then
          unpatched_count = unpatched_count + 1
        end
        break
      else
        debug_logger.log("REACT_PATCH", string.format("No backup found for: %s", filepath))
      end
    end
  end

  if unpatched_count > 0 then
    debug_logger.log("REACT_PATCH", string.format("Successfully unpatched %d React file(s)", unpatched_count))
  else
    debug_logger.log("REACT_PATCH", "No React patches found to remove")
  end
end

return M
