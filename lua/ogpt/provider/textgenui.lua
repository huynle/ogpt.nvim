local utils = require("ogpt.utils")
local M = {}

M.envs = {
  api_host = os.getenv("OGPT_API_HOST"),
  api_key = os.getenv("OGPT_API_KEY"),
}

function M.load_envs()
  local _envs = {}
  _envs.MODELS_URL = utils.ensureUrlProtocol(M.envs.api_host .. "/api/tags")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(M.envs.api_host)
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(M.envs.api_host)
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (M.envs.api_key or " ")
  M.envs = vim.tbl_extend("force", M.envs, _envs)
  return M.envs
end

M.textgenui_options = { "seed", "top_k", "top_p", "stop" }

function M.conform_to_textgenui_api(params)
  local model_params = {
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

  local request_params = {
    "inputs",
    "parameters",
    "stream",
  }

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(request_params, key) then
      if vim.tbl_contains(model_params, key) then
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
function M.update_messages(messages)
  -- https://huggingface.co/mistralai/Mixtral-8x7B-Instruct-v0.1
  local tokens = {
    BOS = "<s>",
    EOS = "</s>",
    INST_START = "[INST]",
    INST_END = "[/INST]",
  }
  local _input = { tokens.BOS }
  for i, message in ipairs(messages) do
    if i < #messages then -- Stop before the last item
      if message.role == "user" then
        table.insert(_input, tokens.INST_START)
        table.insert(_input, message.content)
        table.insert(_input, tokens.INST_END)
      elseif message.role == "system" then
        table.insert(_input, message.content)
        if i == #message - 1 then
          table.insert(_input, tokens.EOS)
        end
      end
    else
      table.insert(_input, tokens.INST_START)
      table.insert(_input, message.content)
      table.insert(_input, tokens.INST_END)
    end
  end
  local final_string = table.concat(_input, " ")
  return final_string
end

function M.conform(params)
  params = params or {}
  params.max_new_tokens = 1024

  params.inputs = M.update_messages(params.messages or {})
  return M.conform_to_textgenui_api(params)
end

function M.process_line(_json, ctx, raw_chunks, state, cb)
  if _json.token then
    if _json.token.text == "</s>" then
      ctx.context = _json.context
      cb(raw_chunks, "END", ctx)
    else
      cb(_json.token.text, state, ctx)
      raw_chunks = raw_chunks .. _json.token.text
      state = "CONTINUE"
    end
  else
    print(_json)
  end
  return ctx, raw_chunks, state
end

return M
