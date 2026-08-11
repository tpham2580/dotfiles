-- Send a visual selection (plus a prompt) to the Copilot agent running in the
-- current Herdr session -- the terminal equivalent of VS Code's
-- "add selection to Copilot chat".
--
-- Pairs with the `hunk` review flow: press `e` on a hunk to open the file here,
-- select the lines you care about, then <leader>ai.

local M = {}

local function herdr_exe()
  local onpath = vim.fn.exepath('herdr')
  if onpath ~= '' then return onpath end
  local bundled = vim.fn.expand('~/.herdr/packages/standalone/current/herdr.exe')
  if vim.uv.fs_stat(bundled) then return bundled end
  return nil
end

local function run(args)
  local exe = herdr_exe()
  if not exe then return nil, 'herdr not found (not on PATH, no bundled copy)' end
  local cmd = { exe }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    return nil, (res.stderr ~= '' and res.stderr or res.stdout or 'herdr exited ' .. res.code)
  end
  local ok, data = pcall(vim.json.decode, res.stdout)
  if not ok then return nil, 'could not parse herdr output' end
  return data, nil
end

local function repo_root()
  local res = vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if res.code ~= 0 then return nil end
  return (vim.trim(res.stdout):gsub('/', '\\'))
end

-- workspace_id -> label. `agent list` only carries the opaque id (wA, wB), but
-- the label is the one field that reliably tells two candidates apart: agent
-- names are often unset, terminal titles are truncated task names, and folder
-- basenames repeat across checkouts.
local function workspace_labels()
  local data = run({ 'workspace', 'list' })
  local out = {}
  if not data then return out end
  for _, w in ipairs((data.result or {}).workspaces or {}) do
    if w.workspace_id then out[w.workspace_id] = w.label end
  end
  return out
end

-- tab_id -> label. Tab names are unique *within* a workspace but repeat across
-- them ("agent 1" in two workspaces), so this is the second half of the key,
-- not a replacement for the workspace label. It is what separates two agents
-- in the same workspace, where cwd and workspace label are identical.
local function tab_labels()
  local data = run({ 'tab', 'list' })
  local out = {}
  if not data then return out end
  for _, t in ipairs((data.result or {}).tabs or {}) do
    if t.tab_id then out[t.tab_id] = t.label end
  end
  return out
end

-- Rank candidates so the agent in *this* repo/workspace wins automatically.
local function score(agent, root, pane)
  local s = 0
  if root and agent.cwd then
    local a = agent.cwd:gsub('[\\/]+$', ''):lower()
    if a == root:lower() then s = s + 10 end
  end
  if pane then
    local ws = pane:match('^([^:]+):')
    if ws and agent.workspace_id == ws then s = s + 5 end
  end
  if agent.agent_status == 'idle' or agent.agent_status == 'done' then s = s + 1 end
  return s
end

local function candidates()
  local data, err = run({ 'agent', 'list' })
  if not data then return nil, err end
  local all = (data.result or {}).agents or {}
  local root, pane = repo_root(), vim.env.HERDR_PANE_ID
  local labels, tabs = workspace_labels(), tab_labels()
  local out = {}
  for _, a in ipairs(all) do
    if a.agent == 'copilot' then
      -- Agents started by hand have no name; the pane id is a valid target too.
      a._target = (a.name ~= nil and a.name ~= '') and a.name or a.pane_id
      if a._target then
        a._workspace = labels[a.workspace_id] or a.workspace_id or '?'
        a._tab = tabs[a.tab_id] or a.tab_id or '?'
        a._score = score(a, root, pane)
        table.insert(out, a)
      end
    end
  end
  table.sort(out, function(x, y)
    if x._score ~= y._score then return x._score > y._score end
    if x._workspace ~= y._workspace then return x._workspace < y._workspace end
    return x._tab < y._tab
  end)
  return out, nil
end

local function pick(list, cb)
  -- Lay the rows out in columns with workspace then tab first: together they
  -- are what disambiguates. The workspace alone is not enough when a workspace
  -- runs several agents -- there the tab name is the only thing that differs,
  -- since cwd and workspace label are identical.
  local wsw, tabw, whow = 0, 0, 0
  for _, a in ipairs(list) do
    a._who = (a._target ~= a.pane_id) and (a._target .. ' (' .. a.pane_id .. ')') or a.pane_id
    wsw = math.max(wsw, #a._workspace)
    tabw = math.max(tabw, #a._tab)
    whow = math.max(whow, #a._who)
  end

  local fmt = '%-' .. wsw .. 's  %-' .. tabw .. 's  %-' .. whow .. 's  [%s]  %s'
  local function format_item(a)
    return string.format(fmt, a._workspace, a._tab, a._who, a.agent_status or '?', a.cwd or '')
  end

  vim.ui.select(list, { prompt = 'Send to which Copilot agent?', format_item = format_item },
    function(choice)
      if not choice then return end
      vim.g.ai_agent = choice._target
      cb(choice._target, choice)
    end)
end

--- Resolve the target agent, asking only when genuinely ambiguous.
local function resolve(cb, force)
  if vim.g.ai_agent and not force then return cb(vim.g.ai_agent) end

  local list, err = candidates()
  if not list then
    return vim.notify('AiSend: ' .. err, vim.log.levels.ERROR)
  end
  if #list == 0 then
    return vim.notify(
      'AiSend: no Copilot agent found in this Herdr session.\n' ..
      'Start one with `hr`, or run copilot in a pane, then :AiAgent.',
      vim.log.levels.WARN)
  end
  if force or #list > 1 then
    -- More than one candidate: always let the user choose rather than guess.
    if not force and list[1]._score > list[2]._score then
      vim.g.ai_agent = list[1]._target
      return cb(list[1]._target)
    end
    return pick(list, cb)
  end
  vim.g.ai_agent = list[1]._target
  return cb(list[1]._target)
end

local function relpath()
  local abs = vim.fn.expand('%:p')
  local root = repo_root()
  if root and abs:lower():sub(1, #root) == root:lower() then
    abs = abs:sub(#root + 2)
  end
  return (abs:gsub('\\', '/'))
end

local function build(l1, l2, note)
  local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  local width = #tostring(l2)
  local numbered = {}
  for i, line in ipairs(lines) do
    table.insert(numbered, string.format('%' .. width .. 'd  %s', l1 + i - 1, line))
  end

  local loc = (l1 == l2) and tostring(l1) or (l1 .. '-' .. l2)
  local ft = vim.bo.filetype ~= '' and vim.bo.filetype or ''

  local parts = {
    ('Reviewing `%s` lines %s:'):format(relpath(), loc),
    '',
    '```' .. ft,
    table.concat(numbered, '\n'),
    '```',
    '',
    note,
  }
  return table.concat(parts, '\n')
end

local function deliver(name, text, opts)
  local exe = herdr_exe()
  local cmd = { exe, 'agent', 'prompt', name, text }
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify('AiSend -> ' .. name .. ' failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      else
        vim.notify('Sent to ' .. name, vim.log.levels.INFO)
        if opts and opts.focus then vim.system({ exe, 'agent', 'focus', name }) end
      end
    end)
  end)
end

--- Send lines l1..l2 of the current buffer, with `note`, to the Copilot agent.
--- opts.pick forces the agent picker even if a target is already cached.
function M.send(l1, l2, note, opts)
  if vim.fn.expand('%') == '' then
    return vim.notify('AiSend: buffer has no file', vim.log.levels.WARN)
  end
  opts = opts or {}

  local function go(text)
    resolve(function(name) deliver(name, text, opts) end, opts.pick)
  end

  if note and note ~= '' then
    return go(build(l1, l2, note))
  end

  vim.ui.input({ prompt = 'Prompt for Copilot: ' }, function(input)
    if not input or input == '' then
      return vim.notify('AiSend: cancelled', vim.log.levels.INFO)
    end
    go(build(l1, l2, input))
  end)
end

--- Choose (or clear) the agent that AiSend targets.
function M.choose(arg)
  if arg == 'auto' then
    vim.g.ai_agent = nil
    return vim.notify('AiSend target: auto')
  end
  if arg and arg ~= '' then
    vim.g.ai_agent = arg
    return vim.notify('AiSend target: ' .. arg)
  end

  local list, err = candidates()
  if not list then return vim.notify('AiSend: ' .. err, vim.log.levels.ERROR) end
  if #list == 0 then
    return vim.notify('AiSend: no Copilot agent in this Herdr session', vim.log.levels.WARN)
  end
  pick(list, function(t, a)
    vim.notify('AiSend target: ' .. a._workspace .. ' / ' .. a._tab .. ' / ' .. t)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('AiSend', function(o)
    M.send(o.line1, o.line2, o.args, { focus = o.bang })
  end, { range = true, nargs = '?', bang = true, desc = 'Send selection + prompt to Copilot' })

  vim.api.nvim_create_user_command('AiSendTo', function(o)
    M.send(o.line1, o.line2, o.args, { pick = true, focus = o.bang })
  end, { range = true, nargs = '?', bang = true, desc = 'Pick an agent, then send selection' })

  vim.api.nvim_create_user_command('AiAgent', function(o)
    M.choose(o.args)
  end, { nargs = '?', desc = 'Choose the Copilot agent AiSend targets' })

  vim.keymap.set('v', '<leader>ai', ':AiSend<CR>',
    { silent = true, desc = 'Send selection to Copilot' })
  vim.keymap.set('v', '<leader>aI', ':AiSend!<CR>',
    { silent = true, desc = 'Send selection to Copilot + focus it' })
  vim.keymap.set('v', '<leader>as', ':AiSendTo<CR>',
    { silent = true, desc = 'Send selection to a chosen Copilot agent' })
  vim.keymap.set('n', '<leader>ai', ':.AiSend<CR>',
    { silent = true, desc = 'Send current line to Copilot' })
  vim.keymap.set('n', '<leader>aa', function() M.choose() end,
    { silent = true, desc = 'Choose the Copilot agent to target' })
end

return M
