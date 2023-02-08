local M = {}

local util = require('forgit.utils')

local health = vim.health
if not vim.health then
  health = require('health')
end

local start = health.report_start
local ok = health.report_ok
local error = health.report_error
local warn = health.report_warn
local info = health.report_info
local vfn = vim.fn

local function binary_check()
  health.report_start('Binaries')
  local no_err = true
  local git_bin = 'git'
  if vfn.executable(git_bin) == 1 then
    info(git_bin .. ' installed.')
  else
    error(git_bin .. ' is not installed.')
    no_err = false
  end

  if vim.fn.system('type ga'):find('Could not') then
    no_err = false
    warn('forgit is not installed.')
  else
    info('fogit installed')
  end

  if vfn.executable('fzf') == 1 then
    info('fzf installed')
  else
    no_err = false
    warn('fzf is not installed.')
  end

  if vim.fn.exists('*fzf#run') == 1 then
    info('fzf.vim installed')
  else
    no_err = false
    warn(
      'fzf#run function not found. You also need Vim plugin from the main fzf repository (i.e. junegunn/fzf *and* fzf#install())'
    )
  end

  if vfn.executable('fd') == 1 then
    info('fd installed.')
  else
    no_err = false
    warn('fd is not installed')
  end

  if vfn.executable('delta') == 1 then
    info('delta installed.')
  else
    no_err = false
    warn('delta is not installed')
  end

  if vfn.exists('*fugitive#Command') > 0 then
    info ('git fugitive installed')
  else
    no_err = false
    warn('git fugitive is not installed')
  end

  if no_err then
    ok('All binaries installed')
  else
    warn('Some binaries are not installed, please check if your $HOME/go/bin or $GOBIN $exists and in your $PATH')
  end
end

local function plugin_check()
  start('forgit Plugin Check')

  local plugins = {
    'guihua',
  }
  local any_warn = false
  for _, plugin in ipairs(plugins) do
    local pi = util.load_module(plugin)
    if pi ~= nil then
      ok(string.format('%s: plugin is installed', plugin))
    else
      any_warn = true
      warn(string.format('%s: not installed/loaded', plugin))
    end
  end
  if any_warn then
    warn('Not all plugin installed')
  else
    ok('All plugin installed')
  end
end

function M.check()
  binary_check()
  plugin_check()
end

return M
