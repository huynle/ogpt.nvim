local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local ProviderBase = require("ogpt.provider.base")
local Response = require("ogpt.response")
local OpenRouter = ProviderBase:extend("openrouter")

function OpenRouter:init(opts)
  OpenRouter.super.init(self, opts)
  self.name = "openrouter"
  self.api_parameters = {
    "messages",
    "model",

    "stop",
    "stream",

    "max_tokens",
    "temperature",
    "top_p",
    "top_k",
    "frequency_penalty",
    "presence_penalty",
    "repetition_penalty",
    "seed",
  }
  self.api_chat_request_options = {}
end

function OpenRouter:load_envs(override)
  local _envs = {}
  _envs.OPENROUTER_API_HOST = Config.options.providers.openrouter.api_host
  _envs.OPENROUTER_API_KEY = Config.options.providers.openrouter.api_key
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OPENROUTER_API_HOST .. "/v1/models")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENROUTER_API_HOST .. "/v1/completions")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENROUTER_API_HOST .. "/v1/chat/completions")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OPENROUTER_API_KEY or " ")
  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function OpenRouter:parse_api_model_response(res, cb)
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

function OpenRouter:conform_request(params)
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

  -- conform to support text only model
  local messages = params.messages
  local conformed_messages = {}
  for _, message in ipairs(messages) do
    table.insert(conformed_messages, {
      role = message.role,
      content = utils.gather_text_from_parts(message.content),
    })
  end

  -- Insert the updated params.system string at the beginning of conformed_messages
  if params.system then
    table.insert(conformed_messages, 1, {
      role = "system",
      content = params.system,
    })
  end

  params.messages = conformed_messages

  -- general clean up, remove things that shouldnt be here
  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      utils.log("Did not process " .. key .. " for " .. self.name)
      params[key] = nil
    end
  end

  return params
end

function OpenRouter:process_response(response)
  local chunk = response:pop_chunk()
  local raw_json = string.gsub(chunk, "^data:", "")
  local _ok, _json = pcall(vim.json.decode, raw_json)
  if _ok then
    self:_process_line({ json = _json, raw = chunk }, response)
  else
    self:_process_line({ json = nil, raw = chunk }, response)
  end
end

function OpenRouter:_process_line(content, response)
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
    utils.log("Could not process chunk for openrouter: " .. _raw, vim.log.levels.DEBUG)
  end
end

return OpenRouter
