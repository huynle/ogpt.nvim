local BaseAction = require("ogpt.flows.actions.base")
local Response = require("ogpt.response")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")
local Layout = require("ogpt.common.layout")
local Popup = require("ogpt.common.popup")
local ChatInput = require("ogpt.input")
local Parameters = require("ogpt.parameters")
local UtilWindow = require("ogpt.util_window")

local EditAction = BaseAction:extend("EditAction")

local STRATEGY_EDIT = "edit"
local STRATEGY_EDIT_CODE = "edit_code"

function EditAction:init(name, opts)
  self.name = name or ""
  opts = opts or {}
  EditAction.super.init(self, opts)
  self.provider = Config.get_provider(opts.provider, self)
  self.params = Config.get_action_params(self.provider, opts.params or {})
  self.system = type(opts.system) == "function" and opts.system() or opts.system or ""
  self.template = type(opts.template) == "function" and opts.template() or opts.template or "{{{input}}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_EDIT
  self.edgy = Config.options.edit.edgy

  self.instructions_input = nil
  self.layout = nil
  self.selection_panel = nil
  self.output_panel = nil
  self.parameters_panel = nil
  self.timer = nil
  self.filetype = vim.api.nvim_buf_get_option(self:get_bufnr(), "filetype")

  self.ui = opts.ui or {}

  self:update_variables()
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
      })
    elseif self.strategy == STRATEGY_EDIT_CODE then
      self:edit_with_instructions({}, { self:get_visual_selection() }, {
        template = self.template,
        variables = self.variables,
        edit_code = true,
        filetype = self:get_filetype(),
      })
    end
  end)
end

function EditAction:on_complete(response)
  -- on the completion, execute this function to extract out codeblocks
  local output_txt = response:get_processed_text()
  local nlcount = utils.count_newlines_at_end(output_txt)
  if self.strategy == STRATEGY_EDIT_CODE then
    output_txt = response:extract_code()
  end
  local output_txt_nlfixed = utils.replace_newlines_at_end(output_txt, nlcount)
  local _output = utils.split_string_by_line(output_txt_nlfixed)
  if self.output_panel.bufnr then
    vim.api.nvim_buf_set_lines(self.output_panel.bufnr, 0, -1, false, _output)
  end
end

function EditAction:edit_with_instructions(output_lines, selection, opts, ...)
  opts = opts or {}
  opts.params = opts.params or self.params
  local api_params = opts.params

  local visual_lines, start_row, start_col, end_row, end_col
  if selection == nil then
    visual_lines, start_row, start_col, end_row, end_col = utils.get_visual_lines(self.bufnr)
  else
    visual_lines, start_row, start_col, end_row, end_col = unpack(selection)
  end

  self.parameters_panel = Parameters({
    type = "edits",
    default_params = vim.tbl_extend("force", api_params, {
      provider = self.provider.name,
      model = self.provider.model,
    }),
    session = nil,
    parent = self,
    edgy = Config.options.edit.edgy,
  })
  self.selection_panel = UtilWindow({
    filetype = "ogpt-selection",
    display = "{{{selection}}}",
    virtual_text = "No selection was made..",
  }, Config.options.chat.edgy)
  self.template_panel = UtilWindow({
    filetype = "ogpt-template",
    display = "Template",
    virtual_text = "Template is not defined.. will use the {{{selection}}}",
    default_text = self.template,
    on_change = function(text)
      self.template = text
    end,
  }, Config.options.chat.edgy)

  self.system_role_panel = UtilWindow({
    filetype = "ogpt-system-window",
    display = "System",
    virtual_text = "Define your LLM system message here...",
    default_text = opts.params.system,
    on_change = function(text)
      self.system = text
    end,
  }, Config.options.chat.edgy)

  self.output_panel = Popup(Config.options.output_window, Config.options.edit.edgy)
  self.instructions_input = ChatInput(Config.options.instruction_window, {
    edgy = Config.options.edit.edgy,
    prompt = Config.options.instruction_window.prompt,
    default_value = opts.instruction or "",
    on_close = function()
      -- if self.spinner:is_running() then
      --   self.spinner:stop()
      -- end
      self:run_spinner(self.instructions_input, false)
      if self.timer ~= nil then
        self.timer:stop()
      end
    end,
    on_submit = vim.schedule_wrap(function(instruction)
      local response = Response(self.provider)
      -- clear input
      vim.api.nvim_buf_set_lines(self.instructions_input.bufnr, 0, -1, false, { "" })
      vim.api.nvim_buf_set_lines(self.output_panel.bufnr, 0, -1, false, { "" })
      -- show_progress()
      self:run_spinner(self.instructions_input, true)

      local input = table.concat(vim.api.nvim_buf_get_lines(self.selection_panel.bufnr, 0, -1, false), "\n")

      -- if instruction is empty, try to get the original instruction from opts
      if instruction == "" then
        instruction = opts.instruction or ""
      end
      local messages = self:build_edit_messages(input, instruction, opts)
      local params = vim.tbl_extend("keep", { messages = messages }, self.parameters_panel.params)

      params.stream = true
      self.provider.api:chat_completions(response, {
        custom_params = params,
        partial_result_fn = function(...)
          self:addAnswerPartial(...)
        end,
      })
    end),
  })

  self.layout = Layout(
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
        Layout.Box(self.selection_panel, { grow = 1 }),
        Layout.Box(self.instructions_input, { size = 3 }),
      }, { dir = "col", grow = 1 }),
      Layout.Box(self.output_panel, { grow = 1 }),
      Layout.Box({
        Layout.Box(self.parameters_panel, { grow = 1 }),
        Layout.Box(self.system_role_panel, { size = 10 }),
        Layout.Box(self.template_panel, { size = 8 }),
      }, { dir = "col", grow = 1 }),
    }, { dir = "row" }),

    Config.options.edit.edgy
  )

  -- accept output window
  for _, window in ipairs({
    self.selection_panel,
    self.output_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
  }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit.keymaps.accept, function()
        self.instructions_input.input_props.on_close()
        local lines = vim.api.nvim_buf_get_lines(self.output_panel.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_text(self.bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
        vim.notify("Successfully applied the change!", vim.log.levels.INFO)
      end, { noremap = true })
    end
  end

  -- use output as input
  for _, window in ipairs({
    self.selection_panel,
    self.output_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
  }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit.keymaps.use_output_as_input, function()
        local lines = vim.api.nvim_buf_get_lines(self.output_panel.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_lines(self.selection_panel.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_lines(self.output_panel.bufnr, 0, -1, false, {})
      end, { noremap = true })
    end
  end

  -- close
  for _, window in ipairs({
    self.selection_panel,
    self.output_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
    self.parameters_panel,
  }) do
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
  local parameters_open = true
  for _, popup in ipairs({
    self.parameters_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
    self.selection_panel,
    self.output_panel,
  }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit.keymaps.toggle_parameters, function()
        if parameters_open then
          self.layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(self.selection_panel, { grow = 1 }),
              Layout.Box(self.instructions_input, { size = 3 }),
            }, { dir = "col", size = "50%" }),
            Layout.Box(self.output_panel, { size = "50%" }),
          }, { dir = "row" }))
          self.parameters_panel:hide()
          vim.api.nvim_set_current_win(self.instructions_input.winid)
        else
          self.layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(self.selection_panel, { grow = 1 }),
              Layout.Box(self.instructions_input, { size = 3 }),
            }, { dir = "col", grow = 1 }),
            Layout.Box(self.output_panel, { grow = 1 }),
            Layout.Box({
              Layout.Box(self.parameters_panel, { grow = 1 }),
              Layout.Box(self.system_role_panel, { size = 10 }),
              Layout.Box(self.template_panel, { size = 8 }),
            }, { dir = "col", grow = 1 }),
          }, { dir = "row" }))
          self.parameters_panel:show()
          self.parameters_panel:mount()
          self.template_panel:show()
          self.template_panel:mount()
          self.system_role_panel:show()
          self.system_role_panel:mount()

          vim.api.nvim_set_current_win(self.parameters_panel.winid)
          vim.api.nvim_buf_set_option(self.parameters_panel.bufnr, "modifiable", false)
          vim.api.nvim_win_set_option(self.parameters_panel.winid, "cursorline", true)
        end
        parameters_open = not parameters_open
        -- set input and output settings
        --  TODO
        for _, window in ipairs({ self.selection_panel, self.output_panel }) do
          vim.api.nvim_buf_set_option(window.bufnr, "syntax", self.filetype)
          vim.api.nvim_win_set_option(window.winid, "number", true)
        end
      end, {})
    end
  end

  -- cycle windows
  local active_panel = self.instructions_input
  for _, popup in ipairs({
    self.selection_panel,
    self.output_panel,
    self.parameters_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
  }) do
    for _, mode in ipairs({ "n", "i" }) do
      if mode == "i" and (popup == self.selection_panel or popup == self.output_panel) then
        goto continue
      end
      popup:map(mode, Config.options.edit.keymaps.cycle_windows, function()
        if active_panel == self.instructions_input then
          vim.api.nvim_set_current_win(self.selection_panel.winid)
          active_panel = self.selection_panel
          vim.api.nvim_command("stopinsert")
        elseif active_panel == self.selection_panel and mode ~= "i" then
          vim.api.nvim_set_current_win(self.output_panel.winid)
          active_panel = self.output_panel
          vim.api.nvim_command("stopinsert")
        elseif active_panel == self.output_panel and mode ~= "i" then
          if parameters_open then
            vim.api.nvim_set_current_win(self.parameters_panel.winid)
            active_panel = self.parameters_panel
          else
            vim.api.nvim_set_current_win(self.instructions_input.winid)
            active_panel = self.instructions_input
          end
        elseif active_panel == self.parameters_panel then
          vim.api.nvim_set_current_win(self.system_role_panel.winid)
          active_panel = self.system_role_panel
        elseif active_panel == self.system_role_panel then
          vim.api.nvim_set_current_win(self.template_panel.winid)
          active_panel = self.template_panel
        elseif active_panel == self.template_panel then
          vim.api.nvim_set_current_win(self.instructions_input.winid)
          active_panel = self.instructions_input
        end
      end, {})
      ::continue::
    end
  end

  -- toggle diff mode
  local diff_mode = Config.options.edit.diff
  for _, popup in ipairs({
    self.parameters_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
    self.output_panel,
    self.selection_panel,
  }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit.keymaps.toggle_diff, function()
        diff_mode = not diff_mode
        for _, winid in ipairs({ self.selection_panel.winid, self.output_panel.winid }) do
          vim.api.nvim_set_current_win(winid)
          if diff_mode then
            vim.api.nvim_command("diffthis")
          else
            vim.api.nvim_command("diffoff")
          end
          vim.api.nvim_set_current_win(self.instructions_input.winid)
        end
      end, {})
    end
  end

  -- set events
  for _, popup in ipairs({
    self.parameters_panel,
    self.instructions_input,
    self.system_role_panel,
    self.template_panel,
    self.output_panel,
    self.selection_panel,
  }) do
    popup:on({ "BufUnload" }, function()
      self:set_loading(false)
    end)
  end

  self.layout:mount()
  -- set input
  if visual_lines then
    vim.api.nvim_buf_set_lines(self.selection_panel.bufnr, 0, -1, false, visual_lines)
  end

  -- set output
  if output_lines then
    vim.api.nvim_buf_set_lines(self.output_panel.bufnr, 0, -1, false, output_lines)
  end

  -- set input and output settings
  for _, window in ipairs({ self.selection_panel, self.output_panel }) do
    vim.api.nvim_buf_set_option(window.bufnr, "syntax", "markdown")
    vim.api.nvim_win_set_option(window.winid, "number", true)
  end
  -- end)
end

function EditAction:build_edit_messages(input, instructions, opts)
  local _input = input

  _input = "```" .. (opts.filetype or "") .. "\n" .. input .. "````"

  local variables = vim.tbl_extend("force", opts.variables, {
    instruction = instructions,
    input = _input,
    filetype = opts.filetype,
  })
  local system_msg = self.system
  local messages = {
    {
      role = "system",
      content = system_msg,
    },
    {
      role = "user",
      content = self:render_template(variables),
    },
  }

  return messages
end

return EditAction
