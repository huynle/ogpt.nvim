local Session = require("ogpt.flows.chat.session")
local Prompts = require("ogpt.prompts")
local Chat = require("ogpt.flows.chat.base")
local SimpleChat = require("ogpt.flows.chat.simple")

local M = {
  chat = nil,
  simple_chat = nil,
}

M.open = function(opts)
  if M.chat ~= nil and M.chat.active then
    M.chat:toggle()
  else
    M.chat = Chat(opts)
    M.chat:open(opts)
  end
end

M.focus = function(opts)
  if M.chat ~= nil then
    if not M.chat.focused then
      M.chat:hide(opts)
      M.chat:show(opts)
    end
  else
    M.chat = Chat(opts)
    M.chat:open(opts)
  end
end

M.open_simple_chat = function(opts)
  if M.simple_chat ~= nil and M.simple_chat.active then
    M.simple_chat:toggle()
  else
    M.simple_chat = SimpleChat(opts)
    M.simple_chat:open(opts)
  end
end

M.focus_simple_chat = function(opts)
  if M.simple_chat ~= nil then
    if not M.simple_chat.focused then
      M.simple_chat:hide(opts)
      M.simple_chat:show(opts)
    end
  else
    M.simple_chat = SimpleChat(opts)
    M.simple_chat:open(opts)
  end
end

M.open_with_awesome_prompt = function()
  Prompts.selectAwesomePrompt({
    cb = vim.schedule_wrap(function(act, prompt)
      -- create new named session
      local session = Session.new({ name = act })
      session:save()

      local chat = Chat()
      chat:open()
      chat.chat_window.border:set_text("top", " OGPT - Acts as " .. act .. " ", "center")

      chat:set_system_message(prompt)
      chat:open_system_panel()
    end),
  })
end

return M
