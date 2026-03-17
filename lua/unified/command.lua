local M = {}

-- augroup used for the BufReadPost autocmd registered while Unified is active
local augroup = vim.api.nvim_create_augroup("UnifiedBufApply", { clear = true })

local function detect_filetype(buf, path, lines)
  local ok, ft = pcall(vim.filetype.match, {
    buf = buf,
    filename = path,
    contents = lines,
  })
  if ok and ft and ft ~= "" then
    vim.bo[buf].filetype = ft
    return
  end

  local ext = path:match("%.([^%.]+)$")
  if ext and ext ~= "" then
    vim.bo[buf].filetype = ext
  end
end

-- Open all files changed in `commit_ref`, loaded from git at that commit,
-- and show their diff against the parent commit (commit_ref~1).
local function open_commit(commit_ref)
  local cwd = vim.fn.getcwd()
  local git = require("unified.git")
  local navigation = require("unified.navigation")

  local root_out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = cwd, text = true }):wait()
  if root_out.code ~= 0 then
    vim.api.nvim_echo({ { "Unified: not a git repository", "ErrorMsg" } }, false, {})
    return
  end
  local root = vim.trim(root_out.stdout)

  local files_out = vim.system(
    { "git", "diff-tree", "--no-commit-id", "-r", "--name-only", commit_ref },
    { cwd = root, text = true }
  ):wait()
  if files_out.code ~= 0 then
    vim.api.nvim_echo({ { "Unified: could not list files for " .. commit_ref, "ErrorMsg" } }, false, {})
    return
  end

  local rel_paths = vim.split(vim.trim(files_out.stdout), "\n", { trimempty = true })
  if #rel_paths == 0 then
    vim.api.nvim_echo({ { "Unified: no files changed in " .. commit_ref, "WarningMsg" } }, false, {})
    return
  end

  local parent = commit_ref .. "~1"
  local first_buf = nil

  for _, rel in ipairs(rel_paths) do
    local abs = root .. "/" .. rel

    local content_out = vim.system(
      { "git", "show", commit_ref .. ":" .. rel },
      { cwd = root, text = true }
    ):wait()
    if content_out.code ~= 0 then
      goto continue
    end

    local buf = vim.api.nvim_create_buf(true, false)
    pcall(vim.api.nvim_buf_set_name, buf, abs)

    local lines = vim.split(content_out.stdout, "\n", { plain = true })
    -- git show output ends with \n which produces a trailing empty string
    if lines[#lines] == "" then
      table.remove(lines)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].endofline = true
    vim.bo[buf].modified = false

    detect_filetype(buf, abs, lines)

    git.show_git_diff_against_commit(parent, buf)
    navigation.attach_buffer_keymaps(buf)

    -- After diff is applied lock the buffer
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true

    if not first_buf then
      first_buf = buf
    end

    ::continue::
  end

  if first_buf then
    vim.api.nvim_set_current_buf(first_buf)
  end
end

local function apply_to_buf(buf, commit_ref)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return
  end
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  -- Skip buffers that don't exist on disk (e.g. a commit hash mistaken for a file)
  if vim.fn.filereadable(name) == 0 then
    return
  end
  local git = require("unified.git")
  local auto_refresh = require("unified.auto_refresh")
  local navigation = require("unified.navigation")
  git.show_git_diff_against_commit(commit_ref, buf)
  auto_refresh.setup(buf)
  navigation.attach_buffer_keymaps(buf)
end

M.setup = function()
  vim.api.nvim_create_user_command("Unified", function(opts)
    M.run(opts.args)
  end, {
    nargs = "?",
    complete = function(ArgLead, _, _)
      local suggestions = { "HEAD", "HEAD~1", "HEAD~2", "reset" }
      local out = {}
      for _, s in ipairs(suggestions) do
        if s:sub(1, #ArgLead) == ArgLead then
          table.insert(out, s)
        end
      end
      return out
    end,
    desc = "Show inline git diff. Usage: :Unified [ref]  (default: HEAD)",
  })
end

M.run = function(args)
  if args == "reset" then
    M.reset()
    return
  end

  local commit_ref = (args and args ~= "") and args or nil

  -- If no commit ref was given as a command argument, check the vim arglist
  -- for any item that is not a readable file or directory (treat it as a git ref)
  if not commit_ref then
    for i = 0, vim.fn.argc() - 1 do
      local arg = vim.fn.argv(i)
      if vim.fn.filereadable(arg) == 0 and vim.fn.isdirectory(arg) == 0 then
        commit_ref = arg
        break
      end
    end
  end

  commit_ref = commit_ref or "HEAD"
  local git = require("unified.git")
  local state = require("unified.state")
  local cwd = vim.fn.getcwd()

  git.resolve_commit_hash(commit_ref, cwd, function(hash)
    if not hash then
      vim.api.nvim_echo(
        { { 'Unified: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } },
        false,
        {}
      )
      return
    end

    state.set_active(true)
    state.set_commit_base(commit_ref)

    -- Apply to every buffer that is already loaded
    vim.schedule(function()
      local has_files = false
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if vim.api.nvim_buf_is_loaded(buf) and vim.fn.filereadable(name) == 1 then
          has_files = true
          apply_to_buf(buf, commit_ref)
        end
      end

      -- No real files open: treat commit_ref as a commit to browse
      if not has_files then
        open_commit(commit_ref)
      end
    end)

    -- Apply to buffers opened after this command runs (e.g. switching args)
    vim.api.nvim_clear_autocmds({ group = augroup })
    vim.api.nvim_create_autocmd("BufReadPost", {
      group = augroup,
      callback = function(ev)
        apply_to_buf(ev.buf, commit_ref)
      end,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = augroup,
      callback = function(ev)
        require("unified.diff").disable_listchars(ev.buf)
      end,
    })
  end)
end

function M.reset()
  local config = require("unified.config")
  local diff = require("unified.diff")
  local ns_id = config.ns_id
  local hunk_store = require("unified.hunk_store")
  local navigation = require("unified.navigation")
  local state = require("unified.state")

  -- Clear marks from all loaded buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      vim.fn.sign_unplace("unified_diff", { buffer = buf })
      hunk_store.clear(buf)
      navigation.clear_buffer_keymaps(buf)
      diff.restore_listchars(buf)
    end
  end

  -- Stop applying to new buffers
  vim.api.nvim_clear_autocmds({ group = augroup })

  state.set_active(false)
end

return M
