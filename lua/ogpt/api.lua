local job = require("plenary.job")
local Config = require("ogpt.config")
local logger = require("ogpt.common.logger")
local classes = require("ogpt.common.classes")
local utils = require("ogpt.utils")

local Api = classes.class()

function Api:init(provider, action, opts)
  self.opts = opts
  self.provider = provider
  self.action = action
end

function Api:completions(custom_params, cb)
  local params = vim.tbl_extend("keep", custom_params, Config.options.api_params)
  params.stream = false
  self:make_call(self.COMPLETIONS_URL, params, cb)
end

function Api:chat_completions(custom_params, cb, should_stop, opts)
  local stream = custom_params.stream or false
  local params, _completion_url = Config.expand_model(self, custom_params)

  local ctx = {}
  ctx.params = params
  utils.log("Request to: " .. _completion_url)
  utils.log(params)

  if stream then
    local raw_chunks = ""
    local state = "START"

    cb = vim.schedule_wrap(cb)

    self:exec(
      "curl",
      {
        "--silent",
        "--show-error",
        "--no-buffer",
        _completion_url,
        "-H",
        "Content-Type: application/json",
        "-H",
        self.provider.envs.AUTHORIZATION_HEADER,
        "-d",
        vim.json.encode(params),
      },
      function(chunk)
        local ok, json = pcall(vim.json.decode, chunk)
        if ok then
          if json.error ~= nil then
            local error_msg = {
              "OGPT ERROR:",
              self.provider.name,
              json.error.message or "",
              "Something went wrong.",
            }
            error_msg = table.insert(error_msg, vim.tbl_flatten(params))
            -- local error_msg = "OGPT ERROR: " .. (json.error.message or "Something went wrong")
            cb(table.concat(error_msg, " "), "ERROR", ctx)
            return
          end
          ctx, raw_chunks, state = self.provider.process_line(json, ctx, raw_chunks, state, cb)
          return
        end

        for line in chunk:gmatch("[^\n]+") do
          local raw_json = string.gsub(line, "^data:", "")
          local _ok, _json = pcall(vim.json.decode, raw_json)
          if _ok then
            ctx, raw_chunks, state = self.provider.process_line(_json, ctx, raw_chunks, state, cb)
          end
        end
      end,
      function(err, _)
        cb(err, "ERROR", ctx)
      end,
      should_stop,
      function()
        cb(raw_chunks, "END", ctx)
      end
    )
  else
    params.stream = false
    self:make_call(self.provider.envs.CHAT_COMPLETIONS_URL, params, cb)
  end
end

function Api:edits(custom_params, cb)
  local params = self.action.params
  params.stream = true
  params = vim.tbl_extend("force", params, custom_params)
  self:chat_completions(params, cb)
end

function Api:make_call(url, params, cb)
  TMP_MSG_FILENAME = os.tmpname()
  local f = io.open(TMP_MSG_FILENAME, "w+")
  if f == nil then
    vim.notify("Cannot open temporary message file: " .. TMP_MSG_FILENAME, vim.log.levels.ERROR)
    return
  end
  f:write(vim.fn.json_encode(params))
  f:close()
  self.job = job
    :new({
      command = "curl",
      args = {
        url,
        "-H",
        "Content-Type: application/json",
        "-H",
        self.AUTHORIZATION_HEADER,
        "-d",
        "@" .. TMP_MSG_FILENAME,
      },
      on_exit = vim.schedule_wrap(function(response, exit_code)
        os.remove(TMP_MSG_FILENAME)
        if exit_code ~= 0 then
          vim.notify("An Error Occurred ...", vim.log.levels.ERROR)
          cb("ERROR: API Error")
        end

        local result = table.concat(response:result(), "\n")
        local json = vim.fn.json_decode(result)
        if json == nil then
          cb("No Response.")
        elseif json.error then
          cb("// API ERROR: " .. json.error)
        else
          local message = json.message
          if message ~= nil then
            local message_response
            local first_message = json.message.content
            if first_message.function_call then
              message_response = vim.fn.json_decode(first_message.function_call.arguments)
            else
              message_response = first_message
            end
            if (type(message_response) == "string" and message_response ~= "") or type(message_response) == "table" then
              cb(message_response, "CONTINUE")
            else
              cb("...")
            end
          else
            local response_text = json.response
            if type(response_text) == "string" and response_text ~= "" then
              cb(response_text, "CONTINUE")
            else
              cb("...")
            end
          end
        end
      end),
    })
    :start()
end

function Api:close()
  if self.job then
    job:shutdown()
  end
end

local splitCommandIntoTable = function(command)
  local cmd = {}
  for word in command:gmatch("%S+") do
    table.insert(cmd, word)
  end
  return cmd
end

local function loadConfigFromCommand(command, optionName, callback, defaultValue)
  local cmd = splitCommandIntoTable(command)
  job
    :new({
      command = cmd[1],
      args = vim.list_slice(cmd, 2, #cmd),
      on_exit = function(j, exit_code)
        if exit_code ~= 0 then
          logger.warn("Config '" .. optionName .. "' did not return a value when executed")
          return
        end
        local value = j:result()[1]:gsub("%s+$", "")
        if value ~= nil and value ~= "" then
          callback(value)
        elseif defaultValue ~= nil and defaultValue ~= "" then
          callback(defaultValue)
        end
      end,
    })
    :start()
end

local function loadConfigFromEnv(envName, configName, callback)
  local variable = os.getenv(envName)
  if not variable then
    return
  end
  local value = variable:gsub("%s+$", "")
  Api[configName] = value
  if callback then
    callback(value)
  end
end

local function loadApiHost(envName, configName, optionName, callback, defaultValue)
  loadConfigFromEnv(envName, configName)
  if Api[configName] then
    callback(Api[configName])
  else
    if Config.options[optionName] ~= nil and Config.options[optionName] ~= "" then
      loadConfigFromCommand(Config.options[optionName], optionName, callback, defaultValue)
    else
      callback(defaultValue)
    end
  end
end

local function loadApiKey(envName, configName, optionName, callback, defaultValue)
  loadConfigFromEnv(envName, configName, callback)
  if not Api[configName] then
    if Config.options[optionName] ~= nil and Config.options[optionName] ~= "" then
      loadConfigFromCommand(Config.options[optionName], optionName, callback, defaultValue)
    elseif defaultValue ~= nil then
      callback(defaultValue)
    else
      logger.warn(envName .. " environment variable not set")
      return
    end
  end
end

local function loadAzureConfigs()
  loadApiKey("OPENAI_API_BASE", "OPENAI_API_BASE", "azure_api_base_cmd", function(value)
    self.OPENAI_API_BASE = value
  end)
  loadApiKey("OPENAI_API_AZURE_ENGINE", "OPENAI_API_AZURE_ENGINE", "azure_api_engine_cmd", function(value)
    self.OPENAI_API_AZURE_ENGINE = value
  end)
  loadApiHost("OPENAI_API_AZURE_VERSION", "OPENAI_API_AZURE_VERSION", "azure_api_version_cmd", function(value)
    self.OPENAI_API_AZURE_VERSION = value
  end, "2023-05-15")

  if Api["OPENAI_API_BASE"] and Api["OPENAI_API_AZURE_ENGINE"] then
    self.COMPLETIONS_URL = self.OPENAI_API_BASE
      .. "/openai/deployments/"
      .. self.OPENAI_API_AZURE_ENGINE
      .. "/completions?api-version="
      .. self.OPENAI_API_AZURE_VERSION
    self.CHAT_COMPLETIONS_URL = self.OPENAI_API_BASE
      .. "/openai/deployments/"
      .. self.OPENAI_API_AZURE_ENGINE
      .. "/chat/completions?api-version="
      .. self.OPENAI_API_AZURE_VERSION
  end
end

local function startsWith(str, start)
  return string.sub(str, 1, string.len(start)) == start
end

local function ensureUrlProtocol(str)
  if startsWith(str, "https://") or startsWith(str, "http://") then
    return str
  end

  return "https://" .. str
end

function Api:exec(cmd, args, on_stdout_chunk, on_complete, should_stop, on_stop)
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local stderr_chunks = {}

  local handle, err
  local function on_stdout_read(_, chunk)
    if chunk then
      vim.schedule(function()
        if should_stop and should_stop() then
          if handle ~= nil then
            handle:kill(2) -- send SIGINT
            stdout:close()
            stderr:close()
            handle:close()
            on_stop()
          end
          return
        end
        on_stdout_chunk(chunk)
      end)
    end
  end

  local function on_stderr_read(_, chunk)
    if chunk then
      table.insert(stderr_chunks, chunk)
    end
  end

  handle, err = vim.loop.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    if handle ~= nil then
      handle:close()
    end

    vim.schedule(function()
      if code ~= 0 then
        on_complete(vim.trim(table.concat(stderr_chunks, "")))
      end
    end)
  end)

  if not handle then
    on_complete(cmd .. " could not be started: " .. err)
  else
    stdout:read_start(on_stdout_read)
    stderr:read_start(on_stderr_read)
  end
end

return Api
