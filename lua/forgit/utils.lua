local utils = {}

local os_name = vim.loop.os_uname().sysname
local is_windows = os_name == 'Windows' or os_name == 'Windows_NT'
function utils.sep()
  if is_windows then
    return '\\'
  end
  return '/'
end

function utils.load_plugin(name, modulename)
  assert(name ~= nil, 'plugin should not empty')
  modulename = modulename or name
  local has, plugin = pcall(require, modulename)
  if has then
    return plugin
  end
  if packer_plugins ~= nil then
    -- packer installed
    local loader = require('packer').loader
    if not packer_plugins[name] or not packer_plugins[name].loaded then
      loader(name)
    end
  else
    vim.cmd('packadd ' .. name) -- load with default
  end

  has, plugin = pcall(require, modulename)
  if not has then
    utils.warn('plugin failed to load ' .. name)
  end
  return plugin
end

function utils.warn(msg)
  vim.api.nvim_echo({ { 'WRN: ' .. msg, 'WarningMsg' } }, true, {})
end

function utils.error(msg)
  vim.api.nvim_echo({ { 'ERR: ' .. msg, 'ErrorMsg' } }, true, {})
end

function utils.info(msg)
  vim.api.nvim_echo({ { 'Info: ' .. msg } }, true, {})
end
local function path_join(...)
  return table.concat(vim.tbl_flatten({ ... }), utils.sep())
end

local log = function(...)
  local arg = { ... }
  local str = 'שׁ '
  local lineinfo = ''

  local info = debug.getinfo(2, 'Sl')
  lineinfo = info.short_src .. ':' .. info.currentline
  str = string.format('%s %s %s:', str, lineinfo, os.date('%H:%M:%S'))
  str = str .. ' dir: ' .. vim.fn.getcwd()

  for i, v in ipairs(arg) do
    if type(v) == 'table' then
      str = str .. ' |' .. tostring(i) .. ': ' .. vim.inspect(v) .. '\n'
    else
      str = str .. ' |' .. tostring(i) .. ': ' .. tostring(v)
    end
  end
  local log_path = _FORGIT_CFG.log_path or path_join(vim.fn.stdpath('cache'), 'forgit.log')
  if #str > 2 then
    if log_path ~= nil and #log_path > 3 then
      local f = io.open(log_path, 'a+')
      if f == nil then
        print('not found or failed to open ', log_path)
        return
      end
      io.output(f)
      io.write(str .. '\n')
      io.close(f)
    else
      print(str .. '\n')
    end
  end
end

utils.log = function(...)
  if _FORGIT_CFG.debug then
    log(...)
  end
end

return utils
