local M = {}

function M.setup()
	vim.api.nvim_create_user_command("ConsoleLogToggle", function()
		require("consolelog").toggle()
	end, { desc = "Toggle ConsoleLog" })

	vim.api.nvim_create_user_command("ConsoleLogClear", function()
		require("consolelog").clear()
	end, { desc = "Clear all console outputs" })

	vim.api.nvim_create_user_command("ConsoleLogRun", function()
		require("consolelog").run()
	end, { desc = "Run current file with ConsoleLog (for quick testing)" })

	vim.api.nvim_create_user_command("ConsoleLogInspect", function()
		local consolelog = require("consolelog")
		local bufnr = vim.api.nvim_get_current_buf()
		local outputs = consolelog.outputs[bufnr]
		require("consolelog.display.float_inspector").inspect_at_cursor(outputs)
	end, { desc = "Inspect console output at cursor line with detailed info" })

	vim.api.nvim_create_user_command("ConsoleLogInspectAll", function()
		local consolelog = require("consolelog")
		local float_inspector = require("consolelog.display.float_inspector")
		float_inspector.inspect_all(consolelog.outputs, consolelog.unmatched_outputs)
	end, { desc = "Show all console outputs in floating window" })

	vim.api.nvim_create_user_command("ConsoleLogInspectBuffer", function()
		local consolelog = require("consolelog")
		local bufnr = vim.api.nvim_get_current_buf()
		local buffer_outputs = consolelog.outputs[bufnr]
		local buffer_unmatched = consolelog.unmatched_outputs and consolelog.unmatched_outputs[bufnr]
		require("consolelog.display.float_inspector").inspect_buffer(buffer_outputs, buffer_unmatched)
	end, { desc = "Show all console outputs for current buffer" })

	vim.api.nvim_create_user_command("ConsoleLogExplain", function(opts)
		local bufnr = vim.api.nvim_get_current_buf()
		local explain = require("consolelog.explain")
		if opts.range == 0 then
			explain.explain_range(bufnr, 1, vim.api.nvim_buf_line_count(bufnr))
		else
			explain.explain_range(bufnr, opts.line1, opts.line2)
		end
	end, { range = true, desc = "Explain code in English inline (selection or whole buffer)" })

	vim.api.nvim_create_user_command("ConsoleLogExplainClear", function()
		require("consolelog.explain").clear(vim.api.nvim_get_current_buf())
	end, { desc = "Clear inline code explanations" })

	vim.api.nvim_create_user_command("ConsoleLogExplainInspect", function()
		require("consolelog.explain").inspect(vim.api.nvim_get_current_buf())
	end, { desc = "Show the full explanation for the current line in a float" })

	vim.api.nvim_create_user_command("ConsoleLogExplainToggle", function()
		require("consolelog.explain").toggle(vim.api.nvim_get_current_buf())
	end, { desc = "Toggle visibility of inline code explanations" })

	vim.api.nvim_create_user_command("ConsoleLogExplainStop", function()
		require("consolelog.explain").stop(vim.api.nvim_get_current_buf())
	end, { desc = "Stop an in-flight explain request" })

	vim.api.nvim_create_user_command("ConsoleLogDebugToggle", function()
		require("consolelog.core.debug_logger").toggle()
	end, { desc = "Toggle debug logging on/off" })

	vim.api.nvim_create_user_command("ConsoleLogStatus", function()
		local consolelog = require("consolelog")
		local bufnr = vim.api.nvim_get_current_buf()
		local filepath = vim.api.nvim_buf_get_name(bufnr)

		local ws_server = require("consolelog.communication.ws_server")
		local ws_port = ws_server.port or 0
		local ws_status = ws_server.server and "Running" or "Stopped"
		local ws_clients = ws_server.clients and #ws_server.clients or 0
		
		local status = {
			"=== ConsoleLog Status ===",
			"",
			string.format("Plugin: %s", consolelog.config.enabled and "Enabled" or "Disabled"),
			string.format("Project Root: %s", consolelog.project_root or "none"),
			string.format("Project ID: %s", consolelog.project_id or "none"),
			"",
			string.format("WebSocket Server: %s (port %d)", ws_status, ws_port),
			string.format("WebSocket clients: %d", ws_clients),
			string.format("Tracked buffers: %d", vim.tbl_count(consolelog.outputs)),
			"",
			string.format("Current buffer: %s", filepath ~= "" and filepath or "unnamed"),
			string.format("Console outputs: %d", consolelog.outputs[bufnr] and #consolelog.outputs[bufnr] or 0),
		}

		-- Add WebSocket connection info for debugging
		if ws_server.server and ws_port > 0 then
			table.insert(status, "")
			table.insert(status, "--- WebSocket Connection Info ---")
			table.insert(status, string.format("Browser should connect to: ws://localhost:%d", ws_port))
			table.insert(status, "Check browser console for: window.__CONSOLELOG_WS_PORT")
			
			if ws_clients == 0 then
				table.insert(status, "")
				table.insert(status, "⚠ No browser clients connected")
				table.insert(status, "1. Restart your Next.js dev server")
				table.insert(status, "2. Check browser console for injection errors")
				table.insert(status, "3. Verify window.__CONSOLELOG_WS_PORT is defined")
			end
		end

		-- Add patch status for Next.js projects
		local project_root = require("consolelog.communication.port_manager").find_project_root()
		if project_root then
			local package_json = project_root .. "/package.json"
			if vim.fn.filereadable(package_json) == 1 then
				local content = table.concat(vim.fn.readfile(package_json), "\n")
				if content:match('"next"') then
					table.insert(status, "")
					table.insert(status, "--- Next.js Patch Status ---")
					
					-- Use same search logic as the patcher (find monorepo root)
					local search_roots = { project_root }
					local dir = project_root
					while dir ~= "/" do
						local parent = vim.fn.fnamemodify(dir, ":h")
						if parent == dir then break end

						local parent_package = parent .. "/package.json"
						if vim.fn.filereadable(parent_package) == 1 then
							local parent_content = table.concat(vim.fn.readfile(parent_package), "\n")
							if parent_content:match('"workspaces"') then
								table.insert(search_roots, parent)
								break
							end
						end
						dir = parent
					end
					
					local nextjs_files = {
						"/node_modules/next/dist/client/index.js",
						"/node_modules/next/dist/client/app-index.js",
						"/node_modules/next/dist/esm/client/index.js",
					}
					
					local patched_files = 0
					local found_files = 0
					
					for _, file in ipairs(nextjs_files) do
						local found_in_root = nil
						for _, root in ipairs(search_roots) do
							local filepath = root .. file
							if vim.fn.filereadable(filepath) == 1 then
								found_in_root = root
								found_files = found_files + 1
								
								local file_content = table.concat(vim.fn.readfile(filepath), "\n")
								if file_content:match("window%.__CONSOLELOG_WS_PORT") then
									patched_files = patched_files + 1
									local port_match = file_content:match("window%.__CONSOLELOG_WS_PORT = (%d+)")
									if port_match then
										table.insert(status, string.format("✓ PATCHED: %s (port %s)", file, port_match))
									else
										table.insert(status, "✓ PATCHED: " .. file)
									end
								else
									table.insert(status, "✗ NOT PATCHED: " .. file)
								end
								break
							end
						end
						
						if not found_in_root then
							table.insert(status, "- FILE NOT FOUND: " .. file)
						end
					end
					
					if found_files == 0 then
						table.insert(status, "No Next.js files found in any search root")
					elseif patched_files > 0 then
						table.insert(status, string.format("Next.js is PATCHED (%d/%d files)", patched_files, found_files))
					else
						table.insert(status, "Next.js is NOT patched - run :ConsoleLogToggle")
					end
				end
			end
		end

		vim.notify(table.concat(status, "\n"), vim.log.levels.INFO)
	end, { desc = "Show ConsoleLog status and diagnostics" })

	vim.api.nvim_create_user_command("ConsoleLogDebug", function()
		require("consolelog.core.debug_logger").open_debug_window()
	end, { desc = "Open debug log" })

	vim.api.nvim_create_user_command("ConsoleLogDebugClear", function()
		require("consolelog.core.debug_logger").clear()
	end, { desc = "Clear debug log" })

	

	vim.api.nvim_create_user_command("ConsoleLogReload", function()
		package.loaded["consolelog"] = nil
		for k, _ in pairs(package.loaded) do
			if k:match("^consolelog%.") then
				package.loaded[k] = nil
			end
		end
		require("consolelog").setup()
		vim.notify("ConsoleLog reloaded", vim.log.levels.INFO)
	end, { desc = "Reload ConsoleLog plugin" })
end

return M
