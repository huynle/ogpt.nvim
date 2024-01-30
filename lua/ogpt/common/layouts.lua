local Config = require("ogpt.config")
local SimpleParameters = require("ogpt.simple_parameters")
local Layout = require("nui.layout")

local M = {}

M.edit_with_nui_layout = function(layout, input, instruction, output, parameters, opts)
  opts = opts or {}
  local _boxes
  if opts.show_parameters then
    _boxes = Layout.Box({
      Layout.Box({
        Layout.Box(input, { grow = 1 }),
        Layout.Box(instruction, { size = 3 }),
      }, { dir = "col", grow = 1 }),
      Layout.Box(output, { grow = 1 }),
      Layout.Box(parameters, { size = 40 }),
    }, { dir = "row" })
  else
    _boxes = Layout.Box({
      Layout.Box({
        Layout.Box(input, { grow = 1 }),
        Layout.Box(instruction, { size = 3 }),
      }, { dir = "col", size = "50%" }),
      Layout.Box(output, { size = "50%" }),
    }, { dir = "row" })
  end

  if not layout then
    layout = Layout({
      relative = "editor",
      position = "50%",
      size = {
        width = Config.options.popup_layout.center.width,
        height = Config.options.popup_layout.center.height,
      },
    }, _boxes)
  else
    layout:update(_boxes)
  end

  layout:mount()

  if opts.show_parameters then
    parameters:show()
    parameters:mount()

    vim.api.nvim_set_current_win(parameters.winid)
    vim.api.nvim_buf_set_option(parameters.bufnr, "modifiable", false)
    vim.api.nvim_win_set_option(parameters.winid, "cursorline", true)
  else
    parameters:hide()
    vim.api.nvim_set_current_win(instruction.winid)
  end

  return layout
end

M.edit_with_no_layout = function(layout, input, instruction, output, parameters, opts)
  opts = opts or {}
  opts = vim.tbl_extend("force", opts, {
    buf = {
      vars = {
        ogpt = true,
      },
    },
  })

  input:mount()
  output:mount()
  instruction:mount()

  if opts.show_parameters then
    parameters:mount()

    vim.api.nvim_set_current_win(parameters.winid)
    vim.api.nvim_buf_set_option(parameters.bufnr, "modifiable", false)
    vim.api.nvim_win_set_option(parameters.winid, "cursorline", true)

    SimpleParameters.refresh_panel()
  else
    parameters:hide()
    -- vim.api.nvim_set_current_win(instruction.winid)
  end

  return nil
end

return M
