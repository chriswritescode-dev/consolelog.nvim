local M = {}

local utils = require("consolelog.core.utils")

-- Generation counter for invalidating stale deferred reruns.
-- Incremented on disable so queued callbacks from a prior lifecycle are discarded.
M._rerun_generation = 0
M._rerun_tokens = {}

function M.invalidate_reruns()
	M._rerun_generation = M._rerun_generation + 1
	M._rerun_tokens = {}
end

-- Check if a buffer should be processed by consolelog
local function should_process_buffer(bufnr, winid)
	return utils.is_supported_buffer(bufnr)
		and utils.find_regular_buffer_window(bufnr, winid) ~= nil
end

-- Export the function for use by other modules
M.should_process_buffer = should_process_buffer

function M.setup()
	local group = vim.api.nvim_create_augroup("ConsoleLog", { clear = true })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			local winid = vim.api.nvim_get_current_win()

			if not should_process_buffer(bufnr, winid) then
				return
			end

			local consolelog = require("consolelog")
			consolelog.active_buf = bufnr
			if consolelog.config.auto_enable and not consolelog.config.enabled then
				consolelog.enable()
			end

			-- Show outputs for the newly active buffer if they exist
			if consolelog.config.enabled and consolelog.outputs[bufnr] and not vim.tbl_isempty(consolelog.outputs[bufnr]) then
				require("consolelog.display.display").show_outputs(bufnr)
			end
		end,
	})



	-- Clear outputs only when buffer is reloaded from disk
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		callback = function()
			require("consolelog.explain").restore(vim.api.nvim_get_current_buf())
			local bufnr = vim.api.nvim_get_current_buf()
			local winid = vim.api.nvim_get_current_win()

			if not should_process_buffer(bufnr, winid) then
				return
			end

			local consolelog = require("consolelog")

			-- Clear outputs for this buffer on reload
			if consolelog.outputs[bufnr] then
				local debug_logger = require("consolelog.core.debug_logger")
				debug_logger.log("BUFREADPOST", string.format("Clearing outputs for buffer %d", bufnr))
				consolelog.outputs[bufnr] = {}
				require("consolelog.display.display").clear_buffer(bufnr)
			end
		end,
	})

	-- Mark buffer as ready when it's written and clear outputs
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			require("consolelog.explain").sync_lines(args.buf)
			local bufnr = args.buf
			local winid = vim.api.nvim_get_current_win()
			local consolelog = require("consolelog")
			local inspector = require("consolelog.communication.inspector")
			local is_tracked = inspector.is_single_file_buffer(bufnr)
			local is_regular_window = utils.find_regular_buffer_window(bufnr, winid) ~= nil

			-- Clear outputs on save for JS buffers and tracked single-file buffers.
			-- The is_tracked guard lets .mts/.cts files without a recognised
			-- filetype clear stale outputs before the deferred re-run.
			if is_regular_window and (should_process_buffer(bufnr, winid) or is_tracked) then
				if consolelog.outputs[bufnr] then
					local debug_logger = require("consolelog.core.debug_logger")
					debug_logger.log("BUFWRITEPOST", string.format("Clearing outputs for buffer %d on save", bufnr))
					consolelog.outputs[bufnr] = {}
					require("consolelog.display.display").clear_buffer(bufnr)
				end
			end

			-- Auto re-run on save for single-file buffers previously run via :ConsoleLogRun
			local gen = M._rerun_generation
			if is_regular_window
				and is_tracked
				and consolelog.config.enabled
				and consolelog.config.runner.rerun_on_save
				and vim.api.nvim_buf_is_valid(bufnr)
				and vim.api.nvim_buf_is_loaded(bufnr) then
				local token = (M._rerun_tokens[bufnr] or 0) + 1
				M._rerun_tokens[bufnr] = token
				vim.defer_fn(function()
					if M._rerun_generation == gen
						and M._rerun_tokens[bufnr] == token
						and consolelog.config.enabled
						and consolelog.config.runner.rerun_on_save
						and inspector.is_single_file_buffer(bufnr)
						and vim.api.nvim_buf_is_valid(bufnr)
						and vim.api.nvim_buf_is_loaded(bufnr) then
						consolelog.run_buffer(bufnr, winid)
					end
				end, 50)
			end
		end,
	})
end

return M
