local M = {}
local sep = vim.loop.os_uname().sysname == 'Windows' and '\\' or '/'
local vfn = vim.fn
M.run = function(cmd, sink)
  local wrapped = vfn['fzf#wrap']({
    source = vim.fn.systemlist(cmd),
    options = {},
    sink = sink,
  })

  vfn['fzf#run'](wrapped)
end

return M
