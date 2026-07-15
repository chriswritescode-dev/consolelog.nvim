local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"
local utils = require('consolelog.core.utils')

describe("Buffer Filtering", function()
  describe("is_supported_buffer", function()
    it("should reject buffers with non-empty buftype", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "javascript")

      local result = utils.is_supported_buffer(bufnr)
      assert.is_false(result, "Should reject nofile buffers even with javascript filetype")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should reject quickfix buffers", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "quickfix")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "qf")

      local result = utils.is_supported_buffer(bufnr)
      assert.is_false(result, "Should reject quickfix buffers")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should reject help buffers", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "help")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "help")

      local result = utils.is_supported_buffer(bufnr)
      assert.is_false(result, "Should reject help buffers")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should accept regular buffers with javascript filetype", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "javascript")

      local result = utils.is_supported_buffer(bufnr)
      assert.is_true(result, "Should accept regular buffers with javascript filetype")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should accept regular buffers with python filetype", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "python")

      local result = utils.is_supported_buffer(bufnr)
      assert.is_true(result, "Should accept regular buffers with python filetype")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should reject URI-backed virtual buffers", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "typescriptreact")
      vim.api.nvim_buf_set_name(bufnr, "diffview:///repo/.git/:0:/app/example.tsx")

      local result = utils.is_supported_buffer(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.is_false(result, "Should reject virtual URI buffers")
    end)
  end)

  describe("is_javascript_buffer", function()
    it("should reject buffers with non-empty buftype", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "javascript")

      local result = utils.is_javascript_buffer(bufnr)
      assert.is_false(result, "Should reject nofile buffers even with javascript filetype")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("is_python_buffer", function()
    it("should reject buffers with non-empty buftype", function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
      vim.api.nvim_buf_set_option(bufnr, "filetype", "python")

      local result = utils.is_python_buffer(bufnr)
      assert.is_false(result, "Should reject nofile buffers even with python filetype")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("find_regular_buffer_window", function()
    it("should reject diff windows containing regular buffers", function()
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "")
      vim.api.nvim_win_set_buf(winid, bufnr)
      vim.api.nvim_win_set_option(winid, "diff", true)

      local result = utils.find_regular_buffer_window(bufnr, winid)

      vim.api.nvim_win_set_option(winid, "diff", false)
      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.is_nil(result, "Should reject diff windows")
    end)

    it("should accept non-diff windows containing regular buffers", function()
      local winid = vim.api.nvim_get_current_win()
      local previous_bufnr = vim.api.nvim_win_get_buf(winid)
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_option(bufnr, "buftype", "")
      vim.api.nvim_win_set_buf(winid, bufnr)

      local result = utils.find_regular_buffer_window(bufnr, winid)

      vim.api.nvim_win_set_buf(winid, previous_bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.equals(result, winid, "Should accept regular buffer windows")
    end)

    it("should reject floating windows containing regular buffers", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      local winid = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        width = 10,
        height = 2,
        row = 0,
        col = 0,
      })

      local result = utils.find_regular_buffer_window(bufnr, winid)

      vim.api.nvim_win_close(winid, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.is_nil(result, "Should reject floating windows")
    end)
  end)
end)
