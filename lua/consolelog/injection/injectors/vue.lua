local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local base_injector = require("consolelog.injection.injectors.base_injector")

local VUE_FILES = {
  "/node_modules/vue/dist/vue.runtime.esm-browser.js",
  "/node_modules/vue/dist/vue.esm-browser.js",
  "/node_modules/@vue/runtime-dom/dist/runtime-dom.esm-bundler.js",
  "/node_modules/@vitejs/plugin-vue/dist/index.js",
}

function M.detect(project_root)
  local package_json = project_root .. "/package.json"
  if vim.fn.filereadable(package_json) == 1 then
    local content = table.concat(vim.fn.readfile(package_json), "\n")
    return content:match('"vue"') ~= nil and not content:match('"vite"')
  end
  return false
end

function M.is_patched(project_root)
  local search_roots = base_injector.find_search_roots(project_root)
  local patched_files = 0

  for _, file in ipairs(VUE_FILES) do
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if base_injector.is_file_patched(filepath, true) then
        patched_files = patched_files + 1
        debug_logger.log("VUE_PATCH", string.format("Found patched file: %s", filepath))
      end
      break
    end
  end

  return patched_files > 0, patched_files
end

function M.patch(project_root, ws_port)
  debug_logger.log("VUE_PATCH", string.format("Patching Vue for port %d", ws_port))

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
    ws_port, project_id, "Vue", true, sourcemap_content, inject_content
  )

  for _, file in ipairs(VUE_FILES) do
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
          debug_logger.log("VUE_PATCH", string.format("Patched %s in %s", file, root))
        end
        break
      end
    end
    if not found_file then
      debug_logger.log("VUE_PATCH", string.format("File not found in any search root: %s", file))
    end
  end

  if patched then
    base_injector.notify_success("Vue", ws_port)
  else
    debug_logger.log("VUE_PATCH", "No Vue files found to patch")
    base_injector.notify_error("Vue", "No Vue files found to patch")
  end

  return patched
end

function M.unpatch(project_root)
  debug_logger.log("VUE_PATCH", "Removing Vue patches")

  local search_roots = base_injector.find_search_roots(project_root)
  local unpatched_count = 0

  for _, file in ipairs(VUE_FILES) do
    for _, root in ipairs(search_roots) do
      local filepath = root .. file
      if base_injector.restore_from_backup(filepath) then
        unpatched_count = unpatched_count + 1
      end
    end
  end

  if unpatched_count > 0 then
    debug_logger.log("VUE_PATCH", string.format("Successfully unpatched %d Vue file(s)", unpatched_count))
  else
    debug_logger.log("VUE_PATCH", "No Vue patches found to remove")
  end
end

return M