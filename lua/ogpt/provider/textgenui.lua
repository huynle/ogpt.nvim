local Config = require("ogpt.config")
local utils = require("ogpt.utils")

local ProviderBase = require("ogpt.provider.base")
local Textgenui = ProviderBase:extend("Textgenui")

function Textgenui:init(opts)
  Textgenui.super.init(self, opts)
  self.name = "textgenui"
  self.api_parameters = {
    "inputs",
    "parameters",
    "stream",
  }
  self.api_chat_request_options = {
    "best_of",
    "decoder_input_details",
    "details",
    "do_sample",
    "max_new_tokens",
    "repetition_penalty",
    "return_full_text",
    "seed",
    "stop",
    "temperature",
    "top_k",
    "top_n_tokens",
    "top_p",
    "truncate",
    "typical_p",
    "watermark",
  }
end

function Textgenui:load_envs(override)
  local _envs = {}
  _envs.TEXTGEN_API_HOST = Config.options.providers.textgenui.api_host
    or os.getenv("TEXTGEN_API_HOST")
    or "https://api.textgen.com"
  _envs.TEXTGEN_API_KEY = Config.options.providers.textgenui.api_key or os.getenv("TEXTGEN_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.TEXTGEN_API_HOST .. "/api/tags")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.TEXTGEN_API_HOST)
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.TEXTGEN_API_HOST)
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.TEXTGEN_API_KEY or " ")
  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function Textgenui:conform_request(params)
  params = params or {}

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      if vim.tbl_contains(self.api_chat_request_options, key) then
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

function Textgenui:conform_messages(params)
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

function M:process_line(content, ctx, raw_chunks, state, cb)
  local _json = content.json
  local raw = content.raw
  if _json.token then
    if _json.token.text and string.find(_json.token.text, "</s>") then
      ctx.context = _json.context
      cb(raw_chunks, "END", ctx)
    elseif
      _json.token.text
      and vim.tbl_get(ctx, "tokens", "end_of_result")
      and string.find(_json.token.text, vim.tbl_get(ctx, "tokens", "end_of_result"))
    then
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

return Textgenui
