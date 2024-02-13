local Object = require("ogpt.common.object")
local utils = require("ogpt.utils")
local async = require("plenary.async.async")
local channel = require("plenary.async.control").channel

local Response = Object("Response")

Response.STRATEGY_LINE_BY_LINE = "line"
Response.STRATEGY_CHUNK = "chunk"

function Response:init(provider)
  self.accumulated_chunks = {}
  self.processed_text = {}
  self.rest_params = {}
  self.ctx = {}
  self.partial_result_cb = nil
  self.in_progress = false
  self.strategy = provider.rest_strategy
  self.provider = provider
  self.not_processed = ""
  self.raw_chunk_tx, self.raw_chunk_rx = channel.mpsc()
  self.processed_raw_tx, self.processsed_raw_rx = channel.mpsc()
  self.processed_content_tx, self.processsed_content_rx = channel.mpsc()
end

function Response:set_processed_text(text)
  self.processed_text = text
end

function Response:add_chunk(chunk)
  self.raw_chunk_tx.send(chunk)
end

function Response:could_not_process(chunk)
  self.not_processed = chunk
end

function Response:run_async()
  async.run(function()
    while true do
      self:_process_added_chunk(self.raw_chunk_rx.recv())
    end
  end)

  async.run(function()
    while true do
      self.provider:process_raw(self)
    end
  end)

  async.run(function()
    while true do
      self:render()
      -- self.partial_result_cb(self)
    end
  end)
end

function Response:_process_added_chunk(chunk)
  if self.strategy == self.STRATEGY_LINE_BY_LINE then
    for line in chunk:gmatch("[^\n]+") do
      self.processed_raw_tx.send(line)
    end
  elseif self.strategy == self.STRATEGY_CHUNK then
    self.processed_raw_tx.send(chunk)
  else
    utils.log("did not add chunk: " .. chunk)
  end
end

function Response:pop_content()
  local content = self.processsed_content_rx.recv()
  if content[2] == "END" and (content[1] and content[1] == "") then
    content[1] = self:get_processed_text()
  end
  return content
end

function Response:render()
  self.partial_result_cb(self)
end

function Response:pop_chunk()
  local _value = self.not_processed
  self.not_processed = ""
  return _value .. self.processsed_raw_rx.recv()
end

function Response:get_accumulated_chunks()
  return table.concat(self.accumulated_chunks, "")
end

function Response:add_processed_text(text, state)
  text = text or ""
  if vim.tbl_isempty(self.processed_text) then
    -- remove the first space found in most llm responses
    text = string.gsub(text, "^ ", "")
  end
  table.insert(self.processed_text, text)
  self.processed_content_tx.send({ text, state })
end

function Response:get_processed_text()
  return vim.trim(table.concat(self.processed_text, ""), " ")
end

function Response:get_processed_text_by_lines()
  return vim.split(self:get_processed_text(), "\n")
end

function Response:get_context()
  return self.ctx
end

function Response:set_state(state)
  self.state = state
end

function Response:is_in_progress()
  if self.state ~= "END" then
    return true
  end
  return false
end

return Response
