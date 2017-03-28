if v:version < 800
  echohl WarningMsg
  echomsg 'vim-jdb: Vim version is too old, vim-jdb requires at least 8.0'
  echohl None
  finish
endif

if !has('job')
  echohl WarningMsg
  echomsg 'vim-jdb: Vim not compiled with job support, vim-jdb requires job'
  echohl None
  finish
endif

if !has('channel')
  echohl WarningMsg
  echomsg 'vim-jdb: Vim not compiled with channel support, vim-jdb requires channel'
  echohl None
  finish
endif

if !has('signs')
  echohl WarningMsg
  echomsg 'vim-jdb: Vim not compiled with sign support, vim-jdb requires signs'
  echohl None
  finish
endif

command! -nargs=? JDBDebugProcess call s:createDebugProcess(<f-args>)
command! -nargs=? JDBAttach call s:attach(<f-args>)
command! JDBDebugUnit call s:startUnitTest()
command! JDBDetach call s:detach()
command! JDBBreakpointOnLine call s:setBreakpoint()
command! JDBClearBreakpointOnLine call s:removeBreakpoint()
command! JDBContinue call s:continue()
command! JDBStepOver call s:stepOver()
command! JDBStepIn call s:stepIn()
command! JDBStepUp call s:stepUp()
command! JDBStepI call s:stepI()
command! JDBToggleWatchWindow call s:toggleWatchWindow()
command! -nargs=1 JDBCommand call s:command(<f-args>)

if has('multi_byte') && has('unix') && &encoding == 'utf-8' && (empty(&termencoding) || &termencoding == 'utf-8')
  " ⭙  ⬤  ⏺  ⚑  ⛔
  sign define breakpoint text=⛔ texthl=Debug
else
  sign define breakpoint text=x texthl=Debug
endif

sign define currentline text=-> texthl=Search

let s:job = ''
let s:channel = ''
let s:running = 0
let s:org_win_id = 0
let s:currentfile = ''

function! s:hash(name, linenumber)
  let l:result = 1
  for c in split(a:name, '\zs')
    let l:result = (l:result * 2) + char2nr(c)
  endfor
  let l:result = (l:result * 2) + a:linenumber
  return strpart(l:result, 4)
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
  echom a:msg
  let l:breakpoint = ''
  if -1 < stridx(a:msg, 'Breakpoint hit: "thread')
    echom "breakpoint hit"
    let l:breakpoint = split(a:msg, ',')
    let l:filename = l:breakpoint[1]
    let l:filename = substitute(l:filename, '\.\w*()$', '', '')
    let l:filename = substitute(l:filename, ' ', '', 'g')
    let l:filenamefrag= split(l:filename, '\.')
    let l:filename = findfile(filenamefrag[-1])
    echom 'found file ' . l:filename
    let l:linenumber = substitute(l:breakpoint[2], ',\|\.\| \|bci=\d*\|line=', '', 'g')
    " only open when current buffer is not the file to open
    if l:filename != s:currentfile
      if filereadable(l:filename)
        exe 'e +%foldopen! **/'. l:filename 
	let s:currentfile = l:filename
        exe l:linenumber
        exe 'sign unplace 2'
        exe 'sign place 2 line='. l:linenumber .' name=currentline file='.  expand("%:p")
      else 
	echom 'tried to open file ' . l:filename
      endif
    endif
  endif
  if -1 < stridx(a:msg, 'Step completed: "thread')
    " TODO handle ClassName$3.get()
    echom "Step completed"
    let l:breakpoint = split(a:msg, ',')
    let l:filename = l:breakpoint[1]
    let l:filename = substitute(l:filename, '\.\w*()$', '', '')
    let l:filename = substitute(l:filename, ' ', '', 'g')
    let l:filenamefrag= split(l:filename, '\.')
    let l:filename = findfile(filenamefrag[-1])
    echom 'found file ' . l:filename
    let l:linenumber = substitute(l:breakpoint[2], ',\|\.\| \|bci=\d*\|line=', '', 'g')
    " only open when current buffer is not the file to open
    " if l:filename != l:currentfile
      if filereadable(l:filename)
        exe 'e +%foldopen! **/'. l:filename
	let s:currentfile = l:filename
        exe l:linenumber
        exe 'sign unplace 2'
        exe 'sign place 2 line='. l:linenumber .' name=currentline file='.  expand("%:p")
      else 
	echom 'tried to open file ' . l:filename
      endif
    " endif
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
  if -1 < stridx(a:msg, 'The application exited')
    exe 'sign unplace 2'
    let s:channel = ''
    let s:job = ''
    let s:running = 0
    let win = bufwinnr('_JDB_SHELL_')
    if win != -1
      exe win . 'wincmd w'
      exe 'close'
    endif
  endif
endfunction

function! JdbErrHandler(channel, msg)
  let s:running = 0
  echoe 'Error on JDB communication: '. a:msg
endfunction

let s:signCounter = 10
let s:signtype = 'breakpoint'

function! s:applyBreakPoints(channel, name)
  let l:points = split(execute('sign place'), '\n')
  let l:fileName = ''
  for line in l:points
    " Start of new file, listing all signs for this
    if -1 < stridx(line, 'Signs for')
      let l:lineparts = split(line, ' ')
      let l:fileName = l:lineparts[-1]
      let l:fileName = substitute(l:fileName ,':$', '', 'g')
    endif
    " if sign found with given name
    if -1 < stridx(line, 'name='. a:name)
      let l:lineparts = split(line, ' ')
      let l:lineNumber = substitute(l:lineparts[0], 'line=','','g')
      let l:className = s:getClassNameFromFile(l:fileName)
      echom 'breakpoint line: ' . l:fileName .':'. l:lineNumber
      call ch_sendraw(a:channel, "stop at " . l:className . ":" . l:lineNumber . "\n")
    endif
  endfor
endfunction

function! s:setBreakpoint()
  let l:fileName = expand('%:p')
  let l:lineNumber = line('.') 
  let l:currentBuffer = bufnr('%')
  exe 'sign place ' . s:signCounter . ' line=' . l:lineNumber . ' name=' . s:signtype . ' buffer=' . l:currentBuffer
  let s:signCounter = s:signCounter + 1
  if s:running == 1
    call s:breakpointOnLine(l:fileName, l:lineNumber)
  endif
endfunction

function! s:removeBreakpoint() 
  sign unplace 
  call s:clearBreakpointOnLine(expand('%:p'), line('.'))
endfunction

function! s:openWindow(name, mode, size)
    let win = bufwinnr(a:name)
    if win == -1
        exe 'silent keepalt '. a:mode .' split '. a:name
        exe 'silent '. a:mode .' resize '. a:size
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
endfunction

function! s:attach(...)
  if s:job == '' || job_status(s:job) != 'run'
    " save current window state
	  let s:org_win_id = win_getid()
	  let l:winview = winsaveview()

    let l:arg1 = get(a:, 1, 'localhost:5005')
    let l:jdbCommand = get(g:, 'vimjdb_jdb_command', 'jdb')
    call s:openWindow('_JDB_SHELL_', '', 15)
    echom "Attaching to java process"
    let s:job = job_start(l:jdbCommand .' -attach '. l:arg1, {"out_modifiable": 0, "out_io": "buffer", "out_name": "_JDB_SHELL_", "out_cb": "JdbOutHandler", "err_modifiable": 0, "err_io": "buffer", "err_name": "_JDB_SHELL_", "err_cb": "JdbErrHandler"})
    let s:channel = job_getchannel(s:job)

    call ch_sendraw(s:channel, "run\n")
    call ch_sendraw(s:channel, "monitor where\n")
     
    " apply breakpoint into jdb process from defined signs
    call s:applyBreakPoints(s:channel, 'breakpoint')
    let s:running = 1

    " Set cursor in where you started the process, in the correct buffer
    call win_gotoid(s:org_win_id)
    call winrestview(l:winview)
  else
    echom 'There is already a JDB session running. Detach first before you start a new one.'
  endif
endfunction

function! s:detach()
  if s:job != '' && job_status(s:job) == 'run'
    exe 'sign unplace 2'
    call ch_sendraw(s:channel, "exit\n")
    let s:channel = ''
    let s:job = ''
    let s:running = 0
    let win = bufwinnr('_JDB_SHELL_')
    if win != -1
      exe win . 'wincmd w'
      exe 'close'
    endif
  endif
endfunction

function! s:breakpointOnLine(fileName, lineNumber)
  if s:channel != ''
    let l:fileName = s:getClassNameFromFile(a:fileName)
    call ch_sendraw(s:channel, "stop at " . l:fileName . ":" . a:lineNumber . "\n")
  endif
endfunction

function! s:clearBreakpointOnLine(fileName, lineNumber)
  if s:channel != ''
    let l:fileName = s:getClassNameFromFile(a:fileName)
    call ch_sendraw(s:channel, "clear " . l:fileName . ":" . a:lineNumber . "\n")
  endif
endfunction

" for all driver options check if running=0 if so please start the process by sending run first
function! s:continue()
  if s:running == 0 
     call ch_sendraw(s:channel, "run\n")
     let s:running = 1
  endif
  call ch_sendraw(s:channel, "resume\n")
endfunction

function! s:stepOver()
  if s:running == 0 
     call ch_sendraw(s:channel, "run\n")
     let s:running = 1
  endif
  call ch_sendraw(s:channel, "next\n")
endfunction

function! s:stepUp()
  if s:running == 0 
     call ch_sendraw(s:channel, "run\n")
     let s:running = 1
  endif
  call ch_sendraw(s:channel, "step up\n")
endfunction

function! s:stepIn()
  if s:running == 0 
     call ch_sendraw(s:channel, "run\n")
     let s:running = 1
  endif
  call ch_sendraw(s:channel, "step in\n")
endfunction

function! s:stepI()
  if s:running == 0 
     call ch_sendraw(s:channel, "run\n")
     let s:running = 1
  endif
  call ch_sendraw(s:channel, "stepi\n")
endfunction

function! s:command(command)
  call ch_sendraw(s:channel, a:command . "\n")
endfunction

function! s:toggleWatchWindow()
  let win = bufwinnr('_JDB_WATCH_')
  if win != -1
    exe win . 'wincmd w'
    exe 'close'
  else
    call s:openWindow('_JDB_WATCH_', 'vertical', 15)
  endif
endfunction

function! s:createDebugProcess()
	let l:running = 0

  " save current window state
	let s:org_win_id = win_getid()
	let l:winview = winsaveview()
	" TODO Figure out a way to properly detect if the current function is a test
  " or not, if so start the debugging wih this otherwise fall back to setting
  " main
	" get current function name
	echom 'Finding java process and starting it'
  " Backwards search for @Test annotation and grab the function it defines
  call search('@Test','bce')
	execute "normal! wwwyt("
	let l:fnname = @"
	echom 'Function name: '. l:fnname

	" get package name
	execute "normal! ggwyt;"
	let l:pcname = @"
	
	" get class name
	call search("public class", 'e')
	execute "normal! wyiW"
	let l:clname = @"

  " Build unit test process string
	let l:appArgs = ''
	if l:fnname != ''
		let l:appArgs .= ' -Dtest.single=' . l:fnname
	endif
	let l:appArgs .= ' ' . get(g:, 'vimjdb_unit_test_class', 'org.junit.runner.JUnitCore')
	let l:appArgs .= ' ' . l:pcname . '.' . l:clname 

  " start jdb process in a new buffer
	let l:jdbCommand = get(g:, 'vimjdb_jdb_command', 'jdb')
	let l:process = l:jdbCommand .' '. l:appArgs
	echom 'starting job: ' . l:process
	call s:openWindow('_JDB_SHELL_', '', 15)
	let s:job = job_start(l:process , {"out_modifiable": 0, "out_io": "buffer", "out_name": "_JDB_SHELL_", "out_cb": "JdbOutHandler", "err_modifiable": 0, "err_io": "buffer", "err_name": "_JDB_SHELL_","err_cb": "JdbErrHandler"})
	let s:channel = job_getchannel(s:job)

  " Apply breakpoints stored in sign's into the debug process
  call s:applyBreakPoints(s:channel, 'breakpoint')

  " Set cursor in where you started the process, in the correct buffer
	call win_gotoid(s:org_win_id)
	call winrestview(l:winview)

endfunction
