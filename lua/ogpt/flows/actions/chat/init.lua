-- ChatAction that can be used for actions of type "chat" in actions.PreviewWindowjson
--
-- This enables the use of mistral:7b in user defined actions,
-- as this model only defines the chat endpoint and has no completions endpoint
--
-- Example action for your local actions.json:
--
--   "turbo-summary": {
--     "type": "chat",
--     "opts": {
--       "template": "Summarize the following text.\n\nText:\n\"\"\"\n{{input}}\n\"\"\"\n\nSummary:",
--       "params": {
--         "model": "mistral:7b"
--       }
--     }
--   }
local classes = require("ogpt.common.classes")
local BaseAction = require("ogpt.flows.actions.base")
local Api = require("ogpt.api")
local Utils = require("ogpt.utils")
local Config = require("ogpt.config")
local Edits = require("ogpt.edits")
local Spinner = require("ogpt.spinner")
local PreviewWindow = require("ogpt.common.preview_window")

local ChatAction = classes.class(BaseAction)

local STRATEGY_EDIT = "edit"
local STRATEGY_EDIT_CODE = "edit_code"
local STRATEGY_REPLACE = "replace"
local STRATEGY_APPEND = "append"
local STRATEGY_PREPEND = "prepend"
local STRATEGY_DISPLAY = "display"
local STRATEGY_QUICK_FIX = "quick_fix"

function ChatAction:init(opts)
  self.super:init(opts)
  self.params = opts.params or {}
  self.system = type(opts.system) == "function" and opts.system() or opts.system or ""
  self.template = type(opts.template) == "function" and opts.template() or opts.template or "{{input}}"
  -- self.instruction = type(opts.instruction) == "function" and opts.instruction() or opts.instruction or ""
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_APPEND
  self.ui = opts.ui or {}
  self.cur_win = vim.api.nvim_get_current_win()
  self.popup = PreviewWindow()
  self.stop = false
  self.spinner = Spinner:new(function(state)
    vim.schedule(function()
      -- self:set_lines(self.popup.bufnr, -2, -1, false, { state .. " " .. Config.options.chat.loading_text })
      self:display_input_suffix(state)
    end)
  end)

  self:update_variables()
end

function ChatAction:update_variables()
  self.variables = vim.tbl_extend("force", self.variables, {
    filetype = self:get_filetype(),
    input = self.strategy == STRATEGY_QUICK_FIX and self:get_selected_text_with_line_numbers()
      or self:get_selected_text(),
  })
end

function ChatAction:render_template()
  local result = self.template
  for key, value in pairs(self.variables) do
    local escaped_value = Utils.escape_pattern(value)
    result = string.gsub(result, "{{" .. key .. "}}", escaped_value)
  end
  return result
end

function ChatAction:get_params()
  local messages = self.params.messages or {}
  local message = {
    role = "user",
    content = self:render_template(),
  }
  table.insert(messages, message)
  return vim.tbl_extend("force", Config.options.api_params, self.params, {
    messages = messages,
    system = self.system and "" == self.system and nil or self.system,
  })
end

function ChatAction:run()
  vim.schedule(function()
    local _params = vim.tbl_extend("force", Config.options.api_params, self.params, {
      system = self.system,
    })

    if self.strategy == STRATEGY_EDIT_CODE and self.opts.delay then
      Edits.edit_with_instructions({}, self:get_bufnr(), { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        params = _params,
        edit_code = true,
        filetype = self:get_filetype(),
      })
    elseif self.strategy == STRATEGY_EDIT and self.opts.delay then
      Edits.edit_with_instructions({}, self:get_bufnr(), { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        params = _params,
        edit_code = false,
      })
    else
      self:run_action()
    end
  end)
end

function ChatAction:display_input_suffix(suffix)
  if self.extmark_id and Utils.is_buf_exists(self.popup.bufnr) then
    vim.api.nvim_buf_del_extmark(self.popup.bufnr, Config.namespace_id, self.extmark_id)
  end

  if suffix and Utils.is_buf_exists(self.popup.bufnr) then
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

function ChatAction:set_lines(bufnr, start_idx, end_idx, strict_indexing, lines)
  if Utils.is_buf_exists(bufnr) then
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, strict_indexing, lines)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  end
end

function ChatAction:call_api(panel, params)
  Api.chat_completions(
    params,
    Utils.partial(Utils.add_partial_completion, {
      panel = panel,
      -- finalize_opts = opts,
      progress = function(flag)
        self:run_spinner(flag)
      end,
    }),
    function()
      -- should stop function
      if self.stop then
        self.stop = false
        self:run_spinner(false)
        return true
      else
        return false
      end
    end
  )
end

function ChatAction:run_spinner(flag)
  if flag then
    self.spinner:start()
  else
    self.spinner:stop()
    self:set_lines(self.popup.bufnr, 0, -1, false, {})
  end
end

function ChatAction:run_action()
  local params = self:get_params()
  local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

  if self.strategy == STRATEGY_DISPLAY then
    self:run_spinner(true)
    self.popup:mount({
      name = self.opts.fargs[1],
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
    })
    params.stream = true
    self:call_api(self.popup, params)
  elseif self.strategy == STRATEGY_EDIT then
    Edits.edit_with_instructions({}, self:get_bufnr(), { self:get_visual_selection() }, {
      template = self.template,
      variables = self.variables,
      params = self:get_params(),
    })
  elseif self.strategy == STRATEGY_EDIT_CODE then
    Edits.edit_with_instructions({}, self:get_bufnr(), { self:get_visual_selection() }, {
      template = self.template,
      variables = self.variables,
      params = self:get_params(),
      edit_code = true,
      filetype = self:get_filetype(),
    })
  else
    self:set_loading(true)
    Api.chat_completions(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end
end

function ChatAction:on_result(answer, usage)
  vim.schedule(function()
    self:set_loading(false)
    local lines = Utils.split_string_by_line(answer)
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

return ChatAction
