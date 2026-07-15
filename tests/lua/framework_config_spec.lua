local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("Framework Configuration Tests", function()
  local framework_detector
  
  local function setup()
    framework_detector = require('consolelog.injection.framework_detector')
  end
  
  describe("Inspector support configuration", function()
    it("should NOT enable inspector for Next.js", function()
      setup()
      
      local config = framework_detector.get_framework_config(framework_detector.FRAMEWORKS.NEXTJS)
      assert.is_false(config.supports_inspector, "Next.js should NOT support inspector")
      assert.is_true(config.inject_client, "Next.js should support client injection")
    end)
    
    it("should NOT enable inspector for React", function()
      setup()
      
      local config = framework_detector.get_framework_config(framework_detector.FRAMEWORKS.REACT)
      assert.is_false(config.supports_inspector, "React should NOT support inspector")
      assert.is_true(config.inject_client, "React should support client injection")
    end)
    
    it("should NOT enable inspector for Vue", function()
      setup()
      
      local config = framework_detector.get_framework_config(framework_detector.FRAMEWORKS.VUE)
      assert.is_false(config.supports_inspector, "Vue should NOT support inspector")
      assert.is_true(config.inject_client, "Vue should support client injection")
    end)
    
    it("should NOT enable inspector for Vite", function()
      setup()
      
      local config = framework_detector.get_framework_config(framework_detector.FRAMEWORKS.VITE)
      assert.is_false(config.supports_inspector, "Vite should NOT support inspector")
      assert.is_true(config.inject_client, "Vite should support client injection")
    end)
    
    
    
    it("should NOT enable anything for unknown frameworks", function()
      setup()
      
      local config = framework_detector.get_framework_config(framework_detector.FRAMEWORKS.UNKNOWN)
      assert.is_false(config.supports_inspector, "Unknown should NOT support inspector")
      assert.is_false(config.inject_client, "Unknown should NOT support client injection")
    end)
  end)
  

  
  describe("React framework detection", function()
    it("should detect React from package.json dependencies", function()
      setup()
      
      local temp_dir = "/tmp/test_react_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "react-app",
        "dependencies": {
          "react": "^18.0.0",
          "react-dom": "^18.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.REACT, "Should detect React")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
    
    it("should detect React from devDependencies", function()
      setup()
      
      local temp_dir = "/tmp/test_react_dev_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "react-app",
        "devDependencies": {
          "react": "^18.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.REACT, "Should detect React from devDependencies")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
  end)
  
  describe("Vue framework detection", function()
    it("should detect Vue from package.json", function()
      setup()
      
      local temp_dir = "/tmp/test_vue_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "vue-app",
        "dependencies": {
          "vue": "^3.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.VUE, "Should detect Vue")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
    
    it("should detect Vite from vue plugin in vite config", function()
      setup()
      
      local temp_dir = "/tmp/test_vue_vite_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "vue-app"
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      vim.fn.writefile({ "import vue from '@vitejs/plugin-vue'" }, temp_dir .. "/vite.config.js")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.VITE, "Should detect Vite from vite config")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
  end)
  
  describe("Vite framework detection", function()
    it("should detect Vite from devDependencies", function()
      setup()
      
      local temp_dir = "/tmp/test_vite_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "vite-app",
        "devDependencies": {
          "vite": "^4.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.VITE, "Should detect Vite")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
    
    it("should detect Vite from config file", function()
      setup()
      
      local temp_dir = "/tmp/test_vite_config_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "vite-app"
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      vim.fn.writefile({ "export default {}" }, temp_dir .. "/vite.config.js")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.VITE, "Should detect Vite from config")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
  end)
  
  describe("Framework priority", function()
    it("should prioritize Next.js over React", function()
      setup()
      
      local temp_dir = "/tmp/test_nextjs_priority_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "nextjs-app",
        "dependencies": {
          "next": "^13.0.0",
          "react": "^18.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.NEXTJS, "Should return NEXTJS not REACT")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
    
    it("should detect Vite when Vue and Vite are both present", function()
      setup()
      
      local temp_dir = "/tmp/test_vue_vite_priority_" .. vim.fn.getpid()
      vim.fn.mkdir(temp_dir, "p")
      
      local package_json = [[{
        "name": "vue-vite-app",
        "dependencies": {
          "vue": "^3.0.0"
        },
        "devDependencies": {
          "vite": "^4.0.0"
        }
      }]]
      
      vim.fn.writefile(vim.split(package_json, "\n"), temp_dir .. "/package.json")
      
      local framework = framework_detector.detect_framework(temp_dir)
      assert.equals(framework, framework_detector.FRAMEWORKS.VITE, "Should return VITE when both Vue and Vite present")
      
      vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
    end)
  end)
end)