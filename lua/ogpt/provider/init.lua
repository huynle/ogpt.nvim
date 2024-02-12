local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local Utils = require("ogpt.utils")
local Config = require("ogpt.config")

local function preview_command(entry, bufnr, width)
  vim.api.nvim_buf_call(bufnr, function()
    local preview = Utils.wrapTextToTable(entry.value, width - 5)
    table.insert(preview, 1, "---")
    table.insert(preview, 1, entry.display)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, preview)
  end)
end

local function entry_maker(name, provider)
  return {
    value = name,
    display = name,
    ordinal = name,
    preview_command = preview_command,
  }
end

local finder = function(opts)
  local job_started = false
  local job_completed = false
  local results = {}
  local num_results = 0

  return setmetatable({
    close = function()
      -- TODO: check if we need to make some cleanup
    end,
  }, {
    __call = function(_, prompt, process_result, process_complete)
      if job_completed then
        local current_count = num_results
        for index = 1, current_count do
          if process_result(results[index]) then
            break
          end
        end
        process_complete()
      end

      if not job_started then
        job_started = true
        for name, provider in pairs(Config.options.providers) do
          if provider.enabled then
            local v = entry_maker(name)
            num_results = num_results + 1
            results[num_results] = v
            process_result(v)
          end
        end
        process_complete()
        job_completed = true
      end
    end,
  })
end
--

local M = {}
function M.select_provider(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "Select Provider",
      prompt_prefix = Config.options.input_window.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "Providers",
      finder = finder(),
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          opts.cb(selection.display, selection.value)
        end)
        return true
      end,
    })
    :find()
end

return M
