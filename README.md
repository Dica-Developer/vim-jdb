# vim-jdb

Its a JAVA debugger frontend plugin for VIM. It allows to debug a JAVA program via the JDB debugger. It allows remote debugging via attach parameter.
It marks by vim-jdb setted breakpoints and shows the current file and line the debugger currently stays.

It requires VIM >= 8.0 and that VIm is compiled with `channel`, `signs` and `job` support.


## Commands
|Command|Description|
| ------------- |:-------------:|
|JDBAttach|attach to a running JVM with a debug listener on localhost:5005, can be overwritten by given host:port as an argument|
|JDBDetach|detach the debugger UI from the application that is currently debugged|
|JDBBreakpointOnLine|set a breakpoint on the current line|
|JDBClearBreakpointOnLine|clear the breakpoint on the current line|
|JDBContinue|continues the execution until the next breakpoint|
|JDBStepOver|steps to the next line|
|JDBStepIn|steps a level down the stack|
|JDBStepUp|steps a level up in the stack|
|JDBStepI|steps to the next instruction|
|JDBCommand|send any JDB command to the application under debug|

## Global variables

To specify the JDB command to use you can overwrite the following variable `g:vimjdb_jdb_command`. The default is `jdb`.
