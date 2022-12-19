local M = {}

local utils = require('forgit.utils')
local log = utils.log
local lprint = lprint or log
_FORGIT_CFG = {
  ls_file = 'fd', -- git ls-file
  fugitive = false,
  git_alias = false,
  diff = 'delta', -- diff-so-fancy
  exact = false, -- Exact match
  vsplit = true, -- split sad window the screen vertically
  height_ratio = 0.6, -- height ratio of sad window when split horizontally
  width_ratio = 0.6, -- height ratio of sad window when split vertically
}

local create_cmd = function(cmd, func, opt)
  opt = vim.tbl_extend('force', { desc = 'forgit ' .. cmd }, opt or {})
  vim.api.nvim_create_user_command(cmd, func, opt)
end
local guihua_helper = utils.load_plugin('guihua.lua', 'guihua.helper')
if not guihua_helper then
  utils.warn('guihua not installed, please install ray-x/guihua.lua for GUI functions')
end

local cmds = {
  'Ga',
  'Glo',
  'Gi',
  'Gd',
  'Grh',
  'Gcf',
  'Gcb',
  'Gbd',
  'Gct',
  'Gco',
  'Grc',
  'Gss',
  'Gsp',
  'Gclean',
  'Gcp',
  'Grb',
  'Gbl',
  'Gfu',
}

M.setup = function(cfg)
  cfg = cfg or {}
  _FORGIT_CFG = vim.tbl_extend('force', _FORGIT_CFG, cfg)

  if not guihua_helper.is_installed(_FORGIT_CFG.ls_file) then
    print('please install ' .. _FORGIT_CFG.ls_file .. ' e.g. `brew install' .. _FORGIT_CFG.ls_file .. '`')
  end

  if not guihua_helper.is_installed('fzf') then
    print('please install fzf e.g. `brew install fzf')
  end
  if not guihua_helper.is_installed(_FORGIT_CFG.diff) then
    print('please install ' .. _FORGIT_CFG.diff .. ' e.g. `brew install' .. _FORGIT_CFG.diff .. '`')
  end
  if not guihua_helper.is_installed('git') then
    print('please install git ')
  end
  for _, cmd in ipairs(cmds) do
    -- create_cmd(cmd, 'lua require("forgit").' .. cmd:lower() .. '()')
    create_cmd(cmd, function(_)
      cmd = string.lower(cmd)
      lprint(cmd)
      local term = require('forgit.term').run
      term({ cmd = cmd, autoclose = true })
    end)
  end
  if _FORGIT_CFG.git_alias then
    require('forgit.commands')
  end
end

return M
