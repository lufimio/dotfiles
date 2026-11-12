return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["cspell-lsp"] = {
          filetypes = {
            "typst",
            "latex",
            "markdown",
          },
        },
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tinymist = {
          settings = {
            -- We trigger exports ourselves.
            exportPdf = "never",
            outputPath = "$dir/$name",
          },

          keys = {
            {
              "<leader>cp",
              function()
                local client = vim.lsp.get_clients({
                  bufnr = 0,
                  name = "tinymist",
                })[1]

                if not client then
                  vim.notify("Tinymist is not attached", vim.log.levels.ERROR)
                  return
                end

                local typ = vim.api.nvim_buf_get_name(0)
                local pdf = typ:gsub("%.typ$", ".pdf")

                -- Use Tinymist's LSP export command.
                client:exec_cmd({
                  title = "Export Typst PDF",
                  command = "tinymist.exportPdf",
                  arguments = { typ },
                })

                -- Open Zathura if necessary.
                vim.fn.jobstart({ "zathura", pdf }, {
                  detach = true,
                })
              end,
              desc = "Typst preview (on save)",
            },
          },
        },
      },
    },
  },

  -- Automatically export on save.
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.typ",
        callback = function(args)
          local client = vim.lsp.get_clients({
            bufnr = args.buf,
            name = "tinymist",
          })[1]

          if not client then
            return
          end

          local typ = vim.api.nvim_buf_get_name(args.buf)
          local pdf = typ:gsub("%.typ$", ".pdf")

          client:exec_cmd({
            title = "Export Typst PDF",
            command = "tinymist.exportPdf",
            arguments = { typ },
          })
        end,
      })
    end,
  },
}
