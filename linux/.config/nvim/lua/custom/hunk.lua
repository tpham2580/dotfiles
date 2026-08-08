-- custom/hunk.lua — git diff review from Neovim, backed by the hunk TUI.
-- Replaces diffview.nvim.
--
-- hunk is a terminal program, so each review opens in a :terminal buffer in its
-- own tab. Quitting hunk closes the tab and returns you to the previous layout.

local M = {}

local function git_root()
  local out = vim.fn.systemlist { 'git', 'rev-parse', '--show-toplevel' }
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then
    return nil
  end
  return out[1]
end

---Run `hunk <args>` in a terminal tab rooted at the repo top level.
---@param args string
function M.open(args)
  if vim.fn.executable 'hunk' == 0 then
    vim.notify('hunk not found on PATH (npm i -g hunkdiff)', vim.log.levels.ERROR)
    return
  end

  local root = git_root()
  if not root then
    vim.notify('not inside a git repository', vim.log.levels.WARN)
    return
  end

  vim.cmd 'tabnew'
  local buf = vim.api.nvim_get_current_buf()

  -- termopen spawns hunk directly, not through a shell, so it inherits only
  -- Neovim's environment. If Neovim itself was started from a shell that
  -- predates $EDITOR being set, hunk's `e` command would report
  -- "$EDITOR is not set." Pass it explicitly so that cannot happen.
  vim.fn.termopen('hunk ' .. args, {
    cwd = root,
    env = {
      EDITOR = vim.env.EDITOR or vim.fn.exepath 'nvim',
      VISUAL = vim.env.VISUAL or vim.env.EDITOR or vim.fn.exepath 'nvim',
    },
    on_exit = function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end,
  })

  vim.cmd 'startinsert'
end

---Diff only the file in the current buffer.
---@param target string|nil optional revision to compare against
function M.open_file(target)
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then
    vim.notify('current buffer has no file', vim.log.levels.WARN)
    return
  end
  local args = 'diff'
  if target and target ~= '' then
    args = args .. ' ' .. target
  end
  M.open(args .. ' -- ' .. vim.fn.shellescape(file))
end

---Resolve the repo's default branch (origin/HEAD, then main, then master).
function M.default_branch()
  local head = vim.fn.systemlist { 'git', 'symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD' }
  if vim.v.shell_error == 0 and head[1] and head[1] ~= '' then
    return (head[1]:gsub('^refs/remotes/', ''))
  end
  for _, b in ipairs { 'main', 'master' } do
    vim.fn.systemlist { 'git', 'rev-parse', '--verify', '--quiet', b }
    if vim.v.shell_error == 0 then
      return b
    end
  end
  return 'HEAD'
end

---Diff the working tree against the merge base with the default branch.
function M.diff_default_branch()
  if not git_root() then
    vim.notify('not inside a git repository', vim.log.levels.WARN)
    return
  end
  -- Triple-dot compares against the merge base, so commits that landed on the
  -- base branch after you forked are excluded from the review.
  M.open('diff ' .. M.default_branch() .. '...')
end

---Prompt for an arbitrary revision or range, then review it.
function M.diff_prompt()
  vim.ui.input({ prompt = 'hunk diff (revision or range): ' }, function(input)
    if input and input ~= '' then
      M.open('diff ' .. input)
    end
  end)
end

---Pick a recent commit, then review just that commit.
function M.pick_commit()
  if not git_root() then
    vim.notify('not inside a git repository', vim.log.levels.WARN)
    return
  end
  local log = vim.fn.systemlist {
    'git',
    'log',
    '-100',
    '--pretty=format:%h  %<(18,trunc)%an  %<(60,trunc)%s',
  }
  if vim.v.shell_error ~= 0 or #log == 0 then
    vim.notify('no commits found', vim.log.levels.WARN)
    return
  end
  vim.ui.select(log, { prompt = 'review commit:' }, function(choice)
    if choice then
      M.open('show ' .. choice:match '^(%S+)')
    end
  end)
end

---Pick a branch, then diff against its merge base.
function M.pick_branch()
  if not git_root() then
    vim.notify('not inside a git repository', vim.log.levels.WARN)
    return
  end
  local branches = vim.fn.systemlist {
    'git',
    'for-each-ref',
    '--sort=-committerdate',
    '--format=%(refname:short)',
    'refs/heads',
    'refs/remotes',
  }
  if vim.v.shell_error ~= 0 or #branches == 0 then
    vim.notify('no branches found', vim.log.levels.WARN)
    return
  end
  vim.ui.select(branches, { prompt = 'diff against branch:' }, function(choice)
    if choice then
      M.open('diff ' .. choice .. '...')
    end
  end)
end

return M
