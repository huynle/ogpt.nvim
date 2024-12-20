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
  self.output_panel.parent_winid = self.cur_win
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
  local response = Response(self.provider, {
    on_post_render = function(response)
      self.output_panel:update_popup_size(opts)
    end,
  })

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
  else -- Other Popup strategies: REPLACE, APPEND, PREPEND, QUICK_FIX
    self:set_loading(true)
    self.provider.api:chat_completions(response, {
      custom_params = params,
      partial_result_fn = function(...)
        opts = opts
        self:on_result(...)
      end,
      should_stop = nil,
    })
  end
end

function PopupAction:on_result(response)
  local content = response:pop_content()
  local answer = content[1]
  local state = content[2]


  local bufnr = self:get_bufnr()
  local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

  if state == "ERROR" then
    self:set_loading(false)
    utils.log("An Error Occurred: " .. answer, vim.log.levels.ERROR)
    return
  end

  if state == "END" then
    self:set_loading(false)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_text(
      bufnr,
      start_row - 1,
      start_col - 1,
      end_row - 1,
      end_col,
      utils.split_string_by_line(answer)
    )
    return
  end

  if state == "START" then
    self:set_loading(true)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    -- Delete the text in the specified selection range
    vim.api.nvim_buf_set_text(
      bufnr,
      opts.selection_idx.start_row - 1,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.end_row - 1,
      opts.selection_idx.end_col,
      { "" }
    )
  end

  if state == "START" or state == "CONTINUE" then
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    local lines = vim.split(answer, "\n", {})
    local length = #lines

    for i, line in ipairs(lines) do
      if i > 1 then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" }) -- add in the new line here
      end
      local currentLine = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1]
      if currentLine then
        vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { currentLine .. line })
      end
    end
  end
end

return PopupAction
