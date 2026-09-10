-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

vim.pack.add {
  { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '3' },
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/nvim-tree/nvim-web-devicons',
  'https://github.com/MunifTanjim/nui.nvim',
  'https://github.com/3rd/image.nvim',
}

vim.keymap.set('n', '<leader>et', '<Cmd>Neotree toggle<CR>', { desc = 'Show filetree explorer', silent = true })

require('neo-tree').setup {
  filesystem = {
    hijack_netrw_behavior = 'open_current',
    window = {
      mappings = {
        ['<C-e>'] = 'close_window',
      },
    },
  },
}

vim.api.nvim_create_autocmd('BufEnter', {
  group = vim.api.nvim_create_augroup('NeoTreeInit', { clear = true }),
  callback = function()
    local f = vim.fn.expand '%:p'
    if vim.fn.isdirectory(f) ~= 0 then
      vim.cmd('Neotree current dir=' .. f)
      vim.api.nvim_clear_autocmds { group = 'NeoTreeInit' }
    end
  end,
})
