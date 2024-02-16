local Popup = require("ogpt.common.popup")
local Config = require("ogpt.config")
local Session = require("ogpt.flows.chat.session")
local Utils = require("ogpt.utils")
local InputWidget = require("ogpt.common.input_widget")

local namespace_id = vim.api.nvim_create_namespace("OGPTNS")

local Sessions = Popup:extend("Sessions")

function Sessions:set_current_line()
  self.current_line, _ = unpack(vim.api.nvim_win_get_cursor(self.winid))
  self:render_list()
end

function Sessions:set_session()
  self.active_line = self.current_line
  local selected = self.sessions[self.current_line]
  local session = Session({ filename = selected.filename })
  self:render_list()
  self.set_session_cb(session)
end

function Sessions:rename_session()
  self.active_line = self.current_line
  local selected = self.sessions[self.current_line]
  local session = Session({ filename = selected.filename })
  local input_widget = InputWidget("New Name:", function(value)
    if value ~= nil and value ~= "" then
      session:rename(value)
      self.sessions = Session.list_sessions()
      self:render_list()
    end
  end)
  input_widget:mount()
end

function Sessions:delete_session()
  local selected = self.sessions[self.current_line]
  if self.active_line ~= self.current_line then
    local session = Session({ filename = selected.filename })
    session:delete()
    self.sessions = Session.list_sessions()
    if self.active_line > self.current_line then
      self.active_line = self.active_line - 1
    end
    self:render_list()
  else
    vim.notify("Cannot remove active session", vim.log.levels.ERROR)
  end
end

function Sessions:render_list()
  vim.api.nvim_buf_clear_namespace(self.bufnr, namespace_id, 0, -1)

  local details = {}
  for i, session in pairs(self.sessions) do
    local icon = i == self.active_line and Config.options.chat.sessions_window.active_sign
      or Config.options.chat.sessions_window.inactive_sign
    local cls = i == self.active_line and "ErrorMsg" or "Comment"
    local name = Utils.trimText(session.name, 30)
    local vt = {
      {
        (self.current_line == i and Config.options.chat.sessions_window.current_line_sign or " ") .. icon .. name,
        cls,
      },
    }
    table.insert(details, vt)
  end

  local line = 1
  local empty_lines = {}
  for _ = 1, #details do
    table.insert(empty_lines, "")
  end

  vim.api.nvim_buf_set_lines(self.bufnr, line - 1, line - 1 + #empty_lines, false, empty_lines)
  for _, d in ipairs(details) do
    self.vts[line - 1] =
      vim.api.nvim_buf_set_extmark(self.bufnr, namespace_id, line - 1, 0, { virt_text = d, virt_text_pos = "overlay" })
    line = line + 1
  end
end

function Sessions:refresh()
  self.sessions = Session.list_sessions()
  self.active_line = 1
  self.current_line = 1
  self:render_list()
end

function Sessions:init(opts)
  Sessions.super.init(self, vim.tbl_extend("force", Config.options.chat.sessions_window, opts), opts.edgy)
  self.vts = {}

  local set_session_cb = opts.set_session_cb
  self.sessions = Session.list_sessions()
  self.active_line = 1
  self.current_line = 1
  self.set_session_cb = set_session_cb
  self:set_keymaps(opts)
  self:render_list()
end

function Sessions:set_keymaps(opts)
  self:map("n", Config.options.chat.keymaps.select_session, function()
    self:set_session()
  end, { noremap = true })

  self:map("n", Config.options.chat.keymaps.rename_session, function()
    self:rename_session()
  end, { noremap = true })

  self:map("n", Config.options.chat.keymaps.delete_session, function()
    self:delete_session()
  end, { noremap = true, silent = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = self.bufnr,
    callback = function()
      self:set_current_line()
    end,
  })
end

return Sessions
