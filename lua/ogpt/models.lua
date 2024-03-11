local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local job = require("plenary.job")

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
    display = model.display or model.name,
    ordinal = model.digest or model.name,
    preview_command = preview_command,
  }
end

local finder = function(provider, opts)
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
      local function process_single_model(model)
        local v = entry_maker(model)
        num_results = num_results + 1
        results[num_results] = v
        process_result(v)
      end

      if job_completed then
        local current_count = num_results
        for index = 1, current_count do
          if process_result(results[index]) then
            break
          end
        end
        process_complete()
      end

      for model, conf in pairs(provider.models or {}) do
        process_single_model({ name = model })
      end

      if not job_started and provider:models_url() then
        local args = {}
        vim.list_extend(args, { provider:models_url() })
        vim.list_extend(args, provider:request_headers())
        local job_opts = {
          command = "curl",
          args = args,
          on_exit = vim.schedule_wrap(function(j, exit_code)
            if exit_code ~= 0 then
              vim.notify("An Error Occurred, cannot fetch list of prompts ...", vim.log.levels.ERROR)
            else
              provider:parse_api_model_response(j:result(), process_single_model)
            end

            process_complete()
            job_completed = true
          end),
        }

        job_started = true
        job:new(job_opts):start()
      else
        process_complete()
      end
    end,
  })
end
--

local M = {}
function M.select_model(provider, opts)
  opts = opts or {}
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "Select Ollama Model",
      prompt_prefix = Config.options.input_window.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "Models",
      finder = finder(provider),
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
