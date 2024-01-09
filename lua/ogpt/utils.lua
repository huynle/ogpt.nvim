local M = {}

local ESC_FEEDKEY = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)

M.ollama_options = {
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

M.textgenui_options = {
  "seed",
  "top_k",
  "top_p",
  "stop",
}

function M.split(text)
  local t = {}
  for str in string.gmatch(text, "%S+") do
    table.insert(t, str)
  end
  return t
end

function M.split_string_by_line(text)
  local lines = {}
  if text then
    for line in (text .. "\n"):gmatch("(.-)\n") do
      table.insert(lines, line)
    end
  end
  return lines
end

function M.max_line_length(lines)
  local max_length = 0
  for _, line in ipairs(lines) do
    local str_length = string.len(line)
    if str_length > max_length then
      max_length = str_length
    end
  end
  return max_length
end

function M.wrapText(text, maxLineLength)
  local lines = M.wrapTextToTable(text, maxLineLength)
  return table.concat(lines, "\n")
end

function M.trimText(text, maxLength)
  if #text > maxLength then
    return string.sub(text, 1, maxLength - 3) .. "..."
  else
    return text
  end
end

function M.wrapTextToTable(text, maxLineLength)
  local lines = {}

  local textByLines = M.split_string_by_line(text)
  for _, line in ipairs(textByLines) do
    if #line > maxLineLength then
      local tmp_line = ""
      local words = M.split(line)
      for _, word in ipairs(words) do
        if #tmp_line + #word + 1 > maxLineLength then
          table.insert(lines, tmp_line)
          tmp_line = word
        else
          tmp_line = tmp_line .. " " .. word
        end
      end
      table.insert(lines, tmp_line)
    else
      table.insert(lines, line)
    end
  end
  return lines
end

function M.get_visual_lines(bufnr)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
  local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

  -- get whole buffer if there is no current/previous visual selection
  if start_row == 0 then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    start_row = 1
    start_col = 0
    end_row = #lines
    end_col = #lines[#lines]
  end

  -- use 1-based indexing and handle selections made in visual line mode (see :help getpos)
  start_col = start_col + 1
  end_col = math.min(end_col, #lines[#lines] - 1) + 1

  -- shorten first/last line according to start_col/end_col
  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(start_col)

  return lines, start_row, start_col, end_row, end_col
end

function M.count_newlines_at_end(str)
  local start, stop = str:find("\n*$")
  return (stop - start + 1) or 0
end

function M.replace_newlines_at_end(str, num)
  local res = str:gsub("\n*$", string.rep("\n", num), 1)
  return res
end

function M.change_mode_to_normal()
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", false)
end

function M.change_mode_to_insert()
  vim.api.nvim_command("startinsert")
end

function M.calculate_percentage_width(percentage)
  -- Check that the input is a string and ends with a percent sign
  if type(percentage) ~= "string" or not percentage:match("%%$") then
    error("Input must be a string with a percent sign at the end (e.g. '50%').")
  end

  -- Remove the percent sign from the string
  local percent = tonumber(string.sub(percentage, 1, -2))
  local editor_width = vim.api.nvim_get_option("columns")

  -- Calculate the percentage of the width
  local width = math.floor(editor_width * (percent / 100))
  -- Return the calculated width
  return width
end

function M.match_indentation(input, output)
  local input_indent = input:match("\n*([^\n]*)"):match("^(%s*)")
  local output_indent = output:match("\n*([^\n]*)"):match("^(%s*)")
  if input_indent == output_indent then
    return output
  end
  local lines = {}
  for line in output:gmatch("([^\n]*\n?)") do
    if line:match("^%s*$") then
      table.insert(lines, line)
    else
      table.insert(lines, input_indent .. line)
    end
  end
  return table.concat(lines)
end

function M._conform_to_ollama_api(params)
  local ollama_parameters = {
    "model",
    -- "prompt",
    "messages",
    "format",
    "options",
    "system",
    "template",
    -- "context",
    "stream",
    "raw",
  }

  -- https://github.com/jmorganca/ollama/blob/main/docs/api.md#show-model-information

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(ollama_parameters, key) then
      if vim.tbl_contains(M.ollama_options, key) then
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

function M.conform_to_ollama(params)
  if params.messages then
    --   local messages = params.messages
    --   params.messages = nil
    --   params.system = params.system or ""
    --   params.prompt = params.prompt or ""
    --   for _, message in ipairs(messages) do
    --     if message.role == "system" then
    --       params.system = params.system .. "\n" .. message.content .. "\n"
    --     end
    --   end
    --
    --   for _, message in ipairs(messages) do
    --     if message.role == "user" then
    --       params.prompt = params.prompt .. "\n" .. message.content .. "\n"
    --     end
    --   end
  end

  return M._conform_to_ollama_api(params)
end

function M._conform_to_textgenui_api(params)
  local textgenui_options = {
    "seed",
    "top_k",
    "top_p",
    "stop",
  }

  local textgenui_parameters = {
    -- "model",
    "inputs",
    -- "messages",
    -- "format",
    -- "options",
    "parameters",
    -- "system",
    -- "template",
    -- "context",
    "stream",
    -- "raw",
  }

  -- https://github.com/jmorganca/textgenui/blob/main/docs/api.md#show-model-information

  local param_options = {}

  for key, value in pairs(params) do
    if not vim.tbl_contains(textgenui_parameters, key) then
      if vim.tbl_contains(textgenui_options, key) then
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

function M.conform_to_textgenui(params)
  -- conform to mixtral
  -- <s> [INST] Instruction [/INST] Model answer</s> [INST] Follow-up instruction [/INST]
  if params.messages then
    local messages = params.messages
    params.messages = nil
    -- params.system = params.system or ""
    params.inputs = params.inputs or ""
    -- for _, message in ipairs(messages) do
    --   if message.role == "system" then
    --     params.system = params.system .. "\n" .. message.content .. "\n"
    --   end
    -- end

    for _, message in ipairs(messages) do
      if message.role == "user" then
        params.inputs = params.inputs .. "\n" .. message.content .. "\n"
      end
    end
  end

  return M._conform_to_textgenui_api(params)
end

function M.extract_code(text)
  -- Iterate through all code blocks in the message using a regular expression pattern
  local lastCodeBlock
  for codeBlock in text:gmatch("```.-```%s*") do
    lastCodeBlock = codeBlock
  end
  -- If a code block was found, strip the delimiters and return the code
  if lastCodeBlock then
    local index = string.find(lastCodeBlock, "\n")
    if index ~= nil then
      lastCodeBlock = string.sub(lastCodeBlock, index + 1)
    end
    return lastCodeBlock:gsub("```\n", ""):gsub("```", ""):match("^%s*(.-)%s*$")
  end
  return nil
end

function M.write_virtual_text(bufnr, ns, line, chunks, mode)
  mode = mode or "extmark"
  if mode == "extmark" then
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text = chunks, virt_text_pos = "overlay" })
  elseif mode == "vt" then
    pcall(vim.api.nvim_buf_set_virtual_text, bufnr, ns, line, chunks, {})
  end
end

-- Function to convert a nested table to a string
function M.tableToString(tbl, indent)
  indent = indent or 0
  local str = ""
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      str = str .. string.rep("  ", indent) .. k .. ":\n"
      str = str .. M.tableToString(v, indent + 1)
    else
      str = str .. string.rep("  ", indent) .. k .. ": " .. tostring(v) .. "\n"
    end
  end
  return str
end

-- Partial application of arguments using closures
function M.partial(func, ...)
  local capturedArgs = { ... }
  return function(...)
    local args = { unpack(capturedArgs) } -- Captured arguments
    for _, v in ipairs({ ... }) do
      table.insert(args, v) -- Appending new arguments
    end
    return func(unpack(args))
  end
end

function M.is_buf_exists(bufnr)
  return vim.fn.bufexists(bufnr) == 1
end

function M.trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function M.add_partial_completion(opts, text, state)
  local panel = opts.panel
  local progress = opts.progress

  if state == "ERROR" then
    if not opts.on_complete then
      return
    end
    return opts.on_complete(text)
  end

  local start_line = 0
  if state == "END" and text ~= "" then
    if not opts.on_complete then
      return
    end
    return opts.on_complete(text)
  end

  if state == "START" then
    if progress then
      progress(false)
    end
    if M.is_buf_exists(panel.bufnr) then
      vim.api.nvim_buf_set_option(panel.bufnr, "modifiable", true)
    end
    text = M.trim(text)
  end

  if state == "START" or state == "CONTINUE" then
    local lines = vim.split(text, "\n", {})
    local length = #lines
    local buffer = panel.bufnr

    if M.is_buf_exists(panel.bufnr) then
      for i, line in ipairs(lines) do
        local currentLine = vim.api.nvim_buf_get_lines(buffer, -2, -1, false)[1]
        vim.api.nvim_buf_set_lines(buffer, -2, -1, false, { currentLine .. line })
        if i == length and i > 1 then
          vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "" })
        end
      end
    end
  end
end

function M.process_string(inputString)
  -- Check if the inputString contains a comma
  if inputString:find(",") then
    local resultTable = {} -- Initialize an empty table to store split values
    -- Iterate through inputString and split by commas, adding each part to the resultTable
    for word in inputString:gmatch("[^,]+") do
      table.insert(resultTable, word) -- Insert each part into the resultTable
    end
    return resultTable -- Return the resulting table
  else
    return inputString -- If no commas found, return the inputString as it is
  end
end

function M.getSelectedCode(lines)
  local text = table.concat(lines, "\n")
  -- Iterate through all code blocks in the message using a regular expression pattern
  local lastCodeBlock
  for codeBlock in text:gmatch("```.-```%s*") do
    lastCodeBlock = codeBlock
  end
  -- If a code block was found, strip the delimiters and return the code
  if lastCodeBlock then
    local index = string.find(lastCodeBlock, "\n")
    if index ~= nil then
      lastCodeBlock = string.sub(lastCodeBlock, index + 1)
    end
    return lastCodeBlock:gsub("```\n", ""):gsub("```", ""):match("^%s*(.-)%s*$")
  end
  vim.notify("No codeblock found", vim.log.levels.INFO)
  return nil
end

function M.render_template(data, template)
  local result = template
  for key, value in pairs(data) do
    result = result:gsub("{{" .. key .. "}}", M.escape_pattern(value))
  end
  return result
end

function M.escape_pattern(text)
  -- https://stackoverflow.com/a/34953646/4780010
  return text:gsub("([^%w])", "%%%1")
end

function M.update_url_route(url, new_model)
  local host = url:match("https?://([^/]+)")
  local subdomain, domain, tld = host:match("([^.]+)%.([^.]+)%.([^.]+)")
  local _new_url = url:gsub(host, new_model .. "." .. domain .. "." .. tld)
  return _new_url
end

function M.to_model_string(messages)
  local output = ""
  for _, entry in ipairs(messages) do
    if entry.content then
      output = output .. entry.role .. ": " .. entry.content .. "\n\n"
    end
  end
  return output
end

return M
