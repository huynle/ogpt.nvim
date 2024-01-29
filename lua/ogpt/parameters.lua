local pickers = require("telescope.pickers")
local Utils = require("ogpt.utils")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("ogpt.config")

local namespace_id = vim.api.nvim_create_namespace("OGPTNS")

local float_validator = function(min, max)
  return function(value)
    return tonumber(value)
  end
end

local bool_validator = function(min, max)
  return function(value)
    local stringtoboolean = { ["true"] = true, ["false"] = false }
    return stringtoboolean(value)
  end
end

local integer_validator = function(min, max)
  return function(value)
    return tonumber(value)
  end
end

local model_validator = function()
  return function(value)
    return value
  end
end

local function preview_command(entry, bufnr, width)
  vim.api.nvim_buf_call(bufnr, function()
    local preview = Utils.wrapTextToTable(entry.value, width - 5)
    table.insert(preview, 1, "---")
    table.insert(preview, 1, entry.display)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, preview)
  end)
end

local finder = function(opts)
  return setmetatable({
    close = function()
      -- TODO: check if we need to make some cleanup
    end,
  }, {
    __call = function(_, prompt, process_result, process_complete)
      local _params = {
        values = opts.parameters,
      }
      for _, param in ipairs(_params.values) do
        process_result({
          value = param,
          display = param,
          ordinal = param,
          preview_command = preview_command,
        })
      end
      process_complete()
    end,
  })
end

local params_order = {
  "provider",
  "model",
  "embedding_only",
  "f16_kv",
  "frequency_penalty",
  "logits_all",
  "low_vram",
  "main_gpu",
  "max_tokens",
  "mirostat",
  "mirostat_eta",
  "mirostat_tau",
  "num_batch",
  "num_ctx",
  "num_gpu",
  "num_gqa",
  "num_keep",
  "num_predict",
  "num_thread",
  "presence_penalty",
  "repeat_last_n",
  "repeat_penalty",
  "rope_frequency_base",
  "rope_frequency_scale",
  "seed",
  "stop",
  "temperature",
  "tfs_z",
  "top_k",
  "top_p",
  "typical_p",
  "use_mlock",
  "use_mmap",
  "vocab_only",
}
local params_validators = {
  provider = model_validator(),
  model = model_validator(),
  embedding_only = model_validator(),
  f16_kv = model_validator(),
  frequency_penalty = float_validator(),
  mirostat = integer_validator(),
  mirostat_eta = float_validator(),
  mirostat_tau = float_validator(),
  num_batch = integer_validator(),
  num_ctx = integer_validator(),
  num_gpu = integer_validator(),
  num_gqa = integer_validator(),
  num_keep = integer_validator(),
  num_predict = integer_validator(),
  num_thread = integer_validator(),
  presence_penalty = float_validator(),
  repeat_last_n = integer_validator(),
  repeat_penalty = float_validator(),
  seed = integer_validator(),
  stop = model_validator(),
  temperature = float_validator(),
  tfs_z = float_validator(),
  top_k = float_validator(),
  top_p = float_validator(),
  logits_all = bool_validator(),
  vocab_only = bool_validator(),
  use_mmap = bool_validator(),
  use_mlock = bool_validator(),
  low_vram = bool_validator(),
}

local function write_virtual_text(bufnr, ns, line, chunks, mode)
  mode = mode or "extmark"
  if mode == "extmark" then
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text = chunks, virt_text_pos = "overlay" })
  elseif mode == "vt" then
    pcall(vim.api.nvim_buf_set_virtual_text, bufnr, ns, line, chunks, {})
  end
end

function M.select_parameter(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "Select Additional Parameter",
      prompt_prefix = Config.options.popup_input.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "Parameter",
      finder = finder({
        parameters = params_order,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          opts.cb(selection.display, vim.fn.input("value: "))
        end)
        return true
      end,
    })
    :find()
end

M.read_config = function(session)
  if not session then
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    local file = io.open(home .. "/" .. ".ogpt-" .. M.type .. "-params.json", "rb")
    if not file then
      return nil
    end

    local jsonString = file:read("*a")
    file:close()
    return vim.json.decode(jsonString)
  else
    return session.parameters
  end
end

M.write_config = function(config, session)
  if not session then
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    local file, err = io.open(home .. "/" .. ".ogpt-" .. M.type .. "-params.json", "w")
    if file ~= nil then
      local json_string = vim.json.encode(config)
      file:write(json_string)
      file:close()
    else
      vim.notify("Cannot save parameters: " .. err, vim.log.levels.ERROR)
    end
  else
    session.parameters = config
    session:save()
  end
end

M.refresh_panel = function()
  -- write details as virtual text
  local details = {}
  for _, key in pairs(params_order) do
    if M.params[key] ~= nil then
      local display_text = M.params[key]
      if type(display_text) == "table" then
        if display_text.name then
          display_text = display_text.name
        else
          display_text = table.concat(M.params[key], ", ")
        end
      end

      local vt = {
        { Config.options.parameters_window.setting_sign .. key .. ": ", "ErrorMsg" },
        { display_text .. "", "Identifier" },
      }
      table.insert(details, vt)
    end
  end

  vim.api.nvim_buf_clear_namespace(M.panel.bufnr, namespace_id, 0, -1)

  local line = 1
  local empty_lines = {}
  for _ = 1, #details do
    table.insert(empty_lines, "")
  end

  vim.api.nvim_buf_set_option(M.panel.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.panel.bufnr, line - 1, line - 1 + #empty_lines, false, empty_lines)
  vim.api.nvim_buf_set_option(M.panel.bufnr, "modifiable", false)
  for _, d in ipairs(details) do
    M.vts[line - 1] = write_virtual_text(M.panel.bufnr, namespace_id, line - 1, d)
    line = line + 1
  end
end

M.get_parameters_panel = function(type, default_params, session, parent)
  M.type = type
  local custom_params = M.read_config(session or {})

  M.params = vim.tbl_deep_extend("force", {}, default_params, custom_params or {})
  if session then
    M.params = session.parameters
  end

  M.panel = Popup(Config.options.parameters_window)
  M.refresh_panel()

  M.panel:map("n", "d", function()
    local row, _ = unpack(vim.api.nvim_win_get_cursor(M.panel.winid))

    local existing_order = {}
    for _, key in ipairs(params_order) do
      if M.params[key] ~= nil then
        table.insert(existing_order, key)
      end
    end

    local key = existing_order[row]
    M.update_property(key, row, nil, session)
    M.refresh_panel()
  end)

  M.panel:map("n", "a", function()
    local row, _ = unpack(vim.api.nvim_win_get_cursor(M.panel.winid))
    M.select_parameter({
      cb = function(key, value)
        M.update_property(key, row + 1, value, session)
      end,
    })
  end)

  M.panel:map("n", "<Enter>", function()
    local row, _ = unpack(vim.api.nvim_win_get_cursor(M.panel.winid))

    local existing_order = {}
    for _, key in ipairs(params_order) do
      if M.params[key] ~= nil then
        table.insert(existing_order, key)
      end
    end

    local key = existing_order[row]
    if key == "model" then
      local models = require("ogpt.models")
      models.select_model(parent.provider, {
        cb = function(display, value)
          M.update_property(key, row, value, session)
        end,
      })
    elseif key == "provider" then
      local provider = require("ogpt.provider")
      provider.select_provider({
        cb = function(display, value)
          M.update_property(key, row, value, session)
          parent.provider = Config.get_provider(value)
        end,
      })
    else
      local value = M.params[key]
      M.open_edit_property_input(key, value, row, function(new_value)
        M.update_property(key, row, Utils.process_string(new_value), session)
      end)
    end
  end, {})

  return M.panel
end

M.update_property = function(key, row, new_value, session)
  if not key or not new_value then
    M.params[key] = nil
    vim.api.nvim_buf_set_option(M.panel.bufnr, "modifiable", true)
    vim.api.nvim_del_current_line()
    vim.api.nvim_buf_set_option(M.panel.bufnr, "modifiable", false)
  else
    M.params[key] = params_validators[key](new_value)
  end
  M.write_config(M.params, session)
  M.refresh_panel()
end

M.get_panel = function(session, parent)
  return M.get_parameters_panel(" ", session.parameters or {}, session, parent)
end

M.open_edit_property_input = function(key, value, row, cb)
  -- convert table to string first
  if type(value) == "table" then
    value = table.concat(value, ", ")
  end

  local Input = require("nui.input")

  local input = Input({
    relative = {
      type = "win",
      winid = M.panel.winid,
    },
    position = {
      row = row - 1,
      col = 0,
    },
    size = {
      width = 38,
    },
    border = {
      style = "none",
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    prompt = Config.options.popup_input.prompt .. key .. ": ",
    default_value = "" .. value,
    on_submit = cb,
  })

  -- mount/open the component
  input:mount()
end

return M
