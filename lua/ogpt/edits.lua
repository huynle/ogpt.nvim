local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("ogpt.input")
local Signs = require("ogpt.signs")
local Api = require("ogpt.api")
local Config = require("ogpt.config")
local Utils = require("ogpt.utils")
local Spinner = require("ogpt.spinner")
local Parameters = require("ogpt.parameters")

local build_edit_messages = function(input, instructions, opts)
  local _input = input
  if opts.edit_code then
    _input = "```" .. (opts.filetype or "") .. "\n" .. input .. "````"
  end
  local variables = vim.tbl_extend("force", {}, {
    instruction = instructions,
    input = _input,
    filetype = opts.filetype,
  }, opts.variables)
  local system_msg = opts.params.system or ""

  -- local messages = opts.params.messages or {}
  -- table.insert(messages, {
  --   {
  --     role = "system",
  --     content = system_msg,
  --   },
  --   {
  --     role = "user",
  --     content = _input,
  --   },
  --   {
  --     role = "user",
  --     content = instructions,
  --   },
  -- })

  local messages = {
    {
      role = "system",
      content = system_msg,
    },
    -- {
    --   role = "user",
    --   content = _input,
    -- },
    {
      role = "user",
      content = Utils.render_template(variables, opts.template),
    },
  }

  return messages
end

local namespace_id = vim.api.nvim_create_namespace("OGPTNS")

local instructions_input, layout, input_window, output_window, output, timer, filetype, bufnr, extmark_id

local display_input_suffix = function(suffix)
  if Utils.is_buf_exists(instructions_input.bufnr) then
    if extmark_id then
      vim.api.nvim_buf_del_extmark(instructions_input.bufnr, namespace_id, extmark_id)
    end

    if not suffix then
      return
    end

    extmark_id = vim.api.nvim_buf_set_extmark(instructions_input.bufnr, namespace_id, 0, -1, {
      virt_text = {
        { Config.options.chat.border_left_sign, "OGPTTotalTokensBorder" },
        { "" .. suffix, "OGPTTotalTokens" },
        { Config.options.chat.border_right_sign, "OGPTTotalTokensBorder" },
        { " ", "" },
      },
      virt_text_pos = "right_align",
    })
  end
end

local spinner = Spinner:new(function(state)
  vim.schedule(function()
    output_window.border:set_text("top", " " .. state .. " ", "center")
    display_input_suffix(state)
  end)
end, {
  text = Config.options.loading_text,
})

local show_progress = function()
  spinner:start()
end

local hide_progress = function()
  spinner:stop()
  display_input_suffix()
  if Utils.is_buf_exists(output_window.bufnr) then
    output_window.border:set_text("top", " Result ", "center")
  end
end

local show_process_flag = function(flag)
  if flag then
    show_progress()
  else
    hide_progress()
  end
end

local setup_and_mount = vim.schedule_wrap(function(lines, output_lines, ...)
  layout:mount()
  -- set input
  if lines then
    vim.api.nvim_buf_set_lines(input_window.bufnr, 0, -1, false, lines)
  end

  -- set output
  if output_lines then
    vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, output_lines)
  end

  -- set input and output settings
  for _, window in ipairs({ input_window, output_window }) do
    vim.api.nvim_buf_set_option(window.bufnr, "filetype", filetype)
    vim.api.nvim_win_set_option(window.winid, "number", true)
  end
end)

M.edit_with_instructions = function(output_lines, bufnr, selection, opts, ...)
  opts = opts or {}

  if bufnr == nil then
    bufnr = vim.api.nvim_get_current_buf()
  end
  filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  local visual_lines, start_row, start_col, end_row, end_col
  if selection == nil then
    visual_lines, start_row, start_col, end_row, end_col = Utils.get_visual_lines(bufnr)
  else
    visual_lines, start_row, start_col, end_row, end_col = unpack(selection)
  end
  local api_params = vim.tbl_extend("keep", opts.params or {}, Config.options.api_edit_params)
  local parameters_panel = Parameters.get_parameters_panel("edits", api_params)
  input_window = Popup(Config.options.popup_window)
  output_window = Popup(Config.options.popup_window)
  instructions_input = ChatInput(Config.options.popup_input, {
    prompt = Config.options.popup_input.prompt,
    default_value = opts.instruction or "",
    on_close = function()
      if spinner:is_running() then
        spinner:stop()
      end
      if timer ~= nil then
        timer:stop()
      end
    end,
    on_submit = vim.schedule_wrap(function(instruction)
      -- clear input
      vim.api.nvim_buf_set_lines(instructions_input.bufnr, 0, -1, false, { "" })
      vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, { "" })
      show_progress()

      local input = table.concat(vim.api.nvim_buf_get_lines(input_window.bufnr, 0, -1, false), "\n")

      -- if instruction is empty, try to get the original instruction from opts
      if instruction == "" then
        instruction = opts.instruction or ""
      end
      local messages = build_edit_messages(input, instruction, opts)
      local params = vim.tbl_extend("keep", { messages = messages }, Parameters.params)
      Api.edits(
        params,
        Utils.partial(Utils.add_partial_completion, {
          panel = output_window,
          on_complete = function(response)
            -- on the completion, execute this function to extract out codeblocks
            local nlcount = Utils.count_newlines_at_end(response)
            local output_txt = response
            if opts.edit_code then
              local code_response = Utils.extract_code(response)
              -- if the chat is to edit code, it will try to extract out the code from response
              output_txt = response
              if code_response then
                output_txt = Utils.match_indentation(response, code_response)
              else
                vim.notify("no codeblock detected", vim.log.levels.INFO)
              end
              if response.applied_changes then
                vim.notify(response.applied_changes, vim.log.levels.INFO)
              end
            end
            local output_txt_nlfixed = Utils.replace_newlines_at_end(output_txt, nlcount)
            local _output = Utils.split_string_by_line(output_txt_nlfixed)
            if output_window.bufnr then
              vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, _output)
            end
          end,
          progress = show_process_flag,
        })
      )
    end),
  })

  layout = Layout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = Config.options.popup_layout.center.width,
        height = Config.options.popup_layout.center.height,
      },
    },
    Layout.Box({
      Layout.Box({
        Layout.Box(input_window, { grow = 1 }),
        Layout.Box(instructions_input, { size = 3 }),
      }, { dir = "col", size = "50%" }),
      Layout.Box(output_window, { size = "50%" }),
    }, { dir = "row" })
  )

  -- accept output window
  for _, window in ipairs({ input_window, output_window, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit_with_instructions.keymaps.accept, function()
        instructions_input.input_props.on_close()
        local lines = vim.api.nvim_buf_get_lines(output_window.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
        vim.notify("Successfully applied the change!", vim.log.levels.INFO)
      end, { noremap = true })
    end
  end

  -- use output as input
  for _, window in ipairs({ input_window, output_window, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit_with_instructions.keymaps.use_output_as_input, function()
        local lines = vim.api.nvim_buf_get_lines(output_window.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_lines(input_window.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, {})
      end, { noremap = true })
    end
  end

  -- close
  for _, window in ipairs({ input_window, output_window, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit_with_instructions.keymaps.close, function()
        spinner:stop()
        if vim.fn.mode() == "i" then
          vim.api.nvim_command("stopinsert")
        end
        vim.cmd("q")
      end, { noremap = true })
    end
  end

  -- toggle parameters
  local parameters_open = false
  for _, popup in ipairs({ parameters_panel, instructions_input, input_window, output_window }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_parameters, function()
        if parameters_open then
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(input_window, { grow = 1 }),
              Layout.Box(instructions_input, { size = 3 }),
            }, { dir = "col", size = "50%" }),
            Layout.Box(output_window, { size = "50%" }),
          }, { dir = "row" }))
          parameters_panel:hide()
          vim.api.nvim_set_current_win(instructions_input.winid)
        else
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(input_window, { grow = 1 }),
              Layout.Box(instructions_input, { size = 3 }),
            }, { dir = "col", grow = 1 }),
            Layout.Box(output_window, { grow = 1 }),
            Layout.Box(parameters_panel, { size = 40 }),
          }, { dir = "row" }))
          parameters_panel:show()
          parameters_panel:mount()

          vim.api.nvim_set_current_win(parameters_panel.winid)
          vim.api.nvim_buf_set_option(parameters_panel.bufnr, "modifiable", false)
          vim.api.nvim_win_set_option(parameters_panel.winid, "cursorline", true)
        end
        parameters_open = not parameters_open
        -- set input and output settings
        --  TODO
        for _, window in ipairs({ input_window, output_window }) do
          vim.api.nvim_buf_set_option(window.bufnr, "filetype", filetype)
          vim.api.nvim_win_set_option(window.winid, "number", true)
        end
      end, {})
    end
  end

  -- cycle windows
  local active_panel = instructions_input
  for _, popup in ipairs({ input_window, output_window, parameters_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      if mode == "i" and (popup == input_window or popup == output_window) then
        goto continue
      end
      popup:map(mode, Config.options.edit_with_instructions.keymaps.cycle_windows, function()
        if active_panel == instructions_input then
          vim.api.nvim_set_current_win(input_window.winid)
          active_panel = input_window
          vim.api.nvim_command("stopinsert")
        elseif active_panel == input_window and mode ~= "i" then
          vim.api.nvim_set_current_win(output_window.winid)
          active_panel = output_window
          vim.api.nvim_command("stopinsert")
        elseif active_panel == output_window and mode ~= "i" then
          if parameters_open then
            vim.api.nvim_set_current_win(parameters_panel.winid)
            active_panel = parameters_panel
          else
            vim.api.nvim_set_current_win(instructions_input.winid)
            active_panel = instructions_input
          end
        elseif active_panel == parameters_panel then
          vim.api.nvim_set_current_win(instructions_input.winid)
          active_panel = instructions_input
        end
      end, {})
      ::continue::
    end
  end

  -- toggle diff mode
  local diff_mode = Config.options.edit_with_instructions.diff
  for _, popup in ipairs({ parameters_panel, instructions_input, output_window, input_window }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_diff, function()
        diff_mode = not diff_mode
        for _, winid in ipairs({ input_window.winid, output_window.winid }) do
          vim.api.nvim_set_current_win(winid)
          if diff_mode then
            vim.api.nvim_command("diffthis")
          else
            vim.api.nvim_command("diffoff")
          end
          vim.api.nvim_set_current_win(instructions_input.winid)
        end
      end, {})
    end
  end

  setup_and_mount(visual_lines, output_lines)
end

return M
