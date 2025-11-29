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

-- Detect which framework is being used (backward compatibility)
function M.detect_framework(project_root)
  local handlers = framework_detector.get_available_handlers(project_root)
  
  if #handlers == 0 then
    return nil, nil
  end
  
  -- Return first detected framework for compatibility
  local handler = handlers[1]
  local injector = injectors[handler.injector]
  
  if injector then
    debug_logger.log("INJECTOR", string.format("Detected %s project", handler.framework))
    return handler.framework, injector
  end
  
  return nil, nil
end

-- Get all available injectors for a project
function M.get_available_injectors(project_root)
  local handlers = framework_detector.get_available_handlers(project_root)
  local available_injectors = {}
  
  for _, handler in ipairs(handlers) do
    local injector_module = injectors[handler.injector]
    if injector_module then
      table.insert(available_injectors, {
        framework = handler.framework,
        name = handler.name,
        injector = handler.injector,
        module = injector_module,
        evidence = handler.evidence,
        framework_detection = handler.framework_detection
      })
    end
  end
  
  return available_injectors
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

-- Patch all detected frameworks
function M.patch_all(project_root, ws_port)
  local available_injectors = M.get_available_injectors(project_root)
  local results = {}
  
  if #available_injectors == 0 then
    debug_logger.log("INJECTOR", "No supported frameworks detected")
    return results
  end
  
  for _, injector_info in ipairs(available_injectors) do
    local success = injector_info.module.patch(project_root, ws_port)
    table.insert(results, {
      framework = injector_info.framework,
      name = injector_info.name,
      success = success,
      evidence = injector_info.evidence
    })
    
    if success then
      debug_logger.log("INJECTOR", string.format("Successfully patched %s", injector_info.framework))
    else
      debug_logger.log("INJECTOR", string.format("Failed to patch %s", injector_info.framework))
    end
  end
  
  return results
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