-- Use the same bindings with either LazyVim picker extra.
local function keys(backend)
  local function pick(telescope, snacks, opts)
    return function()
      opts = vim.deepcopy(opts or {})
      if backend == "telescope" then
        require("telescope.builtin")[telescope](opts)
      else
        opts.ignored = opts.no_ignore
        opts.no_ignore = nil
        Snacks.picker.pick(snacks, opts)
      end
    end
  end

  local function recent(cwd_only)
    return function()
      if backend == "telescope" then
        require("telescope").extensions.frecency.frecency(cwd_only and { workspace = "CWD" } or {})
      else
        Snacks.picker.recent({ filter = { cwd = cwd_only } })
      end
    end
  end

  return {
    { "<leader>fa", pick("find_files", "files", { follow = true, no_ignore = true, hidden = true }), desc = "Find all files in PWD" },
    { "<leader>ff", pick("find_files", "files"), desc = "Find files in PWD" },
    { "<leader>fg", pick("git_files", "git_files"), desc = "Find files in git repository" },
    { "<C-/>", pick("git_files", "git_files"), desc = "Find files in git repository" },
    { "<C-p>", pick("git_files", "git_files"), desc = "Find files in git repository" },
    { "<leader>fw", pick("live_grep", "grep"), desc = "Search for string" },
    { "<leader>?h", pick("help_tags", "help"), desc = "Search help tags" },
    { "<leader>?K", pick("keymaps", "keymaps"), desc = "Search keymaps" },
    { "<leader>fb", pick("buffers", "buffers"), desc = "Find open buffers" },
    { "<leader>f:", pick("commands", "commands"), desc = "Search commands" },
    {
      "<leader>fc",
      pick("find_files", "files", { cwd = vim.fn.stdpath("config"), follow = true, no_ignore = true, hidden = true }),
      desc = "Search Neovim config",
    },
    {
      "<leader>fC",
      pick("find_files", "files", { cwd = vim.fn.expand("~/dotfiles"), follow = true, no_ignore = true, hidden = true }),
      desc = "Search global config",
    },
    { "z=", pick("spell_suggest", "spelling"), desc = "Spell suggestions" },
    { "<leader>fr", recent(true), desc = "Find recent files in PWD" },
    { "<leader>fR", recent(false), desc = "Find recent files" },
  }
end

return {
  {
    "nvim-telescope/telescope.nvim",
    optional = true,
    keys = keys("telescope"),
    dependencies = {
      {
        "nvim-telescope/telescope-frecency.nvim",
        version = "*",
        config = function()
          require("telescope").load_extension("frecency")
        end,
      },
      {
        "nvim-telescope/telescope-ui-select.nvim",
        config = function()
          require("telescope").load_extension("ui-select")
        end,
      },
    },
    opts = function(_, opts)
      opts.extensions = opts.extensions or {}
      opts.extensions["ui-select"] = require("telescope.themes").get_dropdown({})
    end,
  },
  {
    "folke/snacks.nvim",
    keys = function(_, existing)
      if LazyVim.pick.picker and LazyVim.pick.picker.name == "snacks" then
        vim.list_extend(existing, keys("snacks"))
      end
    end,
  },
}
