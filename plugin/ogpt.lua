vim.api.nvim_create_user_command("OGPT", function()
  require("ogpt").openChat()
end, {})

vim.api.nvim_create_user_command("OGPTActAs", function()
  require("ogpt").selectAwesomePrompt()
end, {})

vim.api.nvim_create_user_command("OGPTRun", function(opts)
  require("ogpt").run_action(opts)
end, {
  nargs = "*",
  range = true,
  complete = function()
    local ActionFlow = require("ogpt.flows.actions")
    local action_definitions = ActionFlow.read_actions()

    local actions = {}
    for key, _ in pairs(action_definitions) do
      table.insert(actions, key)
    end
    table.sort(actions)

    return actions
  end,
})

vim.api.nvim_create_user_command("OGPTCompleteCode", function(opts)
  require("ogpt").complete_code(opts)
end, {})
