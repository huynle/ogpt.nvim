local Object = require("ogpt.common.object")
local Signs = require("ogpt.signs")
local Spinner = require("ogpt.spinner")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")
local template_helpers = require("ogpt.flows.actions.template_helpers")

local BaseAction = Object("BaseAction")

local namespace_id = vim.api.nvim_create_namespace("OGPTNS")

local function get_selection_center(start_row, start_col, end_row, end_col)
  if start_row < end_row then
    local diff = math.floor((end_row - start_row) / 2)
    start_row = start_row + diff
  end
  return start_row - 1, start_col - 1
end

function BaseAction:init(opts)
  self.opts = opts
  self.stop = true
  self.output_panel = nil
  self.spinner = Spinner:new(function(state) end)
  self.bufnr = self:get_bufnr()
end

function BaseAction:get_bufnr()
  if not self.bufnr then
    self.bufnr = vim.api.nvim_get_current_buf()
  end
  return self.bufnr
end

function BaseAction:get_filetype()
  local bufnr = self:get_bufnr()
  return vim.api.nvim_buf_get_option(bufnr, "filetype")
end

function BaseAction:get_visual_selection()
  -- return lines and selection, but caches them, so they always are the ones used
  -- when the action was started, even if the user has changed buffer/selection
  if self._selection then
    return unpack(self._selection)
  end
  local bufnr = self:get_bufnr()
  local lines, start_row, start_col, end_row, end_col = utils.get_visual_lines(bufnr)
  self._selection = { lines, start_row, start_col, end_row, end_col }

  return lines, start_row, start_col, end_row, end_col
end

function BaseAction:get_selected_text()
  -- selection using vim GV, after selection is made, it remains in
  -- vim registry, and this function recall that selection
  local lines, _, _, _, _ = self:get_visual_selection()
  return table.concat(lines, "\n")
end

function BaseAction:get_selected_text_with_line_numbers()
  local lines, start_row, _, _, _ = self:get_visual_selection()
  local lines_with_numbers = {}
  for i, line in ipairs(lines) do
    table.insert(lines_with_numbers, (start_row + i - 1) .. line)
  end
  return table.concat(lines_with_numbers, "\n")
end

function BaseAction:mark_selection_with_signs()
  local bufnr = self:get_bufnr()
  local _, start_row, _, end_row, _ = self:get_visual_selection()
  Signs.set_for_lines(bufnr, start_row - 1, end_row - 1, "action")
end

function BaseAction:render_spinner(state)
  vim.schedule(function()
    local bufnr = self:get_bufnr()
    local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

    vim.schedule(function()
      if self.extmark_id then
        vim.api.nvim_buf_del_extmark(bufnr, namespace_id, self.extmark_id)
      end
      start_row, start_col = get_selection_center(start_row, start_col, end_row, end_col)
      self.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, namespace_id, start_row, 0, {
        virt_text = {
          { Config.options.chat.border_left_sign, "OGPTTotalTokensBorder" },
          { state .. " Processing, please wait ...", "OGPTTotalTokens" },
          { Config.options.chat.border_right_sign, "OGPTTotalTokensBorder" },
          { " ", "" },
        },
        virt_text_pos = "eol",
      })
    end)
  end)
end

function BaseAction:set_loading(state)
  local bufnr = self:get_bufnr()
  if state then
    if not self.spinner then
      self.spinner = Spinner:new(function(state)
        self:render_spinner(state)
      end)
    end
    self:mark_selection_with_signs()
    self.spinner:start()
    self.stop = false
  else
    self.spinner:stop()
    Signs.del(bufnr)
    if self.extmark_id then
      vim.api.nvim_buf_del_extmark(bufnr, namespace_id, self.extmark_id)
    end
    self.stop = true
  end
end

function BaseAction:run()
  self:set_loading(true)
end

function BaseAction:on_result(answer, usage)
  self:set_loading(false)
end

function BaseAction:update_variables()
  self.variables = vim.tbl_extend("force", self.variables, {
    filetype = function()
      return self:get_filetype()
    end,
    input = function()
      return self:get_selected_text()
    end,
    selection = function()
      return utils.get_selected_range(self:get_bufnr())
    end,
  })

  -- pull in action defined args
  self.variables = vim.tbl_extend("force", self.variables, self.opts.args or {})

  -- add in plugin predefined template helpers
  for helper, helper_fn in pairs(template_helpers) do
    local _v = { [helper] = helper_fn }
    self.variables = vim.tbl_extend("force", self.variables, _v)
  end
end

function BaseAction:render_template(variables)
  variables = vim.tbl_extend("force", self.variables, variables or {})
  -- lazily render the final string.
  -- it recursively loop on the template string until it does not find anymore
  -- {{{}}} patterns
  local stop = false
  local depth = 2
  local template = self.template
  -- deprecating warning of {{}} (double curly)
  if vim.fn.match(template, [[\v\{\{([^}]+)\}\}(})@!]]) ~= -1 then
    utils.log(
      "You may be using the {{<template_helper>}}, please updated to {{{<template_helpers>}}} (triple curly braces)in your custom actions.",
      vim.log.levels.ERROR
    )
  end

  local pattern = "%{%{%{(([%w_]+))%}%}%}"
  repeat
    for match in string.gmatch(template, pattern) do
      local value = variables[match]
      if value then
        -- Get "default" if value is table type
        if type(value) == "table" then
          value = value["default"]
        end
        -- Run function if value is function type
        if type(value) == "function" then
          value = value(self.variables)
        end
        local escaped_value = utils.escape_pattern(value)
        template = string.gsub(template, "{{{" .. match .. "}}}", escaped_value)
      else
        utils.log("Cannot find {{{" .. match .. "}}}", vim.log.levels.ERROR)
        stop = true
      end
    end
    depth = depth - 1
  until not string.match(template, pattern) or stop or depth == 0
  return template
end

function BaseAction:get_params()
  local messages = self.params.messages or {}
  local message = {
    role = "user",
    content = {
      {
        text = self:render_template(),
      },
    },
  }
  table.insert(messages, message)
  return vim.tbl_extend("force", self.params, {
    messages = messages,
    system = self.system and "" == self.system and nil or self.system,
  })
end

function BaseAction:run_spinner(flag)
  if flag then
    self.spinner:start()
  else
    self.spinner:stop()
    if self.output_panel then
      self:set_lines(self.output_panel.bufnr, 0, -1, false, {})
    end
  end
end

function BaseAction:set_lines(bufnr, start_idx, end_idx, strict_indexing, lines)
  if utils.is_buf_exists(bufnr) then
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, strict_indexing, lines)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  end
end

function BaseAction:display_input_suffix(suffix)
  if not self.output_panel then
    return
  end

  if self.stop and self.extmark_id and utils.is_buf_exists(self.output_panel.bufnr) then
    vim.api.nvim_buf_del_extmark(self.output_panel.bufnr, Config.namespace_id, self.extmark_id)
  end

  if not self.stop and suffix and vim.fn.bufexists(self.output_panel.bufnr) then
    self.extmark_id = vim.api.nvim_buf_set_extmark(self.output_panel.bufnr, Config.namespace_id, 0, -1, {
      virt_text = {
        { Config.options.chat.border_left_sign, "OGPTTotalTokensBorder" },
        { "" .. suffix, "OGPTTotalTokens" },
        { Config.options.chat.border_right_sign, "OGPTTotalTokensBorder" },
        { " ", "" },
      },
      virt_text_pos = "right_align",
    })
  end
end

function BaseAction:on_complete(response)
  -- empty
end

function BaseAction:addAnswerPartial(response)
  local content = response:pop_content()
  local text = content[1]
  local state = content[2]

  if state == "ERROR" then
    self:run_spinner(false)
    utils.log("An Error Occurred: " .. text, vim.log.levels.ERROR)
    self.output_panel:unmount()
    return
  end

  if state == "END" then
    utils.log("Received END Flag", vim.log.levels.DEBUG)
    if not utils.is_buf_exists(self.output_panel.bufnr) then
      return
    end
    vim.api.nvim_buf_set_option(self.output_panel.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.output_panel.bufnr, 0, -1, false, {}) -- clear the window, an put the final answer in
    vim.api.nvim_buf_set_lines(self.output_panel.bufnr, 0, -1, false, vim.split(text, "\n"))
    self:on_complete(response)
  end

  if state == "START" then
    self:run_spinner(false)
    if not utils.is_buf_exists(self.output_panel.bufnr) then
      return
    end
    vim.api.nvim_buf_set_option(self.output_panel.bufnr, "modifiable", true)
  end

  if state == "START" or state == "CONTINUE" then
    if not utils.is_buf_exists(self.output_panel.bufnr) then
      return
    end
    vim.api.nvim_buf_set_option(self.output_panel.bufnr, "modifiable", true)
    local lines = vim.split(text, "\n", {})
    local length = #lines

    for i, line in ipairs(lines) do
      if self.output_panel.bufnr and vim.fn.bufexists(self.output_panel.bufnr) then
        if i > 1 then
          -- create a new line in the streaming output only if
          vim.api.nvim_buf_set_lines(self.output_panel.bufnr, -1, -1, false, { "" }) -- add in the new line here
        end
        local currentLine = vim.api.nvim_buf_get_lines(self.output_panel.bufnr, -2, -1, false)[1]
        if currentLine then
          vim.api.nvim_buf_set_lines(self.output_panel.bufnr, -2, -1, false, { currentLine .. line })
        end
      end
    end
  end
end

return BaseAction
