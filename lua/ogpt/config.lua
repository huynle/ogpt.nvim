WELCOME_MESSAGE = [[
 
     If you don't ask the right questions,
        you don't get the right answers.
                                      ~ Robert Half
]]

local M = {}
function M.defaults()
  local defaults = {
    api_key_cmd = nil,
    yank_register = "+",
    edit_with_instructions = {
      diff = false,
      keymaps = {
        close = "<C-c>",
        accept = "<C-y>",
        toggle_diff = "<C-d>",
        toggle_parameters = "<C-o>",
        cycle_windows = "<Tab>",
        use_output_as_input = "<C-u>",
      },
    },
    chat = {
      welcome_message = WELCOME_MESSAGE,
      loading_text = "Loading, please wait ...",
      question_sign = "", -- 🙂
      answer_sign = "ﮧ", -- 🤖
      border_left_sign = "|",
      border_right_sign = "|",
      max_line_length = 120,
      sessions_window = {
        active_sign = " 󰄵 ",
        inactive_sign = " 󰄱 ",
        current_line_sign = "",
        border = {
          style = "rounded",
          text = {
            top = " Sessions ",
          },
        },
        win_options = {
          winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
      },
      keymaps = {
        close = { "<C-c>" },
        yank_last = "<C-y>",
        yank_last_code = "<C-k>",
        scroll_up = "<C-u>",
        scroll_down = "<C-d>",
        new_session = "<C-n>",
        cycle_windows = "<Tab>",
        cycle_modes = "<C-f>",
        next_message = "<C-j>",
        prev_message = "<C-k>",
        select_session = "<CR>",
        rename_session = "r",
        delete_session = "d",
        draft_message = "<C-d>",
        edit_message = "e",
        delete_message = "d",
        toggle_parameters = "<C-o>",
        toggle_message_role = "<C-r>",
        toggle_system_role_open = "<C-s>",
        stop_generating = "<C-x>",
      },
    },
    popup_layout = {
      default = "center",
      center = {
        width = "80%",
        height = "80%",
      },
      right = {
        width = "30%",
        width_parameters_open = "50%",
      },
    },
    popup_window = {
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top = " OGPT ",
        },
      },
      win_options = {
        wrap = true,
        linebreak = true,
        foldcolumn = "1",
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
      buf_options = {
        filetype = "markdown",
      },
    },
    system_window = {
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top = " SYSTEM ",
        },
      },
      win_options = {
        wrap = true,
        linebreak = true,
        foldcolumn = "2",
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },
    popup_input = {
      prompt = "  ",
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top_align = "center",
          top = " Prompt ",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
      submit = "<C-Enter>",
      submit_n = "<Enter>",
      max_visible_lines = 20,
    },
    parameters_window = {
      setting_sign = "  ",
      border = {
        style = "rounded",
        text = {
          top = " Parameters ",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },
    preview_window = {
      position = 1,
      size = {
        width = "40%",
        height = 10,
      },
      padding = { 1, 1, 1, 1 },
      enter = true,
      focusable = true,
      zindex = 50,
      border = {
        style = "rounded",
      },
      buf_options = {
        modifiable = false,
        readonly = false,
        filetype = "markdown",
      },
      win_options = {
        wrap = true,
        linebreak = true,
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },

    api_params = {
      model = "mistral:7b",
      temperature = 0.8,
      top_p = 1,
    },
    api_edit_params = {
      model = "mistral:7b",
      frequency_penalty = 0,
      presence_penalty = 0,
      temperature = 0.5,
      top_p = 1,
    },
    actions = {

      code_completion = {
        type = "chat",
        opts = {
          system = [[You are a CoPilot; a tool that uses natural language processing (NLP)
    techniques to generate and complete code based on user input. You help developers write code more quickly and efficiently by
    generating boilerplate code or completing partially written code. Respond with only the resulting code snippet. This means:
    1. Do not include the code context that was given
    2. Only place comments in the code snippets
    ]],
          strategy = "display",
          params = {
            model = "deepseek-coder:6.7b",
          },
        },
      },

      edit_code_with_instructions = {
        type = "chat",
        opts = {
          strategy = "edit_code",
          delay = true,
          extract_codeblock = true,
          params = {
            model = "deepseek-coder:6.7b",
          },
        },
      },

      edit_with_instructions = {
        type = "chat",
        opts = {
          strategy = "edit",
          delay = true,
          params = {
            model = "mistral:7b",
          },
        },
      },
    },
    actions_paths = {},
    show_quickfixes_cmd = "Trouble quickfix",
    predefined_chat_gpt_prompts = "https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv",
  }
  return defaults
end

M.options = {}

M.namespace_id = vim.api.nvim_create_namespace("OGPTNS")

function M.setup(options)
  options = options or {}
  M.options = vim.tbl_deep_extend("force", {}, M.defaults(), options)
end

return M
