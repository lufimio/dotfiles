local map = vim.keymap.set
local unmap = vim.keymap.del

unmap("n", "<leader>L")

map("i", "<CR>", "<CR><C-g>u")
map("n", "<C-p>", Snacks.picker.git_files)

map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

map("n", "<A-v>", "<C-V>", { desc = "Visual Block Mode" })

map("v", "<A-p>", '"_dP', { desc = "Paste without overwrite" })
map({ "n", "v" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })
map({ "n", "v" }, "<leader>P", '"+P', { desc = "Paste before from system clipboard" })
map("i", "<C-p>", "<Esc>pa", { desc = "Paste from register" })
map("i", "<C-P>", '<Esc>"+pa', { desc = "Paste from register" })

map({ "n", "v" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
map("n", "<leader>Y", '"+Y', { desc = "Copy to system clipboard" })

map({ "n", "v" }, "<A-d>", '"_d', { desc = "Delete to null register" })

require("config.autosave").setup()
