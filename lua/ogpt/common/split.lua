local NuiSplit = require("nui.split")

Split = NuiSplit:extend("OgptSplit")

function Split:init(options, edgy)
  self.view = nil
  options = options or {}
  self.edgy = false
  self.init_update = false
  if options.edgy and options.border or edgy then
    self.edgy = true
    options.border = nil
  else
    options.buf_options.filetype = nil
  end
  Split.super.init(self, options)
end

function Split:mount(...)
  self.view:mount(Popup, ...)
  -- self.view:mount()
  -- Split.super.mount(self)
  -- -- syntax and filetype don't always get set in the correct order.
  -- -- This for syntax to be the last thing to be set.
  -- if self._.buf_options["syntax"] then
  --   vim.api.nvim_buf_set_option(self.bufnr, "syntax", self._.buf_options["syntax"])
  -- end
end

function Split:update_layout(...)
  -- self.view:update_layout(...)
  self.view:update_layout(Popup, ...)
  -- -- ensure layout cannot get updated after the first time, used for setting up
  -- if not self.init_update or not self.edgy then
  --   Split.super.update_layout(self, ...)
  --   self.init_update = true
  -- end
end

return Split
