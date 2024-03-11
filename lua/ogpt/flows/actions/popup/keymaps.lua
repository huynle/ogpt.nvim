local utils = require("ogpt.utils")
local Config = require("ogpt.config")

local M = {}

function M.apply_map(popup, opts)
  -- accept output and replace
  popup:map("n", Config.options.popup.keymaps.accept, function()
    -- local _lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    local _lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    -- table.insert(_lines, "")
    vim.api.nvim_buf_set_text(
      opts.main_bufnr,
      opts.selection_idx.start_row - 1,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.end_row - 1,
      opts.selection_idx.end_col,
      _lines
    )
    vim.cmd("q")
  end)

  -- accept output and prepend
  popup:map("n", Config.options.popup.keymaps.prepend, function()
    local _lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    table.insert(_lines, "")
    table.insert(_lines, "")
    vim.api.nvim_buf_set_text(
      opts.main_bufnr,
      opts.selection_idx.start_row - 1,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.start_row - 1,
      opts.selection_idx.start_col - 1,
      _lines
    )
    vim.cmd("q")
  end)

  -- accept output and append
  popup:map("n", Config.options.popup.keymaps.append, function()
    local _lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    local line_count = vim.api.nvim_buf_line_count(opts.main_bufnr)
    if line_count == opts.selection_idx.end_row then
      -- add an additional line, if not, we get index out or range
      vim.api.nvim_buf_set_lines(opts.main_bufnr, line_count, line_count, false, { "" })
    end
    table.insert(_lines, 1, "")
    table.insert(_lines, "")
    vim.api.nvim_buf_set_text(
      opts.main_bufnr,
      opts.selection_idx.end_row,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.end_row,
      opts.selection_idx.start_col - 1,
      _lines
    )
    vim.cmd("q")
  end)

  -- yank code in output and close
  popup:map("n", Config.options.popup.keymaps.yank_code, function()
    local _lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    local _code = utils.getSelectedCode(_lines)
    vim.fn.setreg(Config.options.yank_register, _code)

    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
    vim.cmd("q")
  end)

  -- yank output and close
  popup:map("n", Config.options.popup.keymaps.yank_to_register, function()
    local _lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    vim.fn.setreg(Config.options.yank_register, _lines)

    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
    vim.cmd("q")
  end)

  local keys = Config.options.popup.keymaps.close
  if type(keys) ~= "table" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    popup:map("n", key, function()
      if opts.stop and type(opts.stop) == "function" then
        opts.stop()
      end
      popup:unmount()
    end)
  end
end

return M
