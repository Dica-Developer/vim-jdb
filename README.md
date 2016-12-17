# vim-jdb

Its a JAVA debugger frontend plugin for VIM. It allows to debug a JAVA program via the JDB debugger. It allows remote debugging via attach parameter.
It marks by vim-jdb setted breakpoints and shows the current file and line the debugger stays in.

It requires VIM >= 8.0 and VIM compiled with `channel`, `signs` and `job` support.

## How to use

1. start JAVA process with the following debug agent option, e.g. `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005'
`
2. attach to the JAVA process from your VIM with VIM-JDB like `:JDBAttach` or by explicitly specifying host and port `:JDBAttach localhost:5005`
3. now the JDB shell buffer should open and signal that it connected to the JAVA process
4. open a JAVA file and go to the line in it where you want to set a breakpoint
5. set a breakpoint on the current line in the current file by using the command `:JDBBreakpointOnLine`
6. breakpoints are marked depending on your terminals and VIMs capabilities with a `⛔` or `x`
7. if your programm stops at the breakpoint this is marked with a `->`
8. use the command `:JDBStepOver` to execute to the next line
9. with `:JDBCommand` you can send any JDB command to the JDB JAVA process, e.g. you want to see all locals do `:JDBCommands locals`

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

