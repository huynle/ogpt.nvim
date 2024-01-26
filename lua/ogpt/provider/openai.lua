local utils = require("ogpt.utils")

local M = {}

M.name = "openai"

M.envs = {}

function M.load_envs()
  local _envs = {}
  _envs.OPENAI_API_HOST = M.envs.api_host or os.getenv("OPENAI_API_HOST") or "https://api.openai.com"
  _envs.OPENAI_API_KEY = M.envs.api_key or os.getenv("OPENAI_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/models")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/completions")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/chat/completions")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OPENAI_API_KEY or " ")
  M.envs = vim.tbl_extend("force", M.envs, _envs)
  return M.envs
end

M.openai_options = {}

function M.process_model(json, cb)
  local data = json.data or {}
  for _, model in ipairs(data) do
    cb({
      name = model.id,
    })
  end
end

function M.conform(params)
  local openai_parameters = {
    "model",
    "messages",
    "stream",
    "temperature",
  }

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(openai_parameters, key) then
      if vim.tbl_contains(M.openai_options, key) then
        param_options[key] = value
        params[key] = nil
      else
        params[key] = nil
      end
    end
  end
  local _options = vim.tbl_extend("keep", param_options, params.options or {})
  if next(_options) ~= nil then
    params.options = _options
  end
  return params
end

function M.process_line(_json, ctx, raw_chunks, state, cb)
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
