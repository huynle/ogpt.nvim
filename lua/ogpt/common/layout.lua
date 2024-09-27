local NuiLayout = require("nui.layout")

Layout = NuiLayout:extend("OgptLayout")

function Layout:init(boxes, options, box, edgy)
  -- Layout.super.init(self, options, box)
  self.boxes = boxes
  self.visible_boxes = {}
  self.edgy = false
  if options.edgy and options.border or edgy then
    self.edgy = true
    for _, _box in ipairs(self.boxes) do
      -- _box.init()
      _box:update_layout({
        relative = "win",
        size = {
          width = 80,
          height = 40,
        },
        position = {
          row = 30,
          col = 20,
        },
      })
      -- _box:show()
    end
  else
    Layout.super.init(self, options, box)
  end
end

function Layout:mount(...)
  if not self.edgy then
    Layout.super.mount(self, ...)
  else
    for _, box in ipairs(self.boxes) do
      if vim.tbl_contains(self.visible_boxes, box) then
        box:mount(...)
      end
    end
  end
end

function Layout:hide(...)
  if not self.edgy then
    Layout.super.hide(self, ...)
  else
    for _, box in ipairs(self.boxes) do
      box:hide(...)
    end
  end
end

function Layout:update(...)
  if not self.edgy then
    Layout.super.update(self, ...)
  end
end

function Layout:show(...)
  if not self.edgy then
    Layout.super.show(self, ...)
  else
    for _, box in ipairs(self.boxes) do
      if vim.tbl_contains(self.visible_boxes, box) then
        box:show(...)
      else
        box:hide(...)
      end
    end
  end
end
return Layout
