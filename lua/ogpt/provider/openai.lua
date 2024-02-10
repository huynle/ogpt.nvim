local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local ProviderBase = require("ogpt.provider.base")

local Openai = ProviderBase:extend("Openai")

function Openai:init(opts)
  Openai.super.init(self, opts)
  -- self.api_parameters = {
  --   "model",
  --   "messages",
  --   "format",
  --   "options",
  --   "system",
  --   "template",
  --   "stream",
  --   "raw",
  -- }

  self.name = "openai"
  self.api_parameters = {
    "model",
    "messages",
    "stream",
    "temperature",
    "presence_penalty",
    "frequency_penalty",
    "top_p",
    "max_tokens",
  }
  self.api_chat_request_options = {}
end

function Openai:load_envs(override)
  local _envs = {}
  _envs.OPENAI_API_HOST = Config.options.providers.openai.api_host
    or os.getenv("OPENAI_API_HOST")
    or "https://api.openai.com"
  _envs.OPENAI_API_KEY = Config.options.providers.openai.api_key or os.getenv("OPENAI_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/models")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/completions")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/chat/completions")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OPENAI_API_KEY or " ")
  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function Openai:parse_api_model_response(json, cb)
  local data = json.data or {}
  for _, model in ipairs(data) do
    cb({
      name = model.id,
    })
  end
end

function Openai:conform_request(params)
  -- params = M._conform_messages(params)

  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      utils.log("Did not process " .. key .. " for " .. self.name)
      params[key] = nil
    end
  end
  return params
end

function Openai:conform_messages(params)
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

  -- https://platform.openai.com/docs/api-reference/chat
  if params.system then
    table.insert(params.messages, 1, {
      role = "system",
      content = params.system,
    })
  end
  return params
end

function Openai:process_line(content, ctx, raw_chunks, state, cb)
  local _json = content.json
  local raw = content.raw
  -- given a JSON response from the STREAMING api, processs it
  if _json and _json.done then
    ctx.context = _json.context
    cb(raw_chunks, "END", ctx)
  elseif type(_json) == "string" and string.find(_json, "[DONE]") then
    cb(raw_chunks, "END", ctx)
  else
    if
      not vim.tbl_isempty(_json)
      and _json
      and _json.choices
      and _json.choices[1]
      and _json.choices[1].delta
      and _json.choices[1].delta.content
    then
      cb(_json.choices[1].delta.content, state)
      raw_chunks = raw_chunks .. _json.choices[1].delta.content
      state = "CONTINUE"
    elseif
      not vim.tbl_isempty(_json)
      and _json
      and _json.choices
      and _json.choices[1]
      and _json.choices[1].message
      and _json.choices[1].message.content
    then
      cb(_json.choices[1].message.content, state)
      raw_chunks = raw_chunks .. _json.choices[1].message.content
    end
  end

  return ctx, raw_chunks, state
end

return Openai
