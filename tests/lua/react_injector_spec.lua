local helper = require('test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("React Injector Tests", function()
  local react_injector
  local temp_dir
  local project_root
  
  -- Setup before each test
  local function setup()
    -- Load the React injector module
    react_injector = require('consolelog.injection.injectors.react')
    
    -- Create temporary directory structure (clean any leftover state)
    temp_dir = "/tmp/consolelog_react_test_" .. vim.fn.getpid()
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end
    project_root = temp_dir
    vim.fn.mkdir(temp_dir, "p")
    
    -- Create node_modules structure
    local node_modules_dir = temp_dir .. "/node_modules/react-dom"
    vim.fn.mkdir(node_modules_dir, "p")
    
    -- Create react-scripts config directory
    local react_scripts_dir = temp_dir .. "/node_modules/react-scripts/config"
    vim.fn.mkdir(react_scripts_dir, "p")
  end
  
  -- Helper to create a mock package.json
  local function create_package_json(content)
    local package_path = project_root .. "/package.json"
    vim.fn.writefile(vim.split(content, "\n"), package_path)
    return package_path
  end
  
  -- Helper to create mock React files
  local function create_react_files()
    local index_path = project_root .. "/node_modules/react-dom/index.js"
    local client_path = project_root .. "/node_modules/react-dom/client.js"
    local webpack_path = project_root .. "/node_modules/react-scripts/config/webpack.config.js"
    
    vim.fn.writefile(vim.split("'use strict';\nfunction checkDCE() {\n  return true;\n}\n", "\n"), index_path)
    vim.fn.writefile(vim.split("'use strict';\nexport function createRoot() {\n  return {};\n}\n", "\n"), client_path)
    vim.fn.writefile(vim.split("module.exports = {\n  mode: 'development',\n  entry: './src/index.js'\n};\n", "\n"), webpack_path)
    
    return index_path, client_path, webpack_path
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
  
  describe("React Detection", function()
    it("should detect React project with react and react-dom", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      
      local detected = react_injector.detect(project_root)
      assert.is_true(detected, "Should detect React project")
      
      cleanup()
    end)
    
    it("should not detect React project without react", function()
      setup()
      create_package_json('{"dependencies": {"vue": "^3.0.0"}}')
      
      local detected = react_injector.detect(project_root)
      assert.is_false(detected, "Should not detect non-React project")
      
      cleanup()
    end)
    
    it("should not detect React project with next (should be Next.js)", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "next": "^14.0.0"}}')
      
      local detected = react_injector.detect(project_root)
      assert.is_false(detected, "Should not detect React when Next.js is present")
      
      cleanup()
    end)
    
    it("should not detect React project with vite (should be Vite)", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "vite": "^5.0.0"}}')
      
      local detected = react_injector.detect(project_root)
      assert.is_false(detected, "Should not detect React when Vite is present")
      
      cleanup()
    end)
  end)
  
  describe("React Patching", function()
    it("should successfully patch React files", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()
      
      local success = react_injector.patch(project_root, 19990)
      assert.is_true(success, "Should successfully patch React files")

      local index_content = read_file_content(index_path)
      assert.is_true(has_injection(index_content), "index.js should contain injection")
      assert.is_true(index_content:find("window.__CONSOLELOG_WS_PORT = 19990") ~= nil,
        "Patched content should contain port 19990")
      assert.is_true(backup_exists(index_path), "index.js backup should exist")
      
      cleanup()
    end)
    
    it("should handle missing files gracefully", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      -- Don't create the React files
      
      local success = react_injector.patch(project_root, 19990)
      assert.is_false(success, "Patching should fail when files don't exist")
      
      cleanup()
    end)
    
    it("should re-patch with updated port", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()
      
      react_injector.patch(project_root, 8888)

      local success = react_injector.patch(project_root, 19991)
      assert.is_true(success, "Should successfully re-patch")

      local patched_content = read_file_content(index_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 19991") ~= nil,
        "Re-patched content should contain new port 19991")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Re-patched content should not contain old port 8888")

      cleanup()
    end)

    it("should upgrade legacy injection without start/end markers", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()

      local original_index = read_file_content(index_path)
      vim.fn.writefile(vim.split(original_index, "\n"), index_path .. ".bk")

      local legacy_content = [[
'use strict';
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = 8888;
  window.__CONSOLELOG_PROJECT_ID = 'test-project';
  window.__CONSOLELOG_FRAMEWORK = 'React';
  window.__CONSOLELOG_DEBUG = true;
}
function checkDCE() {
  return true;
}
]]
      vim.fn.writefile(vim.split(legacy_content, "\n"), index_path)

      local success = react_injector.patch(project_root, 19991)
      assert.is_true(success, "Should successfully upgrade legacy injection")

      local patched_content = read_file_content(index_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 19991") ~= nil,
        "Upgraded content should contain new port 19991")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Upgraded content should not contain legacy port 8888")
      local _, start_count = patched_content:gsub("// ConsoleLog%.nvim auto%-injection start", "")
      assert.equals(1, start_count, "Should contain exactly one start marker")
      
      cleanup()
    end)
  end)
  
  describe("React Unpatching", function()
    it("should restore original files from backup", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()
      
      -- Store original content
      local original_index = read_file_content(index_path)
      local original_client = read_file_content(client_path)
      local original_webpack = read_file_content(webpack_path)
      
      -- Create backup files to simulate a patched state
      vim.fn.writefile(vim.split(original_index, "\n"), index_path .. ".bk")
      vim.fn.writefile(vim.split(original_client, "\n"), client_path .. ".bk")
      vim.fn.writefile(vim.split(original_webpack, "\n"), webpack_path .. ".bk")

      -- Overwrite files with patched content
      vim.fn.writefile(vim.split(original_index .. "\nwindow.__CONSOLELOG_WS_PORT = 19990;", "\n"), index_path)
      
      -- Unpatch should restore from backup
      react_injector.unpatch(project_root)
      
      -- Check that files were restored
      local restored_index = read_file_content(index_path)
      assert.equals(original_index, restored_index, "index.js should be restored")
      
      -- Check that backups were removed
      assert.is_false(backup_exists(index_path), "index.js backup should be removed")
      
      cleanup()
    end)
    
    it("should handle unpatching when no patches exist", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      
      -- Should not throw error when unpatching clean project
      assert.no_throw(function()
        react_injector.unpatch(project_root)
      end, "Unpatching clean project should not throw")
      
      cleanup()
    end)

    it("should remove bounded marker block when backup is missing", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()

      local marker_block = "// ConsoleLog.nvim auto-injection start\n" ..
        "if (typeof window !== 'undefined') {\n" ..
        "  window.__CONSOLELOG_WS_PORT = 19990;\n" ..
        "  window.__CONSOLELOG_PROJECT_ID = 'test';\n" ..
        "  window.__CONSOLELOG_FRAMEWORK = 'React';\n" ..
        "  window.__CONSOLELOG_DEBUG = true;\n" ..
        "}\n" ..
        "// ConsoleLog.nvim auto-injection end\n"

      local file_with_marker = "'use strict';\n" .. marker_block ..
        "function checkDCE() {\n  return true;\n}\n"
      vim.fn.writefile(vim.split(file_with_marker, "\n"), index_path)

      react_injector.unpatch(project_root)

      local result = read_file_content(index_path)
      assert.is_true(result:find("ConsoleLog%.nvim auto%-injection") == nil,
        "Marker block should be removed when backup is missing")
      assert.is_true(result:find("function checkDCE") ~= nil,
        "Surrounding original code should be preserved")

      cleanup()
    end)
  end)
  
  describe("React is_patched", function()
    it("should return true after successful patch", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      create_react_files()
      
      react_injector.patch(project_root, 19990)

      local is_patched, count = react_injector.is_patched(project_root)
      assert.is_true(is_patched, "Should report as patched after patching")
      assert.is_true(count > 0, "Should report at least one patched file")
      
      cleanup()
    end)
    
    it("should return false when not patched", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      create_react_files()
      
      local is_patched, count = react_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should report as not patched")
      assert.equals(0, count, "Should report zero patched files")
      
      cleanup()
    end)

    it("should return false for clean file with stale backup", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()

      vim.fn.writefile(vim.split(read_file_content(index_path), "\n"), index_path .. ".bk")

      local is_patched, count = react_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should not report as patched when file is clean")
      assert.equals(0, count, "Should report zero patched files for clean file with stale backup")

      local clean_content = read_file_content(index_path)
      react_injector.unpatch(project_root)
      assert.equals(clean_content, read_file_content(index_path), "Clean file should remain unchanged after unpatch")
      assert.is_false(backup_exists(index_path), "Stale backup should be deleted after unpatch")

      vim.fn.writefile({ "stale dependency content" }, index_path .. ".bk")
      react_injector.patch(project_root, 19990)
      react_injector.unpatch(project_root)
      assert.equals(clean_content, read_file_content(index_path), "Refreshed backup should restore current dependency content")

      cleanup()
    end)
  end)
end)
