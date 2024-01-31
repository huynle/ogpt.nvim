local classes = require("ogpt.common.classes")
local BaseAction = require("ogpt.flows.actions.base")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")
local SimpleWindow = require("ogpt.common.ui.window")
local popup_keymap = require("ogpt.flows.actions.popup.keymaps")

local PopupAction = classes.class(BaseAction)

local STRATEGY_REPLACE = "replace"
local STRATEGY_APPEND = "append"
local STRATEGY_PREPEND = "prepend"
local STRATEGY_DISPLAY = "display"
local STRATEGY_DISPLAY_WINDOW = "display_window"
local STRATEGY_NEW_DISPLAY_WINDOW = "new_display_window"
local STRATEGY_QUICK_FIX = "quick_fix"

function PopupAction:init(name, opts)
  self.name = name or ""
  self.super:init(opts)
  self.provider = Config.get_provider(opts.provider, self)
  self.params = Config.get_action_params(self.provider.name, opts.params or {})
  self.system = type(opts.system) == "function" and opts.system() or opts.system or ""
  self.template = type(opts.template) == "function" and opts.template() or opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_DISPLAY
  self.ui = opts.ui or {}
  self.cur_win = vim.api.nvim_get_current_win()

  self:post_init()
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
      self.stop = true
    end,
  }

  if self.strategy == STRATEGY_DISPLAY then
    self:set_loading(true)
    self.popup:mount(opts)
    params.stream = true
    self.provider.api:chat_completions(
      params,
      utils.partial(utils.add_partial_completion, {
        panel = self.popup,
        progress = function(flag)
          self:run_spinner(flag)
        end,
        on_complete = function(total_text)
          -- print("completed: " .. total_text)
        end,
      }),
      function()
        -- should stop function
        if self.stop then
          -- self.stop = false
          -- self:run_spinner(false)
          self:set_loading(false)
          return true
        else
          return false
        end
      end
    )
  elseif self.strategy == STRATEGY_DISPLAY_WINDOW or self.strategy == STRATEGY_NEW_DISPLAY_WINDOW then
    self.popup = SimpleWindow("ogpt_popup", {
      new_win = false,
      buf = {
        syntax = "markdown",
      },
      events = {
        {
          events = { "BufUnload" },
          callback = function()
            self:set_loading(false)
          end,
        },
      },
    })
    popup_keymap.apply_map(self.popup, opts)

    self:set_loading(true)
    if self.strategy == STRATEGY_NEW_DISPLAY_WINDOW then
      self.popup:mount(self.name)
    else
      self.popup:mount()
    end

    params.stream = true

    self.provider.api:chat_completions(
      params,
      utils.partial(utils.add_partial_completion, {
        panel = self.popup,
        progress = function(flag)
          self:run_spinner(flag)
        end,
      }),
      function()
        -- should stop function
        if self.stop then
          self:set_loading(false)
          return true
        else
          return false
        end
      end
    )
  else
    self:set_loading(true)
    self.provider.api:chat_completions(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end
end

function PopupAction:on_result(answer, usage)
  vim.schedule(function()
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
  end)
end

return PopupAction
