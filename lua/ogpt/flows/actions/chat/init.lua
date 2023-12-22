-- ChatAction that can be used for actions of type "chat" in actions.json
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
  self.system = opts.system or ""
  self.template = opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_APPEND
  self.ui = opts.ui or {}
  self.main_winid = vim.api.nvim_get_current_win()
end

function ChatAction:render_template()
  local input = self.strategy == STRATEGY_QUICK_FIX and self:get_selected_text_with_line_numbers()
    or self:get_selected_text()
  local data = {
    filetype = self:get_filetype(),
    lang = self:get_filetype(),
    input = input,
  }
  data = vim.tbl_extend("force", {}, data, self.variables)
  local result = self.template
  for key, value in pairs(data) do
    result = result:gsub("{{" .. key .. "}}", value)
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
    system = self.system,
  })
end

function ChatAction:run()
  vim.schedule(function()
    local _params = vim.tbl_extend("force", Config.options.api_params, self.params, {
      system = self.system,
    })

    if self.strategy == STRATEGY_EDIT_CODE and self.opts.delay then
      Edits.edit_with_instructions({}, self:get_bufnr(), { self:get_visual_selection() }, {
        instruction = self.template,
        params = _params,
        edit_code = true,
        filetype = self:get_filetype(),
      })
    elseif self.strategy == STRATEGY_EDIT and self.opts.delay then
      Edits.edit_with_instructions({}, self:get_bufnr(), { self:get_visual_selection() }, {
        instruction = self.template,
        params = _params,
        edit_code = false,
      })
    else
      self:run_action()
    end
  end)
end

function ChatAction:update_popup_size(popup)
  local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
  local ui_opts = self:calculate_size({
    lines = lines,
  })
  popup:update_layout(ui_opts)
end

function ChatAction:calculate_size(opts)
  opts = opts or {}
  -- compute size
  -- the width is calculated based on the maximum number of lines and the height is calculated based on the width
  -- local cur_win = vim.api.nvim_get_current_win()
  local cur_win = self.main_winid
  local max_h = math.ceil(vim.api.nvim_win_get_height(cur_win) * 0.75)
  local max_w = math.ceil(vim.api.nvim_win_get_width(cur_win) * 0.5)
  local ui_w = 0
  local len = 0
  local ncount = 0
  local lines = opts.lines or Utils.split_string_by_line(opts.text or "")
  local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

  for _, v in ipairs(lines) do
    local l = string.len(v)
    if v == "" then
      ncount = ncount + 1
    end
    ui_w = math.max(l, ui_w)
    len = len + l
  end
  ui_w = math.min(ui_w, max_w)
  ui_w = math.max(ui_w, 10)
  local ui_h = math.ceil(len / ui_w) + ncount
  ui_h = math.min(ui_h, max_h)
  ui_h = math.max(ui_h, 1)

  -- use opts
  ui_w = opts.ui_w or ui_w
  ui_h = opts.ui_h or ui_h

  -- build ui opts
  local ui_opts = vim.tbl_deep_extend("keep", {
    size = {
      width = ui_w,
      height = ui_h,
    },
    border = {
      style = "rounded",
      text = {
        top = " " .. (self.opts.title or self.opts.args) .. " ",
        top_align = "left",
      },
    },
    relative = {
      type = "buf",
      position = {
        row = start_row,
        col = start_col,
      },
    },
  }, self.ui)
  return ui_opts
end

function ChatAction:get_popup(opts)
  opts = opts or {}
  local bufnr = self:get_bufnr()
  local lines = Utils.split_string_by_line(opts.answer or "")
  local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

  local ui_opts = self:calculate_size(opts)
  local PreviewWindow = require("ogpt.common.preview_window")
  local popup = PreviewWindow(ui_opts)
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, lines)

  local _replace = function(replace)
    replace = replace or false
    if replace then
      vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
    else
      table.insert(lines, 1, "")
      table.insert(lines, "")
      vim.api.nvim_buf_set_text(bufnr, end_row - 1, start_col - 1, end_row - 1, start_col - 1, lines)
    end

    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
    vim.cmd("q")
  end

  -- accept output and replace
  popup:map("n", "r", function()
    _replace(true)
  end)

  -- accept output and append
  popup:map("n", "a", function()
    _replace(false)
  end)

  -- yank output and close
  popup:map("n", "y", function()
    vim.fn.setreg(Config.options.yank_register, lines)

    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
    vim.cmd("q")
  end)

  return popup
end

function ChatAction:call_api(panel, params)
  Api.chat_completions(
    params,
    Utils.partial(Utils.add_partial_completion, {
      panel = panel,
      -- finalize_opts = opts,
      progress = function(flag)
        self:set_loading(flag)
      end,
    }),
    function()
      -- should stop function
      if self.stop then
        self.stop = false
        self:set_loading(false)
        return true
      else
        return false
      end
    end
  )
end

function ChatAction:run_action()
  self:set_loading(true)
  self.stop = false
  local params = self:get_params()

  if self.strategy == STRATEGY_DISPLAY then
    local popup = self:get_popup()
    popup:mount(self)
    params.stream = true
    self:call_api(popup, params)
  -- elseif self.strategy == STRATEGY_APPEND then
  --   -- answer = self:get_selected_text() .. "\n\n" .. answer .. "\n"
  --   params.stream = true
  --   self:call_api({ bufnr = self:get_bufnr() }, params)
  else
    Api.chat_completions(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end
end

function ChatAction:on_result(answer, usage)
  vim.schedule(function()
    self:set_loading(false)

    local bufnr = self:get_bufnr()
    if self.strategy == STRATEGY_PREPEND then
      answer = answer .. "\n" .. self:get_selected_text()
    elseif self.strategy == STRATEGY_APPEND then
      answer = self:get_selected_text() .. "\n\n" .. answer .. "\n"
    end

    local lines = Utils.split_string_by_line(answer)
    local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

    if self.strategy == STRATEGY_DISPLAY then
      -- moved out
      -- local popup = self:get_popup(answer)
      -- popup:mount()
    elseif self.strategy == STRATEGY_EDIT then
      Edits.edit_with_instructions(lines, bufnr, { self:get_visual_selection() }, {
        instruction = self.template,
        params = self:get_params(),
      })
    elseif self.strategy == STRATEGY_EDIT_CODE then
      Edits.edit_with_instructions(lines, bufnr, { self:get_visual_selection() }, {
        instruction = self.template,
        params = self:get_params(),
        edit_code = true,
      })
    elseif self.strategy == STRATEGY_QUICK_FIX then
      if #lines == 1 and lines[1] == "<OK>" then
        vim.notify("Your Code looks fine, no issues.", vim.log.levels.INFO)
        return
      end

      local entries = {}
      for _, line in ipairs(lines) do
        local lnum, text = line:match("(%d+):(.*)")

        local entry = { filename = vim.fn.expand("%:p"), lnum = tonumber(lnum), text = text }
        table.insert(entries, entry)
      end
      vim.fn.setqflist(entries)
      vim.cmd(Config.options.show_quickfixes_cmd)
    else
      vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)

      -- set the cursor onto the answer
      if self.strategy == STRATEGY_APPEND then
        local target_line = end_row + 3
        vim.api.nvim_win_set_cursor(0, { target_line, 0 })
      end
    end
  end)
end

return ChatAction
