local Config = require("ogpt.config")
local utils = require("ogpt.utils")

local ProviderBase = require("ogpt.provider.base")
local Gemini = ProviderBase:extend("Gemini")

function Gemini:init(opts)
  Gemini.super.init(self, opts)
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

function Gemini:parse_api_model_response(json, cb)
  -- Given a json object from the api, parse this and get the names of the model to be displayed
  for _, model in ipairs(json.models) do
    cb({
      name = model.name,
    })
  end
end

function Gemini:completion_url()
  return utils.ensureUrlProtocol(
    self.envs.GEMINI_API_HOST .. "/models/" .. self.model .. ":streamGenerateContent?" .. self.envs.AUTH
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

  -- -- https://ai.google.dev/tutorials/rest_quickstart#text-only_input
  -- if params.system then
  --   table.insert(params.messages, 1, {
  --     role = "system",
  --     content = params.system,
  --   })
  -- end

  params.messages = nil
  params.contents = _contents
  return params
end

function Gemini:process_raw(content, cb)
  local chunk = content.raw
  local state = content.state
  local raw_chunks = content.content
  local accumulate = content.accumulate

  local ok, json = pcall(vim.json.decode, chunk)
  if not ok then
    -- gemini is missing bracket on returns
    chunk = string.gsub(chunk, "^%[", "")
    chunk = string.gsub(chunk, "^%,", "")
    chunk = string.gsub(chunk, "%]$", "")
    chunk = vim.trim(chunk, "\n")
    chunk = vim.trim(chunk, "\r")
    ok, json = pcall(vim.json.decode, chunk)
  end

  if ok then
    return self:process_line({ json = json, raw = accumulate }, ctx, raw_chunks, state, cb)
  else
    -- if not ok, try to keep process the accumulated stdout
    ok, json = pcall(vim.json.decode, table.concat(accumulate, ""))
    if ok then
      return self:process_line({ json = json, raw = accumulate }, ctx, raw_chunks, state, cb)
    end
  end
end

function Gemini:process_line(content, ctx, raw_chunks, state, cb)
  local _json = content.json or {}
  local raw = content.raw

  if type(_json) == "string" then
    utils.log("Something is going on, _json is a string, expecing a table..", vim.log.levels.ERROR)
  elseif vim.tbl_isempty(_json) then
    if raw == "]" then
      cb(raw_chunks, "END", ctx)
    else
      cb("Could not process the following raw chunk:\n" .. raw, "ERROR", ctx)
    end
  elseif _json then
    local text = vim.tbl_get(_json, "candidates", 1, "content", "parts", 1, "text")
    if text then
      cb(text, state)
      raw_chunks = raw_chunks .. text
      state = "CONTINUE"
    else
      local total_text = {}
      for _, part in ipairs(_json) do
        text = vim.tbl_get(part, "candidates", 1, "content", "parts", 1, "text")
        if text then
          table.insert(total_text, text)
        end
      end
      cb(table.concat(total_text, ""), "END")
    end
  end

  return ctx, raw_chunks, state
end

return Gemini
