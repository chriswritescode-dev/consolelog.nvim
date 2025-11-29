local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local base_injector = require("consolelog.injection.injectors.base_injector")

function M.detect(project_root)
  local package_json = project_root .. "/package.json"
  if vim.fn.filereadable(package_json) == 1 then
    local content = table.concat(vim.fn.readfile(package_json), "\n")
    return content:match('"vite"') ~= nil
  end
  return false
end

local function detect_framework_in_vite(project_root)
  local framework_detector = require("consolelog.injection.framework_detector")
  return framework_detector.detect_vite_underlying_framework(project_root)
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

local function patch_vite_client_file(filepath, inject_script)
  if not base_injector.create_backup(filepath) then
    return false
  end
  
  local content = table.concat(vim.fn.readfile(filepath), "\n")
  content = inject_script .. "\n" .. content

  vim.fn.writefile(vim.split(content, "\n"), filepath)
  debug_logger.log("VITE_PATCH", string.format("Patched %s", filepath))
  return true
end

function M.is_patched(project_root)
  local vite_client_files = find_vite_client_files(project_root)
  for _, filepath in ipairs(vite_client_files) do
    if base_injector.is_file_patched(filepath) then
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
  
  local plugin_dir = base_injector.get_plugin_directory()
  if not plugin_dir then
    return false
  end
  
  local inject_content, sourcemap_content = base_injector.load_injection_scripts(plugin_dir)
  if not inject_content then
    return false
  end
  
  local inject_script = base_injector.generate_injection_script(
    ws_port, project_id, framework, true, sourcemap_content, inject_content
  )

  local search_roots = base_injector.find_search_roots(project_root)
  local patched_count = 0
  local failed_count = 0
  
  for _, root in ipairs(search_roots) do
    local vite_client_files = find_vite_client_files(root)
    for _, filepath in ipairs(vite_client_files) do
      if patch_vite_client_file(filepath, inject_script) then
        patched_count = patched_count + 1
      else
        failed_count = failed_count + 1
      end
    end
  end

  if patched_count > 0 then
    debug_logger.log("VITE_PATCH", string.format("Successfully patched %d file(s)", patched_count))
    base_injector.notify_success("Vite " .. framework, ws_port, string.format("(%d files)", patched_count))
  else
    debug_logger.log("VITE_PATCH", "No Vite client files found to patch")
    base_injector.notify_error("Vite", "No Vite client files found")
  end

  return patched_count > 0
end

function M.unpatch(project_root)
  debug_logger.log("VITE_PATCH", "Unpatching Vite installation")
  
  local search_roots = base_injector.find_search_roots(project_root)
  local unpatched_count = 0
  
  for _, root in ipairs(search_roots) do
    local vite_client_files = find_vite_client_files(root)
    for _, filepath in ipairs(vite_client_files) do
      if base_injector.restore_from_backup(filepath) then
        unpatched_count = unpatched_count + 1
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