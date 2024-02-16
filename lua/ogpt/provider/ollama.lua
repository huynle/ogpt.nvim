local Config = require("ogpt.config")
local utils = require("ogpt.utils")

local M = {}

M.name = "ollama"
M.envs = {}
M.models = {}

function M.load_envs(envs)
  local _envs = {}
  _envs.OLLAMA_API_HOST = Config.options.providers.ollama.api_host
    or os.getenv("OLLAMA_API_HOST")
    or "http://localhost:11434"
  _envs.OLLAMA_API_KEY = Config.options.providers.ollama.api_key or os.getenv("OLLAMA_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/tags")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/generate")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/chat")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OLLAMA_API_KEY or " ")
  M.envs = vim.tbl_extend("force", M.envs, _envs)
  M.envs = vim.tbl_extend("force", M.envs, envs or {})
  return M.envs
end

M.api_parameters = {
  "model",
  "messages",
  "format",
  "options",
  "system",
  "template",
  "stream",
  "raw",
}

M.api_chat_request_options = {
  "num_keep",
  "seed",
  "num_predict",
  "top_k",
  "top_p",
  "tfs_z",
  "typical_p",
  "repeat_last_n",
  "temperature",
  "repeat_penalty",
  "presence_penalty",
  "frequency_penalty",
  "mirostat",
  "mirostat_tau",
  "mirostat_eta",
  "penalize_newline",
  "stop",
  "numa",
  "num_ctx",
  "num_batch",
  "num_gqa",
  "num_gpu",
  "main_gpu",
  "low_vram",
  "f16_kv",
  "logits_all",
  "vocab_only",
  "use_mmap",
  "use_mlock",
  "embedding_only",
  "rope_frequency_base",
  "rope_frequency_scale",
  "num_thread",
}

function M.parse_api_model_response(json, cb)
  -- Given a json object from the api, parse this and get the names of the model to be displayed
  for _, model in ipairs(json.models) do
    cb({
      name = model.name,
    })
  end
end

function M.conform(params)
  -- https://github.com/jmorganca/ollama/blob/main/docs/api.md#show-model-information

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(M.api_parameters, key) then
      if vim.tbl_contains(M.api_chat_request_options, key) then
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
    params.options = _options
  end
  return params
end

function M.process_line(content, ctx, raw_chunks, state, cb)
  local _json = content.json
  local raw = content.raw
  -- given a JSON response from the STREAMING api, processs it
  if _json and _json.done then
    if _json.message then
      -- for stream=false case
      cb(_json.message.content, state, ctx)
      raw_chunks = raw_chunks .. _json.message.content
      state = "CONTINUE"
    else
      ctx.context = _json.context
      cb(raw_chunks, "END", ctx)
    end
  else
    if not vim.tbl_isempty(_json) then
      if _json and _json.message then
        cb(_json.message.content, state, ctx)
        raw_chunks = raw_chunks .. _json.message.content
        state = "CONTINUE"
      end
    end
  end

  return ctx, raw_chunks, state
end

return M
