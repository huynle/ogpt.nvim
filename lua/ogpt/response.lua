local Object = require("ogpt.common.object")
local utils = require("ogpt.utils")

local Response = Object("Response")

Response.STRATEGY_LINE_BY_LINE = "line"
Response.STRATEGY_CHUNK = "chunk"

function Response:init(strategy)
  self.accumulated_chunks = {}
  self.accumulated_chunks_by_lines = {}
  self.current_raw_chunk = ""
  self.current_raw_chunk_new_line = ""
  self.processed_text = {}
  self.current_text = ""
  self.state = "START"
  self.rest_params = {}
  self.ctx = {}
  self.partial_result_cb = nil
  self.error = nil
  self.in_progress = false
  self.strategy = strategy
  self.not_processed = ""
end

function Response:add_raw_chunk(chunk)
  table.insert(self.accumulated_chunks, chunk)
  self.current_raw_chunk = chunk
  utils.log("adding raw chunk: " .. chunk)
end

function Response:add_raw_chunk_by_line(chunk)
  table.insert(self.accumulated_chunks_by_lines, chunk)
  self.current_raw_chunk_new_line = chunk
  utils.log("adding raw chunk by line: " .. chunk)
end

function Response:set_processed_text(text)
  self.processed_text = text
end

function Response:add_chunk(chunk)
  if self.strategy == self.STRATEGY_LINE_BY_LINE then
    for line in chunk:gmatch("[^\n]+") do
      table.insert(self.accumulated_chunks, line)
      self.current_raw_chunk = line
    end
  elseif self.strategy == self.STRATEGY_CHUNK then
    table.insert(self.accumulated_chunks, chunk)
    self.current_raw_chunk = chunk
  end
end

function Response:get_chunk()
  if self.strategy == self.STRATEGY_LINE_BY_LINE then
    return table.remove(self.accumulated_chunks, 1)
  elseif self.strategy == self.STRATEGY_CHUNK then
    return self.accumulated_chunks
  end
end

function Response:add_processed_text(text)
  text = text
  if vim.tbl_isempty(self.processed_text) then
    -- remove the first space found in most llm responses
    text = string.gsub(text, "^ ", "")
  end
  table.insert(self.processed_text, text)
  self.current_text = text
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
