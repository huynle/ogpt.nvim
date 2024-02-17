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
              provider:models_url(),
              table.unpack(provider:request_headers()),
            },
            on_exit = vim.schedule_wrap(function(j, exit_code)
              if exit_code ~= 0 then
                vim.notify("An Error Occurred, cannot fetch list of prompts ...", vim.log.levels.ERROR)
                process_complete()
              end

              local response = table.concat(j:result(), "\n")
              local ok, json = pcall(vim.fn.json_decode, response)

              if not ok then
                vim.print(
                  "OGPT ERRPR: something happened when trying request for models from " .. provider.envs.MODELS_URL
                )
                process_complete()
                job_completed = true
              end

              local function process_single_model(model)
                local v = entry_maker(model)
                num_results = num_results + 1
                results[num_results] = v
                process_result(v)
              end

              local _models = {}
              _models = vim.tbl_extend("force", _models, json.models or {})
              _models = vim.tbl_extend("force", _models, Config.get_local_model_definition(provider) or {})

              provider:parse_api_model_response(json, process_single_model)

              -- default processor for a REST response from a curl for models
              for name, properties in pairs(_models) do
                local v = entry_maker({
                  name = name,
                })
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
