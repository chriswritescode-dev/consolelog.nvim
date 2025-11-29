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
    
    -- Create temporary directory structure
    temp_dir = "/tmp/consolelog_nextjs_test_" .. vim.fn.getpid()
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
    it("should patch app-index.js with console injection", function()
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
      
      -- Patch the file
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      
      assert.is_true(patched, "Should return true when patching succeeds")
      
      -- Check that file was modified
      local modified_content = read_file_content(app_index_path)
      assert.not_nil(modified_content, "File should still exist")
      assert.is_true(modified_content:match("window%.__CONSOLELOG_WS_PORT") ~= nil, "Should set WebSocket port")
      assert.is_true(modified_content:match("window%.__CONSOLELOG_PROJECT_ID") ~= nil, "Should set project ID")
      assert.is_true(modified_content:match("window%.__CONSOLELOG_FRAMEWORK") ~= nil, "Should set framework")
      
      cleanup()
    end)
    
    it("should not patch if already patched with same port", function()
      setup()
      
      -- Create pre-patched app-index.js file
      local pre_patched_content = [[
'use client'
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = 9999;
  window.__CONSOLELOG_PROJECT_ID = 'test-project';
  // Some injected code
}
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(pre_patched_content)
      
      -- Try to patch with same port
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      
      assert.is_true(patched, "Should return true even if already patched")
      
      -- Check that port wasn't changed (but project ID might be updated)
      local modified_content = read_file_content(app_index_path)
      assert.is_true(modified_content:match("window%.__CONSOLELOG_WS_PORT%s*=%s*9999") ~= nil, "Port should remain 9999")
      
      cleanup()
    end)
    
    it("should update port if already patched with different port", function()
      setup()
      
      -- Create pre-patched app-index.js file with different port
      local pre_patched_content = [[
'use client'
if (typeof window !== 'undefined') {
  window.__CONSOLELOG_WS_PORT = 8888;
  window.__CONSOLELOG_PROJECT_ID = 'test-project';
  // Some injected code
}
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(pre_patched_content)
      
      -- Try to patch with different port
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      
      assert.is_true(patched, "Should return true when updating port")
      
      -- Check that port was updated
      local modified_content = read_file_content(app_index_path)
      assert.is_true(modified_content:match("ConsoleLog%.nvim auto%-injection %- Port 9999") ~= nil, "Should update port in comment")
      assert.is_true(modified_content:match("window%.__CONSOLELOG_WS_PORT = 9999") ~= nil, "Should update port variable")
      
      cleanup()
    end)
  end)
  
  describe("Unpatch functionality", function()
    it("should remove ConsoleLog injection from app-index.js", function()
      setup()
      
      -- Create patched app-index.js file
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
      
      -- Unpatch the file
      nextjs_injector.unpatch(project_root)
      
      -- Check that injection was removed
      local modified_content = read_file_content(app_index_path)
      assert.not_nil(modified_content, "File should still exist")
      assert.is_true(modified_content:match("ConsoleLog%.nvim auto%-injection") == nil, "Should not contain ConsoleLog injection")
      assert.is_true(modified_content:match("window%.__CONSOLELOG_WS_PORT") == nil, "Should not contain WebSocket port")
      assert.is_true(modified_content:match("console%.log") ~= nil, "Should preserve original content")
      
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
    it("should successfully patch and then unpatch Next.js files", function()
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
      
      -- Patch both files
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      assert.is_true(patched, "Should patch successfully")
      
      -- Verify both files are patched
      local patched_content = read_file_content(app_index_path)
      local esm_patched_content = read_file_content(esm_app_index_path)
      
      assert.is_true(patched_content:match("ConsoleLog%.nvim auto%-injection") ~= nil, "Regular app-index should be patched")
      assert.is_true(esm_patched_content:match("ConsoleLog%.nvim auto%-injection") ~= nil, "ESM app-index should be patched")
      
      -- Unpatch both files
      nextjs_injector.unpatch(project_root)
      
      -- Verify both files are unpatched
      local unpatched_content = read_file_content(app_index_path)
      local esm_unpatched_content = read_file_content(esm_app_index_path)
      
      assert.is_true(unpatched_content:match("ConsoleLog%.nvim auto%-injection") == nil, "Regular app-index should be unpatched")
      assert.is_true(esm_unpatched_content:match("ConsoleLog%.nvim auto%-injection") == nil, "ESM app-index should be unpatched")
      assert.is_true(unpatched_content:match("console%.log") ~= nil, "Original content should be preserved")
      assert.is_true(esm_unpatched_content:match("console%.log") ~= nil, "ESM original content should be preserved")
      
      cleanup()
    end)
  end)
end)