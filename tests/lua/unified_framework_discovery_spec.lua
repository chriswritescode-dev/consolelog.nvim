local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("Unified Framework Discovery Tests", function()
  local framework_detector
  
  local function setup()
    framework_detector = require('consolelog.injection.framework_detector')
  end
  
  local function create_temp_project(name, package_content, config_files)
    local temp_dir = "/tmp/test_unified_" .. name .. "_" .. vim.fn.getpid()
    vim.fn.mkdir(temp_dir, "p")
    
    -- Create package.json
    if package_content then
      vim.fn.writefile(vim.split(package_content, "\n"), temp_dir .. "/package.json")
    end
    
    -- Create config files
    if config_files then
      for filename, content in pairs(config_files) do
        vim.fn.writefile(vim.split(content, "\n"), temp_dir .. "/" .. filename)
      end
    end
    
    return temp_dir
  end
  
  local function cleanup_temp_dir(temp_dir)
    vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
  end
  
  describe("Framework Registry", function()
    it("should have complete framework registry", function()
      setup()
      
      local registry = framework_detector.get_framework_registry()
      
      assert.not_nil(registry.nextjs, "Should have Next.js in registry")
      assert.not_nil(registry.react, "Should have React in registry")
      assert.not_nil(registry.vue, "Should have Vue in registry")
      assert.not_nil(registry.vite, "Should have Vite in registry")
      assert.not_nil(registry.angular, "Should have Angular in registry")
      assert.not_nil(registry.svelte, "Should have Svelte in registry")
      
      -- Check registry structure
      local nextjs_config = registry.nextjs
      assert.equals(type(nextjs_config.name), "string", "Next.js should have name")
      assert.equals(type(nextjs_config.dependencies), "table", "Next.js should have dependencies")
      assert.equals(type(nextjs_config.config_files), "table", "Next.js should have config files")
      assert.equals(type(nextjs_config.file_patterns), "table", "Next.js should have file patterns")
      assert.equals(nextjs_config.injector, "nextjs", "Next.js should have correct injector")
    end)
  end)
  
  describe("Framework Discovery", function()
    it("should discover Next.js project", function()
      setup()
      
      local package_content = [[{
        "name": "nextjs-app",
        "dependencies": {
          "next": "^13.0.0",
          "react": "^18.0.0"
        }
      }]]
      
      local temp_dir = create_temp_project("nextjs", package_content)
      local detected = framework_detector.discover_all_frameworks(temp_dir)
      
      assert.not_nil(detected.nextjs, "Should detect Next.js")
      assert.equals(detected.nextjs.name, "Next.js", "Should have correct name")
      assert.equals(detected.nextjs.injector, "nextjs", "Should have correct injector")
      assert.is_true(#detected.nextjs.evidence.sources > 0, "Should have evidence sources")
      
      cleanup_temp_dir(temp_dir)
    end)
    
    it("should discover React project", function()
      setup()
      
      local package_content = [[{
        "name": "react-app",
        "dependencies": {
          "react": "^18.0.0",
          "react-dom": "^18.0.0"
        }
      }]]
      
      local temp_dir = create_temp_project("react", package_content)
      local detected = framework_detector.discover_all_frameworks(temp_dir)
      
      assert.not_nil(detected.react, "Should detect React")
      assert.equals(detected.react.name, "React", "Should have correct name")
      assert.equals(detected.react.injector, "react", "Should have correct injector")
      
      cleanup_temp_dir(temp_dir)
    end)
    
    it("should discover Vite project with React", function()
      setup()
      
      local package_content = [[{
        "name": "vite-react-app",
        "devDependencies": {
          "vite": "^4.0.0",
          "@vitejs/plugin-react": "^4.0.0"
        }
      }]]
      
      local temp_dir = create_temp_project("vite_react", package_content)
      local detected = framework_detector.discover_all_frameworks(temp_dir)
      
      assert.not_nil(detected.vite, "Should detect Vite")
      assert.equals(detected.vite.name, "Vite", "Should have correct name")
      assert.is_true(detected.vite.framework_detection, "Vite should support framework detection")
      
      -- Test underlying framework detection
      local underlying = framework_detector.detect_vite_underlying_framework(temp_dir)
      assert.equals(underlying, "React", "Should detect React as underlying framework")
      
      cleanup_temp_dir(temp_dir)
    end)
    
    it("should discover multiple frameworks in complex project", function()
      setup()
      
      local package_content = [[{
        "name": "complex-project",
        "dependencies": {
          "react": "^18.0.0",
          "vue": "^3.0.0"
        },
        "devDependencies": {
          "vite": "^4.0.0"
        }
      }]]
      
      local config_files = {
        ["vite.config.js"] = "import { defineConfig } from 'vite'"
      }
      
      local temp_dir = create_temp_project("complex", package_content, config_files)
      local detected = framework_detector.discover_all_frameworks(temp_dir)
      
      -- Should detect multiple frameworks
      assert.not_nil(detected.react, "Should detect React")
      assert.not_nil(detected.vue, "Should detect Vue")
      assert.not_nil(detected.vite, "Should detect Vite")
      
      cleanup_temp_dir(temp_dir)
    end)
    
    it("should return empty table for unknown project", function()
      setup()
      
      local package_content = [[{
        "name": "unknown-project",
        "dependencies": {
          "lodash": "^4.0.0"
        }
      }]]
      
      local temp_dir = create_temp_project("unknown", package_content)
      local detected = framework_detector.discover_all_frameworks(temp_dir)
      
      -- Should be empty or only contain node/unknown
      local detected_count = 0
      for _ in pairs(detected) do
        detected_count = detected_count + 1
      end
      
      assert.equals(detected_count, 0, "Should not detect any frameworks")
      
      cleanup_temp_dir(temp_dir)
    end)
  end)
  
  describe("Available Handlers", function()
    it("should return available handlers for detected frameworks", function()
      setup()
      
      local package_content = [[{
        "name": "multi-framework",
        "dependencies": {
          "next": "^13.0.0",
          "react": "^18.0.0"
        }
      }]]
      
      local temp_dir = create_temp_project("multi", package_content)
      local handlers = framework_detector.get_available_handlers(temp_dir)
      
      assert.is_true(#handlers >= 1, "Should have at least one handler")
      
      -- Check handler structure
      for _, handler in ipairs(handlers) do
        assert.not_nil(handler.framework, "Handler should have framework")
        assert.not_nil(handler.name, "Handler should have name")
        assert.not_nil(handler.injector, "Handler should have injector")
        assert.not_nil(handler.evidence, "Handler should have evidence")
      end
      
      cleanup_temp_dir(temp_dir)
    end)
  end)
  
  describe("Evidence Collection", function()
    it("should collect evidence from multiple sources", function()
      setup()
      
      local package_content = [[{
        "name": "evidence-test",
        "dependencies": {
          "react": "^18.0.0"
        },
        "devDependencies": {
          "vite": "^4.0.0"
        }
      }]]
      
      local config_files = {
        ["vite.config.js"] = "export default {}"
      }
      
      local temp_dir = create_temp_project("evidence", package_content, config_files)
      local detected = framework_detector.discover_all_frameworks(temp_dir)
      
      -- Check React evidence
      if detected.react then
        assert.is_true(#detected.react.evidence.sources > 0, "React should have evidence")
        assert.is_true(#detected.react.evidence.dependencies > 0, "React should have dependency evidence")
      end
      
      -- Check Vite evidence
      if detected.vite then
        assert.is_true(#detected.vite.evidence.sources > 0, "Vite should have evidence")
        assert.is_true(#detected.vite.evidence.dependencies > 0, "Vite should have dependency evidence")
        assert.is_true(#detected.vite.evidence.config_files > 0, "Vite should have config file evidence")
      end
      
      cleanup_temp_dir(temp_dir)
    end)
  end)
end)