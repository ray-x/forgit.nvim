local utils = {}

local os_name = vim.loop.os_uname().sysname
local is_windows = os_name == 'Windows' or os_name == 'Windows_NT'
function utils.sep()
  if is_windows then
    return '\\'
  end
  return '/'
end


function utils.load_plugin(name)
  local has, loader = pcall(require, 'packer')
  if has and packer_plugins ~= nil then
    pcall(loader.loader, name)
  else
    local lz
    has, lz = pcall(require, 'lazy')
    if has and lz then
      -- lazy installed
      pcall(lz.loader, name)
    end
  end
  -- nothing I can do, packadd
end

function utils.load_module(name, modulename)
  assert(name ~= nil, 'plugin should not empty')
  modulename = modulename or name
  local has, plugin = pcall(require, modulename)
  if has then
    return plugin
  end
  utils.load_plugin(name)

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

utils.log = function(...)
  if _FORGIT_CFG.debug then
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
end

return utils
