local Object = require("ogpt.common.object")
local Path = require("plenary.path")
local scan = require("plenary.scandir")
local Config = require("ogpt.config")

local Session = Object("Session")

local function get_current_date()
  return os.date("%Y-%m-%d_%H:%M:%S")
end

local function get_default_filename()
  return os.time()
end

local function parse_date_time(str)
  local year, month, day, hour, min, sec = string.match(str, "(%d+)-(%d+)-(%d+)_(%d+):(%d+):(%d+)")
  return os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
end

local function read_session_file(filename)
  local file = io.open(filename, "rb")
  if not file then
    vim.notify("Cannot read session file", vim.log.levels.ERROR)
    return nil
  end

  local jsonString = file:read("*a")
  file:close()

  local ok, data = pcall(vim.json.decode, jsonString)
  -- local data = vim.fn.json_decode(jsonString)
  if not ok then
    return nil, nil
  else
    return data.name, data.updated_at
  end
end

function Session:init(opts)
  opts = opts or {}
  self.filename = opts.filename or nil
  if self.filename then
    self:load()
  else
    local dt = get_current_date()
    self.name = opts.name or dt
    self.updated_at = dt
    self.filename = Session.get_dir():joinpath(get_default_filename() .. ".json"):absolute()
    self.conversation = {}
    self.parameters = Config.get_chat_params()
  end
end

function Session:rename(name)
  self.name = name
  self:save()
end

function Session:delete()
  return Path:new(self.filename):rm()
end

function Session:to_export()
  local _val = {
    name = self.name,
    updated_at = self.updated_at,
    parameters = self.parameters,
    conversation = self.conversation,
  }
  _val.parameters.model = self.parameters.model and self.parameters.model.name or self.parameters.model
  return _val
end

function Session:previous_context()
  for ith = #self.conversation, 1, -1 do
    local context = self.conversation[ith].text
    if context then
      return context
    end
  end
  return {}
end

function Session:add_item(item)
  local ctx = item.ctx or {}
  if item.ctx then
    item.ctx = nil
  end
  if ctx and ctx.params and ctx.params.options then
    -- ollama uses "options" to pass in parameters in its api calls
    self.parameters = ctx.params.options
    self.parameters.model = ctx.params.model
  else
    -- self.parameters = vim.tbl_extend("force", self.parameters, vim.tbl_get(ctx, "params", "parameters") or {})
    self.parameters = vim.tbl_get(ctx, "params", "parameters") or {} or self.parameters
  end

  -- add provider anbd model into a session to track
  self.parameters.provider = ctx.provider
  self.parameters.model = ctx.model

  -- handling context token
  item.context = ctx.context

  if self.updated_at == self.name and item.type == 1 then
    self.name = item.text
  end
  -- tmp hack for system message
  if item.type == 3 then
    local found = false
    for index, msg in ipairs(self.conversation) do
      if msg.type == item.type then
        self.conversation[index].text = item.text
        found = true
      end
    end

    if not found then
      table.insert(self.conversation, 1, item)
    end
  else
    table.insert(self.conversation, item)
  end

  self.updated_at = get_current_date()
  self:save()

  return #self.conversation + 1
end

function Session:delete_by_index(idx)
  table.remove(self.conversation, idx)
  self.updated_at = get_current_date()
  self:save()
end

function Session:save()
  local data = self:to_export()

  local file, err = io.open(self.filename, "w")
  if file ~= nil then
    local json_string = vim.json.encode(data)
    file:write(json_string)
    file:close()
  else
    vim.notify("Cannot save session: " .. err, vim.log.levels.ERROR)
  end
end

function Session:load()
  local file = io.open(self.filename, "rb")
  if not file then
    vim.notify("Cannot read session file", vim.log.levels.ERROR)
    return nil
  end

  local jsonString = file:read("*a")
  file:close()

  local ok, data = pcall(vim.json.decode, jsonString)
  if ok then
    self.name = data.name
    self.updated_at = data.updated_at or get_current_date()
    self.parameters = data.parameters
    self.conversation = data.conversation
  end
end

--
-- static methods
--

function Session.get_dir()
  local dir = Path:new(vim.fn.stdpath("state")):joinpath("ogpt")
  if not dir:exists() then
    dir:mkdir()
  end
  return dir
end

function Session.list_sessions()
  local dir = Session.get_dir()
  local files = scan.scan_dir(dir:absolute(), { hidden = false })
  local sessions = {}

  for _, filename in pairs(files) do
    local name, updated_at = read_session_file(filename)
    if updated_at == nil then
      updated_at = filename
    end
    local ok, ts = pcall(parse_date_time, updated_at)
    if ok then
      table.insert(sessions, {
        filename = filename,
        name = name,
        ts = ts,
      })
    end
  end

  table.sort(sessions, function(a, b)
    return a.ts > b.ts
  end)

  return sessions
end

function Session.latest(opts)
  local sessions = Session.list_sessions()
  if #sessions > 0 then
    local session = sessions[1]
    return Session({ filename = session.filename })
  end
  return Session(opts)
end

return Session
