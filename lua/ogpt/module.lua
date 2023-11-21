-- module represents a lua module for the plugin
local M = {}

local Chat = require("ogpt.flows.chat")
local Edits = require("ogpt.code_edits")
local Actions = require("ogpt.flows.actions")
local CodeCompletions = require("ogpt.flows.code_completions")

M.open_chat = Chat.open
M.open_chat_with_awesome_prompt = Chat.open_with_awesome_prompt
M.edit_with_instructions = Edits.edit_with_instructions
M.run_action = Actions.run_action
M.complete_code = CodeCompletions.complete

return M
