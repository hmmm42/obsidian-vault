set clipboard=unnamedplus

imap jj <Esc>

nnoremap H ^
nnoremap L $

nmap <CR> o<Esc>
nmap <S-Enter> O<Esc>

nnoremap x "_x
nnoremap X "_X
nnoremap d "_d
nnoremap D "_D
nnoremap gd :action GotoDeclaration<CR>

nnoremap <Space> <Nop>
vnoremap <Space> <Nop>

vnoremap <C-c> "+y
nnoremap <C-v> "+p
"inoremap <C-v> <C-r><C-o>+
vnoremap <C-v> "+p

vnoremap <C-x> "+d
nnoremap <C-x> :action $Cut<CR>

nnoremap <C-n> :action GotoClass<CR>
inoremap <C-n> <ESC>:action GotoClass<CR>

nnoremap <C-S-n> :action GotoFile<CR>
inoremap <C-S-n> <ESC>:action GotoFile<CR>

nnoremap <C-o> :action OverrideMethods<CR>
nnoremap <C-P> :action ParameterInfo<CR>
inoremap <C-P> <ESC>:action ParameterInfo<CR>a

nnoremap <C-q> :action QuickJavaDoc<CR>

nnoremap <C-H> :action TypeHierarchy<CR>
nnoremap <C-S-H> :action MethodHierarchy<CR>

nnoremap <C-A-l> :action ReformatCode<CR>
inoremap <C-A-l> <ESC>:action ReformatCode<CR>a

map <C-f> <ESC>:action Find<CR>

inoremap <C-j> <ESC>:action InsertLiveTemplate<CR>

nnoremap <C-r> :action $Redo<CR>

" Moving to next/prev heading
exmap nextHeading jsfile .obsidian.markdown-helper.js {jumpHeading(true)}
exmap prevHeading jsfile .obsidian.markdown-helper.js {jumpHeading(false)}
nmap g] :nextHeading
nmap g[ :prevHeading

" Zoom in/out
exmap zoomIn obcommand obsidian-zoom:zoom-in
exmap zoomOut obcommand obsidian-zoom:zoom-out
nmap zi :zoomIn
nmap zo :zoomOut

nmap &a :zoomOut
nmap &b :nextHeading
nmap &c :zoomIn
nmap &d :prevHeading
nmap z] &a&b&c
nmap z[ &a&d&c

exmap toggleStille obcommand obsidian-stille:toggleStille
nmap zs :toggleStille
nmap ,s :toggleStille

nmap [ {
nmap ] }

nmap j gj
nmap k gk

exmap scrollToCenterTop70p jsfile .obsidian.markdown-helper.js {scrollToCursor(0.7)}
nmap zz :scrollToCenterTop70p