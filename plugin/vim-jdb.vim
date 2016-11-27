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

command! JDBAttach call Attach()
command! JDBDetach call Detach()
command! JDBBreakpointOnLine call BreakpointOnLine(expand('%:~:.'), line('.'))
command! JDBClearBreakpointOnLine call ClearBreakpointOnLine(expand('%:~:.'), line('.'))
command! JDBContinue call Continue()
command! JDBStepOver call s:stepOver()
command! JDBStepIn call s:stepIn()
command! JDBStepUp call s:stepUp()
command! JDBStepI call s:stepI()
command! JDBCommand call s:command(<args>)

let s:channel = ''

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
  let l:breakpoint = ''
  let l:match = matchstr(a:msg, '^Breakpoint hit:')
  if l:match == 'Breakpoint hit:'
    let l:breakpoint = split(a:msg, ',')
    echom l:breakpoint[1]
    echom l:breakpoint[2]
  endif
  let l:match = matchstr(a:msg, '^Step completed:')
  if l:match == 'Step completed:'
    let l:breakpoint = split(a:msg, ',')
    echom l:breakpoint[1]
    echom l:breakpoint[2]
  endif
  let l:match = matchstr(a:msg, '^Set breakpoint ')
  if l:match == 'Set breakpoint '
    let l:breakpoint = split(a:msg)
    echom split(l:breakpoint[2], ':')
  endif
endfunction

function! JdbErrHandler(channel, msg)
endfunction

function! Attach()
  " Vim::message('There is already a JDB session running. Detach first before you can start a new one.')
  let win = bufwinnr('_JDB_SHELL_')
  if win == -1
      exe 'silent new _JDB_SHELL_'
      let win = bufwinnr('_JDB_SHELL_')
  endif
  let job = job_start("/home/ms/progs/jdk1.8/bin/jdb -attach localhost:5005", {"out_modifiable": 0, "out_io": "buffer", "out_name": "_JDB_SHELL_", "out_cb": "JdbOutHandler", "err_modifiable": 0, "err_io": "buffer", "err_name": "_JDB_SHELL_", "err_cb": "JdbErrHandler"})
  let s:channel = job_getchannel(job)
  call ch_sendraw(s:channel, "run\n")
  call ch_sendraw(s:channel, "monitor where\n")
endfunction

function! Detach()
  call ch_sendraw(s:channel, "exit\n")
  s:channel = ''
endfunction

function! BreakpointOnLine(fileName, lineNumber)
  "TODO check if we are on a java file and fail if not
  let fileName = s:getClassNameFromFile(a:fileName)
  "TODO store command temporary if not already connected
  call ch_sendraw(s:channel, "stop at " . fileName . ":" . a:lineNumber . "\n")
endfunction

function! ClearBreakpointOnLine(fileName, lineNumber)
  "TODO check if we are on a java file and fail if not
  let fileName = s:getClassNameFromFile(a:fileName)
  "TODO store command temporary if not already connected
  call ch_sendraw(s:channel, "clear " . fileName . ":" . a:lineNumber . "\n")
endfunction

function! Continue()
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

