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
    it("should successfully patch app-index.js", function()
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
      
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      
      assert.is_true(patched, "Should successfully patch app-index.js")

      local patched_content = read_file_content(app_index_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 9999") ~= nil,
        "Patched content should contain port 9999")
      
      cleanup()
    end)
    
    it("should re-patch with updated port", function()
      setup()
      
      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      
      local app_index_path = create_app_index_file(original_content)

      nextjs_injector.patch(project_root, 8888)
      
      local new_ws_port = 9999
      local patched = nextjs_injector.patch(project_root, new_ws_port)
      
      assert.is_true(patched, "Should successfully re-patch")
      
      local patched_content = read_file_content(app_index_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 9999") ~= nil,
        "Re-patched content should contain new port 9999")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Re-patched content should not contain old port 8888")
      
      cleanup()
    end)
    
    it("should create backup when patching", function()
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
      
      local backup_content = read_file_content(app_index_path .. ".bk")
      assert.not_nil(backup_content, "Backup should be created when patch succeeds")
      assert.equals(backup_content, original_content, "Backup should contain original content")

      cleanup()
    end)

    it("should upgrade legacy injection without start/end markers", function()
      setup()

      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]

      local app_index_path = create_app_index_file(original_content)

      vim.fn.writefile(vim.split(original_content, "\n"), app_index_path .. ".bk")

      local legacy_content = [[
'use client'
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
      vim.fn.writefile(vim.split(legacy_content, "\n"), app_index_path)

      local patched = nextjs_injector.patch(project_root, 9999)
      assert.is_true(patched, "Should successfully upgrade legacy injection")

      local patched_content = read_file_content(app_index_path)
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 9999") ~= nil,
        "Upgraded content should contain new port 9999")
      assert.is_true(patched_content:find("window.__CONSOLELOG_WS_PORT = 8888") == nil,
        "Upgraded content should not contain legacy port 8888")
      local _, start_count = patched_content:gsub("// ConsoleLog%.nvim auto%-injection start", "")
      assert.equals(1, start_count, "Should contain exactly one start marker")
      
      cleanup()
    end)

    it("should update injected auto-injector code in cpu-profile.js when re-patching", function()
      setup()

      vim.fn.mkdir(project_root .. "/node_modules/next/dist/server/lib", "p")
      local cpu_profile_path = project_root .. "/node_modules/next/dist/server/lib/cpu-profile.js"
      local cpu_content = "function enableProfiling() {\n  return true;\n}\n"
      vim.fn.writefile(vim.split(cpu_content, "\n"), cpu_profile_path)

      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]
      create_app_index_file(original_content)

      nextjs_injector.patch(project_root, 8888)

      local cpu_after_first = read_file_content(cpu_profile_path)
      assert.is_true(cpu_after_first:find("WS_PORT = 8888") ~= nil,
        "cpu-profile.js should contain port 8888 after first patch")

      local updated_cpu_content = "function updatedProfiling() {\n  return true;\n}\n"
      vim.fn.writefile(vim.split(updated_cpu_content, "\n"), cpu_profile_path)
      nextjs_injector.patch(project_root, 9999)

      local cpu_after_second = read_file_content(cpu_profile_path)
      assert.is_true(cpu_after_second:find("WS_PORT = 9999") ~= nil,
        "cpu-profile.js should contain port 9999 after re-patch")
      assert.is_true(cpu_after_second:find("WS_PORT = 8888") == nil,
        "cpu-profile.js should not contain old port 8888 after re-patch")

      nextjs_injector.unpatch(project_root)
      assert.equals(updated_cpu_content, read_file_content(cpu_profile_path),
        "Unpatch should restore current dependency content")

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

    it("should remove bounded marker block when backup is missing", function()
      setup()

      local marker_block = "// ConsoleLog.nvim auto-injection start\n" ..
        "if (typeof window !== 'undefined') {\n" ..
        "  window.__CONSOLELOG_WS_PORT = 9999;\n" ..
        "  window.__CONSOLELOG_PROJECT_ID = 'test';\n" ..
        "  window.__CONSOLELOG_FRAMEWORK = 'Next.js';\n" ..
        "  window.__CONSOLELOG_DEBUG = false;\n" ..
        "}\n" ..
        "// ConsoleLog.nvim auto-injection end\n"

      local file_with_marker = "'use client'\n" .. marker_block ..
        "if (typeof window !== 'undefined') {\n  console.log('Hello from Next.js');\n}\n"
      local app_index_path = create_app_index_file(file_with_marker)

      nextjs_injector.unpatch(project_root)

      local result = read_file_content(app_index_path)
      assert.is_true(result:find("ConsoleLog%.nvim auto%-injection") == nil,
        "Marker block should be removed when backup is missing")
      assert.is_true(result:find("console.log") ~= nil,
        "Surrounding original code should be preserved")

      cleanup()
    end)
  end)
  
  describe("Complete patch/unpatch cycle", function()
    it("should patch then unpatch and restore original", function()
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
      
      local ws_port = 9999
      local patched = nextjs_injector.patch(project_root, ws_port)
      assert.is_true(patched, "Should successfully patch")
      
      nextjs_injector.unpatch(project_root)
      
      local restored_content = read_file_content(app_index_path)
      assert.equals(restored_content, original_content, "app-index.js should be restored to original")

      cleanup()
    end)
  end)

  describe("is_patched", function()
    it("should return true after successful patch", function()
      setup()

      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]

      create_app_index_file(original_content)

      nextjs_injector.patch(project_root, 9999)

      local is_patched, count = nextjs_injector.is_patched(project_root)
      assert.is_true(is_patched, "Should report as patched after patching")
      assert.equals(1, count, "Should report one patched file")
      
      cleanup()
    end)

    it("should return false for clean file with stale backup", function()
      setup()

      local original_content = [[
'use client'
if (typeof window !== 'undefined') {
  console.log('Hello from Next.js');
}
]]

      local app_index_path = create_app_index_file(original_content)
      vim.fn.writefile(vim.split(original_content, "\n"), app_index_path .. ".bk")

      local is_patched, count = nextjs_injector.is_patched(project_root)
      assert.is_false(is_patched, "Should not report as patched when file is clean")
      assert.equals(0, count, "Should report zero patched files for clean file with stale backup")

      local clean_content = read_file_content(app_index_path)
      nextjs_injector.unpatch(project_root)
      assert.equals(clean_content, read_file_content(app_index_path), "Clean file should remain unchanged after unpatch")
      assert.is_false(vim.fn.filereadable(app_index_path .. ".bk") == 1, "Stale backup should be deleted after unpatch")

      vim.fn.writefile({ "stale dependency content" }, app_index_path .. ".bk")
      nextjs_injector.patch(project_root, 9999)
      nextjs_injector.unpatch(project_root)
      assert.equals(clean_content, read_file_content(app_index_path), "Refreshed backup should restore current dependency content")

      cleanup()
    end)
  end)
end)
