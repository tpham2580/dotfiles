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
  local out = {}
  for _, a in ipairs(all) do
    if a.agent == 'copilot' then
      -- Agents started by hand have no name; the pane id is a valid target too.
      a._target = (a.name ~= nil and a.name ~= '') and a.name or a.pane_id
      if a._target then
        a._score = score(a, root, pane)
        table.insert(out, a)
      end
    end
  end
  table.sort(out, function(x, y) return x._score > y._score end)
  return out, nil
end

local function label(a)
  local base = (a.name ~= nil and a.name ~= '') and (a.name .. '  (' .. a.pane_id .. ')')
    or a.pane_id
  return string.format('%s  [%s]  %s', base, a.agent_status or '?', a.cwd or '')
end

local function pick(list, cb)
  vim.ui.select(list, { prompt = 'Send to which Copilot agent?', format_item = label },
    function(choice)
      if not choice then return end
      vim.g.ai_agent = choice._target
      cb(choice._target)
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
  pick(list, function(t) vim.notify('AiSend target: ' .. t) end)
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
