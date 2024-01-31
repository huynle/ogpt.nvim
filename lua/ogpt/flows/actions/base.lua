local classes = require("ogpt.common.classes")
local Signs = require("ogpt.signs")
local Spinner = require("ogpt.spinner")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")
local PopupWindow = require("ogpt.common.popup_window")

local BaseAction = classes.class()

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
end

function BaseAction:post_init()
  self.popup = PopupWindow()
  self.spinner = Spinner:new(function(state)
    -- vim.schedule(function()
    --   self:display_input_suffix(state)
    -- end)
  end)

  self:update_variables()
end

function BaseAction:get_bufnr()
  if not self._bufnr then
    self._bufnr = vim.api.nvim_get_current_buf()
  end
  return self._bufnr
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
    filetype = self:get_filetype(),
    input = self:get_selected_text(),
  })
end

function BaseAction:render_template()
  local result = self.template
  for key, value in pairs(self.variables) do
    local escaped_value = utils.escape_pattern(value)
    result = string.gsub(result, "{{" .. key .. "}}", escaped_value)
  end
  return result
end

function BaseAction:get_params()
  local messages = self.params.messages or {}
  local message = {
    role = "user",
    content = self:render_template(),
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
    self:set_lines(self.popup.bufnr, 0, -1, false, {})
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
  if self.stop and self.extmark_id and utils.is_buf_exists(self.popup.bufnr) then
    vim.api.nvim_buf_del_extmark(self.popup.bufnr, Config.namespace_id, self.extmark_id)
  end

  if not self.stop and suffix and vim.fn.bufexists(self.popup.bufnr) then
    self.extmark_id = vim.api.nvim_buf_set_extmark(self.popup.bufnr, Config.namespace_id, 0, -1, {
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

return BaseAction
