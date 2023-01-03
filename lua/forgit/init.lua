local M = {}

local utils = require('forgit.utils')
local log = utils.log
_FORGIT_CFG = {
  debug = false, -- set to true to enable debug logging
  log_path = nil, -- set to a path to log to a file
  fugitive = false,
  git_alias = true,
  shell_mode = true, -- set to true if you running zsh and having trouble with the shell command
  diff = 'delta', -- diff-so-fancy, diff
  vsplit = true, -- split forgit window the screen vertically
  show_result = 'quickfix', -- show cmd result in quickfix or notify
  height_ratio = 0.6, -- height ratio of floating window when split horizontally
  width_ratio = 0.6, -- width ratio of floating window when split vertically
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
    create_cmd(cmd, function(opts)
      cmd = string.lower(cmd)
      local autoclose
      if vim.tbl_contains({ 'gd' }, cmd) then
        autoclose = false
      else
        autoclose = true
      end
      if opts and opts.fargs and #opts.fargs > 0 then
        for _, arg in ipairs(opts.fargs) do
          cmd = cmd .. ' ' .. arg
        end
      end
      local sh = vim.o.shell
      if _FORGIT_CFG.shell_mode and (sh:find('zsh') or sh:find('bash')) then
        log('cmd: ' .. cmd)
        cmd = sh .. ' -i -c ' .. cmd
      end
      local term = require('forgit.term').run
      log(cmd)
      term({ cmd = cmd, autoclose = autoclose })
    end, { nargs = '*' })
  end
  if _FORGIT_CFG.git_alias then
    require('forgit.commands').setup()
  end
end

return M
