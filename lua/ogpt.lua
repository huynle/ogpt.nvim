-- main module file
local module = require("ogpt.module")
local config = require("ogpt.config")
local conf = require("telescope.config").values
local signs = require("ogpt.signs")
local pickers = require("telescope.pickers")
local Config = require("ogpt.config")
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

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
  signs.setup()
end

--- select Action
local finder = function(action_definitions)
  return setmetatable({
    close = function() end,
  }, {
    __call = function(_, prompt, process_result, process_complete)
      for key, action_opts in pairs(action_definitions) do
        process_result({
          value = key,
          display = key,
          ordinal = key,
        })
      end
      process_complete()
    end,
  })
end

function M.select_action(opts)
  opts = opts or {}

  local ActionFlow = require("ogpt.flows.actions")
  local action_definitions = ActionFlow.read_actions()
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "Select Ollama action",
      prompt_prefix = Config.options.input_window.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "actions",
      finder = finder(action_definitions),
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          opts.cb(selection.display, selection.value)
        end)
        return true
      end,
    })
    :find()
end

--
-- public methods for the plugin
--

M.openChat = function(opts)
  module.open_chat(opts)
end

M.focusChat = function(opts)
  module.focus_chat(opts)
end

M.selectAwesomePrompt = function()
  module.open_chat_with_awesome_prompt()
end

M.edit_with_instructions = function(opts)
  module.edit_with_instructions(nil, nil, nil, opts)
end

M.run_action = function(opts)
  if opts.args == "" then
    M.select_action({
      cb = function(key, value)
        local _opts = vim.tbl_extend("force", opts, {
          args = key,
          fargs = {
            key,
          },
        })
        module.run_action(_opts)
      end,
    })
  else
    module.run_action(opts)
  end
end

M.complete_code = module.complete_code

return M
