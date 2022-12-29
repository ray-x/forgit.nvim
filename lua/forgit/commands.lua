--

local create_cmd = function(cmd, func, opt)
  opt = vim.tbl_extend('force', { desc = 'git command alias ' .. cmd }, opt or {})
  vim.api.nvim_create_user_command(cmd, func, opt)
end

local function setup()
  local git = 'git'
  if _FORGIT_CFG.fugitive then
    git = 'Git'
  end
  local cmds = {
    Gaa = git .. [[ add --all]],
    Gap = git .. ' add -pu',
    Gs = { cmd = git .. ' status', fcmd = 'Git', close_on_exit = false },
    Gash = git .. ' stash',
    Gasha = git .. ' stash apply',
    Gashl = git .. ' stash list',
    Gashp = git .. ' stash pop',
    Gashu = git .. ' stash --include-untracked',
    Gau = git .. ' add -u',
    Gc = git .. ' commit',
    Gce = git .. ' clean',
    GcB = git .. ' checkout -b',
    Gcef = git .. ' clean -fd',
    Gcl = git .. ' clone',
    Gcm = git .. ' commit -m',
    Gdf = git .. ' diff --',
    Gdnw = git .. ' diff -w --',
    Gdw = git .. ' diff --word-diff',
    Gf = git .. ' fetch',
    Gfa = git .. ' fetch --all',
    Gfr = git .. ' fetch; and git rebase',
    Glg = git .. ' log --graph --max-count=5',
    Gm = git .. ' merge',
    Gmff = git .. ' merge --ff',
    Gmnff = git .. ' merge --no-ff',
    Gopen = git .. ' config --get remote.origin.url | xargs open',
    Gpl = git .. ' pull',
    Gplr = git .. ' pull --rebase',
    Gps = git .. ' push',
    Gpsf = git .. ' push --force-with-lease',
    Gr = git .. ' remote -v',
    Grb = git .. ' rebase',
    Grbi = git .. ' rebase -i',
    Grs = git .. ' reset --',
    Grsh = git .. ' reset --hard',
    Grsl = git .. ' reset HEAD~',
    Gsh = git .. ' show',
    Gt = git .. ' tag',
    Gtop = git .. ' rev-parse --show-toplevel',
    Gurl = git .. ' config --get remote.origin.url',
  }
  for name, cmd in pairs(cmds) do
    local cmdstr = cmd
    if type(cmd) == 'table' then
      if _FORGIT_CFG.fugitive then
        cmdstr = cmd.fcmd
      else
        cmdstr = cmd.cmd
      end
    end
    create_cmd(name, function(opts)
      if opts and opts.fargs and #opts.fargs > 0 then
        for _, arg in ipairs(opts.fargs) do
          cmdstr = cmdstr .. ' ' .. arg
        end
      end
      if _FORGIT_CFG.fugitive then
        vim.cmd(cmdstr)
      else
        local lines = vim.fn.systemlist(vim.split(cmdstr, ' '))
        if _FORGIT_CFG.show_result == 'quickfix' then
          vim.fn.setqflist({}, 'a', { title = 'cmd', lines = lines })
          vim.cmd('copen')
        else
          vim.notify(table.concat(lines, '\n'))
        end
      end
      vim.notify(cmdstr)
    end, { nargs = '*' })
  end
end

return {
  setup = setup,
}
