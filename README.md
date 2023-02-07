# forgit.nvim

Interactive git commands with fzf.

This plug is a wrapper of interactive git commands
 * [forgit](https://github.com/wfxr/forgit) by `Wenxuan Zhang`
 * [git-fuzzy](htps://github.com/bigH/git-fuzzy)
 * 42 git commands alias
 * integrated with [diffview.nvim](https://github.com/sindrets/diffview.nvim)
 * Wraps vim-fugitive commands
 * Up to 100 git commands / alias supported

You need

- [install forgit](https://github.com/wfxr/forgit)
- [fzf](https://github.com/junegunn/fzf) so you can confirm/select the matches to apply your changes, also check [fzf-vim-integration](https://github.com/junegunn/fzf/blob/master/doc/fzf.txt), [as vim plugin](https://github.com/junegunn/fzf#as-vim-plugin) and [fzf README-VIM](https://github.com/junegunn/fzf/blob/master/README-VIM.md)
- install git-fuzzy (optional)
- by default the plugin using [fd](https://github.com/sharkdp/fd) to list all files in the current folder, you can use
  `git ls_file`
- a diff pager, e.g. `delta`
- vim-fugitive (highly recommended)

https://user-images.githubusercontent.com/1681295/207864539-ec65b9c4-d8a0-4509-b13f-bd2192f742d9.mp4

# install

```
Plug 'ray-x/guihua.lua'  "lua GUI lib
Plug 'ray-x/forgit.nvim'
```

# Configure

```lua
require'forgit'.setup({
  debug = false, -- enable debug logging default path is ~/.cache/nvim/forgit.log
  diff_pager = 'delta', -- you can use `diff`, `diff-so-fancy`
  diff_cmd = '', -- you can use `DiffviewOpen`, `Gvdiffsplit` or `!git diff`, auto if not set
  fugitive = false, -- git fugitive installed?
  git_alias = true,  -- git command extensions see: Git command alias
  show_result = 'quickfix', -- show cmd result in quickfix or notify

  shell_mode = true, -- set to true if you using zsh/bash and can not run forgit commands
  height_ratio = 0.6, -- height ratio of floating window when split horizontally
  width_ratio = 0.6, -- width ratio of floating window when split vertically
  cmds_list = {} -- additional commands to show in Forgit command list
  --  e.g. cmd_list = {text = 'Gs get_hunks', cmd = 'Gitsigns get_hunks'}
})
```

# Screenshot

![ga](https://user-images.githubusercontent.com/1681295/207861513-4a22c804-0e4c-46f5-92a1-f1d0c8d5e02a.jpg)

![gbd](https://user-images.githubusercontent.com/1681295/207861692-8c756b00-6e29-4e41-8fd4-dbf8b604fb7a.jpg)


# usage

- [forgit](https://github.com/wfxr/forgit) commands supported by this plugin

| Command               | Action                    |
| :-------------------: | ------------------------- |
|Ga{!}   | Interactive `git add` generator, bang! will unstage files |
|Glo     | Interactive `git log` generator |
|Gi      | Interactive .gitignore generator |
|Gd      | Interactive `git diff` viewer |
|Grh     | Interactive `git reset HEAD <file>` selector |
|Gcf     | Interactive `git checkout <file>` selector |
|Gcb     | Interactive `git checkout <branch>` selector |
|Gbd     | Interactive `git branch -D <branch>` selector |
|Gct     | Interactive `git checkout <tag>` selector |
|Gco     | Interactive `git checkout <commit>` selector |
|Grc     | Interactive `git revert <commit>` selector |
|Gss     | Interactive `git stash` viewer |
|Gsp     | Interactive `git stash push` selector |
|Gclean  | Interactive `git clean` selector |
|Gcp     | Interactive `git cherry-pick` selector |
|Grb     | Interactive `git rebase -i` selector |
|Gbl     | Interactive `git blame` selector |
|Gfu     | Interactive `git commit --fixup && git rebase -i --autosquash` selector |

- git + fzf commands supported only by this plugin

| Command               | Action                    |
| :-------------------: | ------------------------- |
|Gac   | Interactive `git add` generator, if file staged, run 'git commit' |
|Gfz     | run `git fuzzy`, sub commands supports, e.g. `Gfz status` |
|Gbc     | Interactive `git branch && checkout` generator |
|Gdl     | Interactive `git diff --name-only & edit selected file` generator |
|Gdl!    | Interactive `git diff master/main --name-only & edit selected file` generator |
|Gcbc    | Interactive `git branch --sort=-committerdate && checkout` generator, The preview is graphic view of git log|
|Gdc     | Interactive `git log commit_hash & show diff against current` generator |
|Gldt    | Interactive `git log commit_hash & difftool hash of selected filename` generator |
|Gldt!   | Interactive `git log commit_hash & difftool hash of all files` generator |

|Gbdo    | Interactive `git branch & DiffviewOpen selected branch with diffview.nvim` generator |
|Gldo    | Interactive `git log commit_hash & DiffviewOpen current file with diffview.nvim` generator |
|Gldo!   | Interactive `git log commit_hash & DiffviewOpen all diff files with diffview.nvim` generator |
|Grlg   | Interactive `git rev-list & git grep` generator |

### ⌨  Forgit Keybinds

| Key                                           | Action                    |
| :-------------------------------------------: | ------------------------- |
| <kbd>Enter</kbd>                              | Confirm                   |
| <kbd>Tab</kbd>                                | Toggle mark and move up   |
| <kbd>Shift</kbd> - <kbd>Tab</kbd>             | Toggle mark and move down |
| <kbd>?</kbd>                                  | Toggle preview window     |
| <kbd>Alt</kbd> - <kbd>W</kbd>                 | Toggle preview wrap       |
| <kbd>Ctrl</kbd> - <kbd>S</kbd>                | Toggle sort               |
| <kbd>Ctrl</kbd> - <kbd>R</kbd>                | Toggle selection          |
| <kbd>Ctrl</kbd> - <kbd>Y</kbd>                | Copy commit hash*         |
| <kbd>Ctrl</kbd> - <kbd>K</kbd> / <kbd>P</kbd> | Selection move up         |
| <kbd>Ctrl</kbd> - <kbd>J</kbd> / <kbd>N</kbd> | Selection move down       |
| <kbd>Alt</kbd> - <kbd>K</kbd> / <kbd>P</kbd>  | Preview move up           |
| <kbd>Alt</kbd> - <kbd>J</kbd> / <kbd>N</kbd>  | Preview move down         |


### ⌨  Git command alias


| Command               | Action                    |
| :-------------------: | ------------------------- |
|Gaa| git add --all|
|Gap| git  add -pu |
|Gash| git  stash |
|Gasha| git  stash apply |
|Gashp| git  stash pop |
|Gashu| git  stash --include-untracked |
|Gau| git  add -u |
|Gc| git  commit, if -m not specify, will prompt a ui.input |
|Gce| git  clean |
|Gcef| git  clean -fd |
|Gcl| git  clone |
|Gdf| git  diff -- |
|Gdnw| git  diff -w -- |
|Gdw| git  diff --word-diff |
|Gdmn| git  diff master/main --name-only \| fzf |
|Gdn| git  diff --name-only \| fzf |
|Gf| git  fetch |
|Gfa| git  fetch --all |
|Gfr| git  fetch; and git rebase |
|Glg| git  log --graph --decorate |
|Gm| git  merge |
|Gmff| git  merge --ff |
|Gmnff| git  merge --no-ff |
|Gopen| git  config --get remote.origin.url | xargs open |
|Gpl| git  pull |
|Gplr| git  pull --rebase |
|Gps| git  push |
|Gpsf| git  push --force-with-lease |
|Gr| git  remote -v |
|Grb| git  rebase |
|Grbi| git  rebase -i |
|Grbc| git  rebase --continue |
|Grba| git  rebase --abort |
|Grs| git  reset -- |
|Grsh| git  reset --hard |
|Grsl| git  reset HEAD~ |
|Gs| git  status |
|Gsh| git  show |
|Gt| git  tag |
|Gtop| git  rev-parse --show-toplevel |
|Gurl| git  config --get remote.origin.url |

### 🍱 All in One
`Forgit` allows you to list all commands in a list and you can fuzzy search and run any command you want.
* vim-fugitive commands
* forgit commands
* forgit.nvim commands (acronym)
* vim-flog commands
* gitsigns commands

### 📦 Optional dependencies

- [`delta`](https://github.com/dandavison/delta) / [`diff-so-fancy`](https://github.com/so-fancy/diff-so-fancy): For better human readable diffs.

- [`bat`](https://github.com/sharkdp/bat.git): Syntax highlighting for `gitignore`.

- [`emoji-cli`](https://github.com/wfxr/emoji-cli): Emoji support for `git log`.

- git fugitive

- [diffview.nvim](https://github.com/sindrets/diffview.nvim)

