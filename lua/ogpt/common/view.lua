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
  self.ui.view = self
  self.bufnr = self.ui.bufnr
  self.winid = nil
end

function View:mount(UI, ...)
  UI.super.mount(self.ui, ...)
  -- syntax and filetype don't always get set in the correct order.
  -- This for syntax to be the last thing to be set.
  if self.ui._.buf_options["syntax"] then
    vim.api.nvim_buf_set_option(self.ui.bufnr, "syntax", self.ui._.buf_options["syntax"])
  end
  self.winid = self.ui.winid
  self.bufnr = self.ui.bufnr
end

function View:update_layout(UI, ...)
  -- ensure layout cannot get updated after the first time, used for setting up
  if not self.init_update or not self.edgy then
    -- self.ui.update_layout(self.ui, ...)
    UI.super.update_layout(self.ui, ...)
    self.init_update = true
  end
  self.winid = self.ui.winid
  self.bufnr = self.ui.bufnr
end

function View:on(...)
  self.ui:on(...)
  self.winid = self.ui.winid
  self.bufnr = self.ui.bufnr
end

function View:unmount(...)
  self.ui:unmount(...)
  self.winid = self.ui.winid
  self.bufnr = self.ui.bufnr
end

function View:map(...)
  self.ui:map(...)
  self.winid = self.ui.winid
  self.bufnr = self.ui.bufnr
end

function View:hide(...)
  self.ui:hide(...)
  self.winid = self.ui.winid
end

function View:show(...)
  self.ui:show(...)
  self.winid = self.ui.winid
end

return View
