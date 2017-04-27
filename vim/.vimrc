"
" A (not so) minimal vimrc.
"

" You want Vim, not vi. When Vim finds a vimrc, 'nocomptaible' is set anyway.
" We set it explicitely to make our position clear!

" vim-plug (https://github.com/junegunn/vim-plug) settings 
" Automatically install vim-plug and run PlugInstall if vim-plug not found

set nocompatible
scriptencoding utf-8
filetype plugin indent on  " Load plugins according to detected filetype.
syntax on                  " Enable syntax highlighting.

set autoindent             " Indent according to previous line.
set expandtab              " Use spaces instead of tabs.
set softtabstop =4         " Tab key indents by 4 spaces.
set shiftwidth  =4         " >> indents by 4 spaces.
set shiftround             " >> indents to next multiple of 'shiftwidth'.

set backspace   =indent,eol,start  " Make backspace work as you would expect.
set hidden                 " Switch between buffers without having to save first.
set laststatus  =2         " Always show statusline.
set display     =lastline  " Show as much as possible of the last line.

set showmode               " Show current mode in command-line.
set showcmd                " Show already typed keys when more are expected.

set incsearch              " Highlight while searching with / or ?.
set hlsearch               " Keep matches highlighted.
set ignorecase
set smartcase              " disable ignorecase when using any capital letter
nmap \q :nohlsearch<CR>    " Disable search higlight when is annoying

set ttyfast                " Faster redrawing.
set lazyredraw             " Only redraw when necessary.

set splitbelow             " Open new windows below the current window.
set splitright             " Open new windows right of the current window.

set cursorline             " Find the current line quickly.
set wrapscan               " Searches wrap around end-of-file.
set report      =0         " Always report changed lines.
set synmaxcol   =200       " Only highlight the first 200 columns.

set list                   " Show non-printable characters.
if has('multi_byte') && &encoding ==# 'utf-8'
  let &listchars = 'tab:▸ ,extends:❯,precedes:❮,nbsp:±'
else
  let &listchars = 'tab:> ,extends:>,precedes:<,nbsp:.'
endif

" The fish shell is not very compatible to other shells and unexpectedly
" breaks things that use 'shell'.

if &shell =~# 'fish$'
  set shell=/bin/bash
endif

" Plug
"
call plug#begin('~/.vim/plugged')
Plug 'christoomey/vim-tmux-navigator'
Plug 'cyberkov/openhab-vim'
Plug 'https://github.com/morhetz/gruvbox'
Plug 'Valloric/MatchTagAlways'
Plug 'vimwiki/vimwiki', { 'branch': 'dev' }
Plug 'tbabej/taskwiki'
Plug 'powerman/vim-plugin-AnsiEsc'
Plug 'majutsushi/tagbar'
Plug 'farseer90718/vim-taskwarrior'
Plug 'scrooloose/syntastic'
Plug 'whatyouhide/vim-textobj-xmlattr'
Plug 'glts/vim-textobj-comment'
Plug 'https://github.com/vim-scripts/YankRing.vim'
Plug 'honza/vim-snippets'
Plug 'kana/vim-textobj-user'
Plug 'sudar/vim-arduino-snippets'
Plug 'SirVer/ultisnips'
Plug 'vim-airline/vim-airline'
Plug 'lucapette/vim-textobj-underscore' | Plug 'kana/vim-textobj-user'
Plug 'jceb/vim-textobj-uri'             | Plug 'kana/vim-textobj-user'
Plug 'kana/vim-textobj-indent'          | Plug 'kana/vim-textobj-user'
Plug 'kana/vim-textobj-user'
Plug 'sts10/vim-mustard'
Plug 'https://github.com/terryma/vim-smooth-scroll.git'
Plug 'tpope/vim-speeddating'
"Plug 'junegunn/goyo.vim'
Plug 'junegunn/vim-easy-align'
Plug 'mattn/calendar-vim'
"Plug 'amix/vim-zenroom2'
Plug 'https://github.com/fmoralesc/vim-pad.git'
Plug 'https://github.com/cwoac/nvim.git'
Plug 'godlygeek/tabular'
Plug 'https://github.com/plasticboy/vim-markdown.git'
Plug 'https://github.com/tomtom/tcomment_vim.git'
"Plug 'https://github.com/jceb/vim-orgmode'
Plug 'https://github.com/lifepillar/vim-cheat40.git'
Plug 'reedes/vim-pencil'
Plug 'godlygeek/tabular'
Plug 'plasticboy/vim-markdown'
Plug 'https://github.com/tpope/vim-surround.git'
Plug 'https://github.com/tpope/vim-vinegar.git'
Plug 'https://github.com/ctrlpvim/ctrlp.vim.git'
Plug 'https://github.com/flazz/vim-colorschemes.git'
Plug 'https://github.com/justinmk/vim-sneak.git'
Plug 'https://github.com/tpope/vim-fugitive.git'
Plug 'https://github.com/Raimondi/delimitMate.git'
Plug 'https://github.com/terryma/vim-multiple-cursors.git'
"Plug 'vimoutliner/vimoutliner/'
Plug 'thinca/vim-textobj-between'
Plug 'Julian/vim-textobj-brace'
Plug 'https://github.com/glts/vim-textobj-indblock'
Plug 'vim-scripts/DrawIt'
" wywołuje ArduinoIDE 
Plug '4Evergreen4/vim-hardy'
Plug 'jplaut/vim-arduino-ino'
"Plug 'Valloric/YouCompleteMe'
"Plug 'weynhamz/vim-plugin-minibufexpl'

" Add plugins to &runtimepath
call plug#end()


" Put all temporary files under the same directory.
" https://github.com/mhinz/vim-galore#handling-backup-swap-undo-and-viminfo-files
set backup
set backupdir   =$HOME/.vim/files/backup/
set backupext   =-vimbackup
set backupskip  =
set directory   =$HOME/.vim/files/swap/
set updatecount =100
set undofile
set undodir     =$HOME/.vim/files/undo/
set viminfo     ='100,n$HOME/.vim/files/info/viminfo

autocmd BufRead,BufNewFile *.txt set filetype=markdown

" markdown
" au! BufRead,BufNewFile *.markdown set filetype=mkd
" au! BufRead,BufNewFile *.md       set filetype=mkd
" autocm VimEnter *.mk Goyo

" Vim outline
"au! BufRead,BufNewFile *.otl setfiletype votl

augroup pencil
  autocmd!
  autocmd FileType markdown,mkd,org,txt call pencil#init()
augroup END
let g:pencil#wrapModeDefault = 'soft' 

let g:vim_markdown_toml_frontmatter = 1
let g:vim_markdown_folding_disabled = 1
let g:vim_markdown_frontmatter = 1

" VIM-pad config
"
" defulat dir
let g:pad#dir = "~/Library/Mobile\ Documents/com~apple~CloudDocs/Notatki"
" search window height
let g:pad#window_height = 10
" autorename files while save
let g:pad#rename_files = 1
" change grep to ag silver search. Grep is broken on Mac OS X
let g:pad#search_backend = 'ag'
" open file in main window
let g:pad#open_in_split = 0

" Fold and unfold Markdown by space key
nnoremap <silent> <Space> @=(foldlevel('.')?'za':"\<Space>")<CR>
vnoremap <Space> zf

" Language PL spell check
set spell spelllang=pl

set nospell
nnoremap <Leader>s :set spell<CR>

set relativenumber
call tcomment#DefineType('markdown', '> %s')

set clipboard+=unnamed
set mouse+=a

" Highlight dynamically as pattern is typed
set incsearch

" Optimize for fast terminal connections
set ttyfast
" " Add the g flag to search/replace by default
set gdefault

"let g:org_indent = 1

" do not use default cheat sheet 
 let g:cheat40_use_default = 0

" mark two or more spaces after some text as an error
syntax match DoubleSpace /\S\zs {2,}/
highlight link DoubleSpace Error


" Create a Markdown-link structure for the current word or visual selection with
" leader 3. Paste in the URL later. Or use leader 4 to insert the current
" system clipboard as an URL.
nnoremap <Leader>3 ciw[<C-r>"]()<Esc>
vnoremap <Leader>3 c[<C-r>"]()<Esc>
nnoremap <Leader>4 ciw[<C-r>"](<Esc>"*pli)<Esc>
vnoremap <Leader>4 c[<C-r>"](<Esc>"*pli)<Esc>

" Set paste off to pasting
nmap \o :set paste<CR>

" Go back to previously edited file
nmap <C-e> :e#<CR>

" Ctrl-P configuration
nmap ; :CtrlPBuffer<CR>
let g:ctrlp_map = '<Leader>t'
let g:ctrlp_match_window_bottom = 0
let g:ctrlp_match_window_reversed = 0
let g:ctrlp_custom_ignore = '\v\~$|\.(o|swp|pyc|wav|mp3|ogg|blend)$|(^|[/\\])\.(hg|git|bzr)($|[/\\])|__init__\.py'
let g:ctrlp_working_path_mode = 0
let g:ctrlp_dotfiles = 0
let g:ctrlp_switch_buffer = 0

colors gruvbox
set background=dark 

" Powerline
" python from powerline.vim import setup as powerline_setup
" python powerline_setup()
" python del powerline_setup


" Smooth scroll
noremap <silent> <c-u> :call smooth_scroll#up(&scroll, 30, 2)<CR>
noremap <silent> <c-d> :call smooth_scroll#down(&scroll, 30, 2)<CR>
noremap <silent> <c-b> :call smooth_scroll#up(&scroll*2, 30, 4)<CR>
noremap <silent> <c-f> :call smooth_scroll#down(&scroll*2, 30
" j and k don't skip over wrapped lines in following FileTypes, unlehonza/vim-snippetsss given a count (helpful since I display relative line numbers in these file types)
" autocmd FileType html nnoremap <expr> j v:count ? 'j' : 'gj'
" autocmd FileType html nnoremap <expr> k v:count ? 'k' : 'gk'
" autocmd FileType markdown nnoremap <expr> j v:count ? 'j' : 'gj'
" autocmd FileType markdown nnoremap <expr> k v:count ? 'k' : 'gk'
" set it for all files
noremap <silent> <expr> j v:count ? 'j' : 'gj'
noremap <silent> <expr> k v:count ? 'k' : 'gk'


" Sneak
let g:sneak#s_next = 1

set laststatus=2 " Always display the statusline in all windows
set showtabline=2 " Always display the tabline, even if there is only one tab
set noshowmode " Hide the default mode text (e.g. -- INSERT -- below the statusline)

" Make X an operator that removes text without placing text in the default registry
nmap XX "_dd
vmap X "_d

" Insert newline in Normal Mode. You can p line then.
nmap <CR> o<Esc>j

"Airline config
"turn on nice fonts in status line
let g:airline_powerline_fonts = 1
"enable syntastic integration
let g:airline#extensions#syntastic#enabled = 1

" UltiSnip conf for TAB
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<tab>"
let g:UltiSnipsJumpBackwardTrigger="<s-tab>"

" Align GitHub-flavored Markdown tables
vmap <Leader><Bar> :EasyAlign*<Bar><Enter>

" Fix EasyAlign and Explore ambigous E command
cabbrev E Explore

" Start interactive EasyAlign in visual mode (e.g. vipga)

xmap ga <Plug>(EasyAlign)

" Start interactive EasyAlign for a motion/text object (e.g. gaip)
nmap ga <Plug>(EasyAlign)

let g:easy_align_delimiters = {
\ 't': { 'pattern': "\<tab>", 'left_margin': 0, 'right_margin': 0 } }

" YankRing configuraction
let g:yankring_history_file = '.yankring-history'
nnoremap ,yr :YRShow<CR>
nnoremap C-y :YRShow<CR>

autocmd FileType rules setlocal commentstring=/*\ %s\ */

"Syntastic config
"let g:syntastic_always_populate_loc_list = 1
"let g:syntastic_auto_loc_list = 1
"let g:syntastic_check_on_open = 1
"let g:syntastic_check_on_wq = 0

" ARduino
"nnoremap <leader>ad :call ArduinoUpload()<CR>

" disable YouCompleteMe engine for some files
let g:ycm_filetype_blacklist= {
      \ 'gitcommit': 1,
      \ 'markdown': 1,
      \ 'text': 1,
      \ 'html': 1,
      \ 'org': 1
      \}

" Syntastic configuration
let g:syntastic_text_checkers = ['language_check']
let g:syntastic_text_language_check_args = '--language=pl-PL'
let g:syntastic_org_checkers = ['language_check']
let g:syntastic_org_language_check_args = '--language=pl-PL'
"let g:syntastic_html_checkers = ['tidy']
let g:syntastic_markdown_checkers = ['mdl']
let g:syntastic_arduino_checkers = ['avrgcc']
let g:syntastic_disabled_filetypes=['html']

" Allow saving of files as sudo when I forgot to start vim using sudo.
cmap w!! w !sudo tee > /dev/null %

nmap <F8> :TagbarToggle<CR>
let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 4
let g:netrw_altv = 1
let g:netrw_winsize = 25


" automatically reload vimrc when it's saved
au BufWritePost .vimrc so ~/.vimrc

"" ctrl-w then j, it’s just ctrl-j:
"nnoremap <C-J> <C-W><C-J>
"nnoremap <C-K> <C-W><C-K>
"nnoremap <C-L> <C-W><C-L>
"nnoremap <C-H> <C-W><C-H>
set splitbelow
set splitright
nnoremap / /\v
vnoremap / /\v

set gdefault
set list
set listchars=tab:▸\ ,eol:¬

" Autosave on lost focus
au FocusLost * :wa

" jj to enter Normal mode
inoremap jj <ESC>

set iskeyword-=\.
set iskeyword-=\(
set iskeyword-=\)

"Easy split navigation
"nnoremap <C-h> <C-w>h
"nnoremap <C-j> <C-w>j
"nnoremap <C-k> <C-w>k
"nnoremap <C-l> <C-w>l

let wiki_1 = {}
let wiki_1.path = '~/vimwiki/'

