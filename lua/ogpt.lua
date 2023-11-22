-- main module file
local api = require("ogpt.api")
local module = require("ogpt.module")
local config = require("ogpt.config")
local signs = require("ogpt.signs")

local M = {}

M.setup = function(options)
  -- set custom highlights
  vim.api.nvim_set_hl(0, "OGPTQuestion", { fg = "#b4befe", italic = true, bold = false, default = true })

  vim.api.nvim_set_hl(0, "OGPTWelcome", { fg = "#9399b2", italic = true, bold = false, default = true })

  vim.api.nvim_set_hl(0, "OGPTTotalTokens", { fg = "#ffffff", bg = "#444444", default = true })
  vim.api.nvim_set_hl(0, "OGPTTotalTokensBorder", { fg = "#444444", default = true })

  vim.api.nvim_set_hl(0, "OGPTMessageAction", { fg = "#ffffff", bg = "#1d4c61", italic = true, default = true })

  vim.api.nvim_set_hl(0, "OGPTCompletion", { fg = "#9399b2", italic = true, bold = false, default = true })

  vim.cmd("highlight default link OGPTSelectedMessage ColorColumn")

  config.setup(options)
  api.setup()
  signs.setup()
end

--
-- public methods for the plugin
--

M.openChat = function()
  module.open_chat()
end

M.selectAwesomePrompt = function()
  module.open_chat_with_awesome_prompt()
end

M.edit_code_with_instructions = function()
  module.edit_with_instructions(nil, nil, nil, {
    edit_code = true,
  })
end

M.run_action = function(opts)
  module.run_action(opts)
end

M.complete_code = module.complete_code

return M
