set rtp +=.
set rtp +=../plenary.nvim/

runtime! plugin/plenary.vim
runtime! plugin/nvim-treesitter.vim
runtime! plugin/playground.vim
runtime! plugin/nvim-lspconfig.vim

set noswapfile
set nobackup

filetype indent off
set nowritebackup
set noautoindent
set nocindent
set nosmartindent
set indentexpr=
set shada="NONE"

lua << EOF
_G.test_rename = true
_G.test_close = true
require("plenary/busted")
require("forgit").setup({
})
EOF
