local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local ProviderBase = require("ogpt.provider.base")
local Response = require("ogpt.response")
local Openai = ProviderBase:extend("openai")

function Openai:init(opts)
  Openai.super.init(self, opts)
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

function Openai:parse_api_model_response(res, cb)
  local response = table.concat(res, "\n")
  local ok, json = pcall(vim.fn.json_decode, response)
  if not ok then
    vim.print("OGPT ERROR: something happened when trying request for models from " .. self:models_url())
  else
    local data = json.data or {}
    for _, model in ipairs(data) do
      cb({
        name = model.id,
      })
    end
  end
end

function Openai:conform_request(params)
  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      utils.log("Did not process " .. key .. " for " .. self.name)
      params[key] = nil
    end
  end
  return params
end

function Openai:process_response(response)
  local chunk = response:pop_chunk()
  local raw_json = string.gsub(chunk, "^data:", "")
  local _ok, _json = pcall(vim.json.decode, raw_json)
  if _ok then
    self:_process_line({ json = _json, raw = chunk }, response)
  else
    self:_process_line({ json = nil, raw = chunk }, response)
  end
end

function Openai:_process_line(content, response)
  local _json = content.json
  local _raw = content.raw
  if _json then
    local text_delta = vim.tbl_get(_json, "choices", 1, "delta", "content")
    local text = vim.tbl_get(_json, "choices", 1, "message", "content")
    if text_delta then
      response:add_processed_text(text_delta, "CONTINUE")
    elseif text then
      -- done
    end
  elseif not _json and string.find(_raw, "[DONE]") then
    -- done
  else
    response:could_not_process(_raw)
    utils.log("Could not process chunk for openai: " .. _raw, vim.log.levels.DEBUG)
  end
end

return Openai
