local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local Response = require("ogpt.response")
local ProviderBase = require("ogpt.provider.base")
local Anthropic = ProviderBase:extend("Anthropic")

function Anthropic:init(opts)
  Anthropic.super.init(self, opts)
  self.response_params = {
    strategy = Response.STRATEGY_LINE_BY_LINE,
    split_chunk_match_regex = nil,
  }
  self.api_parameters = {
    "messages",
  }
  self.api_chat_request_options = {
    "model",
    "stream",
    "system",
    "stop_sequences",
    "max_tokens",
    "temperature",
    "top_p",
    "top_k",
  }
end

function Anthropic:load_envs(override)
  local _envs = {}
  _envs.ANTHROPIC_API_KEY = Config.options.providers.anthropic.api_key or os.getenv("ANTHROPIC_API_KEY") or ""
  _envs.AUTH = "x-api-key: " .. (_envs.ANTHROPIC_API_KEY or " ")
  _envs.MODEL = "claude-3-opus-20240229"
  _envs.ANTHROPIC_API_HOST = Config.options.providers.anthropic.api_host
    or os.getenv("ANTHROPIC_API_HOST")
    or "https://api.anthropic.com/v1/messages"
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.ANTHROPIC_API_HOST .. "/models")
  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function Anthropic:parse_api_model_response(json, cb)
  -- Given a json object from the api, parse this and get the names of the model to be displayed
  for _, model in ipairs(json.models) do
    cb({
      name = model.name,
    })
  end
end

function Anthropic:completion_url()
  return utils.ensureUrlProtocol(self.envs.ANTHROPIC_API_HOST)
end

function Anthropic:models_url()
  -- no support yet
  return
end

function Anthropic:request_headers()
  return {
    "-H",
    "Content-Type: application/json",
    "-H",
    "anthropic-version: 2023-06-01",
    "-H",
    self.envs.AUTH,
  }
end

function Anthropic:conform_request(params)
  -- https://docs.anthropic.com/claude/reference/messages_post
  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      if vim.tbl_contains(self.api_chat_request_options, key) then
        -- move it to the options
        param_options[key] = value
        params[key] = nil
      else
        params[key] = nil
      end
    end
  end
  local _options = vim.tbl_extend("keep", param_options, params.options or {})
  if next(_options) ~= nil then
    -- params.generationConfig = _options
    params = vim.tbl_extend("force", params, _options)
  end
  return params
end

function Anthropic:conform_messages(params)
  -- ensure we only have one system message
  local _to_remove_system_idx = {}
  for idx, message in ipairs(params.messages) do
    if message.role == "system" then
      table.insert(_to_remove_system_idx, idx)
    end
  end
  -- Remove elements from the list based on indices
  for i = #_to_remove_system_idx, 1, -1 do
    table.remove(params.messages, _to_remove_system_idx[i])
  end

  local messages = params.messages
  local _messages = {}
  for _, content in ipairs(messages) do
    table.insert(_messages, {
      role = content.role == "assistant" and "assistant" or "user",
      -- content = {
      --   type = "text",
      --   text = utils.gather_text_from_parts(content.content),
      -- },
      content = utils.gather_text_from_parts(content.content),
    })
  end

  params.messages = _messages
  return params
end

function Anthropic:process_response(response)
  local chunk = response:pop_chunk()
  local _data

  if string.find(chunk, "^event: ") then
    -- save the event and the raw chunk for reference later
    self._event = { string.gsub(chunk, "^event: ", ""), chunk }
    return
  elseif string.find(chunk, "^data: ") then
    _data = string.gsub(chunk, "^data: ", "")
  else
    return
  end

  local ok, json = pcall(vim.json.decode, _data)

  if not ok then
    utils.log("Cannot process anthropic response: \n" .. vim.inspect(chunk))
    return
  end

  if vim.tbl_get(json, "type", "message_start") then
    utils.log("Start of Anthropic response.", vim.log.levels.DEBUG)
  elseif vim.tbl_get(json, "delta", "text") then
    response:add_processed_text(vim.tbl_get(json, "delta", "text"), "CONTINUE")
    -- Could process more here
  end
end

return Anthropic
