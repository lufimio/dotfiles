return {
  "j-morano/buffer_manager.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local buffer_manager = require("buffer_manager")
    buffer_manager.setup({
      select_menu_item_commands = {
        edit = {
          key = "<CR>",
          command = "edit",
        },
      },
      loop_nav = true,
    })

    local bmui = require("buffer_manager.ui")
    vim.keymap.set({ "t", "n" }, "<leader>b", bmui.toggle_quick_menu, { desc = "toggle buffer list" })
    vim.keymap.set({ "t", "n" }, "<A-h>", bmui.nav_prev, { desc = "previous buffer" })
    vim.keymap.set({ "t", "n" }, "<A-l>", bmui.nav_next, { desc = "next buffer" })
  end,
}
