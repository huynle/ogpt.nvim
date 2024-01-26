local utils = require("ogpt.utils")

local M = {}

M.name = "ollama"

M.envs = {}

function M.load_envs()
  local _envs = {}
  _envs.OLLAMA_API_HOST = M.envs.api_host or os.getenv("OLLAMA_API_HOST") or "http://localhost:11434"
  _envs.OLLAMA_API_KEY = M.envs.api_key or os.getenv("OLLAMA_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/tags")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/generate")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/chat")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OLLAMA_API_KEY or " ")
  M.envs = vim.tbl_extend("force", M.envs, _envs)
  return M.envs
end

M.ollama_options = {
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

function M.process_model(json, cb)
  for _, model in ipairs(json.models) do
    cb({
      name = model.name,
    })
  end
end

function M.conform(params)
  local ollama_parameters = {
    "model",
    "messages",
    "format",
    "options",
    "system",
    "template",
    "stream",
    "raw",
  }

  -- https://github.com/jmorganca/ollama/blob/main/docs/api.md#show-model-information

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(ollama_parameters, key) then
      if vim.tbl_contains(M.ollama_options, key) then
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
