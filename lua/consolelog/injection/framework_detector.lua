local M = {}

local debug_logger = require("consolelog.core.debug_logger")

M.FRAMEWORKS = {
	NEXTJS = "nextjs",
	REACT = "react",
	VUE = "vue",
	VITE = "vite",
	ANGULAR = "angular",
	SVELTE = "svelte",
	NODE = "node",
	UNKNOWN = "unknown"
}

-- Framework registry with detection patterns
local FRAMEWORK_REGISTRY = {
	nextjs = {
		name = "Next.js",
		dependencies = {"next"},
		config_files = {"next.config.js", "next.config.mjs", "next.config.ts"},
		file_patterns = {
			"/node_modules/next/dist/client/index.js",
			"/node_modules/next/dist/client/app-index.js",
			"/node_modules/next/dist/esm/client/index.js",
			"/node_modules/next/dist/server/lib/cpu-profile.js",
			"/node_modules/next/dist/esm/server/lib/cpu-profile.js"
		},
		injector = "nextjs"
	},
	
	react = {
		name = "React",
		dependencies = {"react", "react-dom"},
		config_files = {"webpack.config.js", "craco.config.js"},
		file_patterns = {
			"/node_modules/react-dom/index.js",
			"/node_modules/react-dom/client.js",
			"/node_modules/react-scripts/config/webpack.config.js",
			"/node_modules/@vitejs/plugin-react/dist/index.js"
		},
		injector = "react"
	},
	
	vue = {
		name = "Vue",
		dependencies = {"vue", "@vue/core"},
		config_files = {"vue.config.js"},
		file_patterns = {
			"/node_modules/vue/dist/vue.runtime.esm-browser.js",
			"/node_modules/vue/dist/vue.esm-browser.js",
			"/node_modules/@vue/runtime-dom/dist/runtime-dom.esm-bundler.js",
			"/node_modules/@vitejs/plugin-vue/dist/index.js"
		},
		injector = "vue"
	},
	
	vite = {
		name = "Vite",
		dependencies = {"vite"},
		config_files = {"vite.config.js", "vite.config.ts"},
		file_patterns = {
			"/node_modules/vite/dist/client/client.mjs",
			"/node_modules/vite/dist/client/env.mjs"
		},
		injector = "vite",
		framework_detection = true -- Can detect underlying framework
	},
	
	angular = {
		name = "Angular",
		dependencies = {"@angular/core", "@angular/common"},
		config_files = {"angular.json"},
		file_patterns = {"angular.json"},
		injector = "angular"
	},
	
	svelte = {
		name = "Svelte",
		dependencies = {"svelte"},
		config_files = {"svelte.config.js", "rollup.config.js"},
		file_patterns = {
			"/node_modules/svelte",
			"/node_modules/@sveltejs/kit",
			"/node_modules/@sveltejs/vite-plugin-svelte"
		},
		injector = "svelte"
	}
}

function M.read_package_json(project_root)
	local package_json = project_root .. "/package.json"
	if vim.fn.filereadable(package_json) ~= 1 then
		return nil
	end

	local content = table.concat(vim.fn.readfile(package_json), "\n")
	local ok, parsed = pcall(vim.json.decode, content)
	if not ok then
		debug_logger.log("FRAMEWORK_DETECTOR", "Failed to parse package.json")
		return nil
	end

	return parsed
end

function M.get_all_dependencies(package)
	local deps = {}

	if package.dependencies then
		for dep, _ in pairs(package.dependencies) do
			deps[dep] = true
		end
	end

	if package.devDependencies then
		for dep, _ in pairs(package.devDependencies) do
			deps[dep] = true
		end
	end

	return deps
end

function M.detect_framework_from_deps(deps)
	-- Check for specific frameworks first (more specific before generic)
	-- Specific frameworks take priority over generic build tools
	if deps["next"] then
		return M.FRAMEWORKS.NEXTJS
	elseif deps["@angular/core"] then
		return M.FRAMEWORKS.ANGULAR
	-- Specific frameworks take priority over Vite
	elseif deps["vue"] then
		return M.FRAMEWORKS.VUE
	elseif deps["svelte"] then
		return M.FRAMEWORKS.SVELTE
	elseif (deps["react"] or deps["react-dom"]) then
		return M.FRAMEWORKS.REACT
	-- Fall back to generic build tools if no specific framework found
	elseif deps["vite"] then
		return M.FRAMEWORKS.VITE
	end

	return M.FRAMEWORKS.NODE
end

function M.detect_framework(project_root)
	local package = M.read_package_json(project_root)
	if not package then
		return M.FRAMEWORKS.UNKNOWN
	end

	local deps = M.get_all_dependencies(package)
	local framework = M.detect_framework_from_deps(deps)

	if framework ~= M.FRAMEWORKS.UNKNOWN then
		debug_logger.log("FRAMEWORK_DETECTOR", string.format("Detected %s in main package.json", framework))
		return framework
	end

	-- If no framework found in main package.json, check for monorepo workspaces
	if package.workspaces then
		debug_logger.log("FRAMEWORK_DETECTOR", "Checking monorepo workspaces")
		framework = M.detect_in_workspaces(project_root, package.workspaces)
		if framework ~= M.FRAMEWORKS.UNKNOWN then
			debug_logger.log("FRAMEWORK_DETECTOR", string.format("Detected %s in workspace", framework))
			return framework
		end
	end

	-- Fallback: check for framework-specific config files
	framework = M.detect_by_config_files(project_root)
	if framework ~= M.FRAMEWORKS.UNKNOWN then
		debug_logger.log("FRAMEWORK_DETECTOR", string.format("Detected %s via config file", framework))
		return framework
	end

	-- If we have a package.json but no specific framework detected, it's a Node.js project
	return M.FRAMEWORKS.NODE
end

function M.is_browser_project(project_root)
	local framework = M.detect_framework(project_root)
	return framework ~= M.FRAMEWORKS.UNKNOWN
end

function M.get_framework_config(framework)
	local configs = {
		[M.FRAMEWORKS.NEXTJS] = {
			name = "Next.js",
			dev_server_files = { ".next/server.js", ".next/static" },
			config_files = { "next.config.js", "next.config.mjs" },
			inject_client = true,
			supports_inspector = false
		},
		[M.FRAMEWORKS.REACT] = {
			name = "React",
			dev_server_files = { "node_modules/react-dom", "node_modules/react-scripts" },
			config_files = { "webpack.config.js", "craco.config.js" },
			inject_client = true,
			supports_inspector = false
		},
		[M.FRAMEWORKS.VUE] = {
			name = "Vue",
			dev_server_files = { "node_modules/vue", "node_modules/@vue" },
			config_files = { "vue.config.js" },
			inject_client = true,
			supports_inspector = false
		},
		[M.FRAMEWORKS.VITE] = {
			name = "Vite",
			dev_server_files = { "node_modules/vite" },
			config_files = { "vite.config.js", "vite.config.ts" },
			inject_client = true,
			supports_inspector = false
		},
		[M.FRAMEWORKS.ANGULAR] = {
			name = "Angular",
			dev_server_files = { "angular.json" },
			config_files = { "angular.json" },
			inject_client = true,
			supports_inspector = false
		},
		[M.FRAMEWORKS.SVELTE] = {
			name = "Svelte",
			dev_server_files = { "node_modules/svelte" },
			config_files = { "svelte.config.js", "rollup.config.js" },
			inject_client = true,
			supports_inspector = false
		},
		[M.FRAMEWORKS.NODE] = {
			name = "Node.js",
			dev_server_files = {},
			config_files = {},
			inject_client = false,
			supports_inspector = false
		},
		[M.FRAMEWORKS.UNKNOWN] = {
			name = "Unknown",
			dev_server_files = {},
			config_files = {},
			inject_client = false,
			supports_inspector = false
		}
	}

	return configs[framework] or configs[M.FRAMEWORKS.UNKNOWN]
end

function M.detect_in_workspaces(project_root, workspaces)
	local workspace_dirs = {}

	-- Handle different workspace formats
	if type(workspaces) == "table" then
		for _, workspace in ipairs(workspaces) do
			if type(workspace) == "string" then
				table.insert(workspace_dirs, workspace)
			elseif type(workspace) == "table" and workspace.path then
				table.insert(workspace_dirs, workspace.path)
			end
		end
	elseif type(workspaces) == "string" then
		table.insert(workspace_dirs, workspaces)
	end

	-- Check each workspace directory for framework dependencies
	for _, workspace_dir in ipairs(workspace_dirs) do
		local workspace_path = project_root .. "/" .. workspace_dir

		-- Handle glob patterns in workspaces (e.g., "packages/*")
		if workspace_dir:match("%*") then
			local expanded_dirs = vim.fn.glob(project_root .. "/" .. workspace_dir, false, true)
			for _, expanded_path in ipairs(expanded_dirs) do
				if vim.fn.isdirectory(expanded_path) == 1 then
					local framework = M.check_workspace_for_framework(expanded_path)
					if framework ~= M.FRAMEWORKS.UNKNOWN then
						return framework
					end
				end
			end
		else
			local framework = M.check_workspace_for_framework(workspace_path)
			if framework ~= M.FRAMEWORKS.UNKNOWN then
				return framework
			end
		end
	end

	return M.FRAMEWORKS.UNKNOWN
end

function M.check_workspace_for_framework(workspace_path)
	local package = M.read_package_json(workspace_path)
	if not package then
		return M.FRAMEWORKS.UNKNOWN
	end

	local deps = M.get_all_dependencies(package)
	return M.detect_framework_from_deps(deps)
end

function M.detect_by_config_files(project_root)
	-- Check for framework-specific config files as last resort
	local config_files = {
		{ "next.config.js",   M.FRAMEWORKS.NEXTJS },
		{ "next.config.mjs",  M.FRAMEWORKS.NEXTJS },
		{ "next.config.ts",   M.FRAMEWORKS.NEXTJS },
		{ "angular.json",     M.FRAMEWORKS.ANGULAR },
		{ "vue.config.js",    M.FRAMEWORKS.VUE },
		{ "svelte.config.js", M.FRAMEWORKS.SVELTE }
	}

	-- Check non-vite configs first
	for _, config in ipairs(config_files) do
		if vim.fn.filereadable(project_root .. "/" .. config[1]) == 1 then
			return config[2]
		end
	end

	-- Check vite configs separately to analyze content
	local vite_configs = { "vite.config.js", "vite.config.ts" }
	for _, config_file in ipairs(vite_configs) do
		local config_path = project_root .. "/" .. config_file
		if vim.fn.filereadable(config_path) == 1 then
			-- Read config content to detect specific frameworks
			local content = table.concat(vim.fn.readfile(config_path), "\n")
			
			-- Check for Vue plugin
			if content:match("@vitejs/plugin%-vue") or content:match("vue%(") then
				return M.FRAMEWORKS.VUE
			-- Check for Svelte plugin  
			elseif content:match("@sveltejs/kit") or content:match("svelte%(") then
				return M.FRAMEWORKS.SVELTE
			-- Check for React plugin
			elseif content:match("@vitejs/plugin%-react") or content:match("react%(") then
				return M.FRAMEWORKS.REACT
			end
			
			-- Default to Vite if no specific framework detected
			return M.FRAMEWORKS.VITE
		end
	end

	return M.FRAMEWORKS.NODE
end

-- ============================================================================
-- UNIFIED FRAMEWORK DISCOVERY SYSTEM
-- ============================================================================

-- Helper function to check if file exists
local function file_exists(filepath)
	return vim.fn.filereadable(filepath) == 1
end

-- Helper function to check if directory exists
local function directory_exists(dirpath)
	return vim.fn.isdirectory(dirpath) == 1
end

-- Helper function to add evidence
local function add_evidence(evidence, framework, source_type, source_value)
	if not evidence[framework] then
		evidence[framework] = {
			dependencies = {},
			config_files = {},
			file_patterns = {},
			sources = {}
		}
	end
	
	local framework_evidence = evidence[framework]
	table.insert(framework_evidence.sources, source_type .. ":" .. source_value)
	
	if source_type == "package.json" then
		table.insert(framework_evidence.dependencies, source_value)
	elseif source_type == "config_file" then
		table.insert(framework_evidence.config_files, source_value)
	elseif source_type == "file_system" then
		table.insert(framework_evidence.file_patterns, source_value)
	end
end

-- Collect evidence for all frameworks in a project
local function collect_framework_evidence(project_root)
	local evidence = {}
	
	-- Check each framework in registry
	for framework_id, config in pairs(FRAMEWORK_REGISTRY) do
		-- Check dependencies in package.json
		local package = M.read_package_json(project_root)
		if package then
			local deps = M.get_all_dependencies(package)
			for _, dep in ipairs(config.dependencies) do
				if deps[dep] then
					add_evidence(evidence, framework_id, "package.json", dep)
				end
			end
		end
		
		-- Check config files
		for _, config_file in ipairs(config.config_files) do
			if file_exists(project_root .. "/" .. config_file) then
				add_evidence(evidence, framework_id, "config_file", config_file)
			end
		end
		
		-- Check file patterns
		for _, pattern in ipairs(config.file_patterns) do
			if file_exists(project_root .. pattern) then
				add_evidence(evidence, framework_id, "file_system", pattern)
			elseif directory_exists(project_root .. pattern) then
				add_evidence(evidence, framework_id, "file_system", pattern)
			end
		end
	end
	
	return evidence
end

-- Discover all frameworks present in a project
function M.discover_all_frameworks(project_root)
	local evidence = collect_framework_evidence(project_root)
	local detected = {}
	
	for framework_id, framework_evidence in pairs(evidence) do
		if #framework_evidence.sources > 0 then
			local config = FRAMEWORK_REGISTRY[framework_id]
			detected[framework_id] = {
				name = config.name,
				injector = config.injector,
				evidence = framework_evidence,
				framework_detection = config.framework_detection
			}
			
			debug_logger.log("FRAMEWORK_DISCOVERY", 
				string.format("Found %s: %s", framework_id, table.concat(framework_evidence.sources, ", ")))
		end
	end
	
	return detected
end

-- Get available handlers for detected frameworks
function M.get_available_handlers(project_root)
	local detected = M.discover_all_frameworks(project_root)
	local handlers = {}
	
	for framework_id, info in pairs(detected) do
		table.insert(handlers, {
			framework = framework_id,
			name = info.name,
			injector = info.injector,
			evidence = info.evidence,
			framework_detection = info.framework_detection
		})
	end
	
	return handlers
end

-- Get framework registry information
function M.get_framework_registry()
	return FRAMEWORK_REGISTRY
end

-- Enhanced Vite framework detection (for Vite's underlying framework)
function M.detect_vite_underlying_framework(project_root)
	local package = M.read_package_json(project_root)
	if not package then
		return "Vanilla"
	end
	
	local deps = M.get_all_dependencies(package)
	
	if deps["react"] or deps["@vitejs/plugin-react"] then
		return "React"
	elseif deps["vue"] or deps["@vitejs/plugin-vue"] then
		return "Vue"
	elseif deps["svelte"] or deps["@sveltejs/kit"] or deps["@sveltejs/vite-plugin-svelte"] then
		return "Svelte"
	elseif deps["preact"] or deps["@vitejs/plugin-preact"] or deps["@preact/preset-vite"] then
		return "Preact"
	elseif deps["@vitejs/plugin-lit"] or deps["lit"] then
		return "Lit"
	else
		return "Vanilla"
	end
end

return M

