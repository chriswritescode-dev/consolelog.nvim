(function () {
  if (globalThis.__consolelogNodeFormat) return "already";

  var util =
    typeof process.getBuiltinModule === "function"
      ? process.getBuiltinModule("node:util")
      : null;

  if (!util || typeof util.inspect !== "function") return "unavailable";

  var options = {
    depth: 4,
    breakLength: 100,
    maxArrayLength: 200,
    maxStringLength: 10000,
    colors: false,
    getters: false,
  };

  function describe(value) {
    var kind = typeof value;
    if (kind !== "function" && (value === null || kind !== "object")) return value;
    try {
      return util.inspect(value, options);
    } catch (error) {
      return "[Unserializable]";
    }
  }

  ["log", "info", "warn", "error", "debug", "trace"].forEach(function (method) {
    var original = console[method];
    if (typeof original !== "function") return;

    console[method] = function () {
      var args = new Array(arguments.length);
      for (var i = 0; i < arguments.length; i++) {
        args[i] = describe(arguments[i]);
      }
      return original.apply(console, args);
    };
  });

  globalThis.__consolelogNodeFormat = true;
  return "ok";
})();
//# sourceURL=consolelog-node-format.js
