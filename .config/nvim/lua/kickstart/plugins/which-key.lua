local function gh(repo) return 'https://github.com/' .. repo end

-- Useful plugin to show you pending keybinds.
vim.pack.add { gh 'folke/which-key.nvim' }
require('which-key').setup {
  -- Delay between pressing a key and opening which-key (milliseconds)
  delay = 0,
  icons = { mappings = vim.g.have_nerd_font },
  -- Document existing key chains
  spec = {
    { '<leader>c', group = 'Code', mode = { 'n', 'x' } },
    { '<leader>d', group = 'Debug' },
    { '<leader>e', group = 'Neotree' },
    { '<leader>f', group = 'Find' },
    { '<leader>r', group = 'Rename' },
    { '<leader>t', group = 'Toggle' },
    { '<leader>x', group = 'Trouble' },
    { '<leader>?', group = 'Help' },
  },
}

-- vim: ts=2 sts=2 sw=2 et
