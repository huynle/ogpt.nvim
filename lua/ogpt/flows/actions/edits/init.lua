-- EditAction that can be used for actions of type "chat" in actions.PreviewWindowjson
--
-- This enables the use of mistral:7b in user defined actions,
-- as this model only defines the chat endpoint and has no completions endpoint
--
-- Example action for your local actions.json:
--
--   "turbo-summary": {
--     "type": "chat",
--     "opts": {
--       "template": "Summarize the following text.\n\nText:\n\"\"\"\n{{input}}\n\"\"\"\n\nSummary:",
--       "params": {
--         "model": "mistral:7b"
--       }
--     }
--   }
local classes = require("ogpt.common.classes")
local BaseAction = require("ogpt.flows.actions.base")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local ChatInput = require("ogpt.input")
local Parameters = require("ogpt.parameters")

local EditAction = classes.class(BaseAction)

local STRATEGY_EDIT = "edit"
local STRATEGY_EDIT_CODE = "edit_code"

function EditAction:init(name, opts)
  self.name = name or ""
  opts = opts or {}
  self.super:init(opts)
  self.provider = Config.get_provider(opts.provider, self)
  self.params = Config.get_edit_params(self.provider.name, opts.params or {})
  self.system = type(opts.system) == "function" and opts.system() or opts.system or ""
  self.template = type(opts.template) == "function" and opts.template() or opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_EDIT
  self.ui = opts.ui or {}

  self:post_init()
end

function EditAction:run()
  vim.schedule(function()
    if self.strategy == STRATEGY_EDIT_CODE and self.opts.delay then
      self:edit_with_instructions({}, { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        edit_code = true,
        filetype = self:get_filetype(),
      })
    elseif self.strategy == STRATEGY_EDIT and self.opts.delay then
      self:edit_with_instructions({}, { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        edit_code = false,
      })
    elseif self.strategy == STRATEGY_EDIT then
      self:edit_with_instructions({}, { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        -- params = self:get_params(),
      })
    elseif self.strategy == STRATEGY_EDIT_CODE then
      self:edit_with_instructions({}, { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        -- params = self:get_params(),
        edit_code = true,
        filetype = self:get_filetype(),
      })
    end
  end)
end

local namespace_id = vim.api.nvim_create_namespace("OGPTNS")

local instructions_input, layout, input_window, output_window, output, timer, filetype, bufnr, extmark_id

local display_input_suffix = function(suffix)
  if utils.is_buf_exists(instructions_input.bufnr) then
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
    vim.api.nvim_buf_set_option(window.bufnr, "filetype", "markdown")
    vim.api.nvim_win_set_option(window.winid, "number", true)
  end
end)

function EditAction:edit_with_instructions(output_lines, selection, opts, ...)
  opts = opts or {}
  opts.params = opts.params or self.params
  local api_params = opts.params

  bufnr = self:get_bufnr()

  filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  local visual_lines, start_row, start_col, end_row, end_col
  if selection == nil then
    visual_lines, start_row, start_col, end_row, end_col = utils.get_visual_lines(bufnr)
  else
    visual_lines, start_row, start_col, end_row, end_col = unpack(selection)
  end
  local parameters_panel = Parameters.get_parameters_panel("edits", api_params)
  input_window = Popup(Config.options.popup_window)
  output_window = Popup(Config.options.popup_window)
  instructions_input = ChatInput(Config.options.popup_input, {
    prompt = Config.options.popup_input.prompt,
    default_value = opts.instruction or "",
    on_close = function()
      -- if self.spinner:is_running() then
      --   self.spinner:stop()
      -- end
      self:run_spinner(false)
      if timer ~= nil then
        timer:stop()
      end
    end,
    on_submit = vim.schedule_wrap(function(instruction)
      -- clear input
      vim.api.nvim_buf_set_lines(instructions_input.bufnr, 0, -1, false, { "" })
      vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, { "" })
      -- show_progress()
      self:run_spinner(true)

      local input = table.concat(vim.api.nvim_buf_get_lines(input_window.bufnr, 0, -1, false), "\n")

      -- if instruction is empty, try to get the original instruction from opts
      if instruction == "" then
        instruction = opts.instruction or ""
      end
      local messages = utils.build_edit_messages(input, instruction, opts)
      local params = vim.tbl_extend("keep", { messages = messages }, Parameters.params)
      self.provider.api:edits(
        params,
        utils.partial(utils.add_partial_completion, {
          panel = output_window,
          on_complete = function(response)
            -- on the completion, execute this function to extract out codeblocks
            local nlcount = utils.count_newlines_at_end(response)
            local output_txt = response
            if opts.edit_code then
              local code_response = utils.extract_code(response)
              -- if the chat is to edit code, it will try to extract out the code from response
              output_txt = response
              if code_response then
                output_txt = utils.match_indentation(response, code_response)
              else
                vim.notify("no codeblock detected", vim.log.levels.INFO)
              end
              if response.applied_changes then
                vim.notify(response.applied_changes, vim.log.levels.INFO)
              end
            end
            local output_txt_nlfixed = utils.replace_newlines_at_end(output_txt, nlcount)
            local _output = utils.split_string_by_line(output_txt_nlfixed)
            if output_window.bufnr then
              vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, _output)
            end
          end,
          progress = function(flag)
            self:run_spinner(flag)
          end,
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
      window:map(mode, Config.options.edit.keymaps.accept, function()
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
      window:map(mode, Config.options.edit.keymaps.use_output_as_input, function()
        local lines = vim.api.nvim_buf_get_lines(output_window.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_lines(input_window.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, {})
      end, { noremap = true })
    end
  end

  -- close
  for _, window in ipairs({ input_window, output_window, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit.keymaps.close, function()
        self.spinner:stop()
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
      popup:map(mode, Config.options.edit.keymaps.toggle_parameters, function()
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
      popup:map(mode, Config.options.edit.keymaps.cycle_windows, function()
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
  local diff_mode = Config.options.edit.diff
  for _, popup in ipairs({ parameters_panel, instructions_input, output_window, input_window }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit.keymaps.toggle_diff, function()
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

return EditAction
