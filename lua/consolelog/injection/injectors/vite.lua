local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local constants = require("consolelog.core.constants")

function M.detect(project_root)
  local package_json = project_root .. "/package.json"
  if vim.fn.filereadable(package_json) == 1 then
    local content = table.concat(vim.fn.readfile(package_json), "\n")
    return content:match('"vite"') ~= nil
  end
  return false
end

local function detect_framework_in_vite(project_root)
  local package_json = project_root .. "/package.json"
  if vim.fn.filereadable(package_json) == 1 then
    local content = table.concat(vim.fn.readfile(package_json), "\n")
    if content:match('"react"') or content:match('"@vitejs/plugin%-react"') then
      return "React"
    elseif content:match('"vue"') or content:match('"@vitejs/plugin%-vue"') then
      return "Vue"
    elseif content:match('"svelte"') or content:match('"@sveltejs/kit"') or content:match('"@sveltejs/vite%-plugin%-svelte"') then
      return "Svelte"
    elseif content:match('"preact"') or content:match('"@vitejs/plugin%-preact"') or content:match('"@preact/preset%-vite"') then
      return "Preact"
    elseif content:match('"@vitejs/plugin%-lit"') or content:match('"lit"') then
      return "Lit"
    else
      return "Vanilla"
    end
  end
  return "Unknown"
end

local function find_vite_client_files(project_root)
  local vite_client_files = {
    "/node_modules/vite/dist/client/client.mjs",
    "/node_modules/vite/dist/client/env.mjs"
  }
  
  local found_files = {}
  for _, file in ipairs(vite_client_files) do
    local full_path = project_root .. file
    if vim.fn.filereadable(full_path) == 1 then
      table.insert(found_files, full_path)
    end
  end
  
  return found_files
end

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
        debug_logger.log("VITE_PATCH", string.format("Found monorepo root: %s", parent))
        break
      end
    end
    dir = parent
  end
  return search_roots
end

local function patch_vite_client_file(filepath, inject_script, project_root)
  local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX
  
  if vim.fn.filereadable(backup_path) == 1 then
    local success = vim.fn.writefile(vim.fn.readfile(backup_path, "b"), filepath, "b")
    if success ~= 0 then
      debug_logger.log("VITE_PATCH", string.format("Failed to restore from backup: %s", backup_path))
      return false
    end
    debug_logger.log("VITE_PATCH", string.format("Restored from backup before patching: %s", filepath))
  else
    local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
    if success ~= 0 then
      debug_logger.log("VITE_PATCH", string.format("Failed to create backup: %s", backup_path))
      return false
    end
    debug_logger.log("VITE_PATCH", string.format("Created backup: %s", backup_path))
  end
  
  local content = table.concat(vim.fn.readfile(filepath), "\n")
  content = inject_script .. "\n" .. content

  local success = vim.fn.writefile(vim.split(content, "\n"), filepath)
  if success ~= 0 then
    debug_logger.log("VITE_PATCH", string.format("Failed to write patched file: %s", filepath))
    return false
  end
  
  debug_logger.log("VITE_PATCH", string.format("Patched %s", filepath))
  return true
end

function M.is_patched(project_root)
  local vite_client_files = find_vite_client_files(project_root)
  for _, filepath in ipairs(vite_client_files) do
    local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX
    if vim.fn.filereadable(backup_path) == 1 then
      return true
    end
  end
  return false
end

function M.patch(project_root, ws_port)
  debug_logger.log("VITE_PATCH", string.format("Patching Vite for port %d", ws_port))
  
  local project_id = vim.fn.fnamemodify(project_root, ":t")
  local framework = detect_framework_in_vite(project_root)
  debug_logger.log("VITE_PATCH", string.format("Detected Vite %s project", framework))
  
  local current_file = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(current_file, ":p"):match("(.*[/\\\\]consolelog%.nvim[/\\\\])")
  if not plugin_dir then
    plugin_dir = vim.fn.fnamemodify(current_file, ":p:h:h:h:h:h")
  end
  
  local inject_script_path = plugin_dir .. "js/inject-client.js"
  local sourcemap_script_path = plugin_dir .. "js/sourcemap-resolver.js"
  
  if vim.fn.filereadable(inject_script_path) ~= 1 then
    debug_logger.log("VITE_PATCH", "ERROR: inject-client.js not found")
    return false
  end
  
  local inject_content = table.concat(vim.fn.readfile(inject_script_path), "\n")
  
  local sourcemap_content = ""
  if vim.fn.filereadable(sourcemap_script_path) == 1 then
    sourcemap_content = table.concat(vim.fn.readfile(sourcemap_script_path), "\n")
    debug_logger.log("VITE_PATCH", "Including source map resolver")
  end
  
  local inject_script = string.format([[
%s
  window.__CONSOLELOG_WS_PORT = %d;
  window.__CONSOLELOG_PROJECT_ID = '%s';
  window.__CONSOLELOG_FRAMEWORK = '%s';
  window.__CONSOLELOG_DEBUG = true;
  %s
  %s
}
]], constants.INJECTION.BROWSER_GUARD, ws_port, project_id, framework, sourcemap_content, inject_content)

  local search_roots = find_search_roots(project_root)
  local patched_count = 0
  local failed_count = 0
  
  for _, root in ipairs(search_roots) do
    local vite_client_files = find_vite_client_files(root)
    for _, filepath in ipairs(vite_client_files) do
      if patch_vite_client_file(filepath, inject_script, project_root) then
        patched_count = patched_count + 1
      else
        failed_count = failed_count + 1
      end
    end
  end

  if patched_count > 0 then
    debug_logger.log("VITE_PATCH", string.format("Successfully patched %d file(s)", patched_count))
    vim.notify(string.format("ConsoleLog: Vite %s project patched (%d files). Restart dev server.", framework, patched_count), vim.log.levels.INFO)
  else
    debug_logger.log("VITE_PATCH", "No Vite client files found to patch")
    vim.notify("ConsoleLog: No Vite client files found", vim.log.levels.ERROR)
  end

  return patched_count > 0
end

function M.unpatch(project_root)
  debug_logger.log("VITE_PATCH", "Unpatching Vite installation")
  
  local search_roots = find_search_roots(project_root)
  local unpatched_count = 0
  
  for _, root in ipairs(search_roots) do
    local vite_client_files = find_vite_client_files(root)
    for _, filepath in ipairs(vite_client_files) do
      local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX
      
      if vim.fn.filereadable(backup_path) == 1 then
        local success = vim.fn.writefile(vim.fn.readfile(backup_path, "b"), filepath, "b")
        if success == 0 then
          unpatched_count = unpatched_count + 1
          debug_logger.log("VITE_PATCH", string.format("Restored from backup: %s", filepath))
          
          vim.fn.delete(backup_path)
          debug_logger.log("VITE_PATCH", string.format("Deleted backup: %s", backup_path))
        else
          debug_logger.log("VITE_PATCH", string.format("Failed to restore from backup: %s", filepath))
        end
      else
        debug_logger.log("VITE_PATCH", string.format("No backup found for: %s", filepath))
      end
    end
  end
  


  if unpatched_count > 0 then
    debug_logger.log("VITE_PATCH", string.format("Successfully unpatched %d Vite file(s)", unpatched_count))
  else
    debug_logger.log("VITE_PATCH", "No Vite patches found to remove")
  end
end

return M