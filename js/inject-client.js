(function () {
  if (typeof window === "undefined" || typeof window.addEventListener !== "function" || window.__consolelogInjected) return;
  window.__consolelogInjected = true;
  window.__consolelogEnabled = true;

  const __originalConsole = window.__originalConsole || {
    log: console.log,
    error: console.error,
    warn: console.warn,
    info: console.info,
    debug: console.debug,
  };
  window.__originalConsole = __originalConsole;

  const config = {
    port: window.__CONSOLELOG_WS_PORT || 19990,
    projectId: window.__CONSOLELOG_PROJECT_ID || null,
    projectPath: window.__CONSOLELOG_PROJECT_PATH || null,
    debug: window.__CONSOLELOG_DEBUG || false,
    bufferMap: window.__CONSOLELOG_BUFFER_MAP || {},
    batchDelay: 10,
    reconnectDelay: 1000,
    maxReconnectDelay: 30000,
    maxQueueSize: 1000,
    heartbeatInterval: 5000,
    messageTimeout: 30000,
  };

  class ConsoleLogConnection {
    constructor(port, projectId) {
      this.port = port;
      this.projectId = projectId;
      this.ws = null;
      this.messageQueue = [];
      this.pendingAcks = new Map();
      this.messageIdCounter = 0;
      this.batchTimer = null;
      this.reconnectTimer = null;
      this.heartbeatTimer = null;
      this.reconnectDelay = config.reconnectDelay;
      this.isConnecting = false;
      this.connectionAttempts = 0;
      this.executionCounters = {};
      this.lastPongTime = Date.now();
      this.isShuttingDown = false;

      this.restoreQueue();
      this.setupBeforeUnload();
    }

    async connect() {
      if (this.isShuttingDown || this.isConnecting) return;

      if (
        this.ws &&
        (this.ws.readyState === WebSocket.CONNECTING ||
          this.ws.readyState === WebSocket.OPEN)
      ) {
        return;
      }

      this.isConnecting = true;

      try {
        this.ws = new WebSocket(`ws://localhost:${this.port}`);

        this.ws.onopen = () => {
          this.isConnecting = false;
          this.connectionAttempts = 0;
          this.reconnectDelay = config.reconnectDelay;
          this.lastPongTime = Date.now();

          if (this.reconnectTimer) {
            clearTimeout(this.reconnectTimer);
            this.reconnectTimer = null;
          }

          this.ws.send(
            JSON.stringify({
              type: "identify",
              projectId: this.projectId,
              projectPath: config.projectPath,
              url: window.location.href,
              timestamp: Date.now(),
            }),
          );

          this.startHeartbeat();
          this.flushQueue();
          this.retryPendingMessages();
        };

        this.ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);

            if (data.type === "pong") {
              this.lastPongTime = Date.now();
            } else if (data.type === "ack" && data.messageId) {
              this.pendingAcks.delete(data.messageId);
            } else if (data.type === "command") {
              if (data.command === "ping") {
                this.ws.send(JSON.stringify({ type: "pong" }));
              } else if (data.command === "shutdown") {
                this.shutdown();
              } else if (data.command === "disable") {
                window.__consolelogEnabled = false;
              } else if (data.command === "enable") {
                window.__consolelogEnabled = true;
              }
            }
          } catch (e) {}
        };

        this.ws.onclose = () => {
          this.isConnecting = false;
          this.stopHeartbeat();
          if (!this.isShuttingDown) {
            this.scheduleReconnect();
          }
        };

        this.ws.onerror = (error) => {
          this.isConnecting = false;
        };
      } catch (e) {
        this.isConnecting = false;
        this.scheduleReconnect();
      }
    }

    scheduleReconnect() {
      if (this.reconnectTimer || this.isShuttingDown) return;

      this.connectionAttempts++;
      const delay = Math.min(
        this.reconnectDelay * Math.pow(1.5, this.connectionAttempts - 1),
        config.maxReconnectDelay,
      );

      this.reconnectTimer = setTimeout(() => {
        this.reconnectTimer = null;
        this.connect();
      }, delay);
    }

    startHeartbeat() {
      this.stopHeartbeat();

      this.heartbeatTimer = setInterval(() => {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
          const now = Date.now();

          if (now - this.lastPongTime > config.heartbeatInterval * 3) {
            this.ws.close();
            return;
          }

          this.ws.send(JSON.stringify({ type: "ping", timestamp: now }));
        }
      }, config.heartbeatInterval);
    }

    stopHeartbeat() {
      if (this.heartbeatTimer) {
        clearInterval(this.heartbeatTimer);
        this.heartbeatTimer = null;
      }
    }

    shutdown() {
      this.isShuttingDown = true;
      this.stopHeartbeat();

      if (this.reconnectTimer) {
        clearTimeout(this.reconnectTimer);
        this.reconnectTimer = null;
      }

      if (this.batchTimer) {
        clearTimeout(this.batchTimer);
        this.batchTimer = null;
      }

      if (this.ws) {
        this.ws.close();
        this.ws = null;
      }

      this.messageQueue = [];
      this.pendingAcks.clear();
      this.clearStoredQueue();
    }

    addMessage(message) {
      if (this.messageQueue.length >= config.maxQueueSize) {
        this.messageQueue.shift();
      }

      message.id = ++this.messageIdCounter;
      message.timestamp = Date.now();
      this.messageQueue.push(message);
      this.persistQueue();

      if (!this.batchTimer) {
        this.batchTimer = setTimeout(() => {
          this.flushQueue();
        }, config.batchDelay);
      }
    }

    flushQueue() {
      if (this.batchTimer) {
        clearTimeout(this.batchTimer);
        this.batchTimer = null;
      }

      if (this.messageQueue.length === 0) return;

      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        const batch = this.messageQueue.splice(0, this.messageQueue.length);

        batch.forEach((msg) => {
          this.pendingAcks.set(msg.id, {
            message: msg,
            sentAt: Date.now(),
            retries: 0,
          });
        });

        if (batch.length === 1) {
          this.ws.send(JSON.stringify(batch[0]));
        } else {
          this.ws.send(
            JSON.stringify({
              type: "batch",
              messages: batch,
              timestamp: Date.now(),
            }),
          );
        }

        this.persistQueue();
      }
    }

    retryPendingMessages() {
      const now = Date.now();
      const toRetry = [];

      for (const [id, pending] of this.pendingAcks.entries()) {
        if (now - pending.sentAt > config.messageTimeout) {
          if (pending.retries < 3) {
            pending.retries++;
            toRetry.push(pending.message);
          } else {
            this.pendingAcks.delete(id);
          }
        }
      }

      if (
        toRetry.length > 0 &&
        this.ws &&
        this.ws.readyState === WebSocket.OPEN
      ) {
        toRetry.forEach((msg) => {
          this.pendingAcks.set(msg.id, {
            message: msg,
            sentAt: Date.now(),
            retries: this.pendingAcks.get(msg.id)?.retries || 0,
          });
        });

        this.ws.send(
          JSON.stringify({
            type: "batch",
            messages: toRetry,
            timestamp: Date.now(),
          }),
        );
      }
    }

    persistQueue() {
      try {
        const data = {
          queue: this.messageQueue.slice(0, 100),
          pending: Array.from(this.pendingAcks.entries())
            .slice(0, 100)
            .map(([id, pending]) => ({
              id,
              message: pending.message,
              retries: pending.retries,
            })),
        };
        sessionStorage.setItem("__consolelog_queue", JSON.stringify(data));
      } catch (e) {}
    }

    restoreQueue() {
      try {
        const stored = sessionStorage.getItem("__consolelog_queue");
        if (stored) {
          const data = JSON.parse(stored);
          if (data.queue) {
            this.messageQueue = data.queue;
          }
          if (data.pending) {
            data.pending.forEach(({ id, message, retries }) => {
              this.pendingAcks.set(id, {
                message,
                sentAt: Date.now(),
                retries: retries || 0,
              });
            });
          }
        }
      } catch (e) {}
    }

    clearStoredQueue() {
      try {
        sessionStorage.removeItem("__consolelog_queue");
      } catch (e) {}
    }

    setupBeforeUnload() {
      window.addEventListener("beforeunload", () => {
        this.persistQueue();
      });
    }

    getExecutionCount(locationKey) {
      this.executionCounters[locationKey] =
        (this.executionCounters[locationKey] || 0) + 1;
      return this.executionCounters[locationKey];
    }
  }

  function getProjectIdentifier() {
    if (config.projectId) return config.projectId;

    const pathParts = window.location.pathname.split("/").filter((p) => p);
    const projectId = pathParts[0] || window.location.host || "default";

    return projectId;
  }

  async function extractLocationFromStack(stackTrace) {
    const stack = stackTrace || new Error().stack;

    if (stack) {
      const lines = stack.split("\n");

      for (let i = 2; i < lines.length; i++) {
        const line = lines[i];

        if (
          line.includes("__consolelogInjected") ||
          line.includes("extractLocation") ||
          line.includes("console.<computed>") ||
          line.includes("hydration-error-info.js") ||
          line.includes("chrome-extension://")
        ) {
          continue;
        }

        const webpackInternalMatch = line.match(
          /at\s+(?:.*?\s+\()?(webpack-internal:\/\/\/\(([^)]+)\)\/\.\/(.+?)):(\d+):(\d+)/,
        );
        if (webpackInternalMatch) {
          const fullUrl = webpackInternalMatch[1];
          const context = webpackInternalMatch[2];
          const filePath = webpackInternalMatch[3];
          const lineNum = parseInt(webpackInternalMatch[4]);
          const column = parseInt(webpackInternalMatch[5]);

          if (
            filePath.includes("/node_modules/") ||
            filePath.includes("/next/dist/")
          ) {
            continue;
          }

          let location = {
            file: filePath,
            line: lineNum,
            column: column,
            url: fullUrl,
            context: context,
            confidence: 0.9,
            fullPath: filePath,
          };

          if (window.__consolelogSourceMapResolver) {
            try {
              const resolved =
                await window.__consolelogSourceMapResolver.resolveLocation(
                  location,
                );
              if (resolved && resolved.sourceMapped) {
                return resolved;
              }
            } catch (e) {}
          }

          return location;
        }

        let match = line.match(/at\s+(?:.*?\s+\()?(.+?):(\d+):(\d+)/);
        if (match) {
          const url = match[1];
          const lineNum = parseInt(match[2]);
          const column = parseInt(match[3]);

          if (url.includes("/node_modules/") || url.includes("/next/dist/")) {
            continue;
          }

          const fileName = url.split("/").pop().split("?")[0];

          if (fileName.match(/\.(jsx?|tsx?)$/)) {
            let location = {
              file: fileName,
              line: lineNum,
              column: column,
              url: url,
              confidence: 0.8,
            };

            const needsSourceMap = true;

            if (window.__consolelogSourceMapResolver && needsSourceMap) {
              try {
                const resolved =
                  await window.__consolelogSourceMapResolver.resolveLocation(
                    location,
                  );
                if (resolved && resolved.sourceMapped) {
                  return resolved;
                }
              } catch (e) {
              }
            }

            return location;
          }
        }
      }
    }

    return {
      file: "unknown",
      line: 1,
      column: 0,
      confidence: 0,
    };
  }

  function formatArguments(args) {
    const cleanArgs = [...args];

    if (cleanArgs.length >= 2 && typeof cleanArgs[0] === "string") {
      const firstArg = cleanArgs[0];
      if (
        (firstArg.includes("\u001b[") || firstArg.includes("\\u001b[")) &&
        firstArg.includes("%s")
      ) {
        cleanArgs.shift();
      }
    }

    return cleanArgs
      .map((arg) => {
        if (arg === undefined) return "undefined";
        if (arg === null) return "null";
        if (typeof arg === "object") {
          try {
            return JSON.stringify(arg, null, 2);
          } catch (e) {
            if (arg.constructor && arg.constructor.name) {
              return `[${arg.constructor.name}]`;
            }
            return "[Object]";
          }
        }
        const str = String(arg);
        return str.replace(/\x1b\[[0-9;]*m/g, "");
      })
      .join(" ");
  }

  function generateFingerprint(method, args) {
    const cleanedArgs = [...args];

    if (cleanedArgs.length >= 2 && typeof cleanedArgs[0] === "string") {
      const firstArg = cleanedArgs[0];
      if (
        (firstArg.includes("\u001b[") || firstArg.includes("\\u001b[")) &&
        firstArg.includes("%s")
      ) {
        cleanedArgs.shift();
      }
    }

    const pattern = cleanedArgs
      .map((arg) => {
        if (arg === undefined) return "undefined";
        if (arg === null) return "null";
        if (typeof arg === "string") {
          const cleaned = arg.replace(/\x1b\[[0-9;]*m/g, "").trim();
          if (cleaned.length > 50) {
            return cleaned.substring(0, 50);
          }
          return cleaned;
        }
        if (typeof arg === "number") return "{number}";
        if (typeof arg === "boolean") return `{${arg}}`;
        if (typeof arg === "object") {
          if (Array.isArray(arg)) return "{array}";
          return "{object}";
        }
        if (typeof arg === "function") return "{function}";
        return "{unknown}";
      })
      .join(",");

    return `${method}:${pattern}`;
  }

  let connection = null;
  let projectId = getProjectIdentifier();

  async function initializeConnection() {
    const port = config.port;
    connection = new ConsoleLogConnection(port, projectId);
    await connection.connect();
  }

  let capturedTrace = null;

  const originalPrepareStackTrace = Error.prepareStackTrace;
  Error.prepareStackTrace = (err, stack) => {
    capturedTrace = stack;
    return originalPrepareStackTrace
      ? originalPrepareStackTrace(err, stack)
      : err.stack;
  };

  ["log", "error", "warn", "info", "debug"].forEach((method) => {
    const original = __originalConsole[method];

    // Store current console method (might be overridden by DevTools)
    const currentConsole = console[method];

    console[method] = function (...args) {
      capturedTrace = null;
      const err = new Error();
      const stack = err.stack;

      // Always call the original native console method for actual output
      // This ensures DevTools and browser get normal console behavior
      const result = original.apply(console, arguments);

      if (!window.__consolelogEnabled) {
        return result;
      }

      if (
        args[0] &&
        typeof args[0] === "string" &&
        args[0].includes("[ConsoleLog.nvim]")
      ) {
        return result;
      }

      // If there was a DevTools override, call it too but don't let it interfere
      if (
        currentConsole &&
        currentConsole !== original &&
        currentConsole !== console[method]
      ) {
        try {
          currentConsole.apply(console, arguments);
        } catch (e) {
          // Ignore DevTools errors, our main call already succeeded
        }
      }

      const formattedMessage = formatArguments(args);
      const formattedFingerprint = generateFingerprint(method, args);

      // Process for ConsoleLog asynchronously (don't block)
      setTimeout(() => {
        extractLocationFromStack(stack)
          .then((location) => {
            if (location.file === "unknown" || location.confidence === 0) {
              return;
            }

            const locationKey =
              location.file + ":" + location.line + ":" + location.column;

            const message = {
              type: "console",
              method: method,
              message: formattedMessage,
              location: location,
              locationKey: locationKey,
              fingerprint: formattedFingerprint,
              executionCount: connection
                ? connection.getExecutionCount(locationKey)
                : 1,
              framework: window.__CONSOLELOG_FRAMEWORK || "unknown",
              context: {
                projectId: projectId,
                url: window.location.href,
                timestamp: Date.now(),
              },
            };

            if (connection) {
              connection.addMessage(message);
            } else {
              initializeConnection().then(() => {
                if (connection) {
                  connection.addMessage(message);
                }
              });
            }
          })
          .catch((e) => {
            // Use original console for error logging to avoid conflicts
          });
      }, 0);

      // Return the original result immediately
      return result;
    };
  });

  initializeConnection();
})();
