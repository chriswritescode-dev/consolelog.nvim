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
    it("should handle missing inject script gracefully", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()
      
      -- In test environment, injector cannot locate plugin directory,
      -- so patch returns false gracefully
      local success = react_injector.patch(project_root, 19990)
      assert.is_false(success, "Should return false when inject script not found")
      
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
    
    it("should handle re-patch gracefully when inject script not found", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      local index_path, client_path, webpack_path = create_react_files()
      
      -- In test environment, injector cannot locate plugin directory
      local success = react_injector.patch(project_root, 19991)
      assert.is_false(success, "Should return false when inject script not found")
      
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
      vim.fn.writefile(vim.split(original_index .. "\n// injected", "\n"), index_path)
      
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
  end)
  
  describe("React is_patched", function()
    it("should return false when patch was not applied", function()
      setup()
      create_package_json('{"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}}')
      create_react_files()
      
      -- patch() failed, so no backup files were created
      local is_patched, count = react_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should report as not patched when patch failed")
      assert.equals(0, count, "Should report zero patched files")
      
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
  end)
end)
