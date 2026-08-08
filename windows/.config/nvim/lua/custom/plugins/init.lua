-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'folke/sidekick.nvim',
    event = 'VeryLazy',
    opts = {
      nes = {
        -- Copilot LSP "Next Edit Suggestions" -- the only part of sidekick in daily use.
        -- The LSP is enabled via `vim.lsp.enable('copilot')` in init.lua; run
        -- `:LspCopilotSignIn` if prompted. NES needs a `.git` root to attach.
        enabled = true,
      },
      -- The CLI half is intentionally unused: Copilot CLI runs in its own psmux pane,
      -- which has real scrollback. Kept minimal so `:Sidekick cli toggle` still behaves
      -- if ever invoked.
      cli = {
        mux = {
          -- NEVER enable this under psmux. sidekick runs `tmux new -A -s <id> ...` inside
          -- Neovim's terminal and expects it to attach; psmux cannot attach from Neovim's
          -- embedded pty -- it prints its version banner ("tmux 3.3.6") and exits 0, so the
          -- terminal dies the moment it opens. Leaving it off also means sidekick's
          -- scrollback viewer stays disabled (it is gated on `tmux capture-pane`), which is
          -- precisely why the CLI lives in a psmux pane instead.
          enabled = false,
        },
        -- Default is 'snacks', which isn't installed here.
        picker = 'telescope',
      },
    },
    keys = {
      {
        '<Tab>',
        function()
          -- Jump to the pending Next Edit Suggestion, or apply it once we're on it.
          -- Returning '<Tab>' falls through to the built-in mapping, so <C-i>
          -- (jumplist forward) still works whenever no suggestion is pending.
          if not require('sidekick').nes_jump_or_apply() then
            return '<Tab>'
          end
        end,
        mode = 'n',
        expr = true,
        desc = 'AI: goto/apply Next Edit Suggestion',
      },
    },
  },
}
