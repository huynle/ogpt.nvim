local Config = require("ogpt.config")
local utils = require("ogpt.utils")

local M = {}

M.name = "openai"

M.envs = {}

function M.load_envs()
  local _envs = {}
  _envs.OPENAI_API_HOST = Config.options.providers.openai.api_host
    or os.getenv("OPENAI_API_HOST")
    or "https://api.openai.com"
  _envs.OPENAI_API_KEY = Config.options.providers.openai.api_key or os.getenv("OPENAI_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/models")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/completions")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/chat/completions")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OPENAI_API_KEY or " ")
  M.envs = vim.tbl_extend("force", M.envs, _envs)
  return M.envs
end

M._api_chat_parameters = {
  "model",
  "messages",
  "stream",
  "temperature",
  "presence_penalty",
  "frequency_penalty",
  "top_p",
  "max_tokens",
}

function M.parse_api_model_response(json, cb)
  local data = json.data or {}
  for _, model in ipairs(data) do
    cb({
      name = model.id,
    })
  end
end

function M.conform(params)
  params = M._conform_messages(params)

  for key, value in pairs(params) do
    if not vim.tbl_contains(M._api_chat_parameters, key) then
      utils.log("Did not process " .. key .. " for " .. M.name)
      params[key] = nil
    end
  end
  return params
end

function M._conform_messages(params)
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

function M.process_line(_json, ctx, raw_chunks, state, cb)
  -- given a JSON response from the STREAMING api, processs it
  if _json and _json.done then
    ctx.context = _json.context
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
    end
  end

  return ctx, raw_chunks, state
end

return M
