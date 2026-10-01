let s:suite = themis#suite('SQL Server database tree')
let s:expect = themis#helper('expect')

function! s:suite.before() abort
  let s:bin = fnamemodify('test/bin', ':p')
  let $PATH = s:bin . ':' . $PATH
endfunction

function! s:suite.after() abort
  call Cleanup()
endfunction

function! s:setup_dbs(url) abort
  call db_ui#reset_state()
  let g:dbs = [{'name': 'sqlserver_test', 'url': a:url}]
endfunction

" Each test starts from a clean drawer/connection state.
function! s:begin(...) abort
  call Cleanup()
  call s:setup_dbs(get(a:, 1, 'sqlserver://sa:pass@localhost:1433'))
endfunction

" Mock instance enumerates: master (system), OtherDb, BadDb (unreadable).
" Tree after expanding the connection and Databases:
"   1 ▾ sqlserver_test ✓
"   2   + New query
"   3   ▸ Saved queries (0)
"   4   ▾ Databases (2)
"   5     ▸ OtherDb
"   6     ▸ BadDb
"   7     ▸ System Databases (1)

function! s:suite.should_show_databases_section_on_connection_expand() abort
  call s:begin()
  :DBUI
  normal o
  call s:expect(getline(1, '$')).to_equal([
        \ '▾ sqlserver_test ✓',
        \ '  + New query',
        \ '  ▸ Saved queries (0)',
        \ '  ▸ Databases (2)',
        \ ])
endfunction

function! s:suite.should_group_system_databases_in_folder() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  call s:expect(getline(4, '$')).to_equal([
        \ '  ▾ Databases (2)',
        \ '    ▸ OtherDb',
        \ '    ▸ BadDb',
        \ '    ▸ System Databases (1)',
        \ ])
  " Expand the folder: master is inside and marked as the login default.
  call cursor(7, 1)
  normal o
  call s:expect(getline(7, '$')).to_equal([
        \ '    ▾ System Databases (1)',
        \ '      ▸ master *',
        \ ])
  " Expanding master works like any other database (lazy introspection).
  call cursor(8, 1)
  normal o
  call s:expect(getline(8, '$')).to_equal([
        \ '      ▾ master *',
        \ '        ▸ dbo (2)',
        \ ])
  call cursor(9, 1)
  normal o
  call s:expect(getline(9, '$')).to_equal([
        \ '        ▾ dbo (2)',
        \ '          ▸ orders',
        \ '          ▸ users',
        \ ])
endfunction

function! s:suite.should_list_user_databases_with_url_database_marked() abort
  call s:begin('sqlserver://sa:pass@localhost:1433/OtherDb')
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  call s:expect(getline(4, '$')).to_equal([
        \ '  ▾ Databases (2)',
        \ '    ▸ OtherDb *',
        \ '    ▸ BadDb',
        \ '    ▸ System Databases (1)',
        \ ])
endfunction

function! s:suite.should_lazily_expand_database_to_schemas_and_tables() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand OtherDb (line 5)
  call cursor(5, 1)
  normal o
  call s:expect(getline(5, '$')).to_equal([
        \ '    ▾ OtherDb',
        \ '      ▸ dbo (1)',
        \ '    ▸ BadDb',
        \ '    ▸ System Databases (1)',
        \ ])
  " Expand schema dbo
  call cursor(6, 1)
  normal o
  call s:expect(getline(5, '$')).to_equal([
        \ '    ▾ OtherDb',
        \ '      ▾ dbo (1)',
        \ '        ▸ projects',
        \ '    ▸ BadDb',
        \ '    ▸ System Databases (1)',
        \ ])
endfunction

function! s:suite.should_show_error_hint_for_unreadable_database() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand BadDb, whose introspection fails
  call cursor(6, 1)
  normal o
  call s:expect(getline(5, '$')).to_equal([
        \ '    ▸ OtherDb',
        \ '    ▾ BadDb ✕',
        \ '      (DB exec error: Msg 916, Level 14, State 1, Server mock, Line 1)',
        \ '    ▸ System Databases (1)',
        \ ])
endfunction

function! s:suite.should_open_query_buffer_targeting_database() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand OtherDb and its schema
  call cursor(5, 1)
  normal o
  call cursor(6, 1)
  normal o
  " Expand table projects, then open the List helper on it
  call cursor(7, 1)
  normal o
  call cursor(8, 1)
  normal o
  call s:expect(getbufvar(bufnr(''), 'dbui_database_name')).to_equal('OtherDb')
  call s:expect(getbufvar(bufnr(''), 'db')).to_equal('sqlserver://sa:pass@localhost:1433/OtherDb')
  call s:expect(getline(1, '$')).to_equal(['select top 200 * from [OtherDb].dbo.[projects]'])
  let statusline = db_ui#statusline({'prefix': '', 'show': ['db_name', 'database', 'table']})
  call s:expect(statusline).to_equal('sqlserver_test -> OtherDb -> projects')
endfunction

function! s:suite.should_open_query_buffer_targeting_system_database() abort
  call s:begin()
  :DBUI
  normal o
  call cursor(4, 1)
  normal o
  " Expand System Databases, master, and dbo
  call cursor(7, 1)
  normal o
  call cursor(8, 1)
  normal o
  call cursor(9, 1)
  normal o
  " Open the List helper on orders under master (tables sort alphabetically)
  call cursor(10, 1)
  normal o
  call cursor(11, 1)
  normal o
  call s:expect(getbufvar(bufnr(''), 'dbui_database_name')).to_equal('master')
  call s:expect(getbufvar(bufnr(''), 'db')).to_equal('sqlserver://sa:pass@localhost:1433/master')
  call s:expect(getline(1, '$')).to_equal(['select top 200 * from [master].dbo.[orders]'])
endfunction

function! s:suite.should_show_error_when_enumeration_fails() abort
  " Mock server "broken": connect succeeds, enumeration query fails.
  call s:begin('sqlserver://sa:pass@broken:1433')
  :DBUI
  normal o
  call s:expect(getline(1, '$')).to_equal([
        \ '▾ sqlserver_test ✓',
        \ '  + New query',
        \ '  ▸ Saved queries (0)',
        \ '  ▸ Databases (0) ✕',
        \ ])
  call cursor(4, 1)
  normal o
  call s:expect(getline(4, '$')).to_equal([
        \ '  ▾ Databases (0) ✕',
        \ '    (DB exec error: Sqlcmd: Error: connection failed)',
        \ ])
endfunction

function! s:suite.should_show_error_when_enumeration_fails_silently() abort
  " Mock server "silent": error goes to stderr but sqlcmd exits 0, stdout is
  " empty - previously rendered as a bare Databases (0) with no hint.
  call s:begin('sqlserver://sa:pass@silent:1433')
  :DBUI
  normal o
  call s:expect(getline(4)).to_equal('  ▸ Databases (0) ✕')
  call cursor(4, 1)
  normal o
  call s:expect(getline(4, '$')).to_equal([
        \ '  ▾ Databases (0) ✕',
        \ '    (DB exec error: Sqlcmd: Error: The certificate chain was not issued by a trusted authority.)',
        \ ])
endfunction

function! s:suite.should_pass_trust_flag_from_url_param() abort
  " The trustServerCertificate URL param (any casing, trailing ';' tolerated)
  " must reach every sqlcmd invocation as -C. Mock server "tls*" refuses
  " connections without it.
  call s:begin('sqlserver://sa:pass@tls1:1433?TrustServerCertificate=yes;')
  :DBUI
  normal o
  call s:expect(getline(4)).to_equal('  ▸ Databases (2)')
endfunction

function! s:suite.should_fail_tls_enumeration_without_trust_param() abort
  call s:begin('sqlserver://sa:pass@tls1:1433')
  :DBUI
  normal o
  call s:expect(getline(4)).to_equal('  ▸ Databases (0) ✕')
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
