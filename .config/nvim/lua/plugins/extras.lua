return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<C-i>",
        function()
          Snacks.image.hover()
        end,
        desc = "Preview image",
      },
    },
    opts = {
      image = {
        enabled = true,
        doc = {
          enabled = false,
        },
        math = {
          enabled = true,
        },
      },
    },
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = true,
  },

  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      sync_root_with_cwd = true,
    },
  },
}
