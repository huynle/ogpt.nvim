WELCOME_MESSAGE = [[
 
     If you don't ask the right questions,
        you don't get the right answers.
                                      ~ Robert Half
]]

local M = {}
function M.defaults()
  local defaults = {
    debug = false,
    api_key_cmd = nil,
    default_provider = {
      -- can also support `textgenui`, 'openai'
      name = "ollama",
      api_host = nil,
      api_key = nil,
      model = "mistral:7b",
    },
    yank_register = "+",
    edit_with_instructions = {
      diff = false,
      keymaps = {
        close = "<C-c>",
        accept = "<C-y>", -- accept the output and write to original buffer
        toggle_diff = "<C-d>", -- view the diff between left and right panes and use diff-mode
        toggle_parameters = "<C-o>", -- Toggle parameters window
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
          top = " Instruction ",
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
        -- text = {
        --   top = "",
        -- },
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
      keymaps = {
        close = { "<C-c>", "q" },
        accept = "<C-CR>",
        append = "a",
        prepend = "p",
        yank_code = "c",
        yank_to_register = "y",
      },
    },

    api_params = {
      -- takes a string or a table
      model = nil,
      -- model = {
      --   -- create a modify url specifically for mixtral to run
      --   name = "mixtral-8-7b",
      --   modify_url = function(url)
      --     -- given a URL, this function modifies the URL specifically to the model
      --     -- This is useful when you have different models hosted on different subdomains like
      --     -- https://model1.yourdomain.com/
      --     -- https://model2.yourdomain.com/
      --     local new_model = "mixtral-8-7b"
      --     local host = url:match("https?://([^/]+)")
      --     local subdomain, domain, tld = host:match("([^.]+)%.([^.]+)%.([^.]+)")
      --     local _new_url = url:gsub(host, new_model .. "." .. domain .. "." .. tld)
      --     return _new_url
      --   end,
      --   conform_fn = function(params)
      --     -- Different models might have different instruction format
      --     -- for example, Mixtral operates on `<s> [INST] Instruction [/INST] Model answer</s> [INST] Follow-up instruction [/INST] `
      --   end,
      -- },

      temperature = 0.8,
      top_p = 0.99,
    },
    api_edit_params = {
      -- used for `edit` and `edit_code` strategy in the actions
      model = nil,
      frequency_penalty = 0,
      presence_penalty = 0,
      temperature = 0.5,
      top_p = 0.99,
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

      -- all strategy "edit" have instruction as input
      edit_code_with_instructions = {
        type = "chat",
        opts = {
          strategy = "edit_code",
          template = "Given the follow code snippet, {{instruction}}.\n\nCode:\n```{{filetype}}\n{{input}}\n```",
          delay = true,
          extract_codeblock = true,
          params = {
            model = "deepseek-coder:6.7b",
          },
        },
      },

      -- all strategy "edit" have instruction as input
      edit_with_instructions = {
        type = "chat",
        opts = {
          strategy = "edit",
          template = "Given the follow snippet, {{instruction}}.\n\nSnippet:\n```{{filetype}}\n{{input}}\n```",
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
  local _complete_replace = {
    "actions",
  }

  -- allow to use a default provider model
  M.options.api_params.model = M.options.api_params.model or M.options.default_provider.model
  M.options.api_edit_params.model = M.options.api_edit_params.model or M.options.default_provider.model

  for _, to_replace in pairs(_complete_replace) do
    for key, item in pairs(options[to_replace]) do
      M.options[to_replace][key] = item
    end
  end
end

return M
