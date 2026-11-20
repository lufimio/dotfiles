local M = {}

local INTERVAL = 30 * 1000 -- 30 seconds
local timer = nil
local saving = false

-- Check whether a buffer is eligible for autosaving.
local function can_save(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if not vim.b[buf].autosave_enabled then
    return false
  end

  if not vim.bo[buf].modified then
    return false
  end

  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return false
  end

  -- Skip terminals, help buffers, prompts, etc.
  if vim.bo[buf].buftype ~= "" then
    return false
  end

  -- Do not automatically name or create unnamed buffers.
  if vim.api.nvim_buf_get_name(buf) == "" then
    return false
  end

  return true
end

-- Save a specific buffer without switching the user's window.
local function save(buf)
  if saving or not can_save(buf) then
    return
  end

  saving = true

  local ok, err = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent update")
    end)
  end)

  saving = false

  if not ok then
    vim.schedule(function()
      vim.notify("Autosave failed: " .. tostring(err), vim.log.levels.WARN, { title = "Autosave" })
    end)
  end
end

-- Save every eligible buffer.
local function save_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    save(buf)
  end
end

-- Determine whether any buffer has autosave enabled.
local function has_enabled_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].autosave_enabled then
      return true
    end
  end

  return false
end

-- Start or stop the periodic timer as needed.
local function update_timer()
  if not timer then
    return
  end

  if has_enabled_buffers() then
    if not timer:is_active() then
      timer:start(
        INTERVAL,
        INTERVAL,
        vim.schedule_wrap(function()
          local mode = vim.api.nvim_get_mode().mode

          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            -- Avoid interrupting typing in the active buffer.
            if buf ~= vim.api.nvim_get_current_buf() or not mode:match("^[iRr]") then
              save(buf)
            end
          end
        end)
      )
    end
  else
    timer:stop()
  end
end

-- Toggle autosave independently for the current buffer.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  local enabled = not vim.b[buf].autosave_enabled

  vim.b[buf].autosave_enabled = enabled

  update_timer()

  vim.notify("Autosave " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO, { title = "Autosave" })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("CustomBufferAutosave", { clear = true })

  timer = vim.uv.new_timer()

  -- Save when changing modes (e.g. Insert -> Normal,
  -- Visual -> Normal, or Normal -> Visual).
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function(args)
      local mode = vim.v.event.new_mode

      if mode == "n" or mode == "v" or mode == "V" or mode == "\22" then
        save(args.buf)
      end
    end,
  })

  -- Save when leaving a buffer or closing its window.
  vim.api.nvim_create_autocmd({
    "BufLeave",
    "BufWinLeave",
  }, {
    group = group,
    callback = function(args)
      save(args.buf)
    end,
  })

  -- Save on focus loss, suspension, and exit.
  vim.api.nvim_create_autocmd({
    "FocusLost",
    "VimSuspend",
    "VimLeavePre",
  }, {
    group = group,
    callback = save_all,
  })

  -- Stop the timer when no enabled buffers remain.
  vim.api.nvim_create_autocmd({
    "BufDelete",
    "BufWipeout",
  }, {
    group = group,
    callback = function()
      vim.schedule(update_timer)
    end,
  })

  -- Clean up the timer when exiting.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
    end,
  })

  vim.keymap.set("n", "<leader>uW", M.toggle, {
    desc = "Toggle Autosave (Buffer)",
    silent = true,
  })
end

return M
