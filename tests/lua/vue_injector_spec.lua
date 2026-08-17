local helper = require('test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("Vue Injector Tests", function()
  local vue_injector
  local temp_dir
  local project_root
  
  -- Setup before each test
  local function setup()
    -- Load the Vue injector module
    vue_injector = require('consolelog.injection.injectors.vue')
    
    -- Create temporary directory structure (clean any leftover state)
    temp_dir = "/tmp/consolelog_vue_test_" .. vim.fn.getpid()
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end
    project_root = temp_dir
    vim.fn.mkdir(temp_dir, "p")
    
    -- Create node_modules structure
    local node_modules_dir = temp_dir .. "/node_modules/vue/dist"
    vim.fn.mkdir(node_modules_dir, "p")
    
    -- Create @vue runtime-dom structure
    local vue_runtime_dir = temp_dir .. "/node_modules/@vue/runtime-dom/dist"
    vim.fn.mkdir(vue_runtime_dir, "p")
    
    -- Create @vitejs plugin-vue structure
    local vite_plugin_dir = temp_dir .. "/node_modules/@vitejs/plugin-vue/dist"
    vim.fn.mkdir(vite_plugin_dir, "p")
  end
  
  -- Helper to create a mock package.json
  local function create_package_json(content)
    local package_path = project_root .. "/package.json"
    vim.fn.writefile(vim.split(content, "\n"), package_path)
    return package_path
  end
  
  -- Helper to create mock Vue files
  local function create_vue_files()
    local runtime_path = project_root .. "/node_modules/vue/dist/vue.runtime.esm-browser.js"
    local esm_path = project_root .. "/node_modules/vue/dist/vue.esm-browser.js"
    local runtime_dom_path = project_root .. "/node_modules/@vue/runtime-dom/dist/runtime-dom.esm-bundler.js"
    local vite_plugin_path = project_root .. "/node_modules/@vitejs/plugin-vue/dist/index.js"
    
    vim.fn.writefile(vim.split("/**\n* Vue.js v3.5.0\n* (c) 2018-present Yuxi\n*/\n'use strict';\nfunction createApp() {\n  return {};\n}\n", "\n"), runtime_path)
    vim.fn.writefile(vim.split("/**\n* Vue.js v3.5.0 ESM\n* (c) 2018-present Yuxi\n*/\nexport function createApp() {\n  return {};\n}\n", "\n"), esm_path)
    vim.fn.writefile(vim.split("/**\n* @vue/runtime-dom v3.5.0\n* (c) 2018-present Yuxi\n*/\nexport function createRenderer() {\n  return {};\n}\n", "\n"), runtime_dom_path)
    vim.fn.writefile(vim.split("/**\n* @vitejs/plugin-vue v5.0.0\n* (c) 2018-present Vite\n*/\nmodule.exports = function vuePlugin() {\n  return {\n    name: 'vite:vue'\n  };\n};\n", "\n"), vite_plugin_path)
    
    return runtime_path, esm_path, runtime_dom_path, vite_plugin_path
  end
  
  -- Helper to read file content
  local function read_file_content(filepath)
    if vim.fn.filereadable(filepath) == 1 then
      return table.concat(vim.fn.readfile(filepath), "\n")
    end
    return nil
  end
  
  -- Helper to check if file contains injection
  local function has_injection(content)
    return content and content:match("window%.__CONSOLELOG_WS_PORT") ~= nil
  end
  
  -- Helper to check if backup exists
  local function backup_exists(filepath)
    return vim.fn.filereadable(filepath .. ".bk") == 1
  end
  
  -- Cleanup after each test
  local function cleanup()
    if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end
  
  describe("Vue Detection", function()
    it("should detect Vue project with vue dependency", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      
      local detected = vue_injector.detect(project_root)
      assert.is_true(detected, "Should detect Vue project")
      
      cleanup()
    end)
    
    it("should not detect Vue project without vue", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0"}}')
      
      local detected = vue_injector.detect(project_root)
      assert.is_false(detected, "Should not detect non-Vue project")
      
      cleanup()
    end)
    
    it("should not detect Vue project with vite (should be Vite)", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0", "vite": "^5.0.0"}}')
      
      local detected = vue_injector.detect(project_root)
      assert.is_false(detected, "Should not detect Vue when Vite is present")
      
      cleanup()
    end)
  end)
  
  describe("Vue Patching", function()
    it("should successfully patch Vue files", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()
      
      local success = vue_injector.patch(project_root, 19990)
      assert.is_true(success, "Should successfully patch Vue files")

      local runtime_content = read_file_content(runtime_path)
      assert.is_true(has_injection(runtime_content), "vue.runtime.esm-browser.js should contain injection")
      assert.is_true(runtime_content:find("window.__CONSOLELOG_WS_PORT = 19990") ~= nil,
        "Patched content should contain port 19990")
      assert.is_true(backup_exists(runtime_path), "vue.runtime.esm-browser.js backup should exist")
      
      cleanup()
    end)
    
    it("should handle missing files gracefully", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      -- Don't create the Vue files
      
      local success = vue_injector.patch(project_root, 19990)
      assert.is_false(success, "Patching should fail when files don't exist")
      
      cleanup()
    end)
    
    it("should re-patch with updated port", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()
      
      vue_injector.patch(project_root, 8888)

      local success = vue_injector.patch(project_root, 19991)
      assert.is_true(success, "Should successfully re-patch")

      local patched_content = read_file_content(runtime_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 19991") ~= nil,
        "Re-patched content should contain new port 19991")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Re-patched content should not contain old port 8888")

      cleanup()
    end)

    it("should upgrade legacy injection without start/end markers", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()

      local original_runtime = read_file_content(runtime_path)
      vim.fn.writefile(vim.split(original_runtime, "\n"), runtime_path .. ".bk")

      local legacy_content = [[
'use strict';
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = 8888;
  window.__CONSOLELOG_PROJECT_ID = 'test-project';
  window.__CONSOLELOG_FRAMEWORK = 'Vue';
  window.__CONSOLELOG_DEBUG = true;
}
function createApp() {
  return {};
}
]]
      vim.fn.writefile(vim.split(legacy_content, "\n"), runtime_path)

      local success = vue_injector.patch(project_root, 19991)
      assert.is_true(success, "Should successfully upgrade legacy injection")

      local patched_content = read_file_content(runtime_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 19991") ~= nil,
        "Upgraded content should contain new port 19991")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Upgraded content should not contain legacy port 8888")
      local _, start_count = patched_content:gsub("// ConsoleLog%.nvim auto%-injection start", "")
      assert.equals(1, start_count, "Should contain exactly one start marker")
      
      cleanup()
    end)
  end)
  
  describe("Vue Unpatching", function()
    it("should restore original files from backup", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()
      
      -- Store original content
      local original_runtime = read_file_content(runtime_path)
      
      -- Create backup to simulate a patched state
      vim.fn.writefile(vim.split(original_runtime, "\n"), runtime_path .. ".bk")

      -- Overwrite file with patched content
      vim.fn.writefile(vim.split(original_runtime .. "\nwindow.__CONSOLELOG_WS_PORT = 19990;", "\n"), runtime_path)
      
      -- Unpatch should restore from backup
      vue_injector.unpatch(project_root)
      
      -- Check that file was restored
      local restored_runtime = read_file_content(runtime_path)
      assert.equals(original_runtime, restored_runtime, "vue.runtime.esm-browser.js should be restored")
      
      -- Check that backup was removed
      assert.is_false(backup_exists(runtime_path), "vue.runtime.esm-browser.js backup should be removed")
      
      cleanup()
    end)
    
    it("should handle unpatching when no patches exist", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      
      -- Should not throw error when unpatching clean project
      assert.no_throw(function()
        vue_injector.unpatch(project_root)
      end, "Unpatching clean project should not throw")
      
      cleanup()
    end)

    it("should remove bounded marker block when backup is missing", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()

      local marker_block = "// ConsoleLog.nvim auto-injection start\n" ..
        "if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {\n" ..
        "  window.__CONSOLELOG_WS_PORT = 19990;\n" ..
        "  window.__CONSOLELOG_PROJECT_ID = 'test';\n" ..
        "  window.__CONSOLELOG_FRAMEWORK = 'Vue';\n" ..
        "  window.__CONSOLELOG_DEBUG = true;\n" ..
        "}\n" ..
        "// ConsoleLog.nvim auto-injection end\n"

      local file_with_marker = "/**\n* Vue.js v3.5.0\n*/\n" .. marker_block ..
        "'use strict';\nfunction createApp() {\n  return {};\n}\n"
      vim.fn.writefile(vim.split(file_with_marker, "\n"), runtime_path)

      vue_injector.unpatch(project_root)

      local result = read_file_content(runtime_path)
      assert.is_true(result:find("ConsoleLog%.nvim auto%-injection") == nil,
        "Marker block should be removed when backup is missing")
      assert.is_true(result:find("function createApp") ~= nil,
        "Surrounding original code should be preserved")

      cleanup()
    end)
  end)
  
  describe("Vue is_patched", function()
    it("should return true after successful patch", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      create_vue_files()
      
      vue_injector.patch(project_root, 19990)

      local is_patched, count = vue_injector.is_patched(project_root)
      assert.is_true(is_patched, "Should report as patched after patching")
      assert.is_true(count > 0, "Should report at least one patched file")
      
      cleanup()
    end)
    
    it("should return false when not patched", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      create_vue_files()
      
      local is_patched, count = vue_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should report as not patched")
      assert.equals(0, count, "Should report zero patched files")
      
      cleanup()
    end)

    it("should return false for clean file with stale backup", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()

      vim.fn.writefile(vim.split(read_file_content(runtime_path), "\n"), runtime_path .. ".bk")

      local is_patched, count = vue_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should not report as patched when file is clean")
      assert.equals(0, count, "Should report zero patched files for clean file with stale backup")

      local clean_content = read_file_content(runtime_path)
      vue_injector.unpatch(project_root)
      assert.equals(clean_content, read_file_content(runtime_path), "Clean file should remain unchanged after unpatch")
      assert.is_false(backup_exists(runtime_path), "Stale backup should be deleted after unpatch")

      vim.fn.writefile({ "stale dependency content" }, runtime_path .. ".bk")
      vue_injector.patch(project_root, 19990)
      vue_injector.unpatch(project_root)
      assert.equals(clean_content, read_file_content(runtime_path), "Refreshed backup should restore current dependency content")

      cleanup()
    end)
  end)
end)
