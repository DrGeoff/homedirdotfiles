set nocompatible              " be iMproved, required

" Using https://github.com/junegunn/vim-plug for plugin management
" PlugInstall [name ...] [#threads] 	Install plugins
" PlugUpdate [name ...] [#threads] 	Install or update plugins
" PlugClean[!] 	Remove unused directories (bang version will clean without prompt)
" PlugUpgrade 	Upgrade vim-plug itself
" PlugStatus 	Check the status of plugins
" PlugDiff 	Examine changes from the previous update and the pending changes
" PlugSnapshot[!] [output path] 	Generate script for restoring the current snapshot of the plugins
" Specify a directory for plugins
" - For Neovim: ~/.local/share/nvim/plugged
" - Avoid using standard Vim directory names like 'plugin'

" If Plug is not installed, go grab it.
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source ~/.vimrc
endif

call plug#begin('~/.vim/plugged')

Plug 'ervandew/supertab'
Plug 'ncm2/ncm2'
Plug 'roxma/nvim-yarp'
" enable ncm2 for all buffers
autocmd BufEnter * call ncm2#enable_for_buffer()

" IMPORTANT: :help Ncm2PopupOpen for more information
set completeopt=noinsert,menuone,noselect

" NOTE: you need to install completion sources to get completions. Check
" our wiki page for a list of sources: https://github.com/ncm2/ncm2/wiki
Plug 'ncm2/ncm2-bufword'
Plug 'ncm2/ncm2-path'
Plug 'ncm2/ncm2-pyclang'
Plug 'ncm2/ncm2-neoinclude' | Plug 'Shougo/neoinclude.vim'
Plug 'ncm2/ncm2-jedi'
Plug 'majutsushi/tagbar'
Plug 'elzr/vim-json'
Plug 'altercation/vim-colors-solarized'
Plug 'wincent/terminus'
Plug 'sirtaj/vim-openscad'
Plug 'ambv/black'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'CoatiSoftware/vim-sourcetrail'
Plug 'rhysd/vim-clang-format'
Plug 'kana/vim-operator-user'

" Initialize plugin system
call plug#end()

" path to directory where libclang.so can be found
let g:ncm2_pyclang#library_path = '/usr/lib/llvm-9/lib'

" Jedi settings
let g:jedi#use_tabs_not_buffers = 1
" Turn off jedi completions since we are using ncm2 completions
let g:jedi#completions_enabled = 0

set expandtab
set tabstop=4
set softtabstop=4
set shiftwidth=4
set bg=dark
set mouse=a
syntax on
filetype plugin on
set ruler
set nowrap
set number
set backspace=indent,eol,start
let $PAGER=''
"set tags=./tags;/
"map <C-\> :tab split<CR>:exec("tag ".expand("<cword>"))
"map <A-]> :vsp <CR>:exec("tag ".expand("<cword>"))


if has ("autocmd")
    " File type detection. Indent based on filetype. Recommended.
    filetype plugin indent on
    autocmd FileType c,cpp nnoremap <buffer> gd :tab split<CR>:<c-u>call ncm2_pyclang#goto_declaration()<cr>
endif

" Powerline setup
try
    python3 from powerline.vim import setup as powerline_setup
    python3 powerline_setup()
    python3 del powerline_setup
    set laststatus=2
    set t_Co=256
    set noshowmode " Hide the default mode text (e.g. -- INSERT -- below the statusline)
catch
endtry

"Reselect visual block after in/outdenting
vnoremap < <gv
vnoremap > >gv


" Open corresponding file in another tab.  I.e., if in hpp, open the cpp. And vice versa
map <F5> :tabnew %:p:s,.hpp$,.X123X,:s,.cpp$,.hpp,:s,.X123X$,.cpp,<CR>

" Toggle mouse mode
map <F7> <ESC>:exec &mouse!=""? "set mouse=" : "set mouse=a"<CR>

" F8 toggles the tagbar
map <F8> :TagbarToggle<CR>

" Abbreviations to save typing
abbr ss std::string

" suppress the annoying 'match x of y', 'The only match' and 'Pattern not
" found' messages
set shortmess+=c

" CTRL-C doesn't trigger the InsertLeave autocmd . map to <ESC> instead.
inoremap <c-c> <ESC>

" When the <Enter> key is pressed while the popup menu is visible, it only
" hides the menu. Use this mapping to close the menu and also start a new
" line.
inoremap <expr> <CR> (pumvisible() ? "\<c-y>\<cr>" : "\<CR>")

" Use <TAB> to select the popup menu:
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
"inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" wrap existing omnifunc
" Note that omnifunc does not run in background and may probably block the
" editor. If you don't want to be blocked by omnifunc too often, you could
" add 180ms delay before the omni wrapper:
"  'on_complete': ['ncm2#on_complete#delay', 180,
"               \ 'ncm2#on_complete#omni', 'csscomplete#CompleteCSS'],
au User Ncm2Plugin call ncm2#register_source({
        \ 'name' : 'css',
        \ 'priority': 9,
        \ 'subscope_enable': 1,
        \ 'scope': ['css','scss'],
        \ 'mark': 'css',
        \ 'word_pattern': '[\w\-]+',
        \ 'complete_pattern': ':\s*',
        \ 'on_complete': ['ncm2#on_complete#omni', 'csscomplete#CompleteCSS'],
        \ })

" clang format options
let g:clang_format#code_style = 'webkit'
" map to <Leader>cf in C++ code
autocmd FileType c,cpp,objc nnoremap <buffer><Leader>cf :<C-u>ClangFormat<CR>
autocmd FileType c,cpp,objc vnoremap <buffer><Leader>cf :ClangFormat<CR>
" if you install vim-operator-user
autocmd FileType c,cpp,objc map <buffer><Leader>x <Plug>(operator-clang-format)
" Toggle auto formatting:
nmap <Leader>C :ClangFormatAutoToggle<CR>
