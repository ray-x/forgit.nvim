local M = {}
local vfn = vim.fn
M.run = function(cmd, sink, opts)
  local wrap_opts = {
    source = vim.fn.systemlist(cmd),
    sink = sink,
  }
  if opts then
    wrap_opts.options = opts
  end

  vfn['fzf#run'](vfn['fzf#wrap'](wrap_opts))
end

return M
