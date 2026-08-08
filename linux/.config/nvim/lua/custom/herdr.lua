-- custom/herdr.lua — send text from Neovim to a Copilot CLI agent running in herdr.
--
-- Neovim usually runs inside a herdr pane, so $HERDR_PANE_ID tells us which
-- workspace we are in. Agents in that same workspace are offered first; if there
-- is exactly one we send straight to it, otherwise you pick from a list.

local M = {}

local HERDR = vim.fn.exepath 'herdr'
if HERDR == '' then
  HERDR = vim.fn.expand '~/.local/bin/herdr'
end

local function herdr_json(args)
  local out = vim.fn.system(vim.list_extend({ HERDR }, args))
  if vim.v.shell_error ~= 0 or out == '' then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, out)
  if not ok then
    return nil
  end
  return decoded
end

---Workspace id of the pane Neovim is running in, if any.
local function current_workspace()
  local pane = vim.env.HERDR_PANE_ID or vim.env.HERDR_ACTIVE_PANE_ID
  if not pane or pane == '' then
    return nil
  end
  return pane:match '^([^:]+)'
end

---Map of tab_id -> tab label.
local function tab_labels()
  local data = herdr_json { 'tab', 'list' }
  local map = {}
  if data and data.result and data.result.tabs then
    for _, t in ipairs(data.result.tabs) do
      map[t.tab_id] = t.label
    end
  end
  return map
end

---Map of workspace_id -> workspace label.
local function workspace_labels()
  local data = herdr_json { 'workspace', 'list' }
  local map = {}
  if data and data.result and data.result.workspaces then
    for _, w in ipairs(data.result.workspaces) do
      map[w.workspace_id] = w.label
    end
  end
  return map
end

---All live agents, with agents in the current workspace sorted first.
---Each entry is annotated with its tab and workspace labels, because agent
---names are auto-derived from pane ids and look nearly identical.
function M.agents()
  local data = herdr_json { 'agent', 'list' }
  if not data or not data.result or not data.result.agents then
    return {}
  end
  local agents = data.result.agents
  local tabs = tab_labels()
  local spaces = workspace_labels()

  for _, a in ipairs(agents) do
    a._tab = tabs[a.tab_id]
    a._workspace = spaces[a.workspace_id]
  end

  local ws = current_workspace()
  table.sort(agents, function(a, b)
    if ws then
      local a_local = (a.workspace_id == ws) and 1 or 0
      local b_local = (b.workspace_id == ws) and 1 or 0
      if a_local ~= b_local then
        return a_local > b_local
      end
    end
    return (a._tab or a.name or '') < (b._tab or b.name or '')
  end)
  return agents
end

---Display string for an agent. The tab name leads because that is what the
---user actually named; agent names like "copilot-wk-p1" are not distinguishing.
---@param agent table
---@param ambiguous boolean|nil append the pane id when tab names collide
local function label(agent, ambiguous)
  local parts = { agent._tab or agent.name or '?' }

  if agent.agent_status then
    table.insert(parts, agent.agent_status)
  end
  if agent._workspace then
    table.insert(parts, agent._workspace)
  end
  if ambiguous and agent.pane_id then
    table.insert(parts, agent.pane_id)
  end

  return table.concat(parts, '  ·  ')
end

---Send text to a named agent.
local function submit(name, text)
  local res = vim.system({ HERDR, 'agent', 'prompt', name, text }, { text = true }):wait()
  if res.code ~= 0 then
    local msg = (res.stderr ~= '' and res.stderr) or res.stdout or 'unknown error'
    vim.notify('herdr: ' .. vim.trim(msg), vim.log.levels.ERROR)
    return false
  end
  vim.notify('sent to ' .. name, vim.log.levels.INFO)
  return true
end

---Choose an agent, then run cb(agent_name).
---Sends immediately when only one agent exists.
local function pick_agent(cb)
  local agents = M.agents()
  if #agents == 0 then
    vim.notify('herdr: no running agents (start one with prefix+A)', vim.log.levels.WARN)
    return
  end
  if #agents == 1 then
    cb(agents[1].name)
    return
  end

  local items = {}
  for _, a in ipairs(agents) do
    table.insert(items, a)
  end

  -- Two agents can live in one tab (one per pane), so fall back to showing the
  -- pane id only when the tab names alone would not tell them apart.
  local seen, dup = {}, false
  for _, a in ipairs(items) do
    local key = a._tab or a.name or '?'
    if seen[key] then
      dup = true
      break
    end
    seen[key] = true
  end

  vim.ui.select(items, {
    prompt = 'send to agent:',
    format_item = function(a)
      return label(a, dup)
    end,
  }, function(choice)
    if choice then
      cb(choice.name)
    end
  end)
end

---Text of the most recent visual selection.
local function visual_selection()
  local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, '<'))
  local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, '>'))
  if srow == 0 or erow == 0 then
    return nil
  end

  local function line_len(row)
    return #(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or '')
  end

  -- Linewise (V) sets '> to a huge column, so both ends must be clamped to the
  -- real line lengths before nvim_buf_get_text will accept them.
  local start_col = math.min(scol, line_len(srow))
  local end_col = math.min(ecol + 1, line_len(erow))

  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, srow - 1, start_col, erow - 1, end_col, {})
  if not ok or vim.tbl_isempty(lines) then
    -- Fall back to whole lines rather than losing the selection.
    lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
  end
  if vim.tbl_isempty(lines) then
    return nil
  end
  return table.concat(lines, '\n'), srow, erow
end

local function relpath()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    return '[No Name]'
  end
  return vim.fn.fnamemodify(name, ':~:.')
end

---Send the visual selection, fenced and annotated with file and line range.
---@param instruction string|nil optional question to prepend
function M.send_selection(instruction)
  local text, srow, erow = visual_selection()
  if not text then
    vim.notify('herdr: no visual selection', vim.log.levels.WARN)
    return
  end

  local ft = vim.bo.filetype or ''
  local header = string.format('%s:%d-%d', relpath(), srow, erow)

  -- Built by insertion rather than a table literal: a literal with a
  -- conditional entry yields nil, which table.concat rejects as a hole.
  local parts = {}
  if instruction and instruction ~= '' then
    table.insert(parts, instruction)
    table.insert(parts, '')
  end
  table.insert(parts, header)
  table.insert(parts, '```' .. ft)
  table.insert(parts, text)
  table.insert(parts, '```')

  local body = table.concat(parts, '\n')

  pick_agent(function(name)
    submit(name, vim.trim(body))
  end)
end

---Prompt for a question, then send it with the visual selection.
function M.ask_selection()
  vim.ui.input({ prompt = 'ask copilot: ' }, function(input)
    if input and input ~= '' then
      M.send_selection(input)
    end
  end)
end

---Send an arbitrary prompt with no selection.
function M.send_prompt()
  vim.ui.input({ prompt = 'copilot: ' }, function(input)
    if input and input ~= '' then
      pick_agent(function(name)
        submit(name, input)
      end)
    end
  end)
end

---Send just a reference to the current file.
function M.send_file()
  local name = relpath()
  pick_agent(function(agent)
    submit(agent, 'Look at ' .. name)
  end)
end

---Check every herdr assumption this module depends on.
---Run :HerdrDoctor after upgrading herdr to see exactly what (if anything) broke.
function M.doctor()
  local lines = {}
  local function add(ok, msg)
    table.insert(lines, (ok and '  OK   ' or '  FAIL ') .. msg)
    return ok
  end

  if vim.fn.executable(HERDR) == 0 then
    add(false, 'herdr binary not found at ' .. HERDR)
    vim.notify(table.concat(lines, '\n'), vim.log.levels.ERROR)
    return
  end

  local ver = vim.fn.system { HERDR, '--version' }
  add(true, 'herdr binary: ' .. vim.trim(ver))

  local pane = vim.env.HERDR_PANE_ID or vim.env.HERDR_ACTIVE_PANE_ID
  add(pane ~= nil and pane ~= '', 'HERDR_PANE_ID (workspace-first ordering): ' .. tostring(pane))

  local a = herdr_json { 'agent', 'list' }
  local a_ok = add(
    a ~= nil and a.result ~= nil and a.result.agents ~= nil,
    '`agent list` -> .result.agents'
  )
  if a_ok and a.result.agents[1] then
    local first = a.result.agents[1]
    for _, f in ipairs { 'name', 'pane_id', 'tab_id', 'workspace_id', 'agent_status' } do
      add(first[f] ~= nil, 'agent field: ' .. f)
    end
  end

  local t = herdr_json { 'tab', 'list' }
  local t_ok = add(t ~= nil and t.result ~= nil and t.result.tabs ~= nil, '`tab list` -> .result.tabs')
  if t_ok and t.result.tabs[1] then
    add(t.result.tabs[1].tab_id ~= nil, 'tab field: tab_id')
    add(t.result.tabs[1].label ~= nil, 'tab field: label (picker labels)')
  end

  local w = herdr_json { 'workspace', 'list' }
  add(w ~= nil and w.result ~= nil and w.result.workspaces ~= nil, '`workspace list` -> .result.workspaces')

  local help = vim.fn.system { HERDR, 'agent', 'prompt', '--help' }
  add(help:match 'TARGET' ~= nil and help:match 'TEXT' ~= nil, '`agent prompt <TARGET> <TEXT>` signature')

  vim.notify('herdr.lua doctor\n' .. table.concat(lines, '\n'), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('HerdrDoctor', function()
  M.doctor()
end, { desc = 'Check herdr CLI assumptions used by custom/herdr.lua' })

return M
