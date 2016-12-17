if v:version < 800
  echohl WarningMsg
  echomsg 'vim-jdb: Vim version is too old, vim-jdb requires at least 8.0'
  echohl None
  finish
endif

if !has('job')
  echohl WarningMsg
  echomsg 'vim-jdb: Vim not compiled with job support'
  echohl None
  finish
endif

if !has('channel')
  echohl WarningMsg
  echomsg 'vim-jdb: Vim not compiled with channel support'
  echohl None
  finish
endif

if !has('signs')
  echohl WarningMsg
  echomsg 'vim-jdb: Vim not compiled with sign support'
  echohl None
  finish
endif

command! -nargs=? JDBAttach call s:attach(<f-args>)
command! JDBDetach call s:detach()
command! JDBBreakpointOnLine call s:breakpointOnLine(expand('%:~:.'), line('.'))
command! JDBClearBreakpointOnLine call s:clearBreakpointOnLine(expand('%:~:.'), line('.'))
command! JDBContinue call s:continue()
command! JDBStepOver call s:stepOver()
command! JDBStepIn call s:stepIn()
command! JDBStepUp call s:stepUp()
command! JDBStepI call s:stepI()
command! JDBToggleWatchWindow call s:toggleWatchWindow()
command! -nargs=1 JDBCommand call s:command(<f-args>)

if has('multi_byte') && has('unix') && &encoding == 'utf-8' && (empty(&termencoding) || &termencoding == 'utf-8')
  " ⭙  ⬤  ⏺  ⚑  ⛔
  sign define breakpoint text=⛔
else
  sign define breakpoint text=x
endif

sign define currentline text=-> texthl=Search

let s:job = ''
let s:channel = ''

function! s:hash(name, linenumber)
  let l:result = 1
  for c in split(a:name, '\zs')
    let l:result = (l:result * 2) + char2nr(c)
  endfor
  let l:result = (l:result * 2) + a:linenumber
  return l:result
endfunction

function! s:getClassNameFromFile(filename)
  let l:className = fnamemodify(a:filename,':t:r')
  for l:line in readfile(a:filename)
    let l:matches = matchlist(l:line,'\vpackage\s+(%(\w|\.)+)\s*;')
    if 1 < len(l:matches)
      return l:matches[1].'.'.l:className
    endif
  endfor
  return l:className
endfunction

function! JdbOutHandler(channel, msg)
  "TODO make debug logging out of it
  "echom a:msg
  let l:breakpoint = ''
  if -1 < stridx(a:msg, 'Breakpoint hit:')
    echom "breakpoint hit"
    let l:breakpoint = split(a:msg, ',')
    let l:filename = l:breakpoint[1]
    let l:filename = substitute(l:filename, '\.\a*()$', '', '')
    let l:filename = substitute(l:filename, ' ', '', 'g')
    let l:filename = join(split(l:filename, '\.'), '/')
    let l:linenumber = substitute(l:breakpoint[2], ',\|\.\| \|bci=\d*\|line=', '', 'g')
    " TODO only open when current buffer is not the file to open
    exe 'e +%foldopen! **/'. l:filename .'.java'
    exe l:linenumber
    exe 'sign unplace 2'
    exe 'sign place 2 line='. l:linenumber .' name=currentline file='.  expand("%:p")
  endif
  if -1 < stridx(a:msg, 'Step completed:')
    " TODO handle ClassName$3.get()
    echom "Step completed"
    let l:breakpoint = split(a:msg, ',')
    let l:filename = l:breakpoint[1]
    let l:filename = substitute(l:filename, '\.\a*()$', '', '')
    let l:filename = substitute(l:filename, ' ', '', 'g')
    let l:filename = join(split(l:filename, '\.'), '/')
    let l:linenumber = substitute(l:breakpoint[2], ',\|\.\| \|bci=\d*\|line=', '', 'g')
    " TODO only open when current buffer is not the file to open
    exe 'e +%foldopen! **/'. l:filename .'.java'
    exe l:linenumber
    exe 'sign unplace 2'
    exe 'sign place 2 line='. l:linenumber .' name=currentline file='.  expand("%:p")
  endif
  if -1 < stridx(a:msg, 'Set breakpoint ') || -1 < stridx(a:msg, 'Set deferred breakpoint ')
    echom "Set breakpoint"
    let l:breakpoint = substitute(a:msg, '.*Set breakpoint ', '', '')
    let l:breakpoint = substitute(a:msg, '.*Set deferred breakpoint ', '', '')
    let l:breakpoint = split(l:breakpoint, ':')
    let l:filename = join(split(l:breakpoint[0], '\.'), '/')
    exe 'sign place '. s:hash(expand("%:t"), str2nr(l:breakpoint[1])) .' line='. str2nr(l:breakpoint[1]) .' name=breakpoint file='. expand("%:p")
  endif
  if -1 < stridx(a:msg, 'Removed: breakpoint ')
    echom "Clear breakpoint"
    let l:breakpoint = substitute(a:msg, '.*Removed: breakpoint ', '', '')
    let l:breakpoint = split(l:breakpoint, ':')
    exe 'sign unplace '. s:hash(expand("%:t"), str2nr(l:breakpoint[1]))
  endif
  if -1 < stridx(a:msg, 'All threads resumed.')
    echom "Continue"
    exe 'sign unplace 2'
  endif
endfunction

function! JdbErrHandler(channel, msg)
  echoe 'Error on JDB communication: '. a:msg
endfunction

function! s:attach(...)
  if s:job == '' || job_status(s:job) != 'run'
    let l:hostAndPort = get(a:, 1,'localhost:5005')
    let l:jdbCommand = get(g:, 'vimjdb_jdb_command', 'jdb')
    let win = bufwinnr('_JDB_SHELL_')
    if win == -1
        exe 'silent keepalt leftabove split _JDB_SHELL_'
        exe 'silent resize 15'
        let win = bufwinnr('_JDB_SHELL_')
        setlocal noreadonly
        setlocal filetype=tagbar
        setlocal buftype=nofile
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal nobuflisted
        setlocal nomodifiable
        setlocal textwidth=0
        setlocal nolist
        setlocal nowrap
        setlocal nospell
        setlocal winfixwidth
        setlocal nonumber
        if exists('+relativenumber')
          setlocal norelativenumber
        endif
        setlocal nofoldenable
        setlocal foldcolumn=0
        " Reset fold settings in case a plugin set them globally to something
        " expensive. Apparently 'foldexpr' gets executed even if 'foldenable' is
        " off, and then for every appended line (like with :put).
        setlocal foldmethod&
        setlocal foldexpr&
    endif
    let s:job = job_start(l:jdbCommand .' -attach '. l:hostAndPort, {"out_modifiable": 0, "out_io": "buffer", "out_name": "_JDB_SHELL_", "out_cb": "JdbOutHandler", "err_modifiable": 0, "err_io": "buffer", "err_name": "_JDB_SHELL_", "err_cb": "JdbErrHandler"})
    let s:channel = job_getchannel(s:job)
    call ch_sendraw(s:channel, "run\n")
    call ch_sendraw(s:channel, "monitor where\n")
  else
    echom 'There is already a JDB session running. Detach first before you start a new one.'
  endif
endfunction

function! s:detach()
  if s:job != '' && job_status(s:job) == 'run'
    call ch_sendraw(s:channel, "exit\n")
    let s:channel = ''
    let s:job = ''
    let win = bufwinnr('_JDB_SHELL_')
    if win != -1
      exe win . 'wincmd w'
      exe 'close'
    endif
  endif
endfunction

function! s:breakpointOnLine(fileName, lineNumber)
  "TODO check if we are on a java file and fail if not
  let fileName = s:getClassNameFromFile(a:fileName)
  "TODO store command temporary if not already connected
  call ch_sendraw(s:channel, "stop at " . fileName . ":" . a:lineNumber . "\n")
endfunction

function! s:clearBreakpointOnLine(fileName, lineNumber)
  "TODO check if we are on a java file and fail if not
  let fileName = s:getClassNameFromFile(a:fileName)
  "TODO store command temporary if not already connected
  call ch_sendraw(s:channel, "clear " . fileName . ":" . a:lineNumber . "\n")
endfunction

function! s:continue()
  call ch_sendraw(s:channel, "resume\n")
endfunction

function! s:stepOver()
  call ch_sendraw(s:channel, "next\n")
endfunction

function! s:stepUp()
  call ch_sendraw(s:channel, "step up\n")
endfunction

function! s:stepIn()
  call ch_sendraw(s:channel, "step in\n")
endfunction

function! s:stepI()
  call ch_sendraw(s:channel, "stepi\n")
endfunction

function! s:command(command)
  call ch_sendraw(s:channel, a:command . "\n")
endfunction

function! s:toggleWatchWindow()
  
endfunction

