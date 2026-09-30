let s:suite = themis#suite('SQL Server database tree')
let s:expect = themis#helper('expect')

function! s:suite.before() abort
  let s:bin = fnamemodify('test/bin', ':p')
  let $PATH = s:bin . ':' . $PATH
endfunction

" Each test starts from a clean drawer/connection state.
function! s:begin(...) abort
  call Cleanup()
  call s:setup_dbs(get(a:, 1, 'sqlserver://sa:pass@localhost:1433'))
endfunction

function! s:suite.after() abort
  call Cleanup()
endfunction

function! s:setup_dbs(url) abort
  call db_ui#reset_state()
  let g:dbs = [{'name': 'sqlserver_test', 'url': a:url}]
endfunction

function! s:suite.should_show_databases_section_on_connection_expand() abort
  call s:begin()
  :DBUI
  normal o
  call s:expect(getline(1, '$')).to_equal([
        \ '▾ sqlserver_test ✓',
        \ '  + New query',
        \ '  ▸ Saved queries (0)',
        \ '  ▸ Databases (3)',
        \ ])
endfunction

function! s:suite.should_list_databases_with_current_marked() abort
  call s:begin()
  :DBUI
  normal o
  " Expand Databases (3)
  call cursor(4, 1)
  normal o
  call s:expect(getline(4, '$')).to_equal([
        \ '  ▾ Databases (3)',
        \ '    ▸ master *',
        \ '    ▸ OtherDb',
        \ '    ▸ BadDb',
        \ ])
endfunction

function! s:suite.should_mark_url_database_when_set() abort
  call s:begin('sqlserver://sa:pass@localhost:1433/OtherDb')
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  call s:expect(getline(4, '$')).to_equal([
        \ '  ▾ Databases (3)',
        \ '    ▸ master',
        \ '    ▸ OtherDb *',
        \ '    ▸ BadDb',
        \ ])
endfunction

function! s:suite.should_lazily_expand_database_to_schemas_and_tables() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand OtherDb (line 6)
  call cursor(6, 1)
  normal o
  call s:expect(getline(6, '$')).to_equal([
        \ '    ▾ OtherDb',
        \ '      ▸ dbo (1)',
        \ '    ▸ BadDb',
        \ ])
  " Expand schema dbo
  call cursor(7, 1)
  normal o
  call s:expect(getline(6, '$')).to_equal([
        \ '    ▾ OtherDb',
        \ '      ▾ dbo (1)',
        \ '        ▸ projects',
        \ '    ▸ BadDb',
        \ ])
endfunction

function! s:suite.should_show_error_hint_for_unreadable_database() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand BadDb, whose introspection fails
  call cursor(7, 1)
  normal o
  call s:expect(getline(6, '$')).to_equal([
        \ '    ▸ OtherDb',
        \ '    ▾ BadDb ✕',
        \ '      (DB exec error (exit 1))',
        \ ])
endfunction

function! s:suite.should_open_query_buffer_targeting_database() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand OtherDb and its schema
  call cursor(6, 1)
  normal o
  call cursor(7, 1)
  normal o
  " Expand table projects, then open the List helper on it
  call cursor(8, 1)
  normal o
  call cursor(9, 1)
  normal o
  call s:expect(getbufvar(bufnr(''), 'dbui_database_name')).to_equal('OtherDb')
  call s:expect(getbufvar(bufnr(''), 'db')).to_equal('sqlserver://sa:pass@localhost:1433/OtherDb')
  call s:expect(getline(1, '$')).to_equal(['select top 200 * from [OtherDb].dbo.[projects]'])
  let statusline = db_ui#statusline({'prefix': '', 'show': ['db_name', 'database', 'table']})
  call s:expect(statusline).to_equal('sqlserver_test -> OtherDb -> projects')
endfunction

function! s:suite.should_fall_back_to_schemas_when_adapter_lacks_databases() abort
  " Simulate an older vim-dadbod without the databases() capability.
  silent! delfunction db#adapter#sqlserver#databases
  call s:begin()
  :DBUI
  normal o
  call s:expect(getline(1, '$')).to_equal([
        \ '▾ sqlserver_test ✓',
        \ '  + New query',
        \ '  ▸ Saved queries (0)',
        \ '  ▸ Schemas (1)',
        \ ])
  " Restore the capability for any later runs.
  execute 'source' globpath(&rtp, 'autoload/db/adapter/sqlserver.vim')
endfunction

function! s:suite.should_not_enable_database_level_for_other_schemes() abort
  call s:expect(db_ui#schemas#supports_databases(db_ui#schemas#get('mysql'), 'mysql://root@localhost')).to_equal(0)
  call s:expect(db_ui#schemas#supports_databases(db_ui#schemas#get('postgres'), 'postgres://postgres@localhost')).to_equal(0)
endfunction

" vim:ft=vim
