local NuiLayout = require("nui.layout")

Popup = NuiLayout:extend("OgptLayout")

function Popup:init(options, box)
  Popup.super.init(self, options, box)
end

function Popup:mount()
  -- self._.type = ""
  Popup.super.mount(self)
  -- if self._.loading or self._.mounted then
  --   return
  -- end
  --
  -- self._.loading = true
  --
  -- local type = self._.type
  --
  -- if type == "float" then
  --   local info = self._.float
  --
  --   local container = info.container
  --   if is_component(container) and not is_component_mounted(container) then
  --     container:mount()
  --     self:update(get_layout_config_relative_to_component(container))
  --   end
  --
  --   if not self.bufnr then
  --     self.bufnr = vim.api.nvim_create_buf(false, true)
  --     assert(self.bufnr, "failed to create buffer")
  --   end
  --
  --   self:_open_window()
  -- end
  --
  -- self:_process_layout()
  --
  -- if type == "float" then
  --   float_layout.mount_box(self._.box)
  --
  --   apply_workaround_for_float_relative_position_issue_18925(self)
  -- end
  --
  -- if type == "split" then
  --   split_layout.mount_box(self._.box)
  -- end
  --
  -- self._.loading = false
  -- self._.mounted = true
end

return Popup
