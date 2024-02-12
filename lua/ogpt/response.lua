local Object = require("ogpt.common.object")

local Response = Object("Response")

function Response:init(opts)
  self.accumulated_chunks = {}
  self.current_raw_chunk = ""
  self.processed_text = {}
  self.current_text = ""
  self.state = "START"
  self.rest_params = {}
  self.ctx = {}
  self.partial_result_cb = nil
  self.error = nil
  self.in_progress = false
end

function Response:add_raw_chunk(chunk)
  table.insert(self.accumulated_chunks, chunk)
  self.current_raw_chunk = chunk
end

function Response:add_processed_text(text)
  table.insert(self.processed_text, text)
  self.current_text = text
end

function Response:get_total_processed_text()
  return table.concat(self.processed_text, "")
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
