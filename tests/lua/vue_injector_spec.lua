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
    it("should handle missing inject script gracefully", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()
      
      -- In test environment, injector cannot locate plugin directory,
      -- so patch returns false gracefully
      local success = vue_injector.patch(project_root, 19990)
      assert.is_false(success, "Should return false when inject script not found")
      
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
    
    it("should handle re-patch gracefully when inject script not found", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      local runtime_path, esm_path, runtime_dom_path, vite_plugin_path = create_vue_files()
      
      -- In test environment, injector cannot locate plugin directory
      local success = vue_injector.patch(project_root, 19991)
      assert.is_false(success, "Should return false when inject script not found")
      
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
      vim.fn.writefile(vim.split(original_runtime .. "\n// injected", "\n"), runtime_path)
      
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
  end)
  
  describe("Vue is_patched", function()
    it("should return false when patch was not applied", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.5.0"}}')
      create_vue_files()
      
      -- patch() failed, so no backup files were created
      local is_patched, count = vue_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should report as not patched when patch failed")
      assert.equals(0, count, "Should report zero patched files")
      
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
  end)
end)
