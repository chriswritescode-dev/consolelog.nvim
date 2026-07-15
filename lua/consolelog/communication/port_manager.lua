local M = {}

local uv = vim.loop
local constants = require("consolelog.core.constants")

-- Port range for ConsoleLog instances
M.PORT_RANGE_START = constants.PORTS.MIN
M.PORT_RANGE_END = constants.PORTS.MAX

-- Standard Neovim data directory for persistent registry
local function get_registry_dir()
	local registry_dir = vim.fn.stdpath("data") .. "/consolelog"
	vim.fn.mkdir(registry_dir, "p")
	return registry_dir
end

-- Standard Neovim state directory for locks and temp files
local function get_state_dir()
	local state_dir = vim.fn.stdpath("state") .. "/consolelog"
	vim.fn.mkdir(state_dir, "p")
	return state_dir
end

-- Track allocated ports by project
M.allocated_ports = {} -- { project_path = { ws_port = X, tcp_port = Y } }
M.port_files = {}      -- Track port files for cleanup
M.port_locks = {}      -- Track active port locks

-- Check if port is actually in use by any process
local function is_port_in_use(port)
	-- Method 1: Try lsof (most reliable on macOS/Linux)
	local handle = io.popen(string.format("lsof -i :%d 2>/dev/null | grep LISTEN", port))
	local result = handle:read("*a")
	handle:close()
	
	if result and result:match("LISTEN") then
		return true
	end
	
	-- Method 2: Try netstat as fallback
	handle = io.popen(string.format("netstat -an | grep ':%d.*LISTEN' 2>/dev/null", port))
	result = handle:read("*a")
	handle:close()
	
	if result and result:match("LISTEN") then
		return true
	end
	
	-- Method 3: Final bind test (catches edge cases)
	local tcp = uv.new_tcp()
	local can_bind = pcall(function()
		tcp:bind("127.0.0.1", port)
	end)
	tcp:close()
	
	return not can_bind
end

-- Get a free port in the range with robust detection
local function find_free_port(start_port, end_port, exclude_ports)
	exclude_ports = exclude_ports or {}

	for port = start_port, end_port do
		-- Skip if in exclude list
		local excluded = false
		for _, excluded_port in ipairs(exclude_ports) do
			if port == excluded_port then
				excluded = true
				break
			end
		end

		if not excluded then
			-- First check if port is actually in use by any process
			if not is_port_in_use(port) then
				-- Double-check with our allocation list
				local is_allocated = false
				for _, ports in pairs(M.allocated_ports) do
					if ports.ws_port == port then
						is_allocated = true
						break
					end
				end

				if not is_allocated then
					return port
				end
			end
		end
	end
	return nil
end

-- Get centralized registry file path
local function get_registry_file()
	return get_registry_dir() .. "/port_registry.json"
end

-- Read centralized port registry
local function read_registry()
	local registry_file = get_registry_file()
	if vim.fn.filereadable(registry_file) == 0 then
		return {}
	end
	
	local content = table.concat(vim.fn.readfile(registry_file), "\n")
	local ok, registry = pcall(vim.json.decode, content)
	if not ok then
		return {}
	end
	
	return registry
end

-- Write centralized port registry atomically
local function write_registry(registry)
	local registry_file = get_registry_file()
	local temp_file = registry_file .. ".tmp"
	
	local content = vim.json.encode(registry)
	vim.fn.writefile(vim.split(content, "\n"), temp_file)
	
	-- Atomic move
	local success = os.rename(temp_file, registry_file)
	if not success then
		vim.fn.delete(temp_file)
		error("Failed to write port registry")
	end
end

-- Atomic file-based lock for port allocation
local function acquire_port_lock(port, timeout)
	timeout = timeout or 5000 -- 5 second timeout
	local state_dir = get_state_dir()
	local lock_file = state_dir .. "/.port_" .. port .. ".lock"
	local start_time = vim.loop.hrtime()
	
	while (vim.loop.hrtime() - start_time) / 1000000 < timeout do
		-- Try to create lock file atomically
		local handle = io.open(lock_file, "w")
		if handle then
			local pid = vim.fn.getpid()
			handle:write(string.format("%d\n%d\n", pid, vim.loop.hrtime()))
			handle:close()
			
			-- Verify we own the lock (race condition check)
			local read_handle = io.open(lock_file, "r")
			if read_handle then
				local content = read_handle:read("*a")
				read_handle:close()
				
				if content:match("^" .. pid) then
					M.port_locks[port] = lock_file
					return true
				end
			end
		end
		
		-- Lock failed, wait a bit and retry
		vim.loop.sleep(50)
	end
	
	return false
end

-- Release port lock
local function release_port_lock(port)
	local lock_file = M.port_locks[port]
	if lock_file then
		vim.fn.delete(lock_file)
		M.port_locks[port] = nil
	end
end

-- Write port info to user's data directory
local function write_port_file(project_root, ports)
	local data_dir = vim.fn.stdpath("data")
	local port_dir = data_dir .. "/consolelog"
	vim.fn.mkdir(port_dir, "p")

	-- Use project-specific file in user data directory
	local project_key = project_root:gsub("/", "_"):gsub("^_", "")
	local port_file = port_dir .. "/.consolelog_port_" .. project_key

	local content = string.format("WS_PORT=%d\nPROJECT_ROOT=%s\nPID=%d\n",
		ports.ws_port, project_root, vim.fn.getpid())
	vim.fn.writefile(vim.split(content, "\n"), port_file)

	M.port_files[project_root] = port_file
end

-- Read port info from user's data directory
local function read_port_file(project_root)
	local data_dir = vim.fn.stdpath("data")
	local port_dir = data_dir .. "/consolelog"
	
	-- Use project-specific file in user data directory
	local project_key = project_root:gsub("/", "_"):gsub("^_", "")
	local port_file = port_dir .. "/.consolelog_port_" .. project_key

	if vim.fn.filereadable(port_file) == 1 then
		local lines = vim.fn.readfile(port_file)
		local ports = {}

		for _, line in ipairs(lines) do
			local ws_match = line:match("WS_PORT=(%d+)")
			local project_match = line:match("PROJECT_ROOT=(.+)")

			if ws_match then
				ports.ws_port = tonumber(ws_match)
			end
			if project_match then
				ports.project_root = project_match
			end
		end

		if ports.ws_port then
			return ports
		end
	end

	return nil
end

-- Allocate ports for a project with centralized registry
function M.allocate_ports(project_root)
	-- Generate a unique key for this Neovim instance + project
	local instance_key = project_root .. "_" .. vim.fn.getpid()

	-- Check if we already have ports for this instance
	if M.allocated_ports[instance_key] then
		return M.allocated_ports[instance_key]
	end

	-- Read centralized registry and cleanup stale entries
	local registry = read_registry()
	local current_pid = vim.fn.getpid()
	
	-- Cleanup stale entries (dead processes)
	for project_key, entry in pairs(registry) do
		if entry.pid ~= current_pid then
			-- Check if process is still alive
			local handle = io.popen("ps -p " .. entry.pid .. " > /dev/null 2>&1; echo $?")
			local result = handle:read("*a"):gsub("\n", "")
			handle:close()
			
			if result ~= "0" then
				-- Process is dead, remove entry and release port lock
				release_port_lock(entry.ws_port)
				registry[project_key] = nil
			end
		end
	end

	-- Check if we have an existing entry for this project
	local project_key = project_root
	local existing_entry = registry[project_key]
	if existing_entry and existing_entry.pid == current_pid then
		-- Verify port is still actually free and not used by another process
		if not is_port_in_use(existing_entry.ws_port) then
			M.allocated_ports[instance_key] = existing_entry
			return existing_entry
		else
			-- Port is in use by someone else, remove stale entry
			release_port_lock(existing_entry.ws_port)
			registry[project_key] = nil
		end
	end

	-- Collect all currently allocated ports to avoid conflicts
	local exclude_ports = {}
	for _, entry in pairs(registry) do
		table.insert(exclude_ports, entry.ws_port)
	end
	for _, ports in pairs(M.allocated_ports) do
		table.insert(exclude_ports, ports.ws_port)
	end

	-- Find first available port in range
	local ws_port = find_free_port(M.PORT_RANGE_START, M.PORT_RANGE_END, exclude_ports)
	if not ws_port then
		vim.notify("ConsoleLog: No free ports available in range " .. M.PORT_RANGE_START .. "-" .. M.PORT_RANGE_END, vim.log.levels.ERROR)
		return nil
	end

	-- Acquire port lock to prevent race conditions
	if not acquire_port_lock(ws_port) then
		vim.notify("ConsoleLog: Failed to acquire port lock for " .. ws_port, vim.log.levels.ERROR)
		return nil
	end

	local ports = {
		ws_port = ws_port,
		pid = current_pid,
		project_root = project_root,
		allocated_at = os.time()
	}

	-- Update centralized registry
	registry[project_key] = ports
	write_registry(registry)

	-- Update local state
	M.allocated_ports[instance_key] = ports
	write_port_file(project_root, ports)

	return ports
end

-- Release ports for a project
function M.release_ports(project_root)
	local instance_key = project_root .. "_" .. vim.fn.getpid()
	local ports = M.allocated_ports[instance_key]
	
	if ports then
		-- Release port lock
		release_port_lock(ports.ws_port)
		
		-- Update centralized registry
		local registry = read_registry()
		local project_key = project_root
		if registry[project_key] and registry[project_key].pid == vim.fn.getpid() then
			registry[project_key] = nil
			write_registry(registry)
		end
	end

	M.allocated_ports[instance_key] = nil

	-- Remove port file
	if M.port_files[project_root] then
		vim.fn.delete(M.port_files[project_root])
		M.port_files[project_root] = nil
	end
end

-- Get ports for current project
function M.get_project_ports()
	local project_root = M.find_project_root()
	if not project_root then
		return nil
	end

	return M.allocate_ports(project_root)
end

-- Find project root (looks for package.json)
function M.find_project_root()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		current_file = vim.fn.getcwd()
	end

	local dir = current_file
	-- If current_file is a file path, get its directory
	if vim.fn.filereadable(current_file) == 1 then
		dir = vim.fn.fnamemodify(current_file, ":h")
	end
	local closest_package = nil
	local monorepo_root = nil

	-- Walk up to find both the closest package.json and check for monorepo root
	while dir ~= "/" do
		if vim.fn.filereadable(dir .. "/package.json") == 1 then
			if not closest_package then
				closest_package = dir
			end

			-- Check if this is a monorepo root
			local package_json = vim.fn.readfile(dir .. "/package.json")
			local content = table.concat(package_json, "\n")
			if content:match('"workspaces"') then
				monorepo_root = dir
			end
		end
		dir = vim.fn.fnamemodify(dir, ":h")
	end

	-- If we found a closest package.json, use it
	-- This ensures we use apps/web/package.json in a monorepo
	if closest_package then
		return closest_package
	end

	-- Fallback to cwd if no package.json found
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/package.json") == 1 then
		return cwd
	end

	return nil
end

-- Helper to detect if current file is in a Next.js project
function M.is_nextjs_project()
	local project_root = M.find_project_root()
	if not project_root then
		return false
	end

	local package_json = project_root .. "/package.json"
	if vim.fn.filereadable(package_json) == 1 then
		local content = table.concat(vim.fn.readfile(package_json), "\n")
		return content:match('"next"') ~= nil
	end

	return false
end

-- Clean up all allocated ports
function M.cleanup()
	local pid = vim.fn.getpid()
	for key, _ in pairs(M.allocated_ports) do
		-- Only clean up ports for this PID
		if key:match("_" .. pid .. "$") then
			local project_root = key:gsub("_" .. pid .. "$", "")
			M.release_ports(project_root)
		end
	end
end

-- Clean up stale port files from dead processes
function M.cleanup_stale_ports(project_root)
	local port_dir = project_root .. "/node_modules/.consolelog"
	if vim.fn.isdirectory(port_dir) == 0 then
		return
	end

	local files = vim.fn.glob(port_dir .. "/.ports_*", false, true)
	for _, file in ipairs(files) do
		local pid = file:match("%.ports_(%d+)$")
		if pid then
			-- Check if process is still alive
			local handle = io.popen("ps -p " .. pid .. " > /dev/null 2>&1; echo $?")
			local result = handle:read("*a"):gsub("\n", "")
			handle:close()

			if result ~= "0" then
				-- Process is dead, remove the file
				vim.fn.delete(file)
			end
		end
	end
end

-- Clean up stale lock files in state directory
function M.cleanup_stale_locks()
	local state_dir = get_state_dir()
	local lock_files = vim.fn.glob(state_dir .. "/.port_*.lock", false, true)
	
	for _, lock_file in ipairs(lock_files) do
		local handle = io.open(lock_file, "r")
		if handle then
			local content = handle:read("*a")
			handle:close()
			
			local pid = content:match("^(%d+)")
			if pid then
				-- Check if process is still alive
				local check_handle = io.popen("ps -p " .. pid .. " > /dev/null 2>&1; echo $?")
				local result = check_handle:read("*a"):gsub("\n", "")
				check_handle:close()
				
				if result ~= "0" then
					-- Process is dead, remove the lock file
					vim.fn.delete(lock_file)
				end
			else
				-- Invalid lock file, remove it
				vim.fn.delete(lock_file)
			end
		else
			-- Can't read lock file, remove it
			vim.fn.delete(lock_file)
		end
	end
end

return M

