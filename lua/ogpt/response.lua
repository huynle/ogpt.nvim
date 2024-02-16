local Object = require("ogpt.common.object")
local utils = require("ogpt.utils")
local async = require("plenary.async.async")
local channel = require("plenary.async.control").channel

local Response = Object("Response")

Response.STRATEGY_LINE_BY_LINE = "line"
Response.STRATEGY_CHUNK = "chunk"
Response.STRATEGY_REGEX = "regex"
Response.STATE_INIT = "initialized"
Response.STATE_INPROGRESS = "inprogress"
Response.STATE_COMPLETED = "completed"
Response.STATE_ERRORED = "errored"
Response.STATE_STOPPED = "stopped"

function Response:init(provider, events)
  self.events = events or {}
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
  self.response_state = nil
  self.chunk_regex = ""
  self:set_state(self.STATE_INIT)
end

function Response:set_processed_text(text)
  self.processed_text = text
end

function Response:add_chunk(chunk)
  utils.log("Pushed chunk: " .. chunk, vim.log.levels.TRACE)
  self.raw_chunk_tx.send(chunk)
end

function Response:could_not_process(chunk)
  self.not_processed = chunk
end

function Response:run_async()
  async.run(function()
    while true do
      self:_process_added_chunk()
    end
  end)

  async.run(function()
    while true do
      self.provider:process_response(self)
    end
  end)

  async.run(function()
    while true do
      self:render()
    end
  end)
end

function Response:_process_added_chunk()
  local chunk = self.raw_chunk_rx.recv()
  utils.log("recv'd chunk: " .. chunk, vim.log.levels.TRACE)

  if self.provider.response_params.strategy == self.STRATEGY_CHUNK then
    self.processed_raw_tx.send(chunk)
    return
  end
  -- everything regex related below this line
  local _split_regex = "[^\n]+" -- default regex, for line-by-line strategy
  if self.provider.response_params.strategy == self.STRATEGY_REGEX then
    _split_regex = self.provider.response_params.split_chunk_match_regex or _split_regex
  end

  local success = false
  for line in chunk:gmatch(_split_regex) do
    success = true
    utils.log("Chunk processed using regex: " .. _split_regex, vim.log.levels.DEBUG)
    self.processed_raw_tx.send(line)
  end

  if not success then
    utils.log("Chunk COULD NOT BE PROCESSED by regex: '" .. _split_regex .. "' : " .. chunk, vim.log.levels.DEBUG)
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
  utils.log("Try to pop chunk...", vim.log.levels.TRACE)
  -- pop the next chunk and add anything that is not processs
  local _value = self.not_processed
  self.not_processed = ""
  local _chunk = self.processsed_raw_rx.recv()
  utils.log("Got chunk... now appending to 'not_processed'", vim.log.levels.TRACE)
  return _value .. _chunk
end

function Response:get_accumulated_chunks()
  return table.concat(self.accumulated_chunks, "")
end

function Response:add_processed_text(text, flag)
  text = text or ""
  if vim.tbl_isempty(self.processed_text) then
    -- remove the first space found in most llm responses
    text = string.gsub(text, "^ ", "")
  end
  table.insert(self.processed_text, text)
  self.processed_content_tx.send({ text, flag })
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
  self.response_state = state
  self:monitor_state()
end

function Response:monitor_state()
  if self.response_state == self.STATE_INIT then
    utils.log("Response Initialized.", vim.log.levels.DEBUG)
    if self.events.on_start then
      self.events.on_start()
    end
    --
  elseif self.response_state == self.STATE_INPROGRESS then
    utils.log("Response In-progress.", vim.log.levels.DEBUG)
    --
  elseif self.response_state == self.STATE_ERRORED then
    utils.log("Response Errored.", vim.log.levels.DEBUG)
    --
  elseif self.response_state == self.STATE_COMPLETED then
    utils.log("Response Completed.", vim.log.levels.DEBUG)
    self:add_processed_text("", "END")
    self:set_state(self.STATE_INIT)
  elseif self.response_state == self.STATE_STOPPED then
    utils.log("Response Stoped.", vim.log.levels.DEBUG)
    self:add_processed_text("", "END")
    self:set_state(self.STATE_INIT)
  elseif self.response_state then
    utils.log("unknown state: " .. self.response_state, vim.log.levels.ERROR)
  end
end

function Response:extract_code()
  local response_text = self:get_processed_text()
  local code_response = utils.extract_code(response_text)
  -- if the chat is to edit code, it will try to extract out the code from response
  local output_txt = response_text
  if code_response then
    output_txt = utils.match_indentation(response_text, code_response)
  else
    vim.notify("no codeblock detected", vim.log.levels.INFO)
  end
  if response_text.applied_changes then
    vim.notify(response_text.applied_changes, vim.log.levels.INFO)
  end
  return output_txt
end

return Response
