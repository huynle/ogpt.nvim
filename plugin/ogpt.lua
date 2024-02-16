vim.api.nvim_create_user_command("OGPT", function(opts)
  opts = loadstring("return " .. opts.args)() or {}
  require("ogpt").openChat(opts)
end, { nargs = "?", force = true, complete = "lua" })

vim.api.nvim_create_user_command("OGPTFocus", function(opts)
  opts = loadstring("return " .. opts.args)() or {}
  require("ogpt").focusChat(opts)
end, { nargs = "?", force = true, complete = "lua" })

vim.api.nvim_create_user_command("OGPTActAs", function(opts)
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

vim.api.nvim_create_user_command("OGPTRunWithOpts", function(params)
  local args = loadstring("return " .. params.args)()
  require("ogpt").run_action(args)
end, {
  nargs = "?",
  force = true,
  complete = "lua",
})

vim.api.nvim_create_user_command("OGPTCompleteCode", function(opts)
  opts = loadstring("return " .. opts.args)() or {}
  require("ogpt").complete_code(opts)
end, { nargs = "?", force = true, complete = "lua" })
