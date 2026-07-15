"""ConsoleLog Python runner — captures print/logging/stderr/exception events.

Stdlib only, Python 3.8+ compatible. Emits line-delimited sentinel-prefixed
JSON on stdout so a Neovim plugin can parse structured console events while
preserving normal program output.
"""

import builtins
import json
import logging
import os
import runpy
import sys
import traceback

SENTINEL = "__CONSOLELOG_EVENT__"
_RUN_ID = os.environ.get("CONSOLELOG_RUN_ID", "")

# Capture the real stdout at startup — events go here, never to the
# (potentially replaced) sys.stdout.
_real_stdout = sys.stdout
_real_stderr = sys.stderr


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------


def _serialize_arg(value):
    """Convert a Python value to a JSON-safe representation."""
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, dict):
        try:
            return json.loads(json.dumps(value, default=repr))
        except (TypeError, ValueError):
            return repr(value)
    if isinstance(value, (list, tuple)):
        try:
            return json.loads(json.dumps(list(value), default=repr))
        except (TypeError, ValueError):
            return repr(value)
    try:
        return repr(value)
    except Exception:
        return f"<unprintable {type(value).__name__}>"


# ---------------------------------------------------------------------------
# Event emission
# ---------------------------------------------------------------------------


def emit_console(method, args, filename, lineno):
    event = {
        "event": "console",
        "method": method,
        "file": filename,
        "line": lineno,
        "args": args,
    }
    if _RUN_ID:
        event["run_id"] = _RUN_ID
    _real_stdout.write(SENTINEL + json.dumps(event, default=repr) + "\n")
    _real_stdout.flush()


def emit_exception(text, filename, lineno):
    event = {
        "event": "exception",
        "file": filename,
        "line": lineno,
        "text": text,
    }
    if _RUN_ID:
        event["run_id"] = _RUN_ID
    _real_stdout.write(SENTINEL + json.dumps(event, default=repr) + "\n")
    _real_stdout.flush()


# ---------------------------------------------------------------------------
# Caller location helper
# ---------------------------------------------------------------------------


def _caller_location(skip_modules=()):
    """Walk the stack outward and return (abspath, lineno) of the first frame
    whose filename is not this runner and whose module is not in *skip_modules*.
    """
    frame = sys._getframe(1)
    this_file = os.path.abspath(__file__)
    while frame is not None:
        fname = os.path.abspath(frame.f_code.co_filename)
        if fname != this_file:
            mod = frame.f_globals.get("__name__", "")
            if not any(mod.startswith(m) for m in skip_modules):
                return fname, frame.f_lineno
        frame = frame.f_back
    # Fallback — shouldn't normally happen
    return this_file, 1


# ---------------------------------------------------------------------------
# print wrapper
# ---------------------------------------------------------------------------

_original_print = builtins.print


def _patched_print(*args, **kwargs):
    fname, lineno = _caller_location()
    try:
        serialized = [_serialize_arg(a) for a in args]
    except Exception:
        serialized = []
        for a in args:
            try:
                serialized.append(
                    repr(a) if not isinstance(a, (str, int, float, bool)) else a
                )
            except Exception:
                serialized.append(f"<unprintable {type(a).__name__}>")
    emit_console("log", serialized, fname, lineno)
    # Forward to the real print so plain stdout is preserved
    _original_print(*args, **kwargs)


# ---------------------------------------------------------------------------
# Logging handler
# ---------------------------------------------------------------------------

_LEVEL_TO_METHOD = {
    logging.DEBUG: "debug",
    logging.INFO: "info",
    logging.WARNING: "warn",
    logging.ERROR: "error",
    logging.CRITICAL: "error",
}


class _ConsoleLogHandler(logging.Handler):
    def emit(self, record):
        try:
            method = _LEVEL_TO_METHOD.get(record.levelno, "log")
            fname = os.path.abspath(record.pathname)
            emit_console(method, [record.getMessage()], fname, record.lineno)
        except Exception:
            self.handleError(record)


# ---------------------------------------------------------------------------
# Logger.callHandlers patch — preserve default basicConfig behaviour
# ---------------------------------------------------------------------------

# The module-level logging functions (logging.warning, etc.) check
# ``len(root.handlers) == 0`` before calling basicConfig().  Our handler
# on root makes this check fail, so basicConfig() never runs and the
# default StreamHandler (which produces ``WARNING:root:msg`` on stderr)
# is never installed.  We patch callHandlers to detect the condition
# (root has only _ConsoleLogHandler instances) and call the *original*
# basicConfig before the iteration begins.

_original_callHandlers = logging.Logger.callHandlers
_orig_basicConfig = None  # set in main() before handler installation


def _patched_callHandlers(self, record):
    # Only trigger the root-bootstrap logic for the root logger itself.
    # Named loggers (including non-propagating ones) must not pre-install
    # root's default handler, which would silence a later target
    # logging.basicConfig(...) call.
    if self is logging.root and _orig_basicConfig is not None:
        root_only_ours = not any(
            h for h in logging.root.handlers if not isinstance(h, _ConsoleLogHandler)
        )
        if root_only_ours:
            # Temporarily remove our handler so basicConfig() sees an empty list
            ours = [
                h for h in logging.root.handlers if isinstance(h, _ConsoleLogHandler)
            ]
            for h in ours:
                logging.root.removeHandler(h)
            _orig_basicConfig()
            for h in ours:
                logging.root.addHandler(h)
    _original_callHandlers(self, record)


# ---------------------------------------------------------------------------
# stderr proxy
# ---------------------------------------------------------------------------


class _StderrProxy:
    """Wraps sys.stderr, buffering writes until a newline completes a line,
    then emitting a console/error event.  Writes originating from the logging
    package are forwarded without emitting (to avoid duplication).

    Tracks the source location of each buffered fragment so that partial writes
    followed by logging output or exception-triggered flushes retain the correct
    caller attribution.
    """

    _STDERR_SKIP_MODULES = ("logging", "warnings", "traceback")

    def __init__(self):
        self._buf = ""
        self._source = None  # (filename, lineno) of the buffer's origin
        self._source_set = False  # whether _source has been attributed
        self._real = _real_stderr

    def _is_logging_frame(self):
        frame = sys._getframe(1)
        while frame is not None:
            mod = frame.f_globals.get("__name__", "")
            if mod.startswith("logging"):
                return True
            frame = frame.f_back
        return False

    def _caller_location(self):
        return _caller_location(skip_modules=self._STDERR_SKIP_MODULES)

    def _emit_buf_line(self):
        """Emit the current buffer contents as an error event using the stored
        source location, then clear the buffer."""
        if self._buf:
            fname, lineno = self._source or self._caller_location()
            emit_console("error", [self._buf.rstrip("\n")], fname, lineno)
            self._buf = ""
            self._source = None
            self._source_set = False

    def write(self, s):
        if not isinstance(s, str):
            # Native stderr raises TypeError for non-string writes; do the same
            # so caller code gets the expected exception behaviour.
            self._real.write(s)  # raises TypeError
            return 0  # unreachable, but satisfies type checkers
        # Always forward to real stderr immediately
        self._real.write(s)

        is_logging = self._is_logging_frame()

        if is_logging:
            # Don't buffer logging writes — the logging handler already emits
            # events through our _ConsoleLogHandler.  But first, flush any
            # pending non-logging content so it isn't lost or concatenated.
            if self._buf:
                self._emit_buf_line()
            return len(s)

        # Non-logging write: capture source location when buffer is empty
        if not self._buf:
            if not self._source_set:
                self._source = self._caller_location()
                self._source_set = True

        # Buffer for event emission
        self._buf += s
        while "\n" in self._buf:
            idx = self._buf.index("\n") + 1
            line = self._buf[:idx]
            self._buf = self._buf[idx:]
            fname, lineno = self._source or self._caller_location()
            emit_console("error", [line.rstrip("\n")], fname, lineno)
            if self._buf:
                # Remaining partial content retains the current source location
                # so that flush() attributes it to the original caller.
                pass
            else:
                self._source = None
                self._source_set = False
        return len(s)

    def flush(self):
        # Emit any remaining partial line using the stored source location
        if self._buf:
            fname, lineno = self._source or self._caller_location()
            remaining = self._buf
            self._buf = ""
            self._source = None
            self._source_set = False
            emit_console("error", [remaining], fname, lineno)
        self._real.flush()

    def writelines(self, lines):
        for line in lines:
            self.write(line)

    def __getattr__(self, name):
        return getattr(self._real, name)


def _resolve_exception_location(exc_type, exc_value, exc_tb, target):
    """Resolve (filename, lineno) for an exception, preferring target file frames.

    Selection order:
    1. Deepest traceback frame in the target file (if any).
    2. SyntaxError metadata when a target-frame traceback exists but no frame
       matched the target (compile-time errors have accurate lineno/filename
       but the traceback originates in runpy).
    3. Deepest traceback frame overall (fallback for imported-module exceptions
       whose traceback does not include the target file).
    4. SyntaxError metadata as last resort (bare ``raise SyntaxError(…)``).
    """
    target_abs = os.path.abspath(target)
    # Walk traceback: prefer the deepest target-frame, otherwise the deepest frame
    if exc_tb is not None:
        deepest_frame = None
        target_frame = None
        for frame, lineno in traceback.walk_tb(exc_tb):
            frame_fname = os.path.abspath(frame.f_code.co_filename)
            deepest_frame = (frame_fname, lineno)
            if frame_fname == target_abs:
                target_frame = (frame_fname, lineno)
        if target_frame is not None:
            return target_frame
        # No target frame found — prefer SyntaxError metadata over a
        # non-target deepest frame (e.g. runpy internals for compile errors).
        if isinstance(exc_value, SyntaxError) and exc_value.lineno is not None:
            fname = (
                os.path.abspath(exc_value.filename)
                if exc_value.filename
                else target_abs
            )
            return fname, exc_value.lineno
        if deepest_frame is not None:
            return deepest_frame
    # SyntaxError metadata — last resort when no traceback is available
    if isinstance(exc_value, SyntaxError) and exc_value.lineno is not None:
        fname = (
            os.path.abspath(exc_value.filename) if exc_value.filename else target_abs
        )
        return fname, exc_value.lineno
    return target_abs, 1


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main():
    if len(sys.argv) < 2:
        _real_stderr.write("Usage: python consolelog_runner.py <script.py>\n")
        _real_stderr.flush()
        sys.exit(2)

    target = sys.argv[1]
    if not os.path.isfile(target):
        _real_stderr.write(f"Error: file not found: {target}\n")
        _real_stderr.flush()
        sys.exit(2)

    # Shift argv so the target script sees sys.argv[0] == its own path
    sys.argv = sys.argv[1:]

    # Insert the target's directory at the front of sys.path
    target_dir = os.path.dirname(os.path.abspath(target))
    if target_dir in sys.path:
        sys.path.remove(target_dir)
    sys.path.insert(0, target_dir)

    # Install hooks
    builtins.print = _patched_print
    root_handler = _ConsoleLogHandler()
    logging.root.addHandler(root_handler)

    # Wrap basicConfig so it works with our pre-attached handler:
    # temporarily remove our handler, let basicConfig configure normally,
    # then reattach ours.
    global _orig_basicConfig
    _orig_basicConfig = logging.basicConfig

    def _wrapped_basicConfig(**kwargs):
        logging.root.removeHandler(root_handler)
        _orig_basicConfig(**kwargs)
        logging.root.addHandler(root_handler)

    logging.basicConfig = _wrapped_basicConfig

    # Patch callHandlers so basicConfig() is triggered when root has only
    # our handler (preserving Python's default stderr logging output).
    logging.Logger.callHandlers = _patched_callHandlers

    sys.stderr = _StderrProxy()

    try:
        runpy.run_path(target, run_name="__main__")
    except SystemExit as e:
        # SystemExit with code 0 or None is a clean exit — no exception event
        if e.code not in (0, None):
            exc_type, exc_value, exc_tb = sys.exc_info()
            exc_file, lineno = _resolve_exception_location(
                exc_type, exc_value, exc_tb, target
            )
            text = f"{type(exc_value).__name__}: {exc_value}"
            emit_exception(text, exc_file, lineno)
            sys.stderr.flush()
            sys.exit(e.code if e.code is not None else 1)
    except BaseException:
        exc_type, exc_value, exc_tb = sys.exc_info()
        exc_file, lineno = _resolve_exception_location(
            exc_type, exc_value, exc_tb, target
        )
        text = f"{exc_type.__name__}: {exc_value}"
        emit_exception(text, exc_file, lineno)
        sys.stderr.flush()
        sys.exit(1)
    # Clean exit — flush any buffered stderr events so partial writes are emitted
    sys.stderr.flush()


if __name__ == "__main__":
    main()
