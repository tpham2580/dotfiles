-- Wires up review mode (see lua/custom/review.lua).
--
-- `init` runs at startup but only registers commands/keymaps -- gitsigns and
-- harpoon are require'd lazily inside the command handlers, so this costs
-- nothing measurable at launch.
return {
  {
    'lewis6991/gitsigns.nvim',
    optional = true,
    init = function()
      require('custom.review').setup()
    end,
  },
}
