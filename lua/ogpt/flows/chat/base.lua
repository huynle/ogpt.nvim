local Object = require("ogpt.common.object")
local Layout = require("ogpt.common.layout")
local Popup = require("ogpt.common.popup")

local ChatInput = require("ogpt.input")
local Response = require("ogpt.response")
local Config = require("ogpt.config")
local Parameters = require("ogpt.parameters")
local Sessions = require("ogpt.flows.chat.sessions")
local utils = require("ogpt.utils")
local Signs = require("ogpt.signs")
local Spinner = require("ogpt.spinner")
local Session = require("ogpt.flows.chat.session")
local UtilWindow = require("ogpt.util_window")

QUESTION, ANSWER, SYSTEM = 1, 2, 3
ROLE_ASSISTANT = "assistant"
ROLE_SYSTEM = "system"
ROLE_USER = "user"

local Chat = Object("Chat")

function Chat:init(opts)
  opts = opts or {}
  self.input_extmark_id = nil

  self.active_panel = nil
  self.selected_message_nsid = vim.api.nvim_create_namespace("OGPTNSSM")

  self.is_running = false

  -- quit indicator
  self.active = true
  self.focused = true
  self.session = nil

  -- UI ELEMENTS
  self.edgy = Config.options.chat.edgy
  self.layout = nil
  self.chat_panel = nil
  self.chat_input = nil
  self.chat_window = nil
  self.sessions_panel = nil
  self.parameters_panel = nil
  self.system_role_panel = nil

  -- UI OPEN INDICATORS
  self.parameters_open = false
  self.system_role_open = false

  self.prompt_lines = 1

  self.display_mode = Config.options.popup_layout.default
  self.params = Config.get_chat_params(opts.provider)

  self.session = Session.latest()
  self.provider = nil
  self.selectedIndex = 0
  self.role = ROLE_USER
  self.messages = {}
  self.spinner = Spinner:new(function(state)
    vim.schedule(function()
      -- self:set_lines(-2, -1, false, { state .. " " .. Config.options.chat.loading_text })
      -- self:set_lines(-2, -1, false, { state })
      self:display_input_suffix(state)
    end)
  end, {
    -- text = Config.options.chat.loading_text,
  })
end

function Chat:welcome()
  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:set_system_message(nil, true)
  self.provider = Config.get_provider(self.session.parameters.provider, self)

  local conversation = self.session.conversation or {}
  if #conversation > 0 then
    for idx, item in ipairs(self.session.conversation) do
      if item.type == SYSTEM then
        self:set_system_message(item.text, true)
      else
        self:_add(item.type, item.text, item.usage, idx)
      end
    end
  end

  if #conversation == 0 or (#conversation == 1 and self.system_message ~= nil) then
    local lines = utils.split_string_by_line(Config.options.chat.welcome_message)
    self:set_lines(0, 0, false, lines)
    for line_num = 0, #lines do
      self:add_highlight("OGPTWelcome", line_num, 0, -1)
    end
  end
  self:render_role()
end

function Chat:render_role()
  if self.role_extmark_id ~= nil then
    vim.api.nvim_buf_del_extmark(self.chat_input.bufnr, Config.namespace_id, self.role_extmark_id)
  end

  self.role_extmark_id = vim.api.nvim_buf_set_extmark(self.chat_input.bufnr, Config.namespace_id, 0, 0, {
    virt_text = {
      { Config.options.chat.border_left_sign, "OGPTTotalTokensBorder" },
      {
        string.upper(self.role),
        "OGPTTotalTokens",
      },
      { Config.options.chat.border_right_sign, "OGPTTotalTokensBorder" },
      { " " },
    },
    virt_text_pos = "right_align",
  })
end

function Chat:set_system_message(msg, skip_session_add)
  self.system_message = msg
  if msg == nil then
    self.system_role_panel:set_text({})
    return
  end

  if not skip_session_add then
    self.session:add_item({
      type = SYSTEM,
      text = msg,
      usage = {},
    })
  else
    self.system_role_panel:set_text(utils.split_string_by_line(msg))
  end
end

function Chat:new_session()
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, Config.namespace_id, 0, -1)

  self.session = Session:new()
  self.session:save()

  self.system_message = nil
  self.system_role_panel:set_text({})
  self:welcome()
  self.parameters_panel:reload_session_params(self.session)
end

function Chat:set_session(session)
  self.session = session or self.session

  if vim.fn.bufexists(self.chat_window.bufnr) then
    vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, Config.namespace_id, 0, -1)
  end

  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:welcome()
  self:configure_parameters_panel(self.session)
  self.parameters_panel:reload_session_params(self.session)
  self:set_keymaps()
end

function Chat:isBusy()
  -- return self.spinner:is_running()
  return self.is_running
end

function Chat:add(type, text, usage)
  local idx = self.session:add_item({
    type = type,
    text = text,
    usage = usage,
    ctx = { context = self.session:previous_context() },
  })
  self:_add(type, text, usage, idx)
  self:render_role()
end

function Chat:_add(type, text, usage, idx)
  if not self:is_buf_exists() then
    return
  end

  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    start_line = prev.end_line + (prev.type == ANSWER and 2 or 1)
  end

  local lines = {}
  local nr_of_lines = 0
  for line in string.gmatch(text, "[^\n]+") do
    nr_of_lines = nr_of_lines + 1
    table.insert(lines, line)
  end

  table.insert(self.messages, {
    idx = idx,
    usage = usage or {},
    type = type,
    text = text,
    context = {},
    lines = lines,
    nr_of_lines = nr_of_lines,
    start_line = start_line,
    end_line = start_line + nr_of_lines - 1,
  })
  self.selectedIndex = self.selectedIndex + 1
  self:renderLastMessage()
end

function Chat:addQuestion(text)
  self:add(self.role == ROLE_USER and QUESTION or ANSWER, text)
end

function Chat:addSystem(text)
  self:add(SYSTEM, text)
end

function Chat:addAnswer(text, usage)
  self:add(ANSWER, text, usage)
end

function Chat:addAnswerPartial(response)
  local content = response:pop_content()
  local text = content[1]
  local state = content[2]
  -- local state = response.state
  -- local text = response.current_text
  local ctx = response.ctx
  self:stopSpinner()

  if state == "START" then
    self.is_running = true
    self:set_lines(-2, -1, false, { "" })
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", true)
  end

  if state == "ERROR" then
    -- self:stopSpinner()
    utils.log(text, vim.log.levels.ERROR)
    -- return self:addAnswer(text, {})
  end

  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    start_line = prev.end_line + (prev.type == ANSWER and 2 or 1)
  end

  -- if state == "END" and text == "" then
  --   -- most likely, ended by the using raising the stop flag
  --   self:stopSpinner()
  if state == "END" then
    -- self:stopSpinner()
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", true)
    local usage = {}
    local idx = self.session:add_item({
      type = ANSWER,
      text = text,
      usage = usage,
      ctx = ctx or {},
    })
    self.parameters_panel:reload_session_params()

    local lines = {}
    local nr_of_lines = 0
    for line in string.gmatch(text, "[^\n]+") do
      nr_of_lines = nr_of_lines + 1
      table.insert(lines, line)
    end

    local end_line = start_line + nr_of_lines - 1
    table.insert(self.messages, {
      idx = idx,
      usage = usage or {},
      type = ANSWER,
      text = text,
      lines = lines,
      nr_of_lines = nr_of_lines,
      start_line = start_line,
      end_line = end_line,
      context = response:get_context(),
    })
    self.selectedIndex = self.selectedIndex + 1
    vim.api.nvim_buf_set_lines(self.chat_window.bufnr, -1, -1, false, { "", "" })
    Signs.set_for_lines(self.chat_window.bufnr, start_line, end_line, "chat")
  end

  if state == "START" or state == "CONTINUE" then
    self.is_running = true
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", true)
    local lines = vim.split(text, "\n", {})
    local length = #lines
    local buffer = self.chat_window.bufnr
    local win = self.chat_window.winid

    for i, line in ipairs(lines) do
      local currentLine = vim.api.nvim_buf_get_lines(buffer, -2, -1, false)[1]
      vim.api.nvim_buf_set_lines(buffer, -2, -1, false, { currentLine .. line })

      local last_line_num = vim.api.nvim_buf_line_count(buffer)
      Signs.set_for_lines(self.chat_window.bufnr, start_line, last_line_num - 1, "chat")
      if i == length and i > 1 then
        vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "" })
      end
      if self:is_buf_visiable() then
        vim.api.nvim_win_set_cursor(win, { last_line_num, 0 })
      end
    end
  end
  -- assume after each partial answer, the API stopped streaming
  -- gemini has no stop flag in its response
  self.is_running = false
end

function Chat:get_total_tokens()
  local total_tokens = 0
  for i = 1, #self.messages, 1 do
    local tokens = self.messages[i].usage.total_tokens
    if tokens ~= nil then
      total_tokens = total_tokens + tokens
    end
  end
  return total_tokens
end

function Chat:next()
  local count = self:count()
  if self.selectedIndex < count then
    self.selectedIndex = self.selectedIndex + 1
  else
    self.selectedIndex = 1
  end
  self:show_message_selection()
end

function Chat:prev()
  local count = self:count()
  if self.selectedIndex > 1 then
    self.selectedIndex = self.selectedIndex - 1
  else
    self.selectedIndex = count
  end
  self:show_message_selection()
end

function Chat:show_message_selection()
  local msg = self:getSelected()
  if msg == nil then
    return
  end

  self:set_cursor({ msg.start_line + 1, 0 })
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, self.selected_message_nsid, 0, -1)
  vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, self.selected_message_nsid, msg.start_line, 0, {
    end_col = 0,
    end_row = msg.end_line + 1,
    hl_group = "OGPTSelectedMessage",
    hl_eol = true,
  })
  self:render_message_actions()
end

function Chat:hide_message_selection()
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, self.selected_message_nsid, 0, -1)
end

function Chat:getSelected()
  return self.messages[self.selectedIndex]
end

function Chat:delete_message()
  local selected_index = self.selectedIndex
  local msg = self:getSelected()
  self.session:delete_by_index(msg.idx)

  if msg.extmark_id then
    vim.api.nvim_buf_del_extmark(self.chat_window.bufnr, Config.namespace_id, msg.extmark_id)
  end

  self:welcome()
  if selected_index > 1 then
    self.selectedIndex = selected_index - 1
    local current_msg = self:getSelected()
    self:set_cursor({ current_msg.start_line + 1, 0 })
  end
  self:show_message_selection()
end

function Chat:render_message_actions()
  local msg = self:getSelected()
  if msg ~= nil then
    vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, self.selected_message_nsid, msg.start_line, 0, {
      virt_text = {
        {
          " Delete (" .. Config.options.chat.keymaps.delete_message .. ") ",
          "OGPTMessageAction",
        },
        { " ", "OGPTSelectedMessage" },
      },
      virt_text_pos = "right_align",
    })

    -- vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, self.selected_message_nsid, msg.start_line, 0, {
    --   virt_text = {
    --     { "  ", "OGPTSelectedMessage" },
    --     {
    --       " Edit (" .. Config.options.chat.keymaps.edit_message .. ") ",
    --       "OGPTMessageAction",
    --     },
    --     { " ", "OGPTSelectedMessage" },
    --   },
    --   virt_text_pos = "right_align",
    -- })
  end
end

function Chat:getSelectedCode()
  local msg = self:getSelected()
  local text = msg.text
  -- Iterate through all code blocks in the message using a regular expression pattern
  local lastCodeBlock
  for codeBlock in text:gmatch("```.-```%s*") do
    lastCodeBlock = codeBlock
  end
  -- If a code block was found, strip the delimiters and return the code
  if lastCodeBlock then
    local index = string.find(lastCodeBlock, "\n")
    if index ~= nil then
      lastCodeBlock = string.sub(lastCodeBlock, index + 1)
    end
    return lastCodeBlock:gsub("```\n", ""):gsub("```", ""):match("^%s*(.-)%s*$")
  end
  return nil
end

function Chat:get_last_answer()
  for i = #self.messages, 1, -1 do
    if self.messages[i].type == ANSWER then
      return self.messages[i]
    end
  end
end

function Chat:renderLastMessage()
  self:stopSpinner()
  local msg = self:getSelected()

  local lines = {}
  for w in string.gmatch(msg.text, "[^\r\n]+") do
    table.insert(lines, w)
  end
  table.insert(lines, "")
  if msg.type == ANSWER then
    table.insert(lines, "")
  end

  local startIdx = self.selectedIndex == 1 and 0 or -2
  self:set_lines(startIdx, -1, false, lines)

  if msg.type == QUESTION then
    for index, _ in ipairs(lines) do
      self:add_highlight("OGPTQuestion", msg.start_line + index - 1, 0, -1)
    end

    pcall(vim.fn.sign_place, 0, "ogpt_ns", "ogpt_question_sign", self.chat_window.bufnr, { lnum = msg.start_line + 1 })
  else
    local total_tokens = msg.usage.total_tokens
    if total_tokens ~= nil then
      self.messages[self.selectedIndex].extmark_id =
        vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, Config.namespace_id, msg.end_line + 1, 0, {
          virt_text = {
            { Config.options.chat.border_left_sign, "OGPTTotalTokensBorder" },
            {
              "TOKENS: " .. msg.usage.total_tokens,
              "OGPTTotalTokens",
            },
            { Config.options.chat.border_right_sign, "OGPTTotalTokensBorder" },
            { " ", "" },
          },
          virt_text_pos = "right_align",
        })
    end

    Signs.set_for_lines(self.chat_window.bufnr, msg.start_line, msg.end_line, "chat")
  end

  if self.selectedIndex > 2 then
    self:set_cursor({ msg.end_line - 1, 0 })
  end
end

function Chat:showProgess()
  self.is_running = true
  self.spinner:start()
end

function Chat:stopSpinner()
  -- just for the spinner, stop it, so we can add the response
  self.spinner:stop()
  self:display_input_suffix()
end

function Chat:toString()
  local str = ""
  for _, msg in pairs(self.messages) do
    str = str .. msg.text .. "\n"
  end
  return str
end

function Chat:toMessages()
  local messages = {}
  if self.system_message ~= nil then
    table.insert(messages, { role = "system", content = self.system_message })
  end

  for _, msg in pairs(self.messages) do
    local role = "user"
    if msg.type == SYSTEM then
      role = "system"
    elseif msg.type == ANSWER then
      role = "assistant"
    end
    table.insert(messages, {
      role = role,
      content = {
        {
          text = msg.text,
          token = nil,
        },
      },
    })
  end
  -- return messages[#messages].content
  return messages
end

function Chat:count()
  local count = 0
  for _ in pairs(self.messages) do
    count = count + 1
  end
  return count
end

function Chat:is_buf_exists()
  return vim.fn.bufexists(self.chat_window.bufnr) == 1
end

function Chat:is_buf_visiable()
  -- Get all windows in the current tab
  local wins = vim.api.nvim_tabpage_list_wins(0)
  -- Traverse the window list to determine whether the buffer of chat_window is visible in the window
  local visible = false
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == self.chat_window.bufnr then
      visible = true
      break
    end
  end
  return visible
end

function Chat:set_lines(start_idx, end_idx, strict_indexing, lines)
  if self:is_buf_exists() then
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.chat_window.bufnr, start_idx, end_idx, strict_indexing, lines)
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", false)
  end
end

function Chat:add_highlight(hl_group, line, col_start, col_end)
  if self:is_buf_exists() then
    vim.api.nvim_buf_add_highlight(self.chat_window.bufnr, -1, hl_group, line, col_start, col_end)
  end
end

function Chat:set_cursor(pos)
  if self:is_buf_visiable() then
    pcall(vim.api.nvim_win_set_cursor, self.chat_window.winid, pos)
  end
end

function Chat:get_width()
  if self:is_buf_exists() then
    return vim.api.nvim_win_get_width(self.chat_window.winid)
  end
end

function Chat:display_input_suffix(suffix)
  if self.extmark_id then
    vim.api.nvim_buf_del_extmark(self.chat_input.bufnr, Config.namespace_id, self.extmark_id)
  end

  if suffix then
    self.extmark_id = vim.api.nvim_buf_set_extmark(self.chat_input.bufnr, Config.namespace_id, 0, -1, {
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

function Chat:scroll(direction)
  local speed = vim.api.nvim_win_get_height(self.chat_window.winid) / 2
  local input = direction > 0 and [[]] or [[]]
  local count = math.floor(speed)

  vim.api.nvim_win_call(self.chat_window.winid, function()
    vim.cmd([[normal! ]] .. count .. input)
  end)
end

function Chat:map(keys, fn, windows, modes)
  if windows == nil or next(windows) == nil then
    windows = { self.parameters_panel, self.sessions_panel, self.system_role_panel, self.chat_input, self.chat_window }
  end

  if modes == nil or next(modes) == nil then
    modes = { "n", "i" }
  end

  if type(keys) ~= "table" then
    keys = { keys }
  end

  for _, popup in ipairs(windows) do
    for _, mode in ipairs(modes) do
      for _, key in ipairs(keys) do
        popup:map(mode, key, fn, {})
      end
    end
  end
end

function Chat:set_active_panel(panel)
  vim.api.nvim_set_current_win(panel.winid)
  self.active_panel = panel
  utils.change_mode_to_normal()

  if self.active_panel == self.chat_window then
    self:show_message_selection()
  else
    self:hide_message_selection()
  end
end

function Chat:get_layout_params()
  local lines_height = vim.api.nvim_get_option("lines")
  local statusline_height = vim.o.laststatus == 0 and 0 or 1 -- height of the statusline if present
  local cmdline_height = vim.o.cmdheight -- height of the cmdline if present
  local tabline_height = vim.o.showtabline == 0 and 0 or 1 -- height of the tabline if present
  local total_height = lines_height
  local used_height = statusline_height + cmdline_height + tabline_height
  local layout_height = total_height - used_height
  local starting_row = tabline_height == 0 and 0 or 1

  local width = utils.calculate_percentage_width(Config.options.popup_layout.right.width)
  if self.parameters_open then
    width = width + 40
  end

  local right_layout_config = {
    relative = "editor",
    position = {
      row = starting_row,
      col = "100%",
    },
    size = {
      width = width,
      height = layout_height,
    },
  }

  local center_layout_config = {
    relative = "editor",
    position = "50%",
    size = {
      width = Config.options.popup_layout.center.width,
      height = Config.options.popup_layout.center.height,
    },
  }

  local config = self.display_mode == "right" and right_layout_config or center_layout_config

  local left_layout = Layout.Box(self.chat_window, { grow = 1 })
  if self.system_role_open then
    left_layout = Layout.Box({
      Layout.Box(self.system_role_panel, { size = self.display_mode == "center" and 33 or 10 }),
      Layout.Box(self.chat_window, { grow = 1 }),
    }, { dir = self.display_mode == "center" and "row" or "col", grow = 1 })
  end

  local box
  if self.parameters_open then
    box = Layout.Box({
      Layout.Box({
        left_layout,
        Layout.Box(self.chat_input, { size = 2 + self.prompt_lines }),
      }, { dir = "col", grow = 1 }),
      Layout.Box({
        Layout.Box(self.parameters_panel, { size = "30%" }),
        Layout.Box(self.sessions_panel, { grow = 1 }),
      }, { dir = "col", size = 40 }),
    }, { dir = "row" })
  else
    box = Layout.Box({
      left_layout,
      Layout.Box(self.chat_input, { size = 2 + self.prompt_lines }),
    }, { dir = "col" })
  end

  return config, box
end

--   self:stopSpinner()
-- function Chat:stop_output()
--   self.stop_flag = true
-- end
--
function Chat:on_complete_response(response)
  --
end

function Chat:open()
  self.session.parameters = vim.tbl_extend("keep", self.session.parameters, self.params)
  self.parameters_panel = Parameters({
    type = "chat",
    default_params = self.session.parameters,
    session = self.session,
    parent = self,
    edgy = Config.options.chat.edgy,
  })

  self.sessions_panel = Sessions({
    edgy = Config.options.chat.edgy,
    set_session_cb = function(session)
      self:set_session(session)
    end,
  })
  self.chat_window = Popup(Config.options.output_window, Config.options.chat.edgy)
  self.system_role_panel = UtilWindow({
    filetype = "ogpt-system-window",
    display = "System",
    virtual_text = "Define your LLM system message here...",
    on_change = function(text)
      self:set_system_message(text)
    end,
  }, Config.options.chat.edgy)

  self.chat_input = ChatInput(Config.options.input_window, {
    edgy = Config.options.chat.edgy,
    prompt = Config.options.input_window.prompt,
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
      if self:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end

      -- create response object per api call
      local response = Response(self.provider, {
        on_start = function()
          -- restart stop flag
          self.stop_flag = false
        end,
      })

      -- clear input
      vim.api.nvim_buf_set_lines(self.chat_input.bufnr, 0, -1, false, { "" })

      self:addQuestion(value)

      if self.role == ROLE_USER then
        self:showProgess()
        local params = vim.tbl_extend("keep", {
          stream = true,
          -- context = self.session:previous_context(),
          -- prompt = self.messages[#self.messages].text,
          messages = self:toMessages(),
          system = self.system_message,
        }, self.parameters_panel.params)
        self.provider.api:chat_completions(response, {
          custom_params = params,
          partial_result_fn = function(...)
            self:addAnswerPartial(...)
          end,
          should_stop = function()
            -- check the stop flag if it should stop
            -- return not self.is_running
            return self.stop_flag
          end,
        })
      end
    end,
  })

  local _layout_options, _layout_box = self:get_layout_params()
  self.layout = Layout(_layout_options, _layout_box, Config.options.chat.edgy)
  self:set_keymaps()

  -- initialize
  self.layout:mount()
  self:welcome()

  self.parameters_panel:reload_session_params()
  self:set_events()
end

function Chat:set_events()
  local event = require("nui.utils.autocmd").event
  local windows = { self.parameters_panel, self.chat_input, self.chat_window }

  for _, popup in ipairs(windows) do
    popup:on(event.QuitPre, function()
      self.active = false
    end)
    popup:on(event.WinLeave, function()
      self.focused = false
    end)
    popup:on(event.WinEnter, function()
      self.focused = true
    end)
  end
end

function Chat:set_keymaps()
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
    self.stop_flag = true
    -- self.is_running = false
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
      self.parameters_panel:show()
      self.sessions_panel:show()
      vim.api.nvim_buf_set_option(self.parameters_panel.bufnr, "modifiable", false)
      vim.api.nvim_win_set_option(self.parameters_panel.winid, "cursorline", true)

      self:set_active_panel(self.parameters_panel)
    else
      self.parameters_panel:hide()
      self.sessions_panel:hide()
      self:set_active_panel(self.chat_input)
    end
  end)

  -- new session
  self:map(Config.options.chat.keymaps.new_session, function()
    -- self.stop_flag = true
    self.is_running = false
    self:new_session()
    self.sessions_panel:refresh()
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

function Chat:open_system_panel()
  self.system_role_open = true
  self:redraw()
  self:set_active_panel(self.system_role_panel)
end

function Chat:redraw(noinit)
  noinit = noinit or false
  self.layout:update(self:get_layout_params())
  if not noinit then
    self:welcome()
  end
end

function Chat:hide()
  self.layout:hide()
end

function Chat:show()
  self:redraw(true)
  self.layout:show()
end

function Chat:toggle()
  if self.layout.winid ~= nil then
    self:hide()
  else
    self:show()
  end
end

function Chat:configure_parameters_panel(session)
  -- self.parameters_panel = Parameters(session, self)
  -- self.parameters_panel = Parameters({
  --   type = " ",
  --   default_params = self.session.parameters,
  --   session = self.session,
  --   parent = self,
  -- })
  --
  self:redraw()
end

return Chat
