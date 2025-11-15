# consolelog.nvim

**See your console output right where it belongs - next to your code!**

A Neovim plugin that captures and displays console outputs as virtual text inline with your code. Features automatic framework detection, intelligent project setup, and comprehensive debugging capabilities for modern JavaScript development.

## Demo

![console nvim](https://github.com/user-attachments/assets/344b610c-67f4-40a0-b243-93632e71c419)

## Key Features

- Real-time Console Capture - See console outputs instantly as virtual text next to your code
- Browser Support - Automatic console capture for Next.js, React, Vue, and Vite projects
- Single-File Runner - Run standalone `.js` files with console capture via Node.js Inspector
- Smart Object Display - Inline previews for small objects, floating inspector for large ones
- Zero Config - Works out of the box with intelligent project detection
- Accurate Line Mapping - Outputs appear exactly where they're logged using source maps
- Framework Support - Works with all JavaScript frameworks providing source maps (Next.js, React, Vue, Vite, and more)
- Yankable Output - Copy console outputs directly from the inspector
- Inline History - Navigate through multiple console outputs on the same line
- Multiple Sessions - Run multiple projects simultaneously with automatic port management
- Auto-Reconnection - Robust connection handling with exponential backoff
- Syntax Highlighting - Color-coded output by console type (log, error, warn, info, debug)

## Star This Project

If ConsoleLog.nvim helps you debug faster and code more efficiently, please consider giving it a star! It helps others discover the plugin and motivates continued development.

## Installation

### lazy.nvim

```lua
{
    "chriswritescode-dev/consolelog.nvim",
    config = function()
      require("consolelog").setup()
    end,
}
```


## Usage

ConsoleLog automatically detects your project type and enables console capture:

1. Enable ConsoleLog: `:ConsoleLogToggle` or `<leader>lt`
2. Write code with console.log() in any JavaScript/TypeScript file
3. See output instantly as virtual text next to your code

### Project-Specific Behavior

**Single-File Execution** (`:ConsoleLogRun` or `<leader>lr`):
- Supports: `.js` files only
- Runs via Node.js Inspector with console capture
- Perfect for quick scripts and standalone JavaScript files

**Browser Framework Projects** (automatic):
- Supports: `.js`, `.jsx`, `.ts`, `.tsx`
- Works with: Next.js, React, Vue, Vite, and any framework with source maps
- Automatically injects WebSocket console capture
- Just run `npm run dev` and start coding

## Commands & Keybindings

### Core Commands

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>lr` | `:ConsoleLogRun` | Run current file with ConsoleLog |
| `<leader>lx` | `:ConsoleLogClear` | Clear all console outputs |
| `<leader>ls` | `:ConsoleLogStatus` | Show status and diagnostics |

### Inspect Commands

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>li`  | `:ConsoleLogInspect` | Inspect output at cursor line |
| `<leader>la`  | `:ConsoleLogInspectAll` | Show all outputs (all buffers) |
| `<leader>lb`  | `:ConsoleLogInspectBuffer` | Show all outputs (current buffer) |

**Inspector Navigation:**
- Press `<Enter>` on any output line to jump to its source location
- Press `q` or `<Esc>` to close the inspector window

### Debug Commands

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>ld` | `:ConsoleLogDebugToggle` | Toggle debug logging on/off |
| `<leader>lg` | `:ConsoleLogDebug` | Open debug log |
| `<leader>lG` | `:ConsoleLogDebugClear` | Clear debug log |

### Maintenance

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>lR` | `:ConsoleLogReload` | Reload plugin |

## Configuration

The plugin works out of the box with sensible defaults. Here's the full configuration:
```lua
{
  "chriswritescode-dev/consolelog.nvim",
  config = function()
    require("consolelog").setup({
      auto_enable = true,        -- Auto-enable on startup
      log_level = "silent",      -- "debug", "info", "warn", "error", "silent"
      display = {
        virtual_text = true,     -- Show output as virtual text
        virtual_text_pos = "eol", -- Position: "eol" or "inline"
        prefix = " ▸ ",          -- Prefix before output
        throttle_ms = 50,        -- Throttle updates in milliseconds
        max_width = 0,           -- Maximum width of inline output (0 = no limit)
      },
      websocket = {
        ping_interval = 15000,   -- WebSocket ping interval (ms)
        close_timeout = 30000,   -- WebSocket close timeout (ms)
        display_methods = { "log", "error" }, -- Console methods to display inline
        reconnect = {
          enabled = true,        -- Auto-reconnect on disconnect
          max_attempts = 5,      -- Max reconnection attempts
          delay = 1000,          -- Delay between attempts (ms)
        },
      },
      inspector = {
        auto_resume = true,      -- Auto-resume inspector on new output
        capture_exceptions = true, -- Capture uncaught exceptions
        console_methods = { "log", "error", "warn", "info", "debug" }, -- Methods to capture
      },
      keymaps = {
        enabled = true,          -- Enable default keymaps
        toggle = "<leader>lt",   -- Toggle ConsoleLog
        run = "<leader>lr",      -- Run current file
        clear = "<leader>lx",    -- Clear outputs
        inspect = "<leader>li",  -- Inspect at cursor
        inspect_all = "<leader>la", -- Inspect all
        inspect_buffer = "<leader>lb", -- Inspect buffer
        reload = "<leader>lR",   -- Reload plugin
        debug_toggle = "<leader>ld", -- Toggle debug logging
      },
    })
  end,
  keys = {
    { "<leader>lt", "<cmd>ConsoleLogToggle<cr>",       desc = "Toggle ConsoleLog" },
    { "<leader>lr", "<cmd>ConsoleLogRun<cr>",          desc = "Run file with ConsoleLog" },
    { "<leader>lx", "<cmd>ConsoleLogClear<cr>",        desc = "Clear console outputs" },
    { "<leader>li", "<cmd>ConsoleLogInspect<cr>",      desc = "Inspect output at cursor" },
    { "<leader>la", "<cmd>ConsoleLogInspectAll<cr>",   desc = "Inspect all outputs" },
    { "<leader>lb", "<cmd>ConsoleLogInspectBuffer<cr>", desc = "Inspect buffer outputs" },
    { "<leader>ld", "<cmd>ConsoleLogDebugToggle<cr>",  desc = "Toggle debug logging" },
    { "<leader>ls", "<cmd>ConsoleLogStatus<cr>",       desc = "Show status" },
    { "<leader>lR", "<cmd>ConsoleLogReload<cr>",       desc = "Reload plugin" },
    { "<leader>lg", "<cmd>ConsoleLogDebug<cr>",        desc = "Open debug log" },
    { "<leader>lG", "<cmd>ConsoleLogDebugClear<cr>",   desc = "Clear debug log" },
  },
  cmd = {
    "ConsoleLogToggle",
    "ConsoleLogClear",
    "ConsoleLogRun",
    "ConsoleLogInspect",
    "ConsoleLogInspectAll",
    "ConsoleLogInspectBuffer",
    "ConsoleLogDebugToggle",
    "ConsoleLogStatus",
    "ConsoleLogReload",
    "ConsoleLogDebug",
    "ConsoleLogDebugClear",
  },
  ft = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
}
```


## Why ConsoleLog.nvim?

After using Console Ninja in VSCode, I couldn't find anything similar for Neovim. ConsoleLog.nvim brings that same inline console output experience to Neovim, eliminating context switching between your editor and terminal/browser console.

So it's something I created to make my life easier, and I thought it might be useful to others.


## Contributing

Pull requests are welcome! Especially for:
- Framework compatibility issues
- New framework integrations
- Source map improvements
- Bug fixes and enhancements

If you encounter issues with a specific JavaScript framework, please open an issue with details about your project setup.

## Acknowledgments

Inline output styling inspired by [tiny-inline-diagnostic.nvim](https://github.com/rachartier/tiny-inline-diagnostic.nvim) - a beautiful plugin for inline diagnostics display. 
## Architecture

- **Modular design**: Separate modules for WebSocket, inspector, parser, display
- **State management**: Module-level tables with buffer-specific keys
- **Inline history**: Execution tracking directly in output entries
- **Event-driven**: Callbacks for WebSocket lifecycle events
- **Zero dependencies**: Pure Lua/JavaScript implementation

## Testing

Run all tests:
```bash
make test
```

## License

MIT

