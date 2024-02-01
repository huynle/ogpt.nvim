-- module represents a lua module for the plugin
local M = {}

local Chat = require("ogpt.flows.chat")
local Actions = require("ogpt.flows.actions")

M.open_simple_chat = Chat.open_simple_chat
M.focus_simple_chat = Chat.focus_simple_chat
M.open_chat = Chat.open
M.focus_chat = Chat.focus
M.open_chat_with_awesome_prompt = Chat.open_with_awesome_prompt
M.run_action = Actions.run_action

return M
