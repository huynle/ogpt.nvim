local Config = require("ogpt.config")
local utils = require("ogpt.utils")
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

M.edit_with_no_layout = function(layout, parent, input, instruction, output, parameters, opts)
  opts = opts or {}

  vim.schedule_wrap(input:mount())
  vim.schedule_wrap(output:mount())
  vim.schedule_wrap(instruction:mount())

  if opts.show_parameters then
    parameters:mount()

    vim.api.nvim_set_current_win(parameters.winid)
    vim.api.nvim_buf_set_option(parameters.bufnr, "modifiable", false)
    vim.api.nvim_win_set_option(parameters.winid, "cursorline", true)

    parameters:map("n", "d", function()
      local row, _ = unpack(vim.api.nvim_win_get_cursor(parameters.winid))

      local existing_order = {}
      for _, key in ipairs(SimpleParameters.params_order) do
        if SimpleParameters.params[key] ~= nil then
          table.insert(existing_order, key)
        end
      end

      local key = existing_order[row]
      SimpleParameters.update_property(key, row, nil)
      SimpleParameters.refresh_panel()
    end)

    parameters:map("n", "a", function()
      local row, _ = unpack(vim.api.nvim_win_get_cursor(parameters.winid))
      SimpleParameters.select_parameter({
        cb = function(key, value)
          SimpleParameters.update_property(key, row + 1, value)
        end,
      })
    end)

    parameters:map("n", "<CR>", function()
      local row, _ = unpack(vim.api.nvim_win_get_cursor(parameters.winid))

      local existing_order = {}
      for _, key in ipairs(SimpleParameters.params_order) do
        if SimpleParameters.params[key] ~= nil then
          table.insert(existing_order, key)
        end
      end

      local key = existing_order[row]
      if key == "model" then
        local models = require("ogpt.models")
        models.select_model(parent.provider, {
          cb = function(display, value)
            SimpleParameters.update_property(key, row, value)
          end,
        })
      elseif key == "provider" then
        local provider = require("ogpt.provider")
        provider.select_provider({
          cb = function(display, value)
            SimpleParameters.update_property(key, row, value)
            parent.provider = Config.get_provider(value)
          end,
        })
      else
        local value = SimpleParameters.params[key]
        SimpleParameters.open_edit_property_input(key, value, row, function(new_value)
          SimpleParameters.update_property(key, row, utils.process_string(new_value))
        end)
      end
    end, {})

    SimpleParameters.refresh_panel()
  else
    parameters:hide()
    -- vim.api.nvim_set_current_win(instruction.winid)
  end

  return layout
end

return M
