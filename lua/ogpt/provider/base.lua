local Object = require("ogpt.common.object")
local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local Response = require("ogpt.response")

local Provider = Object("Provider")

function Provider:init(opts)
  self.name = string.lower(self.class.name)
  opts = vim.tbl_extend("force", Config.options.providers[self.name], opts)
  self.enabled = opts.enabled
  self.model = opts.model
  self.stream_response = true
  self.models = opts.models or {}
  self.api_host = opts.api_host
  self.api_key = opts.api_key
  self.api_params = opts.api_params
  self.api_chat_params = opts.api_chat_params
  self.response_params = {
    strategy = Response.STRATEGY_LINE_BY_LINE,
    split_chunk_match_regex = nil,
    -- split_chunk_match_regex = "[^%,]+", -- use to splitting by commas
    -- split_chunk_match_regex = "[^\n]+", -- use to splitting by newline character
  }
  self.envs = {}
  self.api_parameters = {
    "model",
    "messages",
    "format",
    "options",
    "system",
    "template",
    "stream",
    "raw",
  }

  self.api_chat_request_options = {
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
end

function Provider:load_envs(override)
  local _envs = {}
  _envs.OLLAMA_API_HOST = Config.options.providers.ollama.api_host
    or os.getenv("OLLAMA_API_HOST")
    or "http://localhost:11434"
  _envs.OLLAMA_API_KEY = Config.options.providers.ollama.api_key or os.getenv("OLLAMA_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/tags")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/generate")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OLLAMA_API_HOST .. "/api/chat")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OLLAMA_API_KEY or " ")

  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function Provider:completion_url()
  return self.envs.CHAT_COMPLETIONS_URL
end

function Provider:models_url()
  return self.envs.MODELS_URL
end

function Provider:request_headers()
  return {
    "-H",
    "Content-Type: application/json",
    "-H",
    self.envs.AUTHORIZATION_HEADER,
  }
end

function Provider:parse_api_model_response(res, cb)
  local response = table.concat(res, "\n")
  local ok, json = pcall(vim.fn.json_decode, response)

  if not ok then
    vim.print("OGPT ERROR: something happened when trying request for models from " .. self:models_url())
  else
    -- Given a json object from the api, parse this and get the names of the model to be displayed
    for _, model in ipairs(json.models) do
      cb({
        name = model.name,
      })
    end
  end
end

function Provider:conform_request(params)
  -- https://github.com/jmorganca/ollama/blob/main/docs/api.md#show-model-information

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      if vim.tbl_contains(self.api_chat_request_options, key) then
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

function Provider:conform_messages(params)
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

  -- conform to support text only model
  local messages = params.messages
  local conformed_messages = {}
  for _, message in ipairs(messages) do
    table.insert(conformed_messages, {
      role = message.role,
      content = utils.gather_text_from_parts(message.content),
    })
  end
  params.messages = conformed_messages

  return params
end

function Provider:process_response(response)
  local chunk = response:pop_chunk()
  local ok, json = pcall(vim.json.decode, chunk)

  if not ok then
    utils.log("Cannot process ollama response: \n" .. vim.inspect(chunk))
    json = {}
    response:could_not_process(chunk)
    return
  end

  -- given a JSON response from the STREAMING api, processs it
  if type(json) == "string" then
    utils.log("got something weird. " .. json, vim.log.levels.ERROR)
  elseif vim.tbl_isempty(json) then
    utils.log("got nothing in json.")
  elseif json.done then
    if json.message then
      response:add_processed_text(json.message.content, "CONTINUE")
    end
  elseif json.message then
    response:add_processed_text(json.message.content, "CONTINUE")
  else
    utils.log("unexpected case in ollama", vim.log.levels.ERROR)
  end
end

function Provider:get_action_params(opts)
  return vim.tbl_extend(
    "force",
    { model = self.model }, -- add in model from provider default
    self.api_params, -- override with provider api_params
    opts or {}
  ) -- override with final options
end

function Provider:expand_model(params, ctx)
  params.stream = self.stream_response
  params = self:get_action_params(params)
  ctx = ctx or {}
  local provider_models = self.models
  local _model = params.model

  local _completion_url = self:completion_url()

  local function _expand(name, _m)
    if type(_m) == "table" then
      if _m.modify_url and type(_m.modify_url) == "function" then
        _completion_url = _m.modify_url(_completion_url)
      elseif _m.modify_url then
        _completion_url = _m.modify_url
      else
        params.model = _m.name
        for _, model in ipairs(provider_models) do
          if model.name == _m.name then
            _expand(model)
            break
          end
        end
      end
      params.model = _m or name
    else
      for _name, model in pairs(provider_models) do
        if _name == _m then
          if type(model) == "table" then
            _expand(_name, model)
            break
          elseif type(model) == "string" then
            params.model = model
          end
        end
      end
    end
    return params
  end

  local _full_unfiltered_params = _expand(nil, _model)
  ctx.tokens = _full_unfiltered_params.model.tokens or {}
  -- final force override from the params that are set in the mode itself.
  -- This will enforce specific model params, e.g. max_token, etc
  local final_overrided_applied_params =
    vim.tbl_extend("force", params, vim.tbl_get(_full_unfiltered_params, "model", "params") or {})

  params = self:conform_to_provider_request(final_overrided_applied_params)

  return params, _completion_url, ctx
end

function Provider:conform_to_provider_request(params)
  params = self:get_action_params(params)
  local _model = params.model
  local _conform_messages_fn = _model and _model.conform_messages_fn
  local _conform_request_fn = _model and _model.conform_request_fn

  if _conform_messages_fn then
    params = _conform_messages_fn(self, params)
  else
    params = self:conform_messages(params)
  end

  if _conform_request_fn then
    params = _conform_request_fn(self, params)
  else
    params = self:conform_request(params)
  end

  return params
end

return Provider
