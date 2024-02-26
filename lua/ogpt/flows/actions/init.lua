local M = {}

-- local CompletionAction = require("ogpt.flows.actions.completions")
local EditAction = require("ogpt.flows.actions.edits")
local PopupAction = require("ogpt.flows.actions.popup")
local Config = require("ogpt.config")

local classes_by_type = {
  chat = PopupAction,
  -- completion = CompletionAction,
  edit = EditAction,
  popup = PopupAction,
}

local read_actions_from_file = function(filename)
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
  filename = filename:gsub("~", home)
  local file = io.open(filename, "rb")
  if not file then
    vim.notify("Cannot read action file: " .. filename, vim.log.levels.ERROR)
    return nil
  end

  local json_string = file:read("*a")
  file:close()

  local ok, json = pcall(vim.json.decode, json_string)
  if ok then
    return json
  end
end

function M.read_actions()
  local actions = Config.options.actions
  -- local actions = {}
  local paths = {}

  for i = 1, #Config.options.actions_paths do
    paths[#paths + 1] = Config.options.actions_paths[i]
  end

  for _, filename in ipairs(paths) do
    local data = read_actions_from_file(filename)
    if data then
      for action_name, action_definition in pairs(data) do
        actions[action_name] = action_definition
      end
    end
  end
  return actions
end

function M.run_action(opts)
  local ACTIONS = M.read_actions()
  local action_name = table.remove(opts.fargs, 1)

  local action_opts = loadstring("return " .. table.concat(opts.fargs, " "))() or {}

  local item = ACTIONS[action_name]
  if not item then
    vim.notify("Action '" .. action_name .. "' does not exist in OGPT Actions.  Try checking your config table/JSON.")
    return
  end

  opts = vim.tbl_extend("force", {}, item, action_opts)
  local class = classes_by_type[item.type]
  local action = class(action_name, opts)
  vim.schedule_wrap(action:run())
  return action
end

return M
