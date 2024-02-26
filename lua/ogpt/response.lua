local Object = require("ogpt.common.object")
local utils = require("ogpt.utils")
local async = require("plenary.async.async")
local channel = require("plenary.async.control").channel
local Deque = require("plenary.async.structs").Deque

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
  self.not_processed = Deque.new()
  self.not_processed_raw = Deque.new()
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
  self.not_processed:pushleft(chunk)
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
  local _chunk = self.raw_chunk_rx.recv()
  utils.log("recv'd chunk: " .. _chunk, vim.log.levels.TRACE)

  -- push on to queue
  self.not_processed_raw:pushright(_chunk)

  local chunk = ""
  -- clear the queue each time to try to get a full chunk
  for i, queued_chunk in self.not_processed_raw:ipairs_left() do
    utils.log("Adding to final chunk: " .. queued_chunk, vim.log.levels.TRACE)
    self.not_processed_raw[i] = nil
    chunk = chunk .. queued_chunk
  end

  -- Run different strategies for processsing responses here
  if self.provider.response_params.strategy == self.STRATEGY_CHUNK then
    self.processed_raw_tx.send(chunk)
  elseif
    self.provider.response_params.strategy == self.STRATEGY_LINE_BY_LINE
    or self.provider.response_params.strategy == self.STRATEGY_REGEX
  then
    chunk = _chunk
    local _split_regex = "[^\n]+" -- default regex, for line-by-line strategy
    if self.provider.response_params.strategy == self.STRATEGY_REGEX then
      _split_regex = self.provider.response_params.split_chunk_match_regex or _split_regex
    end

    local success = false
    for line in chunk:gmatch(_split_regex) do
      success = true
      utils.log("Chunk processed using regex: " .. _split_regex, vim.log.levels.DEBUG)
      utils.log("Chunk processed result: " .. line, vim.log.levels.DEBUG)
      self.processed_raw_tx.send(line)
    end

    if not success then
      utils.log(
        "Chunk COULD NOT BE PROCESSED by regex (pushed left on queue): '" .. _split_regex .. "' : " .. chunk,
        vim.log.levels.DEBUG
      )
      self.not_processed_raw:pushleft(chunk)
    end
  else
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
  -- -- pop the next chunk and add anything that is not processs
  -- local _value = self.not_processed
  -- self.not_processed = ""
  -- local _chunk = self.processsed_raw_rx.recv()
  -- utils.log("Got chunk... now appending to 'not_processed'", vim.log.levels.TRACE)
  -- return _value .. _chunk

  local _chunk = self.processsed_raw_rx.recv()
  utils.log("pushing processed raw to queue: " .. _chunk, vim.log.levels.TRACE)

  -- push on to queue
  self.not_processed:pushright(_chunk)
  utils.log("popping processed raw from queue: " .. _chunk, vim.log.levels.TRACE)
  return self.not_processed:popleft()

  -- local chunk = _chunk
  -- -- clear the queue each time to try to get a full chunk
  -- for i, queued_chunk in self.not_processed:ipairs_left() do
  --   chunk = chunk .. queued_chunk
  --   utils.log("Adding to final processed output: " .. chunk, vim.log.levels.TRACE)
  --   self.not_processed[i] = nil
  -- end
  -- return chunk
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
