local function fugitive_enabled()
  if _FORGIT_CFG.fugitive == false then
    return false
  end
  vim.cmd('packadd vim-fugitive')
  return vim.fn.exists('*fugitive#Command') > 0
end

local function gitsigns_enabled()
  if _FORGIT_CFG.gitsigns == false then
    return false
  end
  vim.cmd('packadd gitsigns.nvim')
  local ok = pcall(require, 'gitsigns')
  return ok ~= nil
end
local function flog_enabled()
  if _FORGIT_CFG.flog == true then
    vim.cmd('packadd vim-flog')
    return vim.fn.exists('*flog#cmd#Flog') > 0
  end
  return false
end

local fg = {
  { cmd = 'Git', text = 'Git {args} | Run an arbitrary git command and display any output.' },
  {
    cmd = 'Git',
    text = 'Git! {args} | Run an arbitrary git command in the background and stream the output to the preview window.',
  },
  {
    cmd = 'Git -p',
    text = 'Git --paginate {args} | Run an arbitrary git command, capture output to a temp file',
  },
  {
    cmd = '1,10Git -p',
    text = '{range}Git! --paginate {args} | Run an arbitrary git command, and insert the output after {range} in the current buffer.',
  },
  {
    cmd = 'Git blame',
    text = 'Git blame [flags] | Run git-blame [flags] on the current file and open the results in a scroll-bound vertical split.',
  },
  {
    cmd = 'Gclog',
    text = 'Gclog | Use git-log [args] to load the commit history into the |quickfix| list.',
  },
  {
    cmd = '1,10Gclog',
    text = '{range}Gclog | Use git-log -L to load previous revisions of the given range of the current file into the |quickfix| list.',
  },
  {
    cmd = 'Git difftool',
    text = 'Git[!] difftool [args] | Invoke `git diff [args]` and load the changes into the quickfix list.',
  },
  {
    cmd = 'Git mergetool',
    text = 'Git mergetool [args] | Like |:Git_difftool|, but target merge conflicts.',
  },
  {
    cmd = 'Gllog',
    text = 'Gllog |  Like |:Gclog|, but use the location list instead of the |quickfix| list',
  },
  { cmd = 'Gcd', text = 'Gcd [directory] | :cd relative to the repository.' },
  { cmd = 'Glcd', text = 'Glcd [directory] | :lcd relative to the repository.' },
  { cmd = 'Gedit', text = 'Gedit [object] | :edit a |fugitive-object|.' },
  { cmd = 'Gsplit', text = 'Gsplit [object] | :split a |fugitive-object|.' },
  { cmd = 'Gvsplit', text = 'Gvsplit [object] | :vsplit a |fugitive-object|.local' },
  { cmd = 'Gtabedit', text = 'Gtabedit [object] | :tabedit| a |fugitive-object|.' },
  { cmd = 'Gpedit', text = 'Gpedit [object] | :pedit a |fugitive-object|.' },
  { cmd = 'Gdrop', text = 'Gdrop [object] | :drop a |fugitive-object|.' },
  { cmd = 'Gread', text = 'Gread [object] | Empty the buffer and |:read| a |fugitive-object|.' },
  { cmd = '1,10Gread', text = '{range} Gread | :read in a |fugitive-object| after {range}.' },
  { cmd = 'Gwrite', text = 'Gwrite | Write to the path of current file and stage the results.' },
  {
    cmd = 'Gwrite',
    text = 'Gwrite {path} | You can give |:Gwrite| an explicit path of where in the work tree to write.',
  },
  {
    cmd = 'Gwq',
    text = 'Gwq[!] [path] | Like |:Gwrite| followed by |:quit| if the write succeeded.',
  },
  {
    cmd = 'Gdiffsplit',
    text = 'Gdiffsplit [object] | Perform a |vimdiff| against the given file, or if a commit is given, the current file in that commit.',
  },
  {
    cmd = 'Gdiffsplit!',
    text = 'Gdiffsplit! {object}| Diff against any and all direct ancestors, retaining focus on the current window.',
  },
  {
    cmd = 'Gvdiffsplit',
    text = 'Gvdiffsplit [object] | Like |:Gdiffsplit|, but always split vertically. Gdiffsplit ++novertical [object]',
  },
  {
    cmd = 'Ghdiffsplit',
    text = [[Ghdiffsplit [object] | Like |:Gdiffsplit|, but with "vertical" removed from 'diffopt'.]],
  },
  {
    cmd = 'GMove',
    text = 'GMove {destination} | Wrapper around git-mv that renames the buffer afterward. Add a ! to pass -f.',
  },
  {
    cmd = 'GRename',
    text = 'GRename {destination} | Like |:GMove| but operates relative to the parent directory of the current file.',
  },
  {
    cmd = 'GDelete',
    text = 'GDelete | Wrapper around git-rm that deletes the buffer afterward. ',
  },
  { cmd = 'GRemove', text = 'GRemove | Like |:GDelete|, but keep the (now empty) buffer around.' },
  { cmd = 'GUnlink', text = 'GUnlink same as :GRemove' },
  {
    cmd = 'GBrowse',
    text = 'GBrowse | Open the current file, blob, tree, commit, or tag in your browser at the upstream hosting provider.',
  },
  {
    cmd = 'GBrowse',
    text = 'GBrowse {object} | Like :GBrowse, but for a given |fugitive-object|.',
  },
  {
    cmd = '1,10GBrowse',
    text = '{range}Gbrowse [args] | Appends an anchor to the URL that emphasizes the selected lines.',
  },
  {
    cmd = 'GBrowse',
    text = 'GBrowse [...]@{remote} | Force using the given remote rather than the remote for the current branch. ',
  },
  { cmd = 'GBrowse', text = 'GBrowse {url} Open an arbitrary URL in your browser.' },
  {
    cmd = '1,10GBrowse!',
    text = ':[range]GBrowse! | [args] Like :GBrowse, but put the URL on the clipboard rather than opening it.',
  },
}

local gs = {
  { text = 'gitsigns stage_hunk', cmd = 'Gitsigns stage_hunk' },
  { text = 'gitsigns undo_stage_hunk', cmd = 'Gitsigns undo_stage_hunk' },
  { text = 'gitsigns reset_hunk', cmd = 'Gitsigns reset_hunk' },
  { text = 'gitsigns stage_buffer', cmd = 'Gitsigns stage_buffer' },
  { text = 'gitsigns reset_buffer', cmd = 'Gitsigns reset_buffer' },
  { text = 'gitsigns reset_buffer_index', cmd = 'Gitsigns reset_buffer_index' },
  { text = 'gitsigns prev_hunk', cmd = 'Gitsigns prev_hunk' },
  { text = 'gitsigns preview_hunk', cmd = 'Gitsigns preview_hunk' },
  { text = 'gitsigns preview_hunk_inline', cmd = 'Gitsigns preview_hunk_inline' },
  { text = 'gitsigns select_hunk', cmd = 'Gitsigns select_hunk' },
  { text = 'gitsigns get_hunks', cmd = 'Gitsigns get_hunks' },
  { text = 'gitsigns blame_line', cmd = 'Gitsigns blame_line' },
  { text = 'gitsigns change_base', cmd = 'Gitsigns change_base' },
  { text = 'gitsigns reset_base', cmd = 'Gitsigns reset_base' },
  { text = 'gitsigns diffthis', cmd = 'Gitsigns diffthis' },
  { text = 'gitsigns show', cmd = 'Gitsigns show' },
  { text = 'gitsigns setqflist', cmd = 'Gitsigns setqflist' },
  { text = 'gitsigns setloclist', cmd = 'Gitsigns setloclist' },
  { text = 'gitsigns get_actions', cmd = 'Gitsigns get_actions' },
  { text = 'gitsigns refresh', cmd = 'Gitsigns refresh' },
  { text = 'gitsigns toggle_signs', cmd = 'Gitsigns toggle_signs' },
  { text = 'gitsigns toggle_numhl', cmd = 'Gitsigns toggle_numhl' },
  { text = 'gitsigns toggle_linehl', cmd = 'Gitsigns toggle_linehl' },
  { text = 'gitsigns toggle_word_diff', cmd = 'Gitsigns toggle_word_diff' },
  { text = 'gitsigns toggle_current_line_blame', cmd = 'Gitsigns toggle_current_line_blame' },
  { text = 'gitsigns toggle_deleted', cmd = 'Gitsigns toggle_deleted' },
}

local flog = {
  {
    cmd = 'Flog -date=short',
    text = [[Flog | A branch viewer Open Flog in a new tab, showing the git branch graph. options: -biset -merges -reflog -reverse -patch -auther= -date= -format= -limit= -max-count= -order= -skip= -grep- -patch-grep- -rev= -path= -open-cmd= -raw-args= --]],
  },
  {
    cmd = 'Floggit -date=short',
    text = 'Floggit | Open a git command via |:Git| using |flog#Exec()|. All arguments supported by |:Git| are supported.',
  },
  { cmd = 'Floggit!  -date=short', text = 'Floggit! | Same as |:Floggit|, but use |:Git!|.' },
  {
    cmd = 'Floggit --focus',
    text = 'Floggit --focus Instead of returning focus to the |:Flog| window after running the command,  retain focus.',
  },
  {
    cmd = 'Floggit --static -date=short',
    text = 'Floggit --static | Prevent updating |:Flog| after running the command.',
  },
  {
    cmd = 'Floggit --tmp -date=short',
    text = 'Floggit --tmp | Any windows will run in a temporary |flog-side-window|.',
  },
  {
    cmd = 'Flogsetargs[!]',
    text = 'Flogsetargs | Update the arguments passed to |:Flog| or |:Flogsplit|. Can only be run in a |:Flog| window. Merges new arguments with the current arguments. bang to override default arugments',
  },
  {
    cmd = 'Flogsplitcommit',
    text = 'Flogsplitcommit | Open a commit under the cursor using |:Gsplit| in a |flog-temp-window|. Can only be run in the |:Flog| window.',
  },
}

local function git_cmds()
  local cmdlst = require('forgit.commands').cmds()

  local data = {}
  for k, v in pairs(cmdlst) do
    table.insert(data, { k, v })
  end

  vim.list_extend(data, require('forgit').cmds)
  local view_data = {}
  for _, v in ipairs(data) do
    local txt = v[2]
    if type(v[2]) == 'function' then
      txt = v[2]()
    elseif type(v[2]) == 'table' then
      txt = v[2].cmd
    end
    table.insert(view_data, { text = v[1] .. '\t| ' .. txt, cmd = v[1] })
  end
  if gitsigns_enabled() then
    vim.list_extend(view_data, gs)
  end
  if fugitive_enabled() then
    for _, v in ipairs(fg) do
      table.insert(view_data, {
        text = v.text,
        cmd = function()
          vim.fn.feedkeys(':' .. v.cmd, 'ni')
        end,
      })
    end
  end
  if flog_enabled() then
    for _, v in ipairs(flog) do
      table.insert(view_data, {
        text = v.text,
        cmd = function()
          vim.fn.feedkeys(':' .. v.cmd, 'ni')
        end,
      })
    end
  end

  if vim.fn.empty(_FORGIT_CFG.cmds_list) == 0 then
    vim.list.extend(view_data, _FORGIT_CFG.cmds_list)
  end
  local lsview = require('guihua.listview')
  local win = lsview:new({
    loc = 'top_center',
    border = 'single',
    prompt = true,
    enter = true,
    wrap = true,
    rect = { height = 20, width = 60 },
    data = view_data,
    on_confirm = function(item)
      if type(item.cmd) == 'function' then
        return item.cmd()
      else
        vim.cmd(item.cmd)
      end
    end,
  })
  vim.api.nvim_win_set_option(win.win, 'wrap', true)

  -- one command to rule them all
end
return { git_cmds = git_cmds }
