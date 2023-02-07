local term = require('forgit.term').run
local create_cmd = function(cmd, func, opt)
  opt = vim.tbl_extend('force', { desc = 'git command alias ' .. cmd }, opt or {})
  vim.api.nvim_create_user_command(cmd, func, opt)
end
_FORGIT_CFG = _FORGIT_CFG or {} -- supress warnings
local utils = require('forgit.utils')
local log = utils.log
local M = {}
local cmds
local function fugitive_installed()
  vim.cmd('packadd vim-fugitive')
  return vim.fn.exists('*fugitive#Command') > 0
end

local commit_input = function(args)
  local cmdstr = ''
  local need_input = true
  if args then
    for i, arg in ipairs(args) do
      if arg == '-m' and args[i + 1] then
        need_input = false
      end
      cmdstr = cmdstr .. ' ' .. arg
    end
  end
  if not need_input then
    return vim.cmd('silent !git commit ' .. cmdstr)
  end
  -- center pos
  local r, c = require('guihua.location').center(1, 60)
  require('guihua.input').input(
    { prompt = 'commit message: ', width = 40, relative = 'editor', row = r, col = c },
    function(message)
      if message == nil then
        return
      end
      message = message:gsub('"', '\\"')
      vim.cmd('silent !git commit ' .. ' -m "' .. message .. '"')
    end
  )
end

local function use_fugitive()
  return _FORGIT_CFG.fugitive and fugitive_installed()
end

local function diff(cmd, args)
  local _, e = cmd:find('diff')
  local remain = cmd:sub(e + 1)
  if vim.fn.empty(_FORGIT_CFG.diff_cmd) == 0 then
    -- if configed, use configed diff cmd
    return vim.cmd(_FORGIT_CFG.diff_cmd .. ' ' .. remain .. table.concat(args, ' '))
  end
  if vim.fn.exists(':DiffviewOpen') > 0 then
    vim.cmd('DiffviewOpen ' .. remain .. ' ' .. table.concat(args, ' '))
  elseif use_fugitive() then
    vim.cmd('Gvdiffsplit ' .. remain .. ' ' .. table.concat(args, ' '))
  else
    vim.cmd('silent !git diff ' .. remain .. ' ' .. table.concat(args, ' '))
  end
end

function M.setup()
  local git = '' -- leading? delay the eval for lazyloading

  cmds = {
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
    Gcef = git .. ' clean -fd',
    Gcl = git .. ' clone {url}',
    Gdf = git .. ' diff --',
    Gdnw = git .. ' diff -w --',
    Gdw = git .. ' diff --word-diff',
    Gf = git .. ' fetch',
    Gfa = git .. ' fetch --all',
    Gfr = {
      cmd = git .. ' fetch; and git rebase',
      fcmd = 'Gf | Gr',
      close_on_exit = false,
      qf = false,
    }, -- Gf | Gr
    Glg = git
      .. " log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all",
    Gm = git .. ' merge',
    Gmff = git .. ' merge --ff',
    Gmnff = git .. ' merge --no-ff',
    Gpl = git .. ' pull',
    Gplr = git .. ' pull --rebase',
    Gps = git .. ' push',
    Gpsf = git .. ' push --force-with-lease',
    Gr = git .. ' remote -v',
    Grb = git .. ' rebase',
    Grbi = git .. ' rebase -i',
    Grbc = git .. ' rebase --continue',
    Grba = git .. ' rebase --abort',
    Grs = git .. ' reset --',
    Grsh = git .. ' reset --hard',
    Grsl = git .. ' reset HEAD~',
    Gsh = git .. ' show',
    Gt = git .. ' tag',
    Gtop = git .. ' rev-parse --show-toplevel',
    Gurl = git .. ' config --get remote.origin.url',
  }
  M.cmdlst = {}

  if _FORGIT_CFG.git_alias == false then
    cmds = {}
  end

  for name, cmd in pairs(cmds) do
    M.cmdlst[name] = cmd
    create_cmd(name, function(opts)
      local cmdstr = cmd
      local f = use_fugitive()
      if type(cmd) == 'table' then
        if f then
          cmdstr = cmd.fcmd
        else
          cmdstr = cmd.cmd
        end
      end

      if
        type(cmd) == 'string' and cmd:find('diff')
        or (type(cmd) == 'table' and cmd.cmd:find('diff'))
      then
        return diff(cmdstr, opts.fargs)
      end
      if f then
        git = 'Git'
      else
        git = 'git'
      end
      cmdstr = git .. cmdstr -- here is the place to assign Git/!git

      if cmdstr:find('commit') and not use_fugitive() and (not cmdstr:find('graph')) then
        return commit_input(opts.fargs)
      end
      if vim.fn.empty(opts.fargs) == 0 then
        for _, arg in ipairs(opts.fargs) do
          cmdstr = cmdstr .. ' ' .. arg
          log(cmdstr)
        end
      end

      if f then
        vim.cmd(cmdstr)
      else
        if
          type(cmd) == 'string' and (cmd:find('fzf') or cmd:find('log') or cmd:find('show'))
          or (type(cmd) == 'table' and cmd.qf == false)
        then
          term({ cmd = cmdstr, autoclose = false })
        else
          local lines = vim.fn.systemlist(vim.split(cmdstr, ' '))
          if _FORGIT_CFG.show_result == 'quickfix' then
            if #lines > 0 then
              vim.fn.setqflist({}, 'a', { title = cmdstr, lines = lines })
              vim.cmd('copen')
            end
          else
            vim.notify(table.concat(lines, '\n'))
          end
        end
      end

      log(cmdstr)
      vim.notify(cmdstr)
    end, {
      nargs = '*',
      desc = 'forgit command alias ' .. vim.inspect(cmd),
      complete = function(a, l, p)
        if vim.fn.exists('*fugitive#EditComplete') > 0 then
          return vim.fn['fugitive#EditComplete'](a, l, p)
        else
          local files = vim.fn.systemlist('git diff --name-only')

          return files
        end
      end,
    })
  end

  local function diff_prev()
    local diff_str = ''
    local w = math.floor(vim.o.columns * 0.60)
    if _FORGIT_CFG.diff_pager == 'delta' then
      diff_str = '|delta --side-by-side -w ' .. tostring(w)
      if vim.fn.executable('delta') == 0 then
        diff_str = ''
      end
    else
      diff_str = '|' .. _FORGIT_CFG.diff_pager
    end
    return diff_str
  end

  -- other commmands
  -- git diff master/main --name-only

  -- git add and commit
  create_cmd('Gam', function(opts)
    local cmdstr = 'ga'
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmdstr = cmdstr .. ' ' .. arg
      end
    end
    local sh = vim.o.shell
    if _FORGIT_CFG.shell_mode and (sh:find('zsh') or sh:find('bash')) then
      log('cmd: ' .. cmdstr)
      cmdstr = sh .. ' -i -c ' .. cmdstr
    end
    log(cmdstr)
    term({
      cmd = cmdstr,
      autoclose = true,
      on_exit = function(c, d, v)
        print(c, d, v)
        if d == 0 then
          if use_fugitive then
            vim.cmd('Git commit')
          else
            commit_input()
          end
        end
      end,
    })
  end, { nargs = '*', desc = 'forgit ga & commit' })

  M.cmdlst.Gam = 'forgit ga & commit'

  create_cmd('Gdl', function(opts)
    local master = vim.fn.system('git rev-parse --abbrev-ref master')
    if master:find('fatal') then
      master = 'main'
    else
      master = 'master'
    end

    local cmd = 'git diff --name-only'
    if opts.bang then
      cmd = string.format('git diff %s --name-only', master)
    end

    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end

    log(cmd)
    cmd = vim.split(cmd, ' ')
    print(vim.inspect(cmd))

    local preview_cmd = [[--preview-window "right,70%" --preview "git diff ]] .. diff_prev() .. '"'
    local fzf = require('forgit.fzf').run
    fzf(cmd, function(line)
      vim.cmd('edit ' .. line)
    end, preview_cmd)
  end, { nargs = '*', bang = true, desc = 'forgit: git diff --name-only & open file' })

  M.cmdlst.Gdl = 'git diff --name-only && open'

  create_cmd('Gbs', function(opts)
    local cmd = 'git branch --sort=-committerdate'
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end
    cmd = vim.split(cmd, ' ')
    local fzf = require('forgit.fzf').run
    local preview_cmd = [[--preview-window "right,72%" --preview "echo {} | xargs git diff ]]
      .. diff_prev()
      .. '"'
    fzf(cmd, function(line)
      print(vim.fn.system('git checkout ' .. line))
    end, preview_cmd)
  end, { nargs = '*' })

  M.cmdlst.Gbs = 'git branch --sort=-committerdate && checkout'
  if _FORGIT_CFG.git_fuzzy == true then
    create_cmd('Gfz', function(opts)
      local cmd = 'git fuzzy'
      if opts and opts.fargs and #opts.fargs > 0 then
        for _, arg in ipairs(opts.fargs) do
          cmd = cmd .. ' ' .. arg
        end
      end

      log(cmd)
      cmd = vim.split(cmd, ' ')
      term({ cmd = cmd, autoclose = true })
    end, { nargs = '*', desc = 'git fuzzy' })
    M.cmdlst.Gfz = 'git fuzzy'
  end

  create_cmd('Gcbc', function(opts)
    local cmd = 'git branch --sort=-committerdate'
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end

    log(cmd)
    cmd = vim.split(cmd, ' ')
    local fzf = require('forgit.fzf').run
    fzf(
      cmd,
      function(line)
        print(vim.fn.system('git checkout ' .. line))
      end,
      [[--ansi --preview "git log --graph --format='%C(auto)%h%d %s %C(auto)%C(bold)%cr%Creset' {1}"]]
    )
  end, { nargs = '*', desc = 'git branch | fzf | xargs -r git co ' })

  M.cmdlst.Gcbc = 'git branch --sort=-committerdate && checkout'
  create_cmd('Gdc', function(opts)
    local sh = vim.o.shell

    local cmd = [[hash=$(git log  --graph --format='%C(auto)%h%d %s %C(auto)%C(bold)%cr%Creset' | fzf | grep -Eo '[a-f0-9]+' | head -1 | tr -d '[:space:]'); git diff $hash --name-only|fzf -m --ansi  --preview-window "right,75%"  --preview "git diff $hash --color=always -- {-1}]]
      .. diff_prev()
      .. '"'
      .. '|xargs -r git difftool $hash'
    if sh:find('fish') then
      cmd = [[set hash $(git log  --graph --format='%C(auto)%h%d %s %C(auto)%C(bold)%cr%Creset' | fzf | grep -Eo '[a-f0-9]+' | head -1 | tr -d '[:space:]') ; git diff $hash --name-only|fzf -m --ansi  --preview-window "right,75%"  --preview "git diff $hash --color=always -- {-1}]]
        .. diff_prev()
        .. '"'
        .. '|xargs -r git difftool $hash'
    end
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end

    log(cmd)
    term({ cmd = cmd, autoclose = true })
  end, { nargs = '*', desc = 'git log | fzf | xargs git difftool' })

  M.cmdlst.Gdc = 'git log | fzf | xargs git difftool'

  create_cmd('Gbdo', function(opts)
    local cmd = [[git branch]]

    if opts.bang then
      cmd = cmd .. ' -r'
    end
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end
    -- cmd = vim.split(cmd, ' ')
    local fzf = require('forgit.fzf').run
    log(cmd)
    fzf(
      cmd,
      function(line)
        print(line)
        if line:sub(1, 1) == '*' then
          -- no need to compare current branch
          return
        end
        local cmdstr = 'DiffviewOpen ' .. line
        log(cmdstr)
        vim.cmd(cmdstr)
      end,
      [[--ansi --preview "git log --graph --format='%C(auto)%h%d %s %C(auto)%C(bold)%cr%Creset' {1}"]]
    )
  end, { nargs = '*', bang = true, desc = 'select hash and diff file/(all!) with DiffviewOpen' })

  M.cmdlst.Gbdo = 'select hash and diff file/(all!) with DiffviewOpen'
  create_cmd('Gldo', function(opts)
    local cmd = [[git log  --graph --format='%C(auto)%h%d %s %C(auto)%C(bold)%cr%Creset']]
    if not opts.bang then
      cmd = cmd .. ' ' .. vim.fn.expand('%')
    end

    local preview_cmd = [[--preview-window "right,62%" --preview "echo {} | grep -Eo '[a-f0-9]+' | head -1 | tr -d '[:space:]' | xargs -I% git show --color=always -U$_forgit_preview_context % -- $(sed -nE 's/.* -- (.*)/\1/p' <<< "$*") ]]
      .. diff_prev()
      .. '"'

    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end
    -- cmd = vim.split(cmd, ' ')
    local fzf = require('forgit.fzf').run
    log(cmd)
    fzf(cmd, function(line)
      print(line)
      local hex = vim.regex([[[0-9a-fA-F]\+]])
      hex:match_str(line)
      local b, e = hex:match_str(line)
      if b and e then
        local hash = line:sub(b, e)
        local cmdstr = 'DiffviewOpen ' .. hash
        if not opts.bang then
          cmdstr = cmdstr .. ' -- ' .. vim.fn.expand('%')
        end
        log(cmdstr)
        vim.cmd(cmdstr)
      end
    end, preview_cmd)
  end, { nargs = '*', bang = true, desc = 'select hash and diff file/(all!) with DiffviewOpen' })

  M.cmdlst.Gldo = 'select hash and diff file/(all!) with DiffviewOpen'

  -- git log diff tool
  create_cmd('Gldt', function(opts)
    local sh = vim.o.shell

    local diff = diff_prev()

    local cmd = [[$(git log  --graph --format='%C(auto)%h%d %s %C(auto)%C(bold)%cr%Creset' | fzf | grep -Eo '[a-f0-9]+' | head -1 | tr -d '[:space:]'); git diff $hash --name-only|fzf -m --ansi --preview-window "right,72%" --preview "git diff $hash --color=always -- {-1}]]
      .. diff
      .. '"'
      .. '| xargs git difftool $hash'
    if sh:find('fish') then
      cmd = [[set hash ]] .. cmd
    else
      cmd = [[hash=]] .. cmd
    end
    if not opts.bang then
      cmd = cmd .. ' -- ' .. vim.fn.expand('%')
    end
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = cmd .. ' ' .. arg
      end
    end

    log(cmd)
    term({ cmd = cmd, autoclose = true })
  end, {
    nargs = '*',
    bang = true,
    desc = 'git log | diff | fzf | xargs git difftool <hash> file name/all(!)',
  })
  M.cmdlst.Gldt = 'git log | diff | fzf | xargs git difftool <hash> file name/all(!)'

  local grep_input = function(cmdstr)
    -- center pos
    local r, c = require('guihua.location').center(1, 60)
    require('guihua.input').input(
      { prompt = 'grep message: ', width = 40, relative = 'editor', row = r, col = c },
      function(message)
        if message == nil then
          return
        end
        message = message:gsub('"', '\\"')

        cmdstr = string.format(cmdstr, message)

        log(cmdstr)
        local fzf = require('forgit.fzf').run
        fzf(cmdstr, function(line)
          local s, e = line:find('(%w+):([%w_%./\\]+)')
          if s then
            term({ cmd = 'git show ' .. line:sub(s, e) })
          end
        end)
      end
    )
  end

  M.cmdlst.Grlg = 'find git commit by git grep and show file on that version'
  -- git log diff tool
  create_cmd('Grlg', function(opts)
    local cmd = [[git  rev-list --all | xargs git grep -F %s ]]
    if opts and opts.fargs and #opts.fargs > 0 then
      for _, arg in ipairs(opts.fargs) do
        cmd = string.format(cmd, arg)
        log(cmd)
        -- local preview = [[--delimiter=:  --preview "echo  {1}:{2} | xargs git show"]]
        local preview = [[--delimiter=:"]]
        local fzf = require('forgit.fzf').run
        return fzf(cmd, function(line)
          log(line)
          local s, e = line:find('(%w+):([%w_%./\\]+)')
          if s then
            term({ cmd = 'git show ' .. line:sub(s, e) })
          end
        end, preview)
      end
    else
      grep_input(cmd)
    end
  end, {
    nargs = '*',
    bang = true,
    desc = 'git rev-list | xargs git grep keywoard',
  })

  vim.api.nvim_create_user_command(
    'Forgit',
    'lua require("forgit.list").git_cmds()',
    { nargs = '*' }
  )

  M.cmdlst.Gs = 'git status'
  M.cmds = function()
    return M.cmdlst
  end
end
-- term({ cmd = 'git diff --', autoclose = false })

return M
