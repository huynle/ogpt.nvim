M = {}

-- write a function to get the content of all the visible window
M.visible_window_content = function()
  -- get the list of all visible windows
  local wins = vim.api.nvim_list_wins()
  wins = vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
  end, wins)

  -- for each of the win in wins, i need to get the buffer and make sure that the list of buffers are unique
  local _buffers = {}
  for _, win in ipairs(wins) do
    -- get the buffer number of the current window
    local bufnr = vim.api.nvim_win_get_buf(win)

    -- check if the buffer is loaded and resolves to a file in the project
    local file = vim.fn.bufname(bufnr)
    if file ~= "" and vim.fn.filereadable(file) == 1 then
      -- add the buffer to the list of unique buffers
      if not vim.tbl_contains(_buffers, bufnr) then
        table.insert(_buffers, bufnr)
      end
    end
  end

  -- initialize an empty string for the final output
  local final_string = ""

  -- iterate over all unique buffers
  for _, bufnr in ipairs(_buffers) do
    -- get the filepath and line number for the current buffer
    local file = vim.fn.bufname(bufnr)

    -- check if the buffer is loaded and resolves to a file in the project
    if file ~= "" and vim.fn.filereadable(file) == 1 then
      -- get the lines in the buffer
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- concatenate the lines with newline characters
      local content = table.concat(lines, "\n")

      -- add the filepath and content to the final output
      local _file_string = table.concat({ content }, "\n")
      final_string = final_string .. _file_string
    end
  end

  -- return the final output
  return final_string
end

M.quickfix_content = function()
  -- get the content of the quickfix list
  local final_string = ""
  -- Get the number of items in the quickfix list
  local qf_items = vim.fn.getqflist() or {}
  for _, item in ipairs(qf_items) do
    -- Get the filepath and line number for the current item
    local _file_string = table.concat({
      -- "# filepath: " .. filepath,
      -- "#content",
      -- "```",
      item.text,
      -- "````",
      -- "",
    }, "\n")
    final_string = final_string .. _file_string
  end
  return final_string
end

M.quickfix_file_content = function()
  --- Gets the content of the vim quickfix list as a single string.
  --
  -- Returns:
  --  string -- The content of all files in the quickfix list, concatenated together.
  local final_string = ""
  -- Get the number of items in the quickfix list
  local qf_items = vim.fn.getqflist() or {}
  local _buffers = {}
  for _, item in pairs(qf_items) do
    table.insert(_buffers, item.bufnr)
  end
  -- ensure that we only get the content of unique files
  _buffers = vim.fn.uniq(_buffers)

  for _, bufnr in ipairs(_buffers) do
    -- Get the filepath and line number for the current item
    local filepath = vim.fn.bufname(bufnr)
    local fp = io.open(filepath, "r")
    local content = fp:read("*all")
    fp:close()
    local _file_string = table.concat({
      -- string.format("# filepath: %s", filepath),
      -- "#content",
      -- "```",
      content,
      -- "```",
      -- "",
    }, "\n")
    final_string = final_string .. _file_string
  end
  return final_string
end

M.before_cursor = function()
  -- get the current line number
  local current_line = vim.fn.line(".")

  -- get the lines before the current line
  local lines_before = vim.api.nvim_buf_get_lines(0, 0, current_line - 1, false)
  return table.concat(lines_before, "\n")
end

M.after_cursor = function()
  -- get the current line number
  local current_line = vim.fn.line(".")
  -- get the lines after the current line
  local lines_after = vim.api.nvim_buf_get_lines(0, current_line, -1, false)
  return table.concat(lines_after, "\n")
end

return M
