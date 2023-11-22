local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local job = require("plenary.job")
local Api = require("ogpt.api")

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

local function entry_maker(model)
  return {
    value = model.name,
    display = model.name,
    ordinal = model.digest,
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
        job
          :new({
            command = "curl",
            args = {
              opts.url,
            },
            on_exit = vim.schedule_wrap(function(j, exit_code)
              if exit_code ~= 0 then
                vim.notify("An Error Occurred, cannot fetch list of prompts ...", vim.log.levels.ERROR)
                process_complete()
              end

              local response = table.concat(j:result(), "\n")
              local json = vim.fn.json_decode(response)

              for _, model in ipairs(json.models) do
                local v = entry_maker(model)
                num_results = num_results + 1
                results[num_results] = v
                process_result(v)
              end

              process_complete()
              job_completed = true
            end),
          })
          :start()
      end
    end,
  })
end
--

local M = {}
function M.select_model(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "Select Ollama Model",
      prompt_prefix = Config.options.popup_input.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "Models",
      finder = finder({ url = Api.MODELS_URL }),
      sorter = conf.generic_sorter(opts),
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
