local Config = require("ogpt.config")
local utils = require("ogpt.utils")
local ProviderBase = require("ogpt.provider.base")

local Openai = ProviderBase:extend("openai")

function Openai:init(opts)
  Openai.super.init(self, opts)
  self.name = "openai"
  self.api_parameters = {
    "model",
    "messages",
    "stream",
    "temperature",
    "presence_penalty",
    "frequency_penalty",
    "top_p",
    "max_tokens",
  }
  self.api_chat_request_options = {}
end

function Openai:load_envs(override)
  local _envs = {}
  _envs.OPENAI_API_HOST = Config.options.providers.openai.api_host
    or os.getenv("OPENAI_API_HOST")
    or "https://api.openai.com"
  _envs.OPENAI_API_KEY = Config.options.providers.openai.api_key or os.getenv("OPENAI_API_KEY") or ""
  _envs.MODELS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/models")
  _envs.COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/completions")
  _envs.CHAT_COMPLETIONS_URL = utils.ensureUrlProtocol(_envs.OPENAI_API_HOST .. "/v1/chat/completions")
  _envs.AUTHORIZATION_HEADER = "Authorization: Bearer " .. (_envs.OPENAI_API_KEY or " ")
  self.envs = vim.tbl_extend("force", _envs, override or {})
  return self.envs
end

function Openai:parse_api_model_response(json, cb)
  local data = json.data or {}
  for _, model in ipairs(data) do
    cb({
      name = model.id,
    })
  end
end

function Openai:conform_request(params)
  -- params = M._conform_messages(params)

  for key, value in pairs(params) do
    if not vim.tbl_contains(self.api_parameters, key) then
      utils.log("Did not process " .. key .. " for " .. self.name)
      params[key] = nil
    end
  end
  return params
end

function Openai:process_raw(response)
  local chunk = response.current_raw_chunk
  -- local state = response.state
  -- local ctx = response.ctx
  -- local raw_chunks = response.processed_text
  -- local params = response.params
  -- local accumulate = response.accumulate_chunks

  local ok, json = pcall(vim.json.decode, chunk)
  -- if ok then
  --   if json.error ~= nil then
  --     local error_msg = {
  --       "OGPT ERROR:",
  --       self.provider.name,
  --       vim.inspect(json.error) or "",
  --       "Something went wrong.",
  --     }
  --     table.insert(error_msg, vim.inspect(params))
  --     -- local error_msg = "OGPT ERROR: " .. (json.error.message or "Something went wrong")
  --     cb(table.concat(error_msg, " "), "ERROR", ctx)
  --     return
  --   end
  --   ctx, raw_chunks, state = self:process_line({ json = json, raw = chunk }, ctx, raw_chunks, state, cb, opts)
  --   return
  -- end

  for line in chunk:gmatch("[^\n]+") do
    local raw_json = string.gsub(line, "^data:", "")
    local _ok, _json = pcall(vim.json.decode, raw_json)
    if _ok then
      self:process_line({ json = _json, raw = line }, response)
    else
      self:process_line({ json = nil, raw = line }, response)
    end
  end
end

function Openai:process_line(content, response)
  local ctx = response.ctx
  -- local total_text = response.processed_text
  local state = response.state
  local cb = response.partial_result_cb
  local _json = content.json
  local _raw = content.raw
  if _json then
    local text_delta = vim.tbl_get(_json, "choices", 1, "delta", "content")
    local text = vim.tbl_get(_json, "choices", 1, "message", "content")
    if text_delta then
      response:add_processed_text(text_delta)
      cb(response, state)
      response:set_state("CONTINUE")
    elseif text then
      response:add_processed_text(text_delta)
      response:set_state("END")
      cb(response)
    end
  elseif not _json and string.find(_raw, "[DONE]") then
    response:set_state("END")
    cb(response, "END")
  else
    utils.log("Something NOT hanndled openai: _json\n" .. vim.inspect(_json))
    utils.log("Something NOT hanndled openai: _raw\n" .. vim.inspect(_raw))
  end

  -- return ctx, total_text, state
end

return Openai
