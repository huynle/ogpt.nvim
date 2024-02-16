-- module represents a lua module for the plugin
local M = {
  chats = {},
  actions = {},
}

local Config = require("ogpt.config")
local Chat = require("ogpt.flows.chat.base")
local Actions = require("ogpt.flows.actions")
local Session = require("ogpt.flows.chat.session")
local Prompts = require("ogpt.prompts")

-- M.open_chat = Chat.open
-- M.focus_chat = Chat.focus
-- M.open_chat_with_awesome_prompt = Chat.open_with_awesome_prompt
M.run_action = Actions.run_action

function M.clear_windows()
  if not Config.options.single_window then
    return
  end

  for _, chat in ipairs(M.chats) do
    chat:hide()
  end
  for _, action in ipairs(M.actions) do
    action:close()
  end
end

function M.open_chat(opts)
  if Config.options.single_window then
    for _, chat in ipairs(M.chats) do
      chat:hide()
    end
    for _, action in ipairs(M.actions) do
      action:close()
    end
  end

  if M.chats ~= nil and M.chats.active then
    M.chats:toggle()
  else
    M.chats = Chat(opts)
    M.chats:open(opts)
  end
end

function M.focus_chat(opts)
  if M.chats ~= nil then
    if not M.chats.focused then
      M.chats:hide(opts)
      M.chats:show(opts)
    end
  else
    M.chats = Chat(opts)
    M.chats:open(opts)
  end
end

function M.open_chat_with_awesome_prompt(opts)
  Prompts.selectAwesomePrompt({
    cb = vim.schedule_wrap(function(act, prompt)
      -- create new named session
      local session = Session({ name = act })
      session:save()

      local chat = Chat:new()
      chat:open()
      chat.chat_window.border:set_text("top", " OGPT - Acts as " .. act .. " ", "center")

      chat:set_system_message(prompt)
      chat:open_system_panel()
    end),
  })
end

function M.run_action(opts)
  if Config.options.single_window then
    for _, chat in ipairs(M.chats) do
      chat:hide()
    end
    for _, action in ipairs(M.actions) do
      action:close()
    end
  end
  local action_hdl = Actions.run_action(opts)
  if action_hdl then
    table.insert(M.actions, action_hdl)
  end
end

return M
