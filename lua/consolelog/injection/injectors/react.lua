local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local base_injector = require("consolelog.injection.injectors.base_injector")

local REACT_FILES = {
  "/node_modules/react-dom/index.js",
  "/node_modules/react-dom/client.js",
  "/node_modules/react-scripts/config/webpack.config.js",
  "/node_modules/@vitejs/plugin-react/dist/index.js",
}

function M.detect(project_root)
  local package_json = project_root .. "/package.json"
  if vim.fn.filereadable(package_json) == 1 then
    local content = table.concat(vim.fn.readfile(package_json), "\n")
    return content:match('"react"') ~= nil and 
           not content:match('"next"') and 
           not content:match('"vite"') and 
           not content:match('"@vitejs"')
  end
  return false
end

function M.is_patched(project_root)
  local search_roots = base_injector.find_search_roots(project_root)
  local patched_files = 0

  for _, file in ipairs(REACT_FILES) do
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if base_injector.is_file_patched(filepath, true) then
        patched_files = patched_files + 1
        debug_logger.log("REACT_PATCH", string.format("Found patched file: %s", filepath))
      end
      break
    end
  end

  return patched_files > 0, patched_files
end

function M.patch(project_root, ws_port)
  debug_logger.log("REACT_PATCH", string.format("Patching React for port %d", ws_port))

  local search_roots = base_injector.find_search_roots(project_root)
  local patched = false
  local project_id = vim.fn.fnamemodify(project_root, ":t")

  local plugin_dir = base_injector.get_plugin_directory()
  if not plugin_dir then
    return false
  end

  local inject_content, sourcemap_content = base_injector.load_injection_scripts(plugin_dir)
  if not inject_content then
    return false
  end

  local inject_script = base_injector.generate_injection_script(
    ws_port, project_id, "React", true, sourcemap_content, inject_content
  )

  for _, file in ipairs(REACT_FILES) do
    local found_file = false
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if vim.fn.filereadable(filepath) == 1 then
        found_file = true
        
        local patterns = {
          use_strict_directive = true,
          window_check_pattern = "if %(typeof window !== 'undefined'%))"
        }
        
        if base_injector.patch_file_with_injection(filepath, inject_script, patterns) then
          patched = true
          debug_logger.log("REACT_PATCH", string.format("Patched %s in %s", file, root))
        end
        break
      end
    end
    if not found_file then
      debug_logger.log("REACT_PATCH", string.format("File not found in any search root: %s", file))
    end
  end

  if patched then
    base_injector.notify_success("React", ws_port)
  else
    debug_logger.log("REACT_PATCH", "No React files found to patch")
    base_injector.notify_error("React", "No React files found to patch")
  end

  return patched
end

function M.unpatch(project_root)
  debug_logger.log("REACT_PATCH", "Removing React patches")

  local search_roots = base_injector.find_search_roots(project_root)
  local unpatched_count = 0

  for _, file in ipairs(REACT_FILES) do
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if base_injector.restore_from_backup(filepath) then
        unpatched_count = unpatched_count + 1
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