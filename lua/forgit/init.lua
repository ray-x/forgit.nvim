local M = {}

local utils = require('forgit.utils')
local log = utils.log

_FORGIT_CFG = {
  debug = false, -- set to true to enable debug logging
  log_path = nil, -- set to a path to log to a file
  forgit = true,
  fugitive = false, -- vim-fugitive is installed (why not)
  forgit_path = 'git-forgit', -- git_forgit script path
  abbreviate = false, -- abvreviate some of the commands e.g. gps -> Gps
  flog = false, -- vim-flog
  gitsigns = false, -- gitsigns.nvim
  git_fuzzy = false,
  git_alias = true,
  shell_mode = false, -- set to true if you running zsh and having trouble with the shell command
  diff_pager = 'delta', -- diff-so-fancy, diff
  diff_cmd = 'DiffviewOpen', -- auto if not set
  vsplit = true, -- split forgit window the screen vertically
  show_result = 'quickfix', -- show cmd result in quickfix or notify
  height_ratio = 0.6, -- height ratio of floating window when split horizontally
  width_ratio = 0.6, -- width ratio of floating window when split vertically
  cmds_list = {},
}


local function deprecate()
  if _FORGIT_CFG.diff == 'delta' then
    utils.warn(
      'diff option can only be "Gvdiffsplit" | "Gdiffsplit" | "fugitive_diff" | "diffview" now, please update your config'
    )
  end
end

M.setup = function(cfg)
  cfg = cfg or {}
  _FORGIT_CFG = vim.tbl_extend('force', _FORGIT_CFG, cfg)

  if not guihua_helper.is_installed('fzf') then
    print('please install fzf e.g. `brew install fzf')
  end
  if is_installed(_FORGIT_CFG.diff_pager) ~= 1 then
    print(
      'please install '
        .. _FORGIT_CFG.diff_pager
        .. ' e.g. `brew install'
        .. _FORGIT_CFG.diff_pager
        .. '`'
    )
  end
  if is_installed('git') ~= 1 then
    print('please install git ')
  end
  if _FORGIT_CFG.fugitive then
    require('forgit.utils').load_plugin('vim-fugitive')
  end
  if _FORGIT_CFG.forgit then
    require('forgit.forgit_cmds').setup()
  end

  require('forgit.commands').setup()
  require('forgit.diff').setup()
  require('forgit.list')
end

return M
