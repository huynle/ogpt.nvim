local Split = require("nui.split")

local BaseChat = require("ogpt.flows.chat.base")
local ChatInput = require("ogpt.common.simple_input")
local Config = require("ogpt.config")
local Parameters = require("ogpt.common.parameters")
local Sessions = require("ogpt.common.simple_sessions")
local SystemWindow = require("ogpt.common.simple_system_window")

QUESTION, ANSWER, SYSTEM = 1, 2, 3
ROLE_ASSISTANT = "assistant"
ROLE_SYSTEM = "system"
ROLE_USER = "user"

local SimpleChat = BaseChat:extend("SimpleChat")

function SimpleChat:set_session(session)
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, Config.namespace_id, 0, -1)
  self.session = session
  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:welcome()
  self:configure_parameters_panel(session)
  self:redraw()
end

function SimpleChat:get_simple_layout_params()
  self.chat_window:show()
  self.chat_input:show()

  if self.parameters_open then
    self:configure_parameters_panel()
    self.parameters_panel:show()
    self.sessions_panel:show()
  else
    self.parameters_panel:hide()
    self.sessions_panel:hide()
  end

  if self.system_role_open then
    self.system_role_panel:show()
  else
    self.system_role_panel:hide()
  end
end

function SimpleChat:open()
  self.session.parameters = vim.tbl_extend("keep", self.session.parameters, self.params)
  self.parameters_panel = Parameters.get_panel(self.session, self)
  self.sessions_panel = Sessions.get_panel(function(session)
    self:set_session(session)
  end)
  self.chat_window = Split(Config.options.popup_window)
  self.system_role_panel = SystemWindow({
    on_change = function(text)
      self:set_system_message(text)
    end,
  })
  self.stop = false
  self.should_stop = function()
    if self.stop then
      self.stop = false
      return true
    else
      return false
    end
  end
  self.chat_input = ChatInput(Config.options.popup_input, {
    prompt = Config.options.popup_input.prompt,
    on_close = function()
      self:hide()
    end,
    on_change = vim.schedule_wrap(function(lines)
      if self.prompt_lines ~= #lines then
        self.prompt_lines = #lines
        self:redraw()
      end
    end),
    on_submit = function(value)
      -- clear input
      vim.api.nvim_buf_set_lines(self.chat_input.bufnr, 0, -1, false, { "" })

      if self:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end

      self:addQuestion(value)

      if self.role == ROLE_USER then
        self:showProgess()
        local params = vim.tbl_extend("keep", {
          stream = true,
          -- context = self.session:previous_context(),
          -- prompt = self.messages[#self.messages].text,
          messages = self:toMessages(),
          system = self.system_message,
        }, Parameters.params)
        self.provider.api:chat_completions(params, function(answer, state, ctx)
          self:addAnswerPartial(answer, state, ctx)
        end, self.should_stop)
      end
    end,
  })

  self:redraw()
  self:welcome()
  self:set_events()
end

function SimpleChat:set_keymaps()
  -- yank last answer
  self:map(Config.options.chat.keymaps.yank_last, function()
    local msg = self:getSelected()
    vim.fn.setreg(Config.options.yank_register, msg.text)
    vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
  end, { self.chat_input })

  -- yank last code
  self:map(Config.options.chat.keymaps.yank_last_code, function()
    local code = self:getSelectedCode()
    if code ~= nil then
      vim.fn.setreg(Config.options.yank_register, code)
      vim.notify("Successfully copied code to yank register!", vim.log.levels.INFO)
    else
      vim.notify("No code to yank!", vim.log.levels.WARN)
    end
  end, { self.chat_input })

  -- scroll down
  self:map(Config.options.chat.keymaps.scroll_down, function()
    self:scroll(1)
  end, { self.chat_input })

  -- next message
  self:map(Config.options.chat.keymaps.next_message, function()
    self:next()
  end, { self.chat_window }, { "n" })

  -- prev message
  self:map(Config.options.chat.keymaps.prev_message, function()
    self:prev()
  end, { self.chat_window }, { "n" })

  -- scroll up
  self:map(Config.options.chat.keymaps.scroll_up, function()
    self:scroll(-1)
  end, { self.chat_input })

  -- stop generating
  self:map(Config.options.chat.keymaps.stop_generating, function()
    self.stop = true
  end, { self.chat_input })

  -- close
  self:map(Config.options.chat.keymaps.close, function()
    self:hide()
    -- If current in insert mode, switch to insert mode
    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
  end)

  -- toggle parameters
  self:map(Config.options.chat.keymaps.toggle_parameters, function()
    self.parameters_open = not self.parameters_open
    self:redraw()

    if self.parameters_open then
      vim.api.nvim_buf_set_option(self.parameters_panel.bufnr, "modifiable", false)
      vim.api.nvim_win_set_option(self.parameters_panel.winid, "cursorline", true)

      self:set_active_panel(self.parameters_panel)
    else
      self:set_active_panel(self.chat_input)
    end
  end)

  -- new session
  self:map(Config.options.chat.keymaps.new_session, function()
    self:new_session()
    Sessions:refresh()
  end, { self.parameters_panel, self.chat_input, self.chat_window })

  -- cycle panes
  self:map(Config.options.chat.keymaps.cycle_windows, function()
    if not self.active_panel then
      self:set_active_panel(self.chat_input)
    end
    if self.active_panel == self.parameters_panel then
      self:set_active_panel(self.sessions_panel)
    elseif self.active_panel == self.chat_input then
      if self.system_role_open then
        self:set_active_panel(self.system_role_panel)
      else
        self:set_active_panel(self.chat_window)
      end
    elseif self.active_panel == self.system_role_panel then
      self:set_active_panel(self.chat_window)
    elseif self.active_panel == self.chat_window and self.parameters_open == true then
      self:set_active_panel(self.parameters_panel)
    else
      self:set_active_panel(self.chat_input)
    end
  end)

  -- cycle modes
  self:map(Config.options.chat.keymaps.cycle_modes, function()
    self.display_mode = self.display_mode == "right" and "center" or "right"
    self:redraw()
  end)

  -- toggle system
  self:map(Config.options.chat.keymaps.toggle_system_role_open, function()
    if self.system_role_open and self.active_panel == self.system_role_panel then
      self:set_active_panel(self.chat_input)
    end

    self.system_role_open = not self.system_role_open

    self:redraw()

    if self.system_role_open then
      self:set_active_panel(self.system_role_panel)
    end
  end)

  -- toggle role
  self:map(Config.options.chat.keymaps.toggle_message_role, function()
    self.role = self.role == ROLE_USER and ROLE_ASSISTANT or ROLE_USER
    self:render_role()
  end)

  -- draft message
  self:map(Config.options.chat.keymaps.draft_message, function()
    if self:isBusy() then
      vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(self.chat_input.bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")
    if #text > 0 then
      vim.api.nvim_buf_set_lines(self.chat_input.bufnr, 0, -1, false, { "" })
      self:add(self.role == ROLE_USER and QUESTION or ANSWER, text)
      if self.role ~= ROLE_USER then
        self.role = ROLE_USER
        self:render_role()
      end
    else
      vim.notify("Cannot add empty message.", vim.log.levels.WARN)
    end
  end)

  -- delete message
  self:map(Config.options.chat.keymaps.delete_message, function()
    if self:count() > 0 then
      self:delete_message()
    else
      vim.notify("Nothing selected.", vim.log.levels.WARN)
    end
  end, { self.chat_window }, { "n" })

  -- edit message
  self:map(Config.options.chat.keymaps.edit_message, function()
    if self:count() > 0 then
      self:edit_message()
    else
      vim.notify("Nothing selected.", vim.log.levels.WARN)
    end
  end, { self.chat_window }, { "n" })
end

function SimpleChat:redraw(noinit)
  noinit = noinit or false
  self:get_simple_layout_params()
  if not noinit then
    self:welcome()
  end
  self:set_keymaps()
end

function SimpleChat:hide()
  self.chat_window:hide()
  self.chat_input:hide()
  self.parameters_panel:hide()
  self.system_role_panel:hide()
  self.sessions_panel:hide()
end

function SimpleChat:unmount()
  self.chat_window:unmount()
  self.chat_input:unmount()
  self.parameters_panel:unmount()
  self.system_role_panel:unmount()
  self.sessions_panel:unmount()
end

function SimpleChat:show()
  self:redraw(true)
end

function SimpleChat:configure_parameters_panel(session)
  session = session or self.session
  self.parameters_panel:unmount()
  self.parameters_panel = Parameters.get_panel(session, self)
  self.parameters_panel:mount()
end

return SimpleChat
