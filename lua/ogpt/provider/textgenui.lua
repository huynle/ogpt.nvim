local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local M = {}

M.name = "textgenui"

M.request_params = {
  "inputs",
  "parameters",
  "stream",
}

M.model_params = {
  "seed",
  "top_k",
  "top_p",
  "top_n_tokens",
  "typical_p",
  "stop",
  "details",
  "max_new_tokens",
  "repetition_penalty",
}

M.envs = {}

function M.load_envs()
  local _envs = {}
  _envs.TEXTGEN_API_HOST = Config.options.providers.textgenui.api_host
    or os.getenv("TEXTGEN_API_HOST")
    or "https://api.textgen.com"
  _envs.TEXTGEN_API_KEY = Config.options.providers.textgenui.api_key or os.getenv("TEXTGEN_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.TEXTGEN_API_HOST .. "/api/tags")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.TEXTGEN_API_HOST)
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.TEXTGEN_API_HOST)
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.TEXTGEN_API_KEY or " ")
  M.envs = vim.tbl_extend("force", M.envs, _envs)
  return M.envs
end

M.textgenui_options = { "seed", "top_k", "top_p", "stop" }

function M.conform(params)
  params = params or {}

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(M.request_params, key) then
      if vim.tbl_contains(M.model_params, key) then
        param_options[key] = value
        params[key] = nil
      else
        params[key] = nil
      end
    end
  end
  local _options = vim.tbl_extend("keep", param_options, params.options or {})
  if next(_options) ~= nil then
    params.parameters = _options
  end
  return params
end

function M.conform_messages(params)
  local messages = params.messages or {}
  -- https://huggingface.co/mistralai/Mixtral-8x7B-Instruct-v0.1
  local tokens = {
    BOS = "<s>",
    EOS = "</s>",
    BOSYS = "<<SYS>>",
    EOSYS = "<</SYS>>",
    INST_START = "[INST]",
    INST_END = "[/INST]",
  }
  local _input = { tokens.BOS }
  for i, message in ipairs(messages) do
    if i < #messages then -- Stop before the last item
      if message.role == "system" then
        table.insert(_input, tokens.BOSYS)
        table.insert(_input, message.content)
        table.insert(_input, tokens.EOSYS)
      elseif message.role == "user" then
        table.insert(_input, tokens.INST_START)
        table.insert(_input, message.content)
        table.insert(_input, tokens.INST_END)
      elseif message.role == "assistant" then
        table.insert(_input, message.content)
      end
    else
      table.insert(_input, tokens.EOS)
      table.insert(_input, tokens.BOS)
      table.insert(_input, tokens.INST_START)
      table.insert(_input, message.content)
      table.insert(_input, tokens.INST_END)
    end
  end
  local final_string = table.concat(_input, " ")
  params.inputs = final_string
  return params
end

function M.process_line(content, ctx, raw_chunks, state, cb)
  local _json = content.json
  local raw = content.raw
  if _json.token then
    if _json.token.text and string.find(_json.token.text, "</s>") then
      ctx.context = _json.context
      cb(raw_chunks, "END", ctx)
    elseif _json.token.generated_text then
      ctx.context = _json.context
      cb(raw_chunks, "END", ctx)
    else
      cb(_json.token.text, state, ctx)
      raw_chunks = raw_chunks .. _json.token.text
      state = "CONTINUE"
    end
  elseif _json.error then
    cb(_json.error, "ERROR", ctx)
  else
    print(_json)
  end
  return ctx, raw_chunks, state
end

return M
