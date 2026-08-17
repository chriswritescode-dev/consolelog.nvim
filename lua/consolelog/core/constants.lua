local M = {}

M.PORTS = {
	MIN = 19990,
	MAX = 20100,
	DEFAULT_WS = 19990
}

M.TIMEOUTS = {
	CONNECTION = 15000,
	RECONNECT = 30000,
	PING_INTERVAL = 30000,
	HANDSHAKE = 5000,
	BRIDGE_STARTUP = 500,
	DEFER = 100
}

M.BUFFER_LIMITS = {
	MAX_SIZE = 1024 * 1024,
	MAX_LINE = 2000,
	MAX_OUTPUT = 1024 * 1024
}

M.RETRY = {
	MAX_ATTEMPTS = 3,
	BACKOFF_BASE = 100,
	MAX_RECONNECT = 5,
	COOLDOWN = 5000
}

M.DISPLAY = {
	MAX_WIDTH = 80,
	TRUNCATE_MARKER = "...",
	THROTTLE_MS = 100,
	THROTTLE_MIN_MS = 100,
	DEFAULT_THROTTLE_MS = 50,
	EXTMARK_PRIORITY = 100,
	WINDOW_WIDTH_RATIO = 0.8,
	WINDOW_HEIGHT_RATIO = 0.6,
	DEFAULT_HISTORY_MAX = 100,
	MAX_INLINE_VALUES = 5,
	FLOAT_WIDTH = 80,
	FLOAT_HEIGHT = 20
}

M.FILE_PATTERNS = {
	JAVASCRIPT_SINGLE = { "%.js$", "%.mjs$", "%.cjs$", "%.ts$", "%.mts$", "%.cts$" },
	TYPESCRIPT = { "%.ts$", "%.mts$", "%.cts$" },
	PYTHON = { "%.py$" },
	FRAMEWORK_SUPPORTED = { "%.js$", "%.jsx$", "%.ts$", "%.tsx$" }
}

M.NETWORK = {
	LOCALHOST_IP = "127.0.0.1",
	LOCALHOST_NAMES = { "localhost", "127.0.0.1" },
	DEFAULT_INSPECTOR_PORT = 9229
}

M.TIMING = {
	INSPECTOR_INIT_DELAY_MS = 150,
	RECONNECT_BASE_DELAY_MS = 1000,
	SHUTDOWN_GRACE_PERIOD_MS = 100,
	AUTO_SETUP_COOLDOWN_MS = 10000,
	DEFER_PROCESSING_MS = 100
}

M.WEBSOCKET = {
	VERSION = 13,
	MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	MAX_FRAME_SIZE = 1024 * 1024
}

M.FILES = {
	PORT_FILE_PREFIX = ".consolelog_port_",
	PID_FILE_PREFIX = ".consolelog_pid_",
	TEMP_DIR = "/tmp",
	MAX_PATH_DEPTH = 10,
	BACKUP_SUFFIX = ".bk"
}

M.INJECTION = {
	START_MARKER = "// ConsoleLog.nvim auto-injection start",
	END_MARKER = "// ConsoleLog.nvim auto-injection end",
	BLOCK_PATTERN = "// ConsoleLog%.nvim auto%-injection start.-// ConsoleLog%.nvim auto%-injection end\n?",
	BROWSER_GUARD = "if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {"
}

M.LOG_LEVELS = {
	DEBUG = "DEBUG",
	INFO = "INFO",
	WARN = "WARN",
	ERROR = "ERROR"
}

M.CONSOLE_TYPES = {
	LOG = "log",
	ERROR = "error",
	WARN = "warn",
	INFO = "info",
	DEBUG = "debug"
}

M.EXPLAIN = {
	RESPONSE_KEY = "explanations",
	HTTP_STATUS_SENTINEL = "__CONSOLELOG_HTTP__",
	DEFAULT_PREFIX = " ⟩ ",
	DEFAULT_MAX_LINES = 50,
	DEFAULT_MAX_CONTEXT_LINES = 1000,
	DEFAULT_TIMEOUT_MS = 120000,
	EXTMARK_PRIORITY = 200,
	MAX_WORDS = 12
}

function M.is_single_file_runnable(filepath)
	for _, pattern in ipairs(M.FILE_PATTERNS.JAVASCRIPT_SINGLE) do
		if filepath:match(pattern) then
			return true
		end
	end
	for _, pattern in ipairs(M.FILE_PATTERNS.PYTHON) do
		if filepath:match(pattern) then
			return true
		end
	end
	return false
end

function M.is_framework_supported(filepath)
	for _, pattern in ipairs(M.FILE_PATTERNS.FRAMEWORK_SUPPORTED) do
		if filepath:match(pattern) then
			return true
		end
	end
	return false
end

function M.is_typescript_file(filepath)
	for _, pattern in ipairs(M.FILE_PATTERNS.TYPESCRIPT) do
		if filepath:match(pattern) then
			return true
		end
	end
	return false
end

function M.is_python_file(filepath)
	for _, pattern in ipairs(M.FILE_PATTERNS.PYTHON) do
		if filepath:match(pattern) then
			return true
		end
	end
	return false
end

return M
