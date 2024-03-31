local Object = require("ogpt.common.object")
local Popup = require("ogpt.common.popup")
local Split = require("ogpt.common.split")

local View = Object("View")

function View:init(options, edgy)
  options = options or {}
  self.edgy = false
  self.init_update = false
  if options.edgy and options.border or edgy then
    self.edgy = true
    options.border = nil
    self.ui = Split(options, edgy)
  else
    options.buf_options.filetype = nil
    self.ui = Popup(options, edgy)
  end
  self.bufnr = self.ui.bufnr
end

function View:mount()
  self.ui.mount(self.ui)
  -- syntax and filetype don't always get set in the correct order.
  -- This for syntax to be the last thing to be set.
  if self.ui._.buf_options["syntax"] then
    vim.api.nvim_buf_set_option(self.ui.bufnr, "syntax", self.ui._.buf_options["syntax"])
  end
end

function View:update_layout(...)
  -- ensure layout cannot get updated after the first time, used for setting up
  if not self.init_update or not self.edgy then
    self.ui.update_layout(self.ui, ...)
    self.init_update = true
  end
end

function View:on(...)
  self.ui:on(...)
end

function View:unmount(...)
  self.ui:unmount(...)
end

return View
