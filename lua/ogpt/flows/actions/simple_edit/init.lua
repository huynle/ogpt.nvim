local classes = require("ogpt.common.classes")
local SimpleWindow = require("ogpt.common.ui.window")
local BaseAction = require("ogpt.flows.actions.base")
local layouts = require("ogpt.flows.actions.edits.layouts")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")
local SimpleParameters = require("ogpt.common.simple_parameters")

local EditAction = classes.class(BaseAction)

local STRATEGY_EDIT = "edit"
local STRATEGY_EDIT_CODE = "edit_code"

function EditAction:init(name, opts)
  self.name = name or ""
  opts = opts or {}
  self.super:init(opts)
  self.provider = Config.get_provider(opts.provider, self)
  self.params = Config.get_action_params(self.provider.name, opts.params or {})
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

local instructions_input, layout, input_window, output_window, output, timer, filetype, bufnr, extmark_id

local setup_and_mount = function(lines, output_lines, ...)
  -- set input
  if lines then
    vim.api.nvim_buf_set_lines(input_window.bufnr, 0, -1, false, lines)
  end

  -- set output
  if output_lines then
    vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, output_lines)
  end

  -- -- set input and output settings
  -- for _, window in ipairs({ input_window, output_window }) do
  --   vim.api.nvim_buf_set_option(window.bufnr, "filetype", "markdown")
  --   vim.api.nvim_win_set_option(window.winid, "number", true)
  -- end
end

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
  local parameters_panel = SimpleParameters.get_parameters_panel("edits", api_params, nil, self)
  input_window = SimpleWindow("ogpt_input", {
    buf = {
      syntax = vim.api.nvim_buf_get_option(0, "filetype"),
    },
  })
  output_window = SimpleWindow("ogpt_output")
  -- instructions_input = ChatInput(Config.options.popup_input, {
  instructions_input = SimpleWindow("ogpt_instruction", {
    keymaps = {
      ["<CR>"] = function()
        local function on_submit(instruction)
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
          local messages = self:build_edit_messages(input, instruction, opts)
          local params = vim.tbl_extend("keep", { messages = messages }, SimpleParameters.params)
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
        end

        local instructions = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
        on_submit = vim.schedule_wrap(on_submit)
        on_submit(table.concat(instructions, "\n"))
      end,
    },
    prompt = Config.options.popup_input.prompt,
    default_value = opts.instruction or "",
    events = {
      {
        events = { "BufUnload" },
        callback = function()
          -- vim.print("turning off spinner")
          self:run_spinner(false)
          if timer ~= nil then
            timer:stop()
          end
        end,
      },
    },
  })

  layout =
    layouts.edit_with_no_layout(layout, self, input_window, instructions_input, output_window, parameters_panel, {
      show_parameters = false,
    })

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
  for _, window in ipairs({ input_window, output_window, instructions_input, parameters_panel }) do
    for _, mode in ipairs({ "n", "i" }) do
      window:map(mode, Config.options.edit.keymaps.close, function()
        self.spinner:stop()
        if vim.fn.mode() == "i" then
          vim.api.nvim_command("stopinsert")
        end
        -- vim.cmd("q")
        input_window:unmount()
        output_window:unmount()
        instructions_input:unmount()
        parameters_panel:unmount()
      end, { noremap = true })
    end
  end

  -- toggle parameters
  local parameters_open = false
  for _, popup in ipairs({ parameters_panel, instructions_input, input_window, output_window }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit.keymaps.toggle_parameters, function()
        if parameters_open then
          layouts.edit_with_no_layout(layout, self, input_window, instructions_input, output_window, parameters_panel, {
            show_parameters = false,
          })
        else
          layouts.edit_with_no_layout(layout, self, input_window, instructions_input, output_window, parameters_panel, {
            show_parameters = true,
          })
          SimpleParameters.refresh_panel()
        end
        parameters_open = not parameters_open
        -- set input and output settings
        --  TODO
        -- for _, window in ipairs({ input_window, output_window }) do
        --   vim.api.nvim_buf_set_option(window.bufnr, "filetype", filetype)
        --   vim.api.nvim_win_set_option(window.winid, "number", true)
        -- end
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

function EditAction:build_edit_messages(input, instructions, opts)
  local _input = input
  if opts.edit_code then
    _input = "```" .. (opts.filetype or "") .. "\n" .. input .. "````"
  else
    _input = "```" .. (opts.filetype or "") .. "\n" .. input .. "````"
  end
  local variables = vim.tbl_extend("force", {}, {
    instruction = instructions,
    input = _input,
    filetype = opts.filetype,
  }, opts.variables)
  local system_msg = opts.params.system or ""
  local messages = {
    {
      role = "system",
      content = system_msg,
    },
    {
      role = "user",
      content = self:render_template(variables, opts.template),
    },
  }

  return messages
end

function EditAction:render_template(variables, template)
  local result = template
  for key, value in pairs(variables) do
    local escaped_value = utils.escape_pattern(value)
    result = string.gsub(result, "{{" .. key .. "}}", escaped_value)
  end
  return result
end

return EditAction
