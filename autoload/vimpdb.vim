" vim:set fenc=utf-8 ff=unix foldmethod=marker :

function! vimpdb#Test()"{{{
  echo "vimpdb Test"
endfunction"}}}

function! vimpdb#test2()"{{{
  echo "vimpdb Test2"
	"let current_dir = expand("%:p:h")
  let files = globpath(&runtimepath, "autoload/vimpdb.vim")
  let file = split(files, "\n")
  if empty(file)
    throw 'vimpdb.vim not found'
    finish
  endif
  echo file
	"let current_dir = expand("<sfile>")
  let current_dir = substitute(file[0], '\v(/.*)/(.*)', '\1', '')
  let parent_dir = substitute(current_dir, '\v(/.*)/(.*)', '\1', '')
  echo current_dir
  echo parent_dir
	python import sys
	"exe 'python sys.path.insert(0, "' . current_dir . '")'
	exe 'python sys.path.insert(0, r"' . parent_dir . '")'
	python import VimPdb
endfunction"}}}

function! vimpdb#Initialize()"{{{
	" Initializes the VimPdb pluging.

	"au BufLeave *.py :call vimpdb#BuffLeave()
	"au BufEnter *.py :call vimpdb#BuffEnter()
	"au BufEnter *.py :call vimpdb#MapKeyboard()
	"au VimLeave *.py :call vimpdb#StopDebug()

	"call vimpdb#MapKeyboard()

	"let current_dir = expand("%:p:h")
	let current_dir = expand("<sfile>:p:h")
  let parent_dir = substitute(current_dir, '\v(/.*)/(.*)', '\1', '')
	python import sys
	exe 'python sys.path.insert(0, "' . parent_dir . '")'
	python import VimPdb

	python << EOF
import vim
import threading
import time
import re

reload(VimPdb)


# The VimPdb instance used for debugging.
vim_pdb = VimPdb.VimPdb()
vim_pdb.stack_entry_format = vim.eval('g:stack_entry_format')
vim_pdb.stack_entry_prefix = vim.eval('g:stack_entry_prefix')
vim_pdb.current_stack_entry_prefix = vim.eval('g:current_stack_entry_prefix')
vim_pdb.stack_entries_joiner = vim.eval('g:stack_entries_joiner')


def vim_pdb_start_debug(stop_immediately, args):
	global vim_pdb
	vim_pdb.start_debugging(vim.current.buffer.name, stop_immediately, args)


def parse_command_line(line):
	"""Parses command line."""
	args = []
	while (len(line) > 0):
		if (line[0] == '"'):
			next_quotation_mark = line.find('"', 1)
			if (next_quotation_mark == -1):
				# No ending quotation mark found.
				line = line[1:]
				continue

			# Treat anything between the two quotation marks as one argument.
			args.append(line[1:next_quotation_mark])
			line = line[next_quotation_mark + 1:]
			continue

		match = re.search('\s+', line)
		if (not match):
			# No whitespace found - save the argument until the end of the line.
			args.append(line)
			line = ""
			continue
		if (match.start() == 0):
			# Whitespace in the beginning of the line - skip it.
			line = line[match.end():]
			continue

		args.append(line[:match.start()])
		line = line[match.end():]

	return args
EOF

endfunction"}}}



"
" Vim event related functions
"

function! vimpdb#BuffLeave()
	" Used when leaving the current buffer - clear all highlighting.

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('clear_current_line_highlighting')
	vim_pdb.add_queued_method('clear_breakpoints_highlighting')
EOF
endfunction

function! vimpdb#BuffEnter()
	" Used when entering a new buffer - highlighting all breakpoints, etc (if there are any).

	python <<EOF
if (vim_pdb.is_debugged()):
	file('out.txt', 'a').write('BuffEnter\n')
	vim_pdb.add_queued_method('highlight_current_line_for_file', vim.current.buffer.name)
	vim_pdb.add_queued_method('highlight_breakpoints_for_file', vim.current.buffer.name)
EOF
endfunction


"
" Start\Stop debugging functions
"


function! vimpdb#StartDebug(stop_immediately, args)
	" Start a debugging session for the current buffer.
	
	python << EOF
if ((not vim_pdb) or (not vim_pdb.is_debugged())):
	# Start a new VimPdb debugging thread (so Vim won't get halted).
	stop_immediately = bool(int(vim.eval('a:stop_immediately')))
	args = list(vim.eval('a:args'))
	vim_pdb_thread = threading.Thread(target = vim_pdb_start_debug, args = (stop_immediately, args))
	vim_pdb_thread.setDaemon(False)
	vim_pdb_thread.start()
else:
	# Just continue the debugging.
	vim_pdb.add_queued_method('do_continue')
EOF


	if (g:auto_load_breakpoints_file == 1)
		" Load the default breakpoints file at the beginning of the
		" debugging session.
		call vimpdb#LoadSavedBreakpoints(g:default_breakpoints_filename)
	endif
endfunction

function! vimpdb#StartDebugWithArguments()
	" Start a debugging session for the current buffer, with a list of
	" arguments given by the user.
	
	python << EOF
# Get the arguments from the user.
command_line = vim.eval('input("Arguments: ")')

if (command_line is not None):
	# Parse the arguments.
	args = parse_command_line(command_line)

	if (not vim_pdb):
		vim.command('call vimpdb#StartDebug(1, %s)' % (args))
	else:
		# TODO - special case?
		if (vim_pdb.is_debugged()):
			# Stop the existing debugging session.
			vim.command('call vimpdb#StopDebug()')
			vim.command('call vimpdb#Initialize()')

		vim.command('call vimpdb#StartDebug(1, %s)' % (args))

EOF
endfunction


function! vimpdb#StopDebug()
	" Stops an active debugging session.

	if (g:auto_save_breakpoints_file == 1)
		" Save to the default breakpoints file at the end of the
		" debugging session.
		call vimpdb#SaveSavedBreakpoints(g:default_breakpoints_filename)
	endif
	
	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('stop_debugging')

	# Wait until the thread terminates.
	while (vim_pdb_thread.isAlive()):
		time.sleep(0.1)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF


endfunction

function! vimpdb#RestartDebug()
	" Restarts a debugging session.
	call vimpdb#StopDebug()
	call vimpdb#StartDebug(1, [])
endfunction


"
" Saving\Loading breakpoints methods
"


function! vimpdb#LoadSavedBreakpoints(...)
	" Loads saved breakpoints from a file.

	python <<EOF
if (vim_pdb.is_debugged()):
	if (int(vim.eval('a:0')) == 0):
		filename = vim.eval('input("Filename: ")')
	else:
		filename = vim.eval('a:1')

	if (filename is not None):
		vim_pdb.add_queued_method('load_breakpoints_from_file', filename)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE

EOF
endfunction


function! vimpdb#SaveSavedBreakpoints(...)
	" Saves saved breakpoints to a file.

	python <<EOF
if (vim_pdb.is_debugged()):
	if (int(vim.eval('a:0')) == 0):
		filename = vim.eval('input("Filename: ")')
	else:
		filename = vim.eval('a:1')

	if (filename is not None):
		vim_pdb.add_queued_method('save_breakpoints_to_file', filename)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE

EOF
endfunction




"
" Deubgging methods
"


function! vimpdb#Continue()
	" Continues a debugging session.

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_continue')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#StepInto()
	" Performs a step into

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_step_into')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#StepOver()
	" Performs a step over

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_step_over')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#ContinueUntilReturn()
	" Performs continue until returning

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_continue_until_return')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction


function! vimpdb#JumpToCurrentLine()
	" Jumps to the specified current line.

	python <<EOF
if (vim_pdb.is_debugged()):
	line_number = int(vim.eval('line(".")'))
	vim_pdb.add_queued_method('do_jump', vim.current.buffer.name, line_number)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction


function! vimpdb#MoveUpInStackFrame()
	" Moves up one level in the stack frame.

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_move_up_in_stack_frame')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#MoveDownInStackFrame()
	" Moves down one level in the stack frame.

	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_move_down_in_stack_frame')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction


function! vimpdb#ToggleBreakpointOnCurrentLine()
	" Toggles breakpoint on the current line.

	python << EOF
if (vim_pdb.is_debugged()):
	line_number = int(vim.eval('line(".")'))
	vim_pdb.add_queued_method('do_toggle_breakpoint', vim.current.buffer.name, line_number)
	vim_pdb.add_queued_method('highlight_breakpoints_for_file', vim.current.buffer.name)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#ToggleConditionalBreakpointOnCurrentLine()
	" Toggles a conditional breakpoint on the current line.

	python << EOF
if (vim_pdb.is_debugged()):
	line_number = int(vim.eval('line(".")'))

	if ((not vim_pdb.run_method_and_return_output('is_breakpoint_enabled', vim.current.buffer.name, line_number)) and
		(vim_pdb.run_method_and_return_output('is_code_line', vim.current.buffer.name, line_number))):
		condition = vim.eval('input("Condition: ")')

		if ((condition is not None) and (len(condition.strip()) > 0)):
			vim_pdb.add_queued_method('do_toggle_breakpoint', vim.current.buffer.name, line_number, condition.strip())
	else:
		condition = None
		vim_pdb.add_queued_method('do_toggle_breakpoint', vim.current.buffer.name, line_number, condition)

else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#ToggleTemporaryBreakpointOnCurrentLine()
	" Toggles a temporary breakpoint on the current line.

	python << EOF
if (vim_pdb.is_debugged()):
	line_number = int(vim.eval('line(".")'))
	vim_pdb.add_queued_method('do_toggle_breakpoint', vim.current.buffer.name, line_number, None, True)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction



function! vimpdb#ClearAllBreakpointsInCurrentFile()
	" Clears all breakpoints in the current file.

	python << EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_clear_all_breakpoints', vim.current.buffer.name)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#ClearAllBreakpoints()
	" Clears all breakpoints in all files.

	python << EOF
if (vim_pdb.is_debugged()):
	vim_pdb.add_queued_method('do_clear_all_breakpoints')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction


function! vimpdb#PrintBreakpointConditionOnCurrentLine()
	" Prints the condition of the conditional breakpoint in the current line.

	python << EOF
if (vim_pdb.is_debugged()):
	line_number = int(vim.eval('line(".")'))

	print vim_pdb.run_method('do_print_breakpoint_condition', vim.current.buffer.name, line_number)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction



function! vimpdb#EvalCurrentWord()
	" Evals the word currently under the cursor.

	python <<EOF
if (vim_pdb.is_debugged()):
	current_word = vim.eval('expand("<cword>")')

	if ((current_word is not None) and (len(current_word.strip()) > 0)):
		vim_pdb.run_method('do_eval', current_word)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#EvalCurrentWORD()
	" Evals the WORD currently under the cursor.

	python <<EOF
if (vim_pdb.is_debugged()):
	current_word = vim.eval('expand("<cWORD>")')

	if ((current_word is not None) and (len(current_word.strip()) > 0)):
		vim_pdb.run_method('do_eval', current_word)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction

function! vimpdb#EvalExpression()
	" Evals an expression given by the user.

	python <<EOF
if (vim_pdb.is_debugged()):
	expression = vim.eval('input("Eval Expression: ")')
	if (expression is not None):
		vim_pdb.run_method('do_eval', expression)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction


function! vimpdb#ExecStatement()
	" Execs a statement given by the user.

	python <<EOF
if (vim_pdb.is_debugged()):
	statement = vim.eval('input("Exec Statement: ")')
	if (statement is not None):
		vim_pdb.run_method('do_exec', statement)
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction


function! vimpdb#PrintStackTrace()
	" Prints the current stack trace.
	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.run_method('do_print_stack_trace')
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction



function! vimpdb#SetFocusToCurrentDebugLine()
	" Moves the cursor to the currently debugged line.
	python <<EOF
if (vim_pdb.is_debugged()):
	vim_pdb.set_cursor_to_current_line()
else:
	print VimPdb.VimPdb.MESSAGE_NOT_IN_DEBUG_MODE
EOF
endfunction



" ==========
" EDIT HERE
" ==========



"
" Line highlighting
"


highlight PdbCurrentLine guibg=DarkGreen
highlight PdbBreakpoint guibg=DarkRed
highlight PdbConditionalBreakpoint guibg=Purple
highlight PdbTemporaryBreakpoint guibg=SlateBlue


function! vimpdb#MapKeyboard()
	"
	" Keyboard shortcuts
	"

	map <buffer> <silent> <F5> :call vimpdb#StartDebug(1, [])<CR>
	" Start debug and don't pause immediately.
	map <buffer> <silent> <C-F5> :call vimpdb#StartDebug(0, [])<CR>
	map <buffer> <silent> <C-S-F5> :call vimpdb#StartDebugWithArguments()<CR>
	map <buffer> <silent> <S-F5> :call vimpdb#StopDebug()<CR>
	map <buffer> <silent> <C-A-S-F5> :call vimpdb#RestartDebug()<CR>

	map <buffer> <silent> <LocalLeader>l :call vimpdb#LoadSavedBreakpoints()<CR>
	map <buffer> <silent> <LocalLeader>s :call vimpdb#SaveSavedBreakpoints()<CR>

	map <buffer> <silent> <F7> :call vimpdb#StepInto()<CR>
	map <buffer> <silent> <F8> :call vimpdb#StepOver()<CR>
	map <buffer> <silent> <C-F8> :call vimpdb#ContinueUntilReturn()<CR>

	map <buffer> <silent> <F9> :call vimpdb#MoveUpInStackFrame()<CR>
	map <buffer> <silent> <F10> :call vimpdb#MoveDownInStackFrame()<CR>

	map <buffer> <silent> <F6> :call vimpdb#SetFocusToCurrentDebugLine()<CR>
	map <buffer> <silent> <C-F6> :call vimpdb#JumpToCurrentLine()<CR>

	map <buffer> <silent> <F2> :call vimpdb#ToggleBreakpointOnCurrentLine()<CR>
	map <buffer> <silent> <C-F2> :call vimpdb#ToggleConditionalBreakpointOnCurrentLine()<CR>
	map <buffer> <silent> <S-F2> :call vimpdb#ToggleTemporaryBreakpointOnCurrentLine()<CR>
	map <buffer> <silent> <C-S-F2> :call vimpdb#ClearAllBreakpointsInCurrentFile()<CR>
	map <buffer> <silent> <C-A-S-F2> :call vimpdb#ClearAllBreakpoints()<CR>

	map <buffer> <silent> <F11> :call vimpdb#PrintBreakpointConditionOnCurrentLine()<CR>

	map <buffer> <silent> <F4> :call vimpdb#EvalCurrentWord()<CR>
	map <buffer> <silent> <C-F4> :call vimpdb#EvalCurrentWORD()<CR>

	map <buffer> <silent> <F3> :call vimpdb#EvalExpression()<CR>
	map <buffer> <silent> <C-F3> :call vimpdb#ExecStatement()<CR>

	map <buffer> <silent> <F12> :call vimpdb#PrintStackTrace()<CR>
endfunction


" The format string for displaying a stack entry.
let g:stack_entry_format = "%(dir)s\\%(filename)s (%(line)d): %(function)s(%(args)s) %(return_value)s %(source_line)s"
" The string used to join stack entries together.
let g:stack_entries_joiner = " ==>\n"
" The prefix to each stack entry - 'regular' and current stack entry.
let g:stack_entry_prefix = "  "
let g:current_stack_entry_prefix = "* "

" Should VimPdb look for saved breakpoints file when starting a debug session?
let g:auto_load_breakpoints_file = 0
" Should VimPdb save the breakpoints file when stopping the debug session?
let g:auto_save_breakpoints_file = 0
" The name of the default saved breakpoints file (in the currently debugged directory).
" Used when auto_load_breakpoints_file/auto_save_breakpoints_file are turned on.
let g:default_breakpoints_filename = "bplist.vpb"



"
" Main code
"


" call vimpdb#Initialize()

