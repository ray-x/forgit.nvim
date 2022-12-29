--
local git = '!git'
if _FORGIT_CFG.fugitive then
  git = 'Git'
end
local cmds = {
  Gaa = git .. [[ add --all]],
  Gap = git .. ' add -pu',
  Gs = git .. ' stash',
  Gsa = git .. ' stash apply',
  -- Gsl = git .. ' stash list', gss
  Gspop = git .. ' stash pop',
  Gsu = git .. ' stash --include-untracked',
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

local create_cmd = function(cmd, func, opt)
  opt = vim.tbl_extend('force', { desc = 'git command alias ' .. cmd }, opt or {})
  vim.api.nvim_create_user_command(cmd, func, opt)
end

for name, cmd in pairs(cmds) do
  create_cmd(name, function(opts)
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end
    -- lprint(cmd)
    vim.cmd(cmd)
    vim.notify(cmd)
  end, { nargs = '*' })
end
