local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local Response = require("ogpt.response")
local ProviderBase = require("ogpt.provider.base")
local Gemini = ProviderBase:extend("Gemini")

function Gemini:init(opts)
  Gemini.super.init(self, opts)
  self.response_params = {
    strategy = Response.STRATEGY_REGEX,
    -- split_chunk_match_regex = "^%,\n+",
    split_chunk_match_regex = '"text": %"(.-)%"\n',
    -- split_chunk_match_regex = '"text": %"(.-)%"[\n%}]',
    -- split_chunk_match_regex = '"parts": %[[\n%s]+(.-)%]', -- capture everything in the "content.parts" of the response
  }
  self.api_parameters = {
    "contents",
  }
  self.api_chat_request_options = {
    "stopSequences",
    "temperature",
    "topP",
    "topK",
  }
end

function Gemini:load_envs(override)
  local _envs = {}
  _envs.GEMINI_API_KEY = Config.options.providers.gemini.api_key or os.getenv("GEMINI_API_KEY") or ""
  _envs.AUTH = "key=" .. (_envs.GEMINI_API_KEY or " ")
  _envs.MODEL = "gemini-pro"
  _envs.GEMINI_API_HOST = Config.options.providers.gemini.api_host
    or os.getenv("GEMINI_API_HOST")
    or "https://generativelanguage.googleapis.com/v1beta"
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.GEMINI_API_HOST .. "/models")
  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function Gemini:parse_api_model_response(res, cb)
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

function Gemini:completion_url()
  if self.stream_response then
    return utils.ensureUrlProtocol(
      self.envs.GEMINI_API_HOST .. "/models/" .. self.model .. ":streamGenerateContent?" .. self.envs.AUTH
    )
  end
  return utils.ensureUrlProtocol(
    self.envs.GEMINI_API_HOST .. "/models/" .. self.model .. ":generateContent?" .. self.envs.AUTH
  )
end

function Gemini:models_url()
  return utils.ensureUrlProtocol(self.envs.GEMINI_API_HOST .. "/models?" .. self.envs.AUTH)
end

function Gemini:request_headers()
  return {
    "-H",
    "Content-Type: application/json",
  }
end

function Gemini:conform_request(params)
  --https://ai.google.dev/tutorials/rest_quickstart#multi-turn_conversations_chat

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
    params.generationConfig = _options
  end
  return params
end

function Gemini:conform_messages(params)
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

  local messages = params.messages
  local _contents = {}
  for _, content in ipairs(messages) do
    table.insert(_contents, {
      role = content.role == "assistant" and "model" or "user",
      parts = {
        text = utils.gather_text_from_parts(content.content),
      },
    })
  end

  params.messages = nil
  params.contents = _contents
  return params
end

function Gemini:process_response(response)
  local chunk = response:pop_chunk()
  utils.log("Popped processed text: " .. chunk)
  -- response:add_processed_text(chunk, "CONTINUE")

  -- reconstruct a quick json object to properly decode the string
  local ok, json = pcall(vim.json.decode, [[{"text": "]] .. chunk .. [["}]])

  if not ok then
    -- but it back if its not processed
    utils.log("Could not process chunk: " .. chunk)
    response:could_not_process(chunk)
    return
  end

  if type(json) == "string" then
    utils.log("Something is going on, json is a string :" .. vim.inspect(json), vim.log.levels.ERROR)
  else
    local text = vim.tbl_get(json, "text")
    if text then
      response:add_processed_text(text, "CONTINUE")
    else
      utils.log("Mising 'text' from response: " .. vim.inspect(json))
    end
  end
end

return Gemini
