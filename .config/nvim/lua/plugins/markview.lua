return {
    {
        "OXY2DEV/markview.nvim",
        lazy = false,
        config = {
            preview = {
                enable_hybrid_mode = true,
                raw_previews = {
                    typst = { "symbols" },
                },
                modes = { "n", "no", "c" },
                hybrid_modes = { "n" },
                linewise_hybrid_mode = true,
            }
        }
    },
    {
        "OXY2DEV/helpview.nvim",
        lazy = false,
    }
}
