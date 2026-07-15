local M = {}

local describe_stack = {}

local function current_depth()
  return #describe_stack
end

local function push_describe_context()
  local ctx = { failed = false }
  table.insert(describe_stack, ctx)
  return ctx
end

local function pop_describe_context()
  return table.remove(describe_stack)
end

local function mark_child_failed()
  if #describe_stack > 0 then
    describe_stack[#describe_stack].failed = true
  end
end

M.assert = {
  equals = function(actual, expected, message)
    if actual ~= expected then
      error(string.format("%s\nExpected: %s\nActual: %s", 
        message or "Assertion failed", 
        vim.inspect(expected), 
        vim.inspect(actual)))
    end
  end,
  
  not_equals = function(actual, expected, message)
    if actual == expected then
      error(string.format("%s\nShould not equal: %s", 
        message or "Assertion failed", 
        vim.inspect(expected)))
    end
  end,
  
  is_true = function(value, message)
    if not value then
      error(string.format("%s\nExpected true, got: %s", 
        message or "Assertion failed", 
        vim.inspect(value)))
    end
  end,
  
  is_false = function(value, message)
    if value then
      error(string.format("%s\nExpected false, got: %s", 
        message or "Assertion failed", 
        vim.inspect(value)))
    end
  end,
  
  is_nil = function(value, message)
    if value ~= nil then
      error(string.format("%s\nExpected nil, got: %s", 
        message or "Assertion failed", 
        vim.inspect(value)))
    end
  end,
  
  nil_value = function(value, message)
    if value ~= nil then
      error(string.format("%s\nExpected nil, got: %s", 
        message or "Assertion failed", 
        vim.inspect(value)))
    end
  end,
  
  not_nil = function(value, message)
    if value == nil then
      error(string.format("%s\nExpected non-nil value", 
        message or "Assertion failed"))
    end
  end,
  
  contains = function(table, value, message)
    for _, v in pairs(table) do
      if v == value then
        return
      end
    end
    error(string.format("%s\nTable does not contain: %s", 
      message or "Assertion failed", 
      vim.inspect(value)))
  end,
  
  deep_equals = function(actual, expected, message)
    if vim.deep_equal(actual, expected) == false then
      error(string.format("%s\nExpected: %s\nActual: %s", 
        message or "Deep comparison failed", 
        vim.inspect(expected), 
        vim.inspect(actual)))
    end
  end,
  
  throws = function(fn, message)
    local success = pcall(fn)
    if success then
      error(string.format("%s\nExpected function to throw", 
        message or "Assertion failed"))
    end
  end,
  
  no_throw = function(fn, message)
    local success, err = pcall(fn)
    if not success then
      error(string.format("%s\nFunction threw: %s", 
        message or "Assertion failed", 
        err))
    end
  end
}

M.describe = function(name, fn)
  local depth = current_depth()
  local indent = string.rep("  ", depth)
  print(indent .. "Testing: " .. name)
  local ctx = push_describe_context()
  local success, err = pcall(fn)
  pop_describe_context()

  local result_indent = string.rep("  ", depth + 1)
  if success and not ctx.failed then
    print(result_indent .. "✓ " .. name .. " passed")
    return true
  else
    if not success then
      print(result_indent .. "✗ " .. name .. " failed: " .. err)
      print("FAILED: " .. name .. ": " .. tostring(err))
    else
      print(result_indent .. "✗ " .. name .. " failed (child test(s) failed)")
      print("FAILED: " .. name)
    end
    mark_child_failed()
    return false
  end
end

M.it = function(name, fn)
  local depth = current_depth()
  local indent = string.rep("  ", depth + 1)
  local success, err = pcall(fn)
  if success then
    print(indent .. "✓ " .. name)
    return true
  else
    print(indent .. "✗ " .. name .. ": " .. err)
    print("FAILED: " .. name .. ": " .. tostring(err))
    mark_child_failed()
    return false
  end
end

M.before_each = function(fn)
  return fn
end

M.after_each = function(fn)
  return fn
end

M.mock = {
  new = function(name)
    local mock = {
      name = name or "mock",
      calls = {},
      return_value = nil,
      call_count = 0
    }
    
    setmetatable(mock, {
      __call = function(self, ...)
        self.call_count = self.call_count + 1
        table.insert(self.calls, {...})
        return self.return_value
      end
    })
    
    mock.returns = function(self, value)
      self.return_value = value
      return self
    end
    
    mock.was_called = function(self)
      return self.call_count > 0
    end
    
    mock.was_called_with = function(self, ...)
      local args = {...}
      for _, call in ipairs(self.calls) do
        if vim.deep_equal(call, args) then
          return true
        end
      end
      return false
    end
    
    mock.reset = function(self)
      self.calls = {}
      self.call_count = 0
      self.return_value = nil
    end
    
    return mock
  end
}

M.async = {
  wait = function(ms)
    vim.wait(ms or 100)
  end,
  
  wait_for = function(condition, timeout)
    timeout = timeout or 1000
    local start = vim.loop.now()
    while vim.loop.now() - start < timeout do
      if condition() then
        return true
      end
      vim.wait(10)
    end
    return false
  end
}

return M
