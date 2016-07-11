
command! JDBAttach call Attach()
command! JDBDetach call Detach()
command! JDBBreakpointOnLine call BreakpointOnLine(expand('%:~:.'), line('.'))
command! JDBClearBreakpointOnLine call ClearBreakpointOnLine(expand('%:~:.'), line('.'))

function! s:getClassNameFromFile(filename)
  let l:className=fnamemodify(a:filename,':t:r')
  for l:line in readfile(a:filename)
    let l:matches=matchlist(l:line,'\vpackage\s+(%(\w|\.)+)\s*;')
    if 1<len(l:matches)
      return l:matches[1].'.'.l:className
    endif
  endfor
  return l:className
endfunction

function! Attach()
  ruby $jdb.attach()
endfunction

function! Detach()
  ruby $jdb.detach()
endfunction

function! BreakpointOnLine(fileName, lineNumber)
  "TODO check if we are on a java file and fail if not
  let fileName = s:getClassNameFromFile(a:fileName)
  ruby $jdb.addBreakpointOnLine(VIM::evaluate('fileName'), VIM::evaluate('a:lineNumber'))
endfunction

function! ClearBreakpointOnLine(fileName, lineNumber)
  "TODO check if we are on a java file and fail if not
  let fileName = s:getClassNameFromFile(a:fileName)
  ruby $jdb.clearBreakpointOnLine(VIM::evaluate('fileName'), VIM::evaluate('a:lineNumber'))
endfunction

ruby << EOF

require 'open3'

module JDB

  class JDB
    attr_reader :main
    attr_reader :stdin
    attr_reader :stdout
    attr_reader :stderr
    attr_reader :breakpoints

    def initialize
      @breakpoints = Array.new
    end

    public
    def attach
      if nil == @main
        @main = Thread.new {
          @stdin, @stdout, @stderr = Open3.popen3('/home/ms/progs/jdk1.8/bin/jdb -attach localhost:5005')

          Thread.new {
            while true
              Vim::message(@stdout.gets)
            end
          }

          Thread.new {
            while true
              Vim::message(@stderr.gets)
            end
          }

          @stdin.puts('monitor where')
          @stdin.puts('run')
          Vim::message('Attached to JVM!')
        }
        Thread.new {
          @main.join
        }
      else
        Vim::message('There is already a JDB session running. Detach first before you can start a new one.')
      end
    end

    def detach
      @stdin.puts('exit')
      @stdin.puts('exit')
      @main.kill if nil != @main
      @main = nil
    end

    def addBreakpointOnLine(fileName, lineNumber)
      Vim::message("stop at #{fileName}:#{lineNumber}")
      if nil != @main
        @stdin.puts("stop at #{fileName}:#{lineNumber}")
      else
        @breakpoints.push("stop at #{fileName}:#{lineNumber}")
      end
    end

    def clearBreakpointOnLine(fileName, lineNumber)
      Vim::message("clear at #{fileName}:#{lineNumber}")
      if nil != @main
        @stdin.puts("clear at #{fileName}:#{lineNumber}")
      else
        @breakpoints.push("clear at #{fileName}:#{lineNumber}")
      end
    end
  end
end

$jdb = JDB::JDB.new

EOF

