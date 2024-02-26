local BaseAction = require("ogpt.flows.actions.base")
local Response = require("ogpt.response")
local Spinner = require("ogpt.spinner")
local PopupWindow = require("ogpt.flows.actions.popup.window")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")

local PopupAction = BaseAction:extend("PopupAction")

local STRATEGY_REPLACE = "replace"
local STRATEGY_APPEND = "append"
local STRATEGY_PREPEND = "prepend"
local STRATEGY_DISPLAY = "display"
local STRATEGY_QUICK_FIX = "quick_fix"

function PopupAction:init(name, opts)
  self.name = name or ""
  PopupAction.super.init(self, opts)

  local popup_options = Config.options.popup
  popup_options = vim.tbl_extend("force", popup_options, opts.type_opts or {})

  self.provider = Config.get_provider(opts.provider, self)
  -- self.params = Config.get_action_params(self.provider, opts.params or {})
  self.params = self.provider:get_action_params(opts.params)
  self.system = type(opts.system) == "function" and opts.system() or opts.system or ""
  self.template = type(opts.template) == "function" and opts.template() or opts.template or "{{{input}}}"
  self.variables = opts.variables or {}
  self.on_events = opts.on_events or {}
  self.strategy = opts.strategy or STRATEGY_DISPLAY
  self.ui = opts.ui or {}
  self.cur_win = vim.api.nvim_get_current_win()
  self.output_panel = PopupWindow(popup_options)
  self.spinner = Spinner:new(function(state) end)

  self:update_variables()

  self.output_panel:on({ "BufUnload" }, function()
    self:set_loading(false)
  end)
end

function PopupAction:close()
  self.stop = true
  self.output_panel:unmount()
end

function PopupAction:run()
  -- self.stop = false
  local response = Response(self.provider)
  local params = self:get_params()
  local _, start_row, start_col, end_row, end_col = self:get_visual_selection()
  local opts = {
    name = self.name,
    cur_win = self.cur_win,
    main_bufnr = self:get_bufnr(),
    selection_idx = {
      start_row = start_row,
      start_col = start_col,
      end_row = end_row,
      end_col = end_col,
    },
    default_ui = self.ui,
    title = self.opts.title,
    args = self.opts.args,
    stop = function()
      self:close()
      -- self.stop = true
    end,
  }

  if self.strategy == STRATEGY_DISPLAY then
    self:set_loading(true)
    self.output_panel:mount(opts)
    params.stream = true
    self.provider.api:chat_completions(response, {
      custom_params = params,
      partial_result_fn = function(...)
        self:addAnswerPartial(...)
      end,
      should_stop = function()
        -- should stop function
        if self.stop then
          -- self.stop = false
          -- self:run_spinner(false)
          self:set_loading(false)
          return true
        else
          return false
        end
      end,
    })
  else
    self:set_loading(true)
    self.provider.api:chat_completions(response, {
      custom_params = params,
      partial_result_fn = function(...)
        self:on_result(...)
      end,
      should_stop = nil,
    })
  end
end

function PopupAction:on_result(answer, usage)
  self:set_loading(false)
  local lines = utils.split_string_by_line(answer)
  local _, start_row, start_col, end_row, end_col = self:get_visual_selection()
  local bufnr = self:get_bufnr()
  if self.strategy == STRATEGY_PREPEND then
    answer = answer .. "\n" .. self:get_selected_text()
    vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
  elseif self.strategy == STRATEGY_APPEND then
    answer = self:get_selected_text() .. "\n\n" .. answer .. "\n"
    vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
  elseif self.strategy == STRATEGY_REPLACE then
    answer = answer
    vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
  elseif self.strategy == STRATEGY_QUICK_FIX then
    if #lines == 1 and lines[1] == "<OK>" then
      vim.notify("Your Code looks fine, no issues.", vim.log.levels.INFO)
      return
    end

    local entries = {}
    for _, line in ipairs(lines) do
      local lnum, text = line:match("(%d+):(.*)")
      if lnum then
        local entry = { filename = vim.fn.expand("%:p"), lnum = tonumber(lnum), text = text }
        table.insert(entries, entry)
      end
    end
    if entries then
      vim.fn.setqflist(entries)
      vim.cmd(Config.options.show_quickfixes_cmd)
    end
  end

  -- set the cursor onto the answer
  if self.strategy == STRATEGY_APPEND then
    local target_line = end_row + 3
    vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  end
end

return PopupAction
