local M = {}
local debug_logger = require("consolelog.core.debug_logger")
local constants = require("consolelog.core.constants")

local NEXTJS_FILES = {
	"/node_modules/next/dist/client/index.js",
	"/node_modules/next/dist/client/app-index.js",
	"/node_modules/next/dist/esm/client/index.js",
}

local CPU_PROFILE_FILES = {
	"/node_modules/next/dist/server/lib/cpu-profile.js",
	"/node_modules/next/dist/esm/server/lib/cpu-profile.js",
}

local function find_search_roots(project_root)
	local search_roots = { project_root }
	local dir = project_root
	while dir ~= "/" do
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then break end

		local parent_package = parent .. "/package.json"
		if vim.fn.filereadable(parent_package) == 1 then
			local content = table.concat(vim.fn.readfile(parent_package), "\n")
			if content:match('"workspaces"') then
				table.insert(search_roots, parent)
				debug_logger.log("NEXTJS_PATCH", string.format("Found monorepo root: %s", parent))
				break
			end
		end
		dir = parent
	end
	return search_roots
end

local function patch_cpu_profile(project_root, plugin_dir, ws_port)
	local auto_injector_path = plugin_dir .. "js/nextjs-auto-injector.js"
	local inject_client_path = plugin_dir .. "js/inject-client.js"
	local sourcemap_resolver_path = plugin_dir .. "js/sourcemap-resolver.js"

	if vim.fn.filereadable(auto_injector_path) ~= 1 then
		debug_logger.log("NEXTJS_PATCH", "nextjs-auto-injector.js not found")
		return false
	end

	if vim.fn.filereadable(inject_client_path) ~= 1 then
		debug_logger.log("NEXTJS_PATCH", "inject-client.js not found")
		return false
	end

	if vim.fn.filereadable(sourcemap_resolver_path) ~= 1 then
		debug_logger.log("NEXTJS_PATCH", "sourcemap-resolver.js not found")
		return false
	end

	local auto_injector_template = table.concat(vim.fn.readfile(auto_injector_path), "\n")
	local inject_client_code = table.concat(vim.fn.readfile(inject_client_path), "\n")
	local sourcemap_resolver_code = table.concat(vim.fn.readfile(sourcemap_resolver_path), "\n")
	local combined_client_code = sourcemap_resolver_code .. "\n\n" .. inject_client_code

	local project_id = vim.fn.fnamemodify(project_root, ":t")

	local search_roots = find_search_roots(project_root)
	for _, root in ipairs(search_roots) do
		local next_dir = root .. "/node_modules/next"
		if vim.fn.isdirectory(next_dir) == 1 then
			local temp_client_path = next_dir .. "/.consolelog-client-inject.js"
			vim.fn.writefile(vim.split(combined_client_code, "\n"), temp_client_path)
			debug_logger.log("NEXTJS_PATCH", string.format("Wrote combined client code to: %s", temp_client_path))
			break
		end
	end

	local auto_injector_code = auto_injector_template
	    :gsub("__WS_PORT__", tostring(ws_port))
	    :gsub("__PROJECT_ID__", project_id)

	local search_roots = find_search_roots(project_root)
	local patched_count = 0

	for _, cpu_file in ipairs(CPU_PROFILE_FILES) do
		for _, root in ipairs(search_roots) do
			local filepath = root .. cpu_file
			if vim.fn.filereadable(filepath) == 1 then
				local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX

				if vim.fn.filereadable(backup_path) ~= 1 then
					local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
					if success ~= 0 then
						debug_logger.log("NEXTJS_PATCH",
							string.format("Failed to backup: %s", filepath))
						break
					end
					debug_logger.log("NEXTJS_PATCH", string.format("Created backup: %s", backup_path))
				end

				local content = table.concat(vim.fn.readfile(filepath), "\n")
				if not content:match("ConsoleLog%.nvim auto%-injection") then
					local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
					if success ~= 0 then
						debug_logger.log("NEXTJS_PATCH", string.format("Failed to refresh backup: %s", backup_path))
						break
					end
				end

				if content:match("ConsoleLog%.nvim auto%-injection") then
					content = table.concat(vim.fn.readfile(backup_path), "\n")
				end

				local injection = "\n" .. auto_injector_code

				content = content .. injection

				local success = vim.fn.writefile(vim.split(content, "\n"), filepath)
				if success == 0 then
					patched_count = patched_count + 1
					debug_logger.log("NEXTJS_PATCH", string.format("Patched cpu-profile: %s", filepath))
				else
					debug_logger.log("NEXTJS_PATCH", string.format("Failed to patch cpu-profile: %s", filepath))
				end
				break
			end
		end
	end

	return patched_count > 0
end

local function unpatch_cpu_profile(project_root)
	local search_roots = find_search_roots(project_root)
	local unpatched_count = 0

	for _, cpu_file in ipairs(CPU_PROFILE_FILES) do
		for _, root in ipairs(search_roots) do
			local filepath = root .. cpu_file
			local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX

			if vim.fn.filereadable(backup_path) == 1 then
				local has_injection = vim.fn.filereadable(filepath) ~= 1
				    or table.concat(vim.fn.readfile(filepath), "\n"):find("window.__CONSOLELOG_WS_PORT", 1, true)
				if not has_injection then
					vim.fn.delete(backup_path)
					break
				end
				local success = vim.fn.writefile(vim.fn.readfile(backup_path, "b"), filepath, "b")
				if success == 0 then
					unpatched_count = unpatched_count + 1
					debug_logger.log("NEXTJS_PATCH",
						string.format("Restored cpu-profile: %s", filepath))
					vim.fn.delete(backup_path)
					debug_logger.log("NEXTJS_PATCH", string.format("Deleted backup: %s", backup_path))
				end
				break
			end
		end
	end

	return unpatched_count > 0
end

function M.detect(project_root)
	local package_json = project_root .. "/package.json"
	if vim.fn.filereadable(package_json) == 1 then
		local content = table.concat(vim.fn.readfile(package_json), "\n")
		return content:match('"next"') ~= nil
	end
	return false
end

function M.should_skip_sourcemap_resolver()
	-- Temporarily include sourcemap resolver to test line number accuracy
	-- The optimization was causing incorrect line numbers
	debug_logger.log("NEXTJS_PATCH", "Next.js detected - including sourcemap resolver (testing line accuracy)")
	return false
end

function M.is_patched(project_root)
	local search_roots = find_search_roots(project_root)
	local patched_files = 0

	for _, file in ipairs(NEXTJS_FILES) do
		for _, root in ipairs(search_roots) do
			local filepath = root .. file
			if vim.fn.filereadable(filepath) == 1 then
				local content = table.concat(vim.fn.readfile(filepath), "\n")

				-- Check for ConsoleLog injection markers
				if content:match("window%.__CONSOLELOG_WS_PORT") and
				    content:match("ConsoleLog%.nvim auto%-injection") then
					patched_files = patched_files + 1
					debug_logger.log("NEXTJS_PATCH",
						string.format("Found patched file: %s", filepath))
				end
				break
			end
		end
	end

	return patched_files > 0, patched_files
end

function M.patch(project_root, ws_port)
	debug_logger.log("NEXTJS_PATCH", string.format("Patching Next.js for port %d", ws_port))

	local search_roots = find_search_roots(project_root)
	local patched = false
	local project_id = vim.fn.fnamemodify(project_root, ":t")

	local current_file = debug.getinfo(1, "S").source:sub(2)
	local plugin_dir = vim.fn.fnamemodify(current_file, ":p"):match("(.*[/\\]consolelog%.nvim[/\\])")
	if not plugin_dir then
		plugin_dir = vim.fn.fnamemodify(current_file, ":p:h:h:h:h:h")
		debug_logger.log("NEXTJS_PATCH", string.format("Using fallback plugin directory: %s", plugin_dir))

		if not plugin_dir or plugin_dir == "" then
			debug_logger.log("NEXTJS_PATCH", "ERROR: Could not determine plugin directory")
			vim.notify("ConsoleLog: Failed to determine plugin directory", vim.log.levels.ERROR)
			return false
		end
	end

	local inject_script_path = plugin_dir .. "js/inject-client.js"
	local sourcemap_script_path = plugin_dir .. "js/sourcemap-resolver.js"

	if vim.fn.filereadable(inject_script_path) ~= 1 then
		debug_logger.log("NEXTJS_PATCH", "ERROR: inject-client.js not found at: " .. inject_script_path)
		vim.notify("ConsoleLog: Failed to patch - inject script not found", vim.log.levels.ERROR)
		return false
	end

	local inject_content = table.concat(vim.fn.readfile(inject_script_path), "\n")

	local sourcemap_content = ""
	local should_skip = M.should_skip_sourcemap_resolver()
	
	if should_skip then
		debug_logger.log("NEXTJS_PATCH", "Skipping sourcemap resolver for Next.js 14.2.33+ (dev mode provides perfect sourcemaps)")
		sourcemap_content = ""
	elseif vim.fn.filereadable(sourcemap_script_path) == 1 then
		sourcemap_content = table.concat(vim.fn.readfile(sourcemap_script_path), "\n")
		debug_logger.log("NEXTJS_PATCH", "Including source map resolver")
	else
		debug_logger.log("NEXTJS_PATCH", "Source map resolver not found, skipping")
	end

	local inject_script = constants.INJECTION.START_MARKER .. "\n" .. string.format([[
%s
  window.__CONSOLELOG_WS_PORT = %d;
  window.__CONSOLELOG_PROJECT_ID = '%s';
  window.__CONSOLELOG_FRAMEWORK = 'Next.js';
  window.__CONSOLELOG_DEBUG = false;
  %s
  %s
}
]], constants.INJECTION.BROWSER_GUARD, ws_port, project_id, sourcemap_content, inject_content) .. constants.INJECTION.END_MARKER

	for _, file in ipairs(NEXTJS_FILES) do
		local found_file = false
		for _, root in ipairs(search_roots) do
			local filepath = root .. file
			if vim.fn.filereadable(filepath) == 1 then
				found_file = true
				local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX

				if vim.fn.filereadable(backup_path) ~= 1 then
					local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
					if success == 0 then
						debug_logger.log("NEXTJS_PATCH",
							string.format("Created backup: %s", backup_path))
					else
						debug_logger.log("NEXTJS_PATCH",
							string.format("Failed to create backup: %s", backup_path))
						break
					end
				else
					debug_logger.log("NEXTJS_PATCH", string.format("Backup exists: %s", backup_path))
				end

				local content = table.concat(vim.fn.readfile(filepath), "\n")
				if not content:find("window.__CONSOLELOG_WS_PORT", 1, true) then
					local success = vim.fn.writefile(vim.fn.readfile(filepath, "b"), backup_path, "b")
					if success ~= 0 then
						debug_logger.log("NEXTJS_PATCH", string.format("Failed to refresh backup: %s", backup_path))
						break
					end
				end
				if not content:find(constants.INJECTION.START_MARKER, 1, true)
				    and content:find("window.__CONSOLELOG_WS_PORT", 1, true) then
					content = table.concat(vim.fn.readfile(backup_path), "\n")
				end

				if content:find(constants.INJECTION.START_MARKER, 1, true) then
					content = content:gsub(constants.INJECTION.BLOCK_PATTERN, "", 1)
					debug_logger.log("NEXTJS_PATCH",
						string.format("Removed old injection from %s", filepath))
				end

				local pattern = "if %(typeof window !== 'undefined'%)"
				local replacement = inject_script .. "\n" .. pattern

				if content:match(pattern) then
					content = content:gsub(pattern, replacement, 1)
				else
					if content:match("^'use client'") then
						content = content:gsub("('use client'.-\n)",
							"%1\n" .. inject_script .. "\n")
					else
						content = inject_script .. "\n" .. content
					end
				end

				vim.fn.writefile(vim.split(content, "\n"), filepath)
				patched = true
				debug_logger.log("NEXTJS_PATCH", string.format("Patched %s in %s", file, root))
				break
			end
		end
		if not found_file then
			debug_logger.log("NEXTJS_PATCH", string.format("File not found in any search root: %s", file))
		end
	end

	local cpu_patched = patch_cpu_profile(project_root, plugin_dir, ws_port)
	if cpu_patched then
		patched = true
		debug_logger.log("NEXTJS_PATCH", "Installed auto-patcher in cpu-profile.js")
	end

	if patched then
		vim.notify("ConsoleLog: Next.js patched with auto-patcher. Run 'npm run dev' to start.",
			vim.log.levels.INFO)
	end

	return patched
end

function M.unpatch(project_root)
	debug_logger.log("NEXTJS_PATCH", "Removing Next.js patches")

	local search_roots = find_search_roots(project_root)
	local unpatched_count = 0

	unpatch_cpu_profile(project_root)

	for _, file in ipairs(NEXTJS_FILES) do
		for _, root in ipairs(search_roots) do
			local filepath = root .. file
			local backup_path = filepath .. constants.FILES.BACKUP_SUFFIX

			if vim.fn.filereadable(backup_path) == 1 then
				local success = vim.fn.writefile(vim.fn.readfile(backup_path, "b"), filepath, "b")
				if success == 0 then
					unpatched_count = unpatched_count + 1
					debug_logger.log("NEXTJS_PATCH",
						string.format("Restored from backup: %s", filepath))

					vim.fn.delete(backup_path)
					debug_logger.log("NEXTJS_PATCH", string.format("Deleted backup: %s", backup_path))
				else
					debug_logger.log("NEXTJS_PATCH",
						string.format("Failed to restore from backup: %s", filepath))
				end
				break
			elseif vim.fn.filereadable(filepath) == 1 then
				local content = table.concat(vim.fn.readfile(filepath), "\n")
				local restored, removed = content:gsub(constants.INJECTION.BLOCK_PATTERN, "", 1)
				if removed > 0 and vim.fn.writefile(vim.split(restored, "\n"), filepath) == 0 then
					unpatched_count = unpatched_count + 1
				end
				break
			else
				debug_logger.log("NEXTJS_PATCH", string.format("No backup found for: %s", filepath))
			end
		end
	end

	if unpatched_count > 0 then
		debug_logger.log("NEXTJS_PATCH",
			string.format("Successfully unpatched %d Next.js file(s)", unpatched_count))
	else
		debug_logger.log("NEXTJS_PATCH", "No Next.js patches found to remove")
	end
end

return M
