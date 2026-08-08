-- Review mode: read a whole branch/PR as normal, editable buffers.
--
-- Problem this solves: gitsigns diffs the buffer against HEAD, so the moment work
-- is committed and pushed the gutter goes blank -- harpooning the changed files
-- then shows you plain text with no indication of what actually changed.
--
-- Fix: repoint gitsigns at the *merge-base* with the target branch. Every hunk
-- introduced by the branch stays highlighted in real files (LSP, treesitter and
-- harpoon all intact), whether it is committed, pushed, or still dirty.

local M = {}

M.state = { base = nil, rev = nil, cwd = nil, files = {} }

---Run git; returns trimmed stdout, or nil plus stderr on failure.
local function git(args, cwd)
  local cmd = { 'git', '-c', 'core.quotepath=false' }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil, vim.trim(res.stderr or '')
  end
  return vim.trim(res.stdout or '')
end

M._git = git

---Repo root for the current buffer, falling back to cwd.
local function repo_root()
  local dir = vim.fn.expand '%:p:h'
  if dir == '' or vim.bo.buftype ~= '' or vim.fn.isdirectory(dir) == 0 then
    dir = vim.uv.cwd()
  end
  return (git({ 'rev-parse', '--show-toplevel' }, dir))
end

---Best guess at the branch this work forked from.
local function default_base(cwd)
  local head = git({ 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd)
  if head and head ~= '' then
    return head
  end
  for _, cand in ipairs { 'origin/master', 'origin/main', 'master', 'main' } do
    if git({ 'rev-parse', '--verify', '--quiet', cand }, cwd) then
      return cand
    end
  end
  return nil
end

---The fork point, so unrelated commits landed on master after branching are excluded.
local function merge_base(base, cwd)
  local mb = git({ 'merge-base', base, 'HEAD' }, cwd)
  if mb and mb ~= '' then
    return mb
  end
  return base
end

---Path relative to nvim's cwd, which is the root harpoon stores against.
local function relative_to_cwd(abs)
  local cwd = (vim.uv.cwd() or ''):gsub('\\', '/')
  abs = abs:gsub('\\', '/')
  if cwd:sub(-1) ~= '/' then
    cwd = cwd .. '/'
  end
  local hay, needle = abs, cwd
  if vim.fn.has 'win32' == 1 then
    hay, needle = hay:lower(), needle:lower()
  end
  if hay:sub(1, #needle) == needle then
    return abs:sub(#needle + 1)
  end
  return abs
end

---Every file the branch touches: committed since `rev`, plus dirty, plus untracked.
---@return string[] paths relative to nvim's cwd
function M.changed_files(rev, cwd)
  local seen, out = {}, {}
  local function collect(text)
    for _, rel in ipairs(vim.split(text or '', '\n', { trimempty = true })) do
      local abs = cwd .. '/' .. rel
      local path = relative_to_cwd(abs)
      if not seen[path] and vim.fn.filereadable(abs) == 1 then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  -- Worktree vs merge-base: covers committed *and* uncommitted in one shot.
  collect(git({ 'diff', '--name-only', '--diff-filter=ACMR', rev }, cwd))
  collect(git({ 'ls-files', '--others', '--exclude-standard' }, cwd))
  table.sort(out)
  return out
end

---Replace the harpoon list with the branch's changed files.
function M.to_harpoon(files)
  local ok, harpoon = pcall(require, 'harpoon')
  if not ok then
    return nil
  end
  local list = harpoon:list()
  list:clear()
  for _, f in ipairs(files) do
    list:add(list.config.create_list_item(list.config, f))
  end
  return list:length()
end

---Enter review mode against `base` (default: origin/HEAD).
function M.start(base)
  local cwd = repo_root()
  if not cwd then
    vim.notify('review: not inside a git repository', vim.log.levels.ERROR)
    return
  end

  base = (base and base ~= '') and base or default_base(cwd)
  if not base then
    vim.notify('review: could not resolve a base branch', vim.log.levels.ERROR)
    return
  end

  local rev = merge_base(base, cwd)
  local gs = require 'gitsigns'
  gs.change_base(rev, true)
  gs.toggle_numhl(true)
  gs.toggle_word_diff(true)

  local files = M.changed_files(rev, cwd)
  M.state = { base = base, rev = rev, cwd = cwd, files = files }
  local marked = M.to_harpoon(files)

  vim.notify(
    ('review: %s (%s) - %d file%s%s'):format(base, rev:sub(1, 8), #files, #files == 1 and '' or 's', marked and ' harpooned' or ''),
    vim.log.levels.INFO
  )
end

---Leave review mode; gitsigns goes back to diffing against the index.
function M.stop()
  local gs = require 'gitsigns'
  gs.change_base(nil, true)
  gs.toggle_numhl(false)
  gs.toggle_word_diff(false)
  gs.toggle_linehl(false)
  M.state = { base = nil, rev = nil, cwd = nil, files = {} }
  vim.notify('review: off', vim.log.levels.INFO)
end

function M.toggle()
  if M.state.rev then
    M.stop()
  else
    M.start()
  end
end

---Every hunk in the branch, as a quickfix list.
---
---Deliberately not gitsigns' own setqflist: that path reads the worktree file
---with `io.open(path, 'rb')` and splits on '\n', so on a CRLF checkout every
---line keeps a trailing \r while the git blob is LF. Every line then compares
---unequal and you get one whole-file "hunk" per file. Oneportal checks out CRLF
---(core.autocrlf=true) so that bug bites here. Parsing `git diff` avoids it and
---is faster than diffing every file in Lua.
function M.qflist(open)
  if not M.state.rev then
    M.start()
  end
  local st = M.state
  if not st.rev then
    return
  end

  local out = git({ 'diff', '--unified=0', '--no-color', st.rev }, st.cwd) or ''
  local items, file = {}, nil
  for _, line in ipairs(vim.split(out, '\n')) do
    local newfile = line:match '^%+%+%+ b/(.*)$'
    if line:match '^%+%+%+ ' then
      file = newfile -- nil for /dev/null (deleted)
    elseif file and line:sub(1, 2) == '@@' then
      local start, count = line:match '^@@ %-%S+ %+(%d+),?(%d*) @@'
      if start then
        local added = tonumber(count) or 1
        local removed = tonumber((line:match '^@@ %-%d+,(%d+)')) or 1
        items[#items + 1] = {
          filename = st.cwd .. '/' .. file,
          lnum = math.max(tonumber(start), 1),
          col = 1,
          text = ('+%d -%d'):format(added, removed),
        }
      end
    end
  end

  vim.fn.setqflist({}, ' ', {
    title = ('review %s (%d hunks)'):format(st.base, #items),
    items = items,
  })
  if open ~= false then
    vim.cmd 'copen'
  end
  return #items
end

---Open a changeset in hunk, a terminal review UI, in its own tab.
---`e` inside hunk jumps back here to the real file.
function M.hunk(target)
  if vim.fn.executable 'hunk' ~= 1 then
    vim.notify('review: hunk is not on PATH', vim.log.levels.ERROR)
    return
  end
  local args = target and ('diff ' .. vim.fn.shellescape(target)) or 'diff'
  vim.cmd 'tabnew'
  vim.fn.termopen('hunk ' .. args, {
    on_exit = function()
      if vim.api.nvim_buf_is_valid(0) then
        pcall(vim.cmd, 'bdelete!')
      end
    end,
  })
  vim.cmd 'startinsert'
end

---Hand the active review range to hunk for a whole-changeset pass.
function M.hunk_review()
  if not M.state.base then
    vim.notify('review: not active; run :ReviewStart first', vim.log.levels.WARN)
    return
  end
  M.hunk(('%s...HEAD'):format(M.state.base))
end

---Review the current branch against its default base without starting review mode.
function M.hunk_branch()
  local cwd = repo_root()
  if not cwd then
    vim.notify('review: not in a git repo', vim.log.levels.WARN)
    return
  end
  M.hunk(('%s...HEAD'):format(default_base(cwd)))
end

---For a statusline component.
function M.status()
  if not M.state.rev then
    return ''
  end
  return ('review:%s(%d)'):format(M.state.base, #M.state.files)
end

local function complete_ref(arg)
  local cwd = repo_root()
  if not cwd then
    return {}
  end
  local out = git({ 'for-each-ref', '--format=%(refname:short)', 'refs/heads', 'refs/remotes' }, cwd) or ''
  return vim.tbl_filter(function(r)
    return r:find(arg, 1, true) == 1
  end, vim.split(out, '\n', { trimempty = true }))
end

function M.setup()
  local cmd = vim.api.nvim_create_user_command
  cmd('ReviewStart', function(o)
    M.start(o.args)
  end, { nargs = '?', complete = complete_ref, desc = 'Review: highlight everything since the branch point' })
  cmd('ReviewStop', M.stop, { desc = 'Review: back to diffing against the index' })
  cmd('ReviewToggle', M.toggle, { desc = 'Review: toggle review mode' })
  cmd('ReviewFiles', function()
    if not M.state.rev then
      return M.start()
    end
    local files = M.changed_files(M.state.rev, M.state.cwd)
    M.state.files = files
    M.to_harpoon(files)
    vim.notify(('review: re-harpooned %d file(s)'):format(#files))
  end, { desc = 'Review: refresh the harpoon list' })
  cmd('ReviewQf', M.qflist, { desc = 'Review: all hunks to quickfix' })
  cmd('ReviewHunk', M.hunk_review, { desc = 'Review: open the same range in hunk' })
  cmd('Hunk', function(o)
    M.hunk(o.args ~= '' and o.args or nil)
  end, { nargs = '?', complete = complete_ref, desc = 'Open a changeset in hunk' })

  local map = function(lhs, rhs, desc)
    vim.keymap.set('n', lhs, rhs, { desc = desc })
  end
  map('<leader>rr', M.toggle, 'Review: toggle')
  map('<leader>rs', function()
    M.start()
  end, 'Review: start')
  map('<leader>rx', M.stop, 'Review: stop')
  map('<leader>rf', function()
    vim.cmd 'ReviewFiles'
  end, 'Review: refresh harpoon list')
  map('<leader>rq', M.qflist, 'Review: hunks to quickfix')
  map('<leader>rd', M.hunk_review, 'Review: open range in hunk')
  map('<leader>gd', function()
    M.hunk()
  end, 'Git: review working tree in hunk')
  map('<leader>gm', M.hunk_branch, 'Git: review branch vs default base in hunk')
  map('<leader>rl', function()
    local on = require('gitsigns').toggle_linehl()
    vim.notify('review: linehl ' .. (on and 'on' or 'off'))
  end, 'Review: toggle full-line highlight')
end

return M
