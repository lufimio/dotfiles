-- [[ Basic Keymaps ]]
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.keymap.set('n', '<A-v>', "<C-V>", { desc = "Visual Block Mode" })
vim.keymap.set({ "i", "n", "v", "s" }, "<C-s>", "<Cmd>w<CR><Esc>", { desc = "Save file" })
vim.keymap.set({ "n", "v", "s" }, "<leader>qq", "<Cmd>wqa<CR>", { desc = "Save and Quit all" })

vim.diagnostic.config {
  update_in_insert = false,
  severity_sort = true,
  float = { border = 'rounded', source = 'if_many' },
  underline = { severity = { min = vim.diagnostic.severity.WARN } },

  virtual_text = true,
  virtual_lines = false,

  jump = {
    on_jump = function(_, bufnr)
      vim.diagnostic.open_float {
        bufnr = bufnr,
        scope = 'cursor',
        focus = false,
      }
    end,
  },
}

vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function() vim.hl.on_yank() end,
})

vim.keymap.set("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
vim.keymap.set({ "x", "o" }, "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
vim.keymap.set("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
vim.keymap.set({ "x", "o" }, "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

vim.keymap.set('n', '<C-d>', '<C-d>zz', { desc = "Move cursor half page down" })
vim.keymap.set('n', '<C-u>', '<C-u>zz', { desc = "Move cursor half page up" })

vim.keymap.set("v", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
vim.keymap.set("v", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })
vim.keymap.set("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
vim.keymap.set("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })

vim.keymap.set('n', 'n', 'nzzzv', { desc = "Next search term" })
vim.keymap.set('n', 'N', 'Nzzzv', { desc = "Previous search term" })

vim.keymap.set('v', '<A-p>', '"_dP', { desc = "Paste without overwrite" })
vim.keymap.set({ 'n', 'v' }, '<leader>p', '"+p', { desc = "Paste from system clipboard" })
vim.keymap.set({ 'n', 'v' }, '<leader>P', '"+P', { desc = "Paste before from system clipboard" })
vim.keymap.set('i', '<C-p>', '<Esc>pa', { desc = "Paste from register" })
vim.keymap.set('i', '<C-P>', '<Esc>"+pa', { desc = "Paste from register" })

vim.keymap.set({ 'n', 'v' }, '<leader>y', '"+y', { desc = "Copy to system clipboard" })
vim.keymap.set('n', '<leader>Y', '"+Y', { desc = "Copy to system clipboard" })

vim.keymap.set({ "n", "v" }, "<A-d>", '"_d', { desc = "Delete to null register" })

vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

vim.keymap.set("n", "<leader>rf", [[:%s///gI<Left><Left><Left>]], { desc = "Replace last find" })
vim.keymap.set("v", "<leader>rf", [[:s///gI<Left><Left><Left>]], { desc = "Replace last find" })

vim.keymap.set("n", "<leader>qe", ":<c-u><c-r><c-r>='let @'. v:register .' = '. string(getreg(v:register))<cr><c-f><left>", { desc = "Edit macro in selected register" })

vim.keymap.set("i", "<A-h>", "<Left>", { desc = "Move left" })
vim.keymap.set("i", "<A-j>", "<Down>", { desc = "Move down" })
vim.keymap.set("i", "<A-k>", "<Up>", { desc = "Move up" })
vim.keymap.set("i", "<A-l>", "<Right>", { desc = "Move right" })
vim.keymap.set("i", "<C-Left>", "<C-o>b", { desc = "Move back 1 word" })
vim.keymap.set("i", "<C-Right>", "<C-o>e", { desc = "Move forward 1 word" })
vim.keymap.set("i", "<C-BS>", "<C-o>db", { desc = "Delete 1 word" })
vim.keymap.set("i", "<C-Del>", "<C-o>dw", { desc = "Delete 1 word after" })

-- vim: ts=2 sts=2 sw=2 et
