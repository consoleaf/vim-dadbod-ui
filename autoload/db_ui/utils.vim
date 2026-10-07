function! db_ui#utils#slug(str) abort
  return substitute(a:str, '[^A-Za-z0-9_\-]', '', 'g')
endfunction

function! db_ui#utils#input(name, default) abort
  return input(a:name, a:default)
endfunction

function! db_ui#utils#inputlist(list) abort
  return inputlist(a:list)
endfunction

function! db_ui#utils#readfile(file) abort
  try
    let content = readfile(a:file)
    let content = json_decode(join(content, "\n"))
    if type(content) !=? type([])
      throw 'Connections file not a valid array'
    endif
    return content
  catch /.*/
    call db_ui#notifications#warning([
          \ 'Error reading connections file.',
          \ printf('Validate that content of file %s is valid json array.', a:file),
          \ "If it's empty, feel free to delete it."
          \ ])
    return []
  endtry
endfunction

function! db_ui#utils#quote_query_value(val) abort
  if a:val =~? "^'.*'$" || a:val =~? '^[0-9]*$' || a:val =~? '^\(true\|false\)$'
    return a:val
  endif

  return "'".a:val."'"
endfunction

function! db_ui#utils#set_mapping(key, plug, ...)
  let mode = a:0 > 0 ? a:1 : 'n'

  if hasmapto(a:plug, mode)
    return
  endif

  let keys = a:key
  if type(a:key) ==? type('')
    let keys = [a:key]
  endif

  for key in keys
    silent! exe mode.'map <silent><buffer><nowait> '.key.' '.a:plug
  endfor
endfunction

function! db_ui#utils#print_debug(msg) abort
  if !g:db_ui_debug
    return
  endif

  echom '[DBUI Debug] '.string(a:msg)
endfunction

" Return a copy of the connection URL with its database segment replaced,
" so a query buffer opened under a specific database subtree executes
" against that database. The rest of the URL (credentials, params) is kept
" verbatim: vim-dadbod does not URL-decode the database segment, so the raw
" name is inserted without re-encoding.
function! db_ui#utils#database_url(url, database) abort
  let base = matchstr(a:url, '^[^:]\+://.\{-\}/')
  if !empty(base)
    let rest = strpart(a:url, len(base))
    let old_database = matchstr(rest, '[^?#]*')
    return base . a:database . strpart(rest, len(old_database))
  endif
  " No database segment at all: insert one before any params.
  let prefix = matchstr(a:url, '^[^:]\+://.\{-\}\ze[?#]')
  if empty(prefix)
    return a:url . '/' . a:database
  endif
  return prefix . '/' . a:database . strpart(a:url, len(prefix))
endfunction
