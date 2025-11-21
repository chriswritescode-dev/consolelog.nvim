local M = {}

local debug_logger = require("consolelog.core.debug_logger")

M.FRAMEWORKS = {
	NEXTJS = "nextjs",
	REACT = "react",
	VUE = "vue",
	VITE = "vite",
	ANGULAR = "angular",
	SVELTE = "svelte",
	UNKNOWN = "unknown"
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
	-- Vite takes priority over individual frameworks as it handles all of them
	if deps["next"] then
		return M.FRAMEWORKS.NEXTJS
	elseif deps["vite"] then
		return M.FRAMEWORKS.VITE
	elseif deps["@angular/core"] then
		return M.FRAMEWORKS.ANGULAR
	-- Note: Vue, Svelte, React are now handled under Vite if Vite is present
	elseif deps["vue"] and not deps["vite"] then
		return M.FRAMEWORKS.VUE
	elseif deps["svelte"] and not deps["vite"] then
		return M.FRAMEWORKS.SVELTE
	elseif (deps["react"] or deps["react-dom"]) and not deps["vite"] then
		return M.FRAMEWORKS.REACT
	end

	return M.FRAMEWORKS.UNKNOWN
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

	return M.FRAMEWORKS.UNKNOWN
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
		{ "vite.config.js",   M.FRAMEWORKS.VITE },
		{ "vite.config.ts",   M.FRAMEWORKS.VITE },
		{ "angular.json",     M.FRAMEWORKS.ANGULAR },
		{ "vue.config.js",    M.FRAMEWORKS.VUE },
		{ "svelte.config.js", M.FRAMEWORKS.SVELTE }
	}

	for _, config in ipairs(config_files) do
		if vim.fn.filereadable(project_root .. "/" .. config[1]) == 1 then
			return config[2]
		end
	end

	return M.FRAMEWORKS.UNKNOWN
end

return M

