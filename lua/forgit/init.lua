local M = {}

local utils = require('forgit.utils')
local log = utils.log
_FORGIT_CFG = {
  debug = false, -- set to true to enable debug logging
  log_path = nil, -- set to a path to log to a file
  fugitive = true, -- vim-fugitive is installed (why not)
  flog = false,   -- vim-flog
  gitsigns = true, -- gitsigns.nvim
  git_fuzzy = false,
  git_alias = true,
  shell_mode = false, -- set to true if you running zsh and having trouble with the shell command
  diff_pager = 'delta', -- diff-so-fancy, diff
  diff_cmd = '', -- auto if not set
  vsplit = true, -- split forgit window the screen vertically
  show_result = 'quickfix', -- show cmd result in quickfix or notify
  height_ratio = 0.6, -- height ratio of floating window when split horizontally
  width_ratio = 0.6, -- width ratio of floating window when split vertically
  cmds_list = {},
}

local create_cmd = function(cmd, func, opt)
  opt = vim.tbl_extend('force', { desc = 'forgit ' .. cmd }, opt or {})
  vim.api.nvim_create_user_command(cmd, func, opt)
end
local guihua_helper = utils.load_plugin('guihua.lua', 'guihua.helper')
if not guihua_helper then
  utils.warn('guihua not installed, please install ray-x/guihua.lua for GUI functions')
end

local ga_bang = function(opts)
  local sh = vim.o.shell
  log('ga_bang', opts)

  local diff = ''
  if _FORGIT_CFG.diff_pager_pager ~= '' then
    if _FORGIT_CFG.diff_pager_pager == 'delta' then
      diff = '|delta --side-by-side -w $FZF_PREVIEW_COLUMNS'
      if vim.fn.executable('delta') == 0 then
        diff = ''
      end
    else
      diff = '|' .. _FORGIT_CFG.diff_pager
    end
  end

  local cmd = '$(git diff --name-only --cached | fzf -m --preview="git diff --cached $(echo {})'
    .. diff
    .. '");   echo $files | xargs -r git restore --staged '
  if sh:find('fish') then
    cmd = [[set files ]] .. cmd
  else
    cmd = [[files=]] .. cmd
  end
  log(cmd)

  local term = require('forgit.term').run
  term({ cmd = cmd, autoclose = true })
end

local cmds = {
  { 'Ga', 'git add' },
  { 'Glo', 'git log' },
  { 'Gi', 'git ignore' },
  { 'Gd', 'git diff' },
  { 'Grh', 'git reset HEAD <file>' },
  { 'Gcf', 'git checkout file' },
  { 'Gcb', 'git checkout <branch>' },
  { 'Gbd', 'git checkout -D branch' },
  { 'Gct', 'git checkout <tag>' },
  { 'Gco', 'git checkout <commit>' },
  { 'Grc', 'git revert <commit>' },
  { 'Gss', 'git stash' },
  { 'Gsp', 'git stash push' },
  { 'Gclean', 'git clean' },
  { 'Gcp', 'git cherry-pick' },
  { 'Grb', 'git rebase -i' },
  { 'Gbl', 'git blame' },
  { 'Gfu', 'git commit --fixup && git rebase -i --autosquash' },
}

M.cmds = cmds

local function deprecate()
  if _FORGIT_CFG.diff =='delta' then
    utils.warn('diff option can only be "Gvdiffsplit" | "Gdiffsplit" | "fugitive_diff" | "diffview" now, please update your config')
  end
end

M.setup = function(cfg)
  cfg = cfg or {}
  _FORGIT_CFG = vim.tbl_extend('force', _FORGIT_CFG, cfg)

  if not guihua_helper.is_installed('fzf') then
    print('please install fzf e.g. `brew install fzf')
  end
  if not guihua_helper.is_installed(_FORGIT_CFG.diff_pager) then
    print('please install ' .. _FORGIT_CFG.diff_pager .. ' e.g. `brew install' .. _FORGIT_CFG.diff_pager .. '`')
  end
  if not guihua_helper.is_installed('git') then
    print('please install git ')
  end
  for _, cmd_info in ipairs(cmds) do
    -- create_cmd(cmd, 'lua require("forgit").' .. cmd:lower() .. '()')
    local cmd = cmd_info[1]
    local cmd_details = cmd_info[2]
    create_cmd(cmd, function(opts)
      local cmdstr = string.lower(cmd)
      local autoclose
      if vim.tbl_contains({ 'gd' }, cmdstr) then
        autoclose = false
      else
        autoclose = true
      end
      if opts and opts.fargs and #opts.fargs > 0 then
        for _, arg in ipairs(opts.fargs) do
          cmdstr = cmdstr .. ' ' .. arg
        end
      end
      if cmdstr:find('ga') and opts.bang then
        -- allow bang
        ga_bang(opts)
        return
      end

      local sh = vim.o.shell
      if _FORGIT_CFG.shell_mode and (sh:find('zsh') or sh:find('bash')) then
        log('cmd: ' .. cmdstr)
        cmdstr = sh .. ' -i -c ' .. cmdstr
      end
      local term = require('forgit.term').run
      log(cmdstr)
      term({ cmd = cmdstr, autoclose = autoclose })
    end, { nargs = '*', bang = true, desc = 'forgit ' .. cmd_details })
  end

  require('forgit.commands').setup()
  require('forgit.list')

end


return M
