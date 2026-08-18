local M = {}

function M.setup()
	vim.api.nvim_set_hl(0, "ConsoleLogOutput", {
		fg = "#1a1b26",
		bg = "#7aa2f7",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogError", {
		fg = "#1a1b26",
		bg = "#f7768e",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogWarning", {
		fg = "#1a1b26",
		bg = "#e0af68",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogInfo", {
		fg = "#1a1b26",
		bg = "#0db9d7",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogDebug", {
		fg = "#1a1b26",
		bg = "#9d7cd8",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogOutputLeft", {
		fg = "#7aa2f7",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogOutputRight", {
		fg = "#7aa2f7",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogErrorLeft", {
		fg = "#f7768e",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogErrorRight", {
		fg = "#f7768e",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogWarningLeft", {
		fg = "#e0af68",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogWarningRight", {
		fg = "#e0af68",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogInfoLeft", {
		fg = "#0db9d7",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogInfoRight", {
		fg = "#0db9d7",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogDebugLeft", {
		fg = "#9d7cd8",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogDebugRight", {
		fg = "#9d7cd8",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogExplain", {
		fg = "#1a1b26",
		bg = "#9ece6a",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogExplainLeft", {
		fg = "#9ece6a",
		default = true
	})

	vim.api.nvim_set_hl(0, "ConsoleLogExplainRight", {
		fg = "#9ece6a",
		default = true
	})
end

return M
