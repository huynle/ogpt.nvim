local job = require("plenary.job")
local Config = require("ogpt.config")
local logger = require("ogpt.common.logger")
local Object = require("ogpt.common.object")
local utils = require("ogpt.utils")
local Response = require("ogpt.response")

local Api = Object("Api")

Api.STATE_COMPLETED = "COMPLETED"

function Api:init(provider, action, opts)
  self.opts = opts
  self.provider = provider
  self.action = action
end

function Api:completions(custom_params, cb, opts)
  -- TODO: not working atm
  local params = vim.tbl_extend("keep", custom_params, Config.options.api_params)
  params.stream = false
  self:make_call(self.COMPLETIONS_URL, params, cb, opts)
end

function Api:chat_completions(response, inputs)
  local custom_params = inputs.custom_params
  local partial_result_fn = inputs.partial_result_fn
  local should_stop = inputs.should_stop or function() end

  -- local stream = custom_params.stream or false
  local params, _completion_url, ctx = self.provider:expand_model(custom_params)

  ctx.params = params
  ctx.provider = self.provider.name
  ctx.model = custom_params.model
  utils.log("Request to: " .. _completion_url)
  utils.log(params)
  response.ctx = ctx
  response.rest_params = params
  response.partial_result_cb = partial_result_fn
  response:run_async()

  local on_complete = inputs.on_complete or function()
    response:set_state(response.STATE_COMPLETED)
  end
  local on_start = inputs.on_start
    or function()
      -- utils.log("Start Exec of: Curl " .. vim.inspect(curl_args), vim.log.levels.DEBUG)
      response:set_state(response.STATE_INPROGRESS)
    end
  local on_error = inputs.on_error
    or function(msg)
      -- utils.log("Error running curl: " .. msg or "", vim.log.levels.ERROR)
      response:set_state(response.STATE_ERROR)
    end
  local on_stop = inputs.on_stop or function()
    response:set_state(response.STATE_STOPPED)
  end

  -- if params.stream then
  -- local accumulate = {}
  local curl_args = {
    "--silent",
    "--show-error",
    "--no-buffer",
    _completion_url,
    "-d",
    vim.json.encode(params),
  }
  for _, header_item in ipairs(self.provider:request_headers()) do
    table.insert(curl_args, header_item)
  end

  self:exec("curl", curl_args, on_start, function(chunk)
    response:add_chunk(chunk)
  end, on_complete, on_error, on_stop, should_stop)
end

-- function Api:edits(custom_params, cb)
--   local params = self.action.params
--   params.stream = true
--   params = vim.tbl_extend("force", params, custom_params)
--   self:chat_completions(params, cb)
-- end

function Api:make_call(url, params, cb, ctx, raw_chunks, state, opts)
  -- TODO:  to be deprecated
  ctx = ctx or {}
  raw_chunks = raw_chunks or ""
  state = state or "START"

  TMP_MSG_FILENAME = os.tmpname()
  local f = io.open(TMP_MSG_FILENAME, "w+")
  if f == nil then
    vim.notify("Cannot open temporary message file: " .. TMP_MSG_FILENAME, vim.log.levels.ERROR)
    return
  end
  f:write(vim.fn.json_encode(params))
  f:close()

  local curl_args = {
    url,
    "-d",
    "@" .. TMP_MSG_FILENAME,
    table.unpack(self.provider:request_headers()),
  }

  self.job = job
    :new({
      command = "curl",
      args = curl_args,
      on_exit = vim.schedule_wrap(function(response, exit_code)
        os.remove(TMP_MSG_FILENAME)
        if exit_code ~= 0 then
          utils.log(
            "An Error Occurred, when calling `curl " .. table.concat(curl_args, " ") .. "`",
            vim.log.levels.ERROR
          )
          cb("ERROR: API Error", "ERROR")
        end

        local result = table.concat(response:result(), "\n")

        local ok, json = pcall(vim.json.decode, result)
        if ok then
          if json.error ~= nil then
            local error_msg = {
              "OGPT ERROR:",
              self.provider.name,
              vim.inspect(json.error) or "",
              "Something went wrong.",
            }
            table.insert(error_msg, vim.inspect(params))
            -- local error_msg = "OGPT ERROR: " .. (json.error.message or "Something went wrong")
            cb(table.concat(error_msg, " "), "ERROR", ctx)
            return
          end
          ctx, raw_chunks, state =
            self.provider:process_line({ json = json, raw = result }, ctx, raw_chunks, state, cb, opts)
          return
        end

        for line in result:gmatch("[^\n]+") do
          local raw_json = string.gsub(line, "^data:", "")
          local _ok, _json = pcall(vim.json.decode, raw_json)
          if _ok then
            ctx, raw_chunks, state =
              self.provider:process_line({ json = _json, raw = line }, ctx, raw_chunks, state, cb, opts)
          else
            ctx, raw_chunks, state =
              self.provider:process_line({ json = _json, raw = line }, ctx, raw_chunks, state, cb, opts)
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

local function startsWith(str, start)
  return string.sub(str, 1, string.len(start)) == start
end

local function ensureUrlProtocol(str)
  if startsWith(str, "https://") or startsWith(str, "http://") then
    return str
  end

  return "https://" .. str
end

function Api:exec(cmd, args, on_start, on_stdout_chunk, on_complete, on_error, on_stop, should_stop)
  local stderr = vim.loop.new_pipe()
  local stdout = vim.loop.new_pipe()
  local stderr_chunks = {}

  local handle, err
  local function on_stdout_read(_, chunk)
    if chunk then
      vim.schedule(function()
        if should_stop() then
          if handle ~= nil then
            handle:kill(2) -- send SIGINT
            pcall(function()
              stdout:close()
            end)
            pcall(function()
              stderr:close()
            end)
            pcall(function()
              handle:close()
            end)
            on_stop()
          end
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

  on_start()
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
        on_error()
      else
        on_complete()
      end
    end)
  end)

  if not handle then
    on_error(cmd .. " could not be started: " .. err)
  else
    stdout:read_start(on_stdout_read)
    stderr:read_start(on_stderr_read)
  end
end

return Api
