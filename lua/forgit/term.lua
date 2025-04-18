local utils = require('forgit.utils')
local api = vim.api
local guihua_term = utils.load_module('guihua.lua', 'guihua.floating')
if not guihua_term then
  utils.warn('guihua not installed, please install ray-x/guihua.lua for GUI functions')
end

local term_name = 'forgit_floaterm'

local function close_float_terminal(code, data)
  local has_var, float_term_win = pcall(api.nvim_buf_get_var, 0, term_name)
  if not has_var or not float_term_win then
    return
  end
  api.nvim_buf_set_var(0, term_name, nil)
  if float_term_win[1] ~= nil and api.nvim_buf_is_valid(float_term_win[1]) then
    api.nvim_buf_delete(float_term_win[1], { force = true })
  end
  if float_term_win[2] ~= nil and api.nvim_win_is_valid(float_term_win[2]) then
    api.nvim_win_close(float_term_win[2], true)
  end
  if code or data then
    vim.notify(vim.inspect(code) .. vim.inspect(data), vim.log.levels.DEBUG)
  end
end

local term = function(opts)
  opts.term_name = term_name
  _FORGIT_CFG = _FORGIT_CFG or {} -- supress luacheck warning
  opts.vsplit = _FORGIT_CFG.vsplit
  opts.height_ratio = _FORGIT_CFG.height_ratio
  opts.width_ratio = _FORGIT_CFG.width_ratio
  opts.title = opts.title or opts.cmd
  opts.closer = function(c, d)
    if d ~= 0 then
      local msg =
        string.format('Error: %s jobid: %s exit code: %s', opts.cmd, vim.inspect(c), vim.inspect(d))
      vim.notify(msg, vim.log.levels.DEBUG)
    end
  end
  utils.log(opts)
  return guihua_term.gui_term(opts)
end

-- term({ cmd = 'echo abddeefsfsafd', autoclose = false })
-- term({ cmd = 'lazygit', autoclose = true })
-- term({ cmd = {'lazygit'}, autoclose = true })

-- term({ cmd = 'git diff --', autoclose = false })
-- term({ cmd = 'git-forgit add', autoclose = false })
-- term({ cmd = 'git show', autoclose = false })
-- term({ cmd = { 'bash', '-i', '-c', 'git-forgit add' }, autoclose = false })
return { run = term, close = close_float_terminal }
