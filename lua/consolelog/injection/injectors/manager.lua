local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local framework_detector = require("consolelog.injection.framework_detector")
local port_manager = require("consolelog.communication.port_manager")

-- Load all framework injectors
local injectors = {
  nextjs = require("consolelog.injection.injectors.nextjs"),
  vite = require("consolelog.injection.injectors.vite"),
  react = require("consolelog.injection.injectors.react"),
  vue = require("consolelog.injection.injectors.vue"),
}

-- Detect which framework is being used
function M.detect_framework(project_root)
  local framework = framework_detector.detect_framework(project_root)
  
  if framework == framework_detector.FRAMEWORKS.UNKNOWN then
    return nil, nil
  end
  
  local injector = injectors[framework]
  if injector then
    debug_logger.log("INJECTOR", string.format("Detected %s project", framework))
    return framework, injector
  end
  
  return nil, nil
end

-- Detect framework using consistent project root detection
function M.detect_framework_for_current_file()
  local project_root = port_manager.find_project_root()
  if not project_root then
    debug_logger.log("INJECTOR", "No project root found")
    return nil, nil
  end
  
  return M.detect_framework(project_root)
end

-- Patch the detected framework
function M.patch(project_root, ws_port)
  local framework, injector = M.detect_framework(project_root)
  
  if not framework then
    debug_logger.log("INJECTOR", "No supported framework detected")
    return false, nil
  end
  
  local success = injector.patch(project_root, ws_port)
  
  if success then
    debug_logger.log("INJECTOR", string.format("Successfully patched %s", framework))
  else
    debug_logger.log("INJECTOR", string.format("Failed to patch %s", framework))
  end
  
  return success, framework
end

-- Unpatch the framework
function M.unpatch(project_root)
  local framework, injector = M.detect_framework(project_root)
  
  if framework and injector.unpatch then
    injector.unpatch(project_root)
    debug_logger.log("INJECTOR", string.format("Unpatched %s", framework))
  end
end

-- Check if project is a supported browser framework  
function M.is_browser_project(project_root)
  return framework_detector.is_browser_project(project_root)
end

return M