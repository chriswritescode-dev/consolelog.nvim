local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("NextJS Injector Tests", function()
  local nextjs_injector
  local temp_dir
  local project_root
  
  -- Setup before each test
  local function setup()
    -- Load the NextJS injector module
    nextjs_injector = require('consolelog.injection.injectors.nextjs')
    
    -- Create temporary directory structure (clean any leftover state)
    temp_dir = "/tmp/consolelog_nextjs_test_" .. vim.fn.getpid()
    if vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end
    project_root = temp_dir
    vim.fn.mkdir(temp_dir, "p")
    
    -- Create node_modules structure
    local node_modules_dir = temp_dir .. "/node_modules/next/dist/client"
    vim.fn.mkdir(node_modules_dir, "p")
    
    -- Create esm structure
    local esm_dir = temp_dir .. "/node_modules/next/dist/esm/client"
    vim.fn.mkdir(esm_dir, "p")
  end
  
  -- Helper to create a mock Next.js app-index.js file
  local function create_app_index_file(content)
    local app_index_path = project_root .. "/node_modules/next/dist/client/app-index.js"
    vim.fn.writefile(vim.split(content, "\n"), app_index_path)
    return app_index_path
  end
  
  -- Helper to create a mock esm app-index.js file
  local function create_esm_app_index_file(content)
    local esm_app_index_path = project_root .. "/node_modules/next/dist/esm/client/app-index.js"
    vim.fn.writefile(vim.split(content, "\n"), esm_app_index_path)
    return esm_app_index_path
  end
  
  -- Helper to read file content
  local function read_file_content(filepath)
    if vim.fn.filereadable(filepath) == 1 then
      return table.concat(vim.fn.readfile(filepath), "\n")
    end
    return nil
  end
  
  -- Cleanup after each test
  local function cleanup()
    if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end
    -- Ensure the original module is loaded (mock test may have swapped it)
    if not nextjs_injector or not nextjs_injector.patch then
      package.loaded["consolelog.injection.injectors.nextjs"] = nil
      nextjs_injector = require('consolelog.injection.injectors.nextjs')
    end
  end
  
  describe("Detection", function()
    it("should detect Next.js project", function()
      setup()
      
      -- Create package.json with next dependency
      local package_json = [[{
        "name": "test-nextjs-app",
        "dependencies": {
          "next": "^13.0.0",
          "react": "^18.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), project_root .. "/package.json")
      
      assert.is_true(nextjs_injector.detect(project_root), "Should detect Next.js project")
      
      cleanup()
    end)
    
    it("should not detect non-Next.js project", function()
      setup()
      
      -- Create package.json without next dependency
      local package_json = [[{
        "name": "test-react-app",
        "dependencies": {
          "react": "^18.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), project_root .. "/package.json")
      
      assert.is_false(nextjs_injector.detect(project_root), "Should not detect non-Next.js project")
      
      cleanup()
    end)
  end)
  
  describe("Patch functionality", function()
    it("should handle missing inject script gracefully", function()
      setup()
      
      -- Create mock app-index.js file
      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  // Some Next.js client code
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(original_content)
      
      -- In test environment, injector cannot locate plugin directory,
      -- so patch returns false gracefully
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      
      assert.is_false(patched, "Should return false when inject script not found")
      
      cleanup()
    end)
    
    it("should re-patch with updated port when inject script is found", function()
      setup()
      
      -- The injector resolves plugin_dir via debug.getinfo. In the fallback path
      -- (when consolelog.nvim pattern doesn't match), fnamemodify(:p) returns a
      -- path WITHOUT trailing slash, causing "lua" .. "js/" to become "luajs/".
      -- Workaround: create a mock consolelog.nvim installation so the primary
      -- pattern match succeeds (it includes the trailing slash in the capture).
      local cwd = vim.fn.getcwd()
      local mock_dir = temp_dir .. "/consolelog.nvim"
      vim.fn.mkdir(mock_dir .. "/lua/consolelog/injection/injectors", "p")
      vim.fn.mkdir(mock_dir .. "/js", "p")
      vim.fn.system("cp " .. vim.fn.shellescape(cwd .. "/lua/consolelog/injection/injectors/nextjs.lua") .. " " .. vim.fn.shellescape(mock_dir .. "/lua/consolelog/injection/injectors/nextjs.lua"))
      vim.fn.system("cp " .. vim.fn.shellescape(cwd .. "/js/inject-client.js") .. " " .. vim.fn.shellescape(mock_dir .. "/js/inject-client.js"))
      vim.fn.system("cp " .. vim.fn.shellescape(cwd .. "/js/nextjs-auto-injector.js") .. " " .. vim.fn.shellescape(mock_dir .. "/js/nextjs-auto-injector.js"))
      vim.fn.system("cp " .. vim.fn.shellescape(cwd .. "/js/sourcemap-resolver.js") .. " " .. vim.fn.shellescape(mock_dir .. "/js/sourcemap-resolver.js"))

      -- Temporarily load the injector from the mock installation
      local orig_path = package.path
      package.path = mock_dir .. "/lua/?.lua;" .. package.path
      package.loaded["consolelog.injection.injectors.nextjs"] = nil
      local mock_injector = require('consolelog.injection.injectors.nextjs')
      package.path = orig_path

      -- Create pre-patched app-index.js with port 8888
      local pre_patched_content = [[
'use client'
// ConsoleLog.nvim auto-injection
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = 8888;
  window.__CONSOLELOG_PROJECT_ID = 'test-project';
  window.__CONSOLELOG_FRAMEWORK = 'Next.js';
  window.__CONSOLELOG_DEBUG = false;
}
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(pre_patched_content)
      
      -- Re-patch with a different port using the mock injector
      local new_ws_port = 9999
      local patched = mock_injector.patch(project_root, new_ws_port)
      
      assert.is_true(patched, "Should successfully re-patch")
      
      -- Verify the new port appears in patched content
      local patched_content = read_file_content(app_index_path)
      assert.is_true(patched_content ~= nil, "Patched file should exist")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 9999") ~= nil,
        "Re-patched content should contain new port 9999")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Re-patched content should not contain old port 8888")

      -- Restore the original module
      package.loaded["consolelog.injection.injectors.nextjs"] = nil
      nextjs_injector = require('consolelog.injection.injectors.nextjs')
      
      cleanup()
    end)
    
    it("should not create backup when patch fails", function()
      setup()
      
      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  // Some Next.js client code
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(original_content)
      local ws_port = 9999
      nextjs_injector.patch(project_root, ws_port)
      
      -- In test environment, patch fails so no backup is created
      local backup_content = read_file_content(app_index_path .. ".bk")
      assert.is_nil(backup_content, "No backup should be created when patch fails")
      
      cleanup()
    end)
  end)
  
  describe("Unpatch functionality", function()
    it("should handle unpatch when no backup exists", function()
      setup()
      
      -- Create a file with injection markers but no backup
      -- unpatch only restores from .bk files, so this should be a no-op
      local patched_content = [[
'use client'
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = 9999;
  window.__CONSOLELOG_PROJECT_ID = 'test-project';
  // Injected sourcemap resolver code
  // Injected client code
}
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(patched_content)
      
      -- Unpatch the file (no backup exists, so nothing happens)
      nextjs_injector.unpatch(project_root)
      
      -- Check that content is unchanged (no backup to restore from)
      local modified_content = read_file_content(app_index_path)
      assert.equals(modified_content, patched_content, "Content should remain unchanged when no backup exists")

      cleanup()
    end)

    it("should restore from backup when it exists", function()
      setup()

      -- Create original file
      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]

      -- Create the file and its backup
      local app_index_path = create_app_index_file(original_content)

      -- Create backup with original content
      local backup_path = app_index_path .. ".bk"
      vim.fn.writefile(vim.split(original_content, "\n"), backup_path)

      -- Now overwrite the file with patched content
      local patched_content = original_content .. "\n// ConsoleLog.nvim auto-injection\nwindow.__CONSOLELOG_WS_PORT = 9999;\n"
      vim.fn.writefile(vim.split(patched_content, "\n"), app_index_path)

      -- Unpatch should restore from backup
      nextjs_injector.unpatch(project_root)

      -- Check that original content was restored
      local restored_content = read_file_content(app_index_path)
      assert.equals(restored_content, original_content, "Should restore original content from backup")

      -- Check that backup was removed
      assert.is_false(vim.fn.filereadable(backup_path) == 1, "Backup should be deleted after restore")

      cleanup()
    end)
    
    it("should handle file without injection gracefully", function()
      setup()
      
      -- Create clean app-index.js file without injection
      local clean_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(clean_content)
      
      -- Unpatch the file (should not error)
      nextjs_injector.unpatch(project_root)
      
      -- Check that content remains unchanged
      local modified_content = read_file_content(app_index_path)
      assert.equals(modified_content, clean_content, "Content should remain unchanged when no injection exists")
      
      cleanup()
    end)
    
    it("should handle missing files gracefully", function()
      setup()
      
      -- Don't create any app-index.js files
      
      -- Unpatch should not error
      nextjs_injector.unpatch(project_root)
      
      cleanup()
    end)
  end)
  
  describe("Complete patch/unpatch cycle", function()
    it("should handle patch failure and unpatch gracefully", function()
      setup()
      
      -- Create both regular and esm app-index.js files
      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(original_content)
      local esm_app_index_path = create_esm_app_index_file(original_content)
      
      -- In test environment, patch fails
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      assert.is_false(patched, "Should return false when inject script not found")
      
      -- Unpatch should not error even with no backups
      nextjs_injector.unpatch(project_root)
      
      -- Verify files are unchanged
      local content = read_file_content(app_index_path)
      assert.equals(content, original_content, "app-index.js should remain unchanged")
      
      cleanup()
    end)
  end)
end)
