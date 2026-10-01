function! s:strip_quotes(results) abort
  return split(substitute(join(a:results),'"','','g'))
endfunction

function! s:results_parser(results, delimiter, min_len) abort
  if a:min_len ==? 1
    return filter(a:results, '!empty(trim(v:val))')
  endif
  let mapped = map(a:results, {_,row -> filter(split(row, a:delimiter), '!empty(trim(v:val))')})
  if a:min_len > 1
    return filter(mapped, 'len(v:val) ==? '.a:min_len)
  endif

  let counts = map(copy(mapped), 'len(v:val)')
  let min_len = max(counts)

  return filter(mapped,'len(v:val) ==? '.min_len)
endfunction

let s:postgres_foreign_key_query = "
      \ SELECT ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name, ccu.table_schema as foreign_table_schema
      \ FROM
      \     information_schema.table_constraints AS tc
      \     JOIN information_schema.key_column_usage AS kcu
      \       ON tc.constraint_name = kcu.constraint_name
      \     JOIN information_schema.constraint_column_usage AS ccu
      \       ON ccu.constraint_name = tc.constraint_name
      \ WHERE constraint_type = 'FOREIGN KEY' and kcu.column_name = '{col_name}' LIMIT 1"

let s:postgres_list_schema_query = "
    \ SELECT nspname as schema_name
    \ FROM pg_catalog.pg_namespace
    \ WHERE nspname !~ '^pg_temp_'
    \   and pg_catalog.has_schema_privilege(current_user, nspname, 'USAGE')
    \ order by nspname"

if empty(g:db_ui_use_postgres_views)
  let postgres_tables_and_views = "
        \ SELECT table_schema, table_name FROM information_schema.tables ;"
else
  let postgres_tables_and_views = "
        \ SELECT table_schema, table_name FROM information_schema.tables UNION ALL
        \ select schemaname, matviewname from pg_matviews;"
endif
let s:postgres_tables_and_views = postgres_tables_and_views

let s:postgresql = {
      \ 'args': ['-A', '-c'],
      \ 'foreign_key_query': s:postgres_foreign_key_query,
      \ 'schemes_query': s:postgres_list_schema_query,
      \ 'schemes_tables_query': s:postgres_tables_and_views,
      \ 'select_foreign_key_query': 'select * from "%s"."%s" where "%s" = %s',
      \ 'cell_line_number': 2,
      \ 'cell_line_pattern': '^-\++-\+',
      \ 'parse_results': {results,min_len -> s:results_parser(filter(results, '!empty(v:val)')[1:-2], '|', min_len)},
      \ 'default_scheme': 'public',
      \ 'layout_flag': '\\x',
      \ 'quote': 1,
      \ }

let s:sqlserver_foreign_keys_query = "
      \ SELECT TOP 1 c2.table_name as foreign_table_name, kcu2.column_name as foreign_column_name, kcu2.table_schema as foreign_table_schema
      \ from   information_schema.table_constraints c
      \        inner join information_schema.key_column_usage kcu
      \          on c.constraint_schema = kcu.constraint_schema and c.constraint_name = kcu.constraint_name
      \        inner join information_schema.referential_constraints rc
      \          on c.constraint_schema = rc.constraint_schema and c.constraint_name = rc.constraint_name
      \        inner join information_schema.table_constraints c2
      \          on rc.unique_constraint_schema = c2.constraint_schema and rc.unique_constraint_name = c2.constraint_name
      \        inner join information_schema.key_column_usage kcu2
      \          on c2.constraint_schema = kcu2.constraint_schema and c2.constraint_name = kcu2.constraint_name and kcu.ordinal_position = kcu2.ordinal_position
      \ where  c.constraint_type = 'FOREIGN KEY'
      \ and kcu.column_name = '{col_name}'
      \ "

let s:sqlserver = {
      \   'args': ['-h-1', '-W', '-s', '|', '-Q'],
      \   'foreign_key_query': trim(s:sqlserver_foreign_keys_query),
      \   'schemes_query': 'SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA',
      \   'schemes_tables_query': 'SELECT table_schema, table_name FROM INFORMATION_SCHEMA.TABLES',
      \   'database_schemas_query': 'SELECT schema_name FROM %s.INFORMATION_SCHEMA.SCHEMATA',
      \   'database_tables_query': 'SELECT table_schema, table_name FROM %s.INFORMATION_SCHEMA.TABLES',
      \   'database_current_query': 'SELECT DB_NAME()',
      \   'select_foreign_key_query': 'select * from %s.%s where %s = %s',
      \   'cell_line_number': 2,
      \   'cell_line_pattern': '^-\+.-\+',
      \   'parse_results': {results, min_len -> s:results_parser(results[0:-3], '|', min_len)},
      \   'quote': 0,
      \   'default_scheme': 'dbo',
      \ }

let s:mysql_foreign_key_query =  "
      \ SELECT referenced_table_name, referenced_column_name, referenced_table_schema
      \ from information_schema.key_column_usage
      \ where referenced_table_name is not null and column_name = '{col_name}' LIMIT 1"
let s:mysql = {
      \ 'foreign_key_query': s:mysql_foreign_key_query,
      \ 'schemes_query': 'SELECT schema_name FROM information_schema.schemata',
      \ 'schemes_tables_query': 'SELECT table_schema, table_name FROM information_schema.tables',
      \ 'select_foreign_key_query': 'select * from %s.%s where %s = %s',
      \ 'cell_line_number': 3,
      \ 'requires_stdin': v:true,
      \ 'cell_line_pattern': '^+-\++-\+',
      \ 'parse_results': {results, min_len -> s:results_parser(results[1:], '\t', min_len)},
      \ 'default_scheme': '',
      \ 'layout_flag': '\\G',
      \ 'quote': 0,
      \ 'filetype': 'mysql',
      \ }

let s:oracle_args = join(
      \    [
           \  'SET linesize 4000',
           \  'SET pagesize 4000',
           \  'COLUMN owner FORMAT a20',
           \  'COLUMN table_name FORMAT a25',
           \  'COLUMN column_name FORMAT a25',
           \  '%s',
      \    ],
      \    ";\n"
      \ ).';'

function! s:get_oracle_queries()
  let common_condition = ""

  if !g:db_ui_is_oracle_legacy
    let common_condition = "AND U.common = 'NO'"
  endif

  let foreign_key_query = "
      \SELECT /*csv*/ DISTINCT RFRD.table_name, RFRD.column_name, RFRD.owner
      \ FROM all_cons_columns RFRD
      \ JOIN all_constraints CON ON RFRD.constraint_name = CON.r_constraint_name
      \ JOIN all_cons_columns RFRING ON CON.constraint_name = RFRING.constraint_name
      \ JOIN all_users U ON CON.owner = U.username
      \ WHERE CON.constraint_type = 'R'
      \ " . common_condition . "
      \ AND RFRING.column_name = '{col_name}'"

  let schemes_query = "
      \SELECT /*csv*/ username
      \ FROM all_users U
      \ WHERE 1 = 1 
      \ " . common_condition . "
      \ ORDER BY username"

  let schemes_tables_query = "
      \SELECT /*csv*/ T.owner, T.table_name
      \ FROM (
      \ SELECT owner, table_name
      \ FROM all_tables
      \ UNION SELECT owner, view_name AS \"table_name\"
      \ FROM all_views
      \ ) T
      \ JOIN all_users U ON T.owner = U.username
      \ WHERE 1 = 1
      \ " . common_condition . "
      \ ORDER BY T.table_name"

  return {
      \ 'foreign_key_query': printf(s:oracle_args, foreign_key_query),
      \ 'schemes_query': printf(s:oracle_args, schemes_query),
      \ 'schemes_tables_query': printf(s:oracle_args, schemes_tables_query),
      \ }
endfunction

let oracle_queries = s:get_oracle_queries()

let s:oracle = {
      \   'callable': 'filter',
      \   'cell_line_number': 1,
      \   'cell_line_pattern': '^-\+\( \+-\+\)*',
      \   'default_scheme': '',
      \   'foreign_key_query': oracle_queries.foreign_key_query,
      \   'has_virtual_results': v:true,
      \   'parse_results': {results, min_len -> s:results_parser(results[3:], '\s\s\+', min_len)},
      \   'parse_virtual_results': {results, min_len -> s:results_parser(results[3:], '\s\s\+', min_len)},
      \   'requires_stdin': v:true,
      \   'quote': v:true,
      \   'schemes_query': oracle_queries.schemes_query,
      \   'schemes_tables_query': oracle_queries.schemes_tables_query,
      \   'select_foreign_key_query': printf(s:oracle_args, 'SELECT /*csv*/ * FROM "%s"."%s" WHERE "%s" = %s'),
      \   'filetype': 'plsql',
      \ }

if index(['sql', 'sqlcl'], get(g:, 'dbext_default_ORA_bin', '')) >= 0
  let s:oracle.parse_results = {results, min_len -> s:results_parser(s:strip_quotes(results[3:]), ',', min_len)}
  let s:oracle.parse_virtual_results = {results, min_len -> s:results_parser(s:strip_quotes(results[3:]), ',', min_len)}
endif

if !exists('g:db_adapter_bigquery_region')
  let g:db_adapter_bigquery_region = 'region-us'
endif

let s:bigquery_schemas_query = printf("
      \ SELECT schema_name FROM `%s`.INFORMATION_SCHEMA.SCHEMATA
      \ ", g:db_adapter_bigquery_region)

let s:bigquery_schema_tables_query = printf("
      \ SELECT table_schema, table_name
      \ FROM `%s`.INFORMATION_SCHEMA.TABLES
      \ ", g:db_adapter_bigquery_region)

let s:db_adapter_bigquery_max_results = 100000
let s:bigquery = {
      \ 'callable': 'filter',
      \ 'args': ['--format=csv', '--max_rows=' .. s:db_adapter_bigquery_max_results],
      \ 'schemes_query': s:bigquery_schemas_query,
      \ 'schemes_tables_query': s:bigquery_schema_tables_query,
      \ 'parse_results': {results, min_len -> s:results_parser(results[1:], ',', min_len)},
      \ 'layout_flag': '\\x',
      \ 'requires_stdin': v:true,
      \ }


let s:clickhouse_schemes_query = "
      \ SELECT name as schema_name
      \ FROM system.databases
      \ ORDER BY name"

let s:clickhouse_schemes_tables_query = "
      \ SELECT database AS table_schema, name AS table_name
      \ FROM system.tables
      \ ORDER BY table_name"

let s:clickhouse = {
      \ 'args': ['-q'],
      \ 'schemes_query': trim(s:clickhouse_schemes_query),
      \ 'schemes_tables_query': trim(s:clickhouse_schemes_tables_query),
      \ 'cell_line_number': 1,
      \ 'cell_line_pattern': '^.*$',
      \ 'parse_results': {results, min_len -> s:results_parser(results, '\t', min_len)},
      \ 'default_scheme': '',
      \ 'quote': 1,
      \ }

" Add ClickHouse to the schemas dictionary
let s:schemas = {
      \ 'postgres': s:postgresql,
      \ 'postgresql': s:postgresql,
      \ 'sqlserver': s:sqlserver,
      \ 'mysql': s:mysql,
      \ 'mariadb': s:mysql,
      \ 'oracle': s:oracle,
      \ 'bigquery': s:bigquery,
      \ 'clickhouse': s:clickhouse,
      \ }


if !exists('g:db_adapter_postgres')
  let g:db_adapter_postgres = 'db#adapter#postgresql#'
endif

if !exists('g:db_adapter_sqlite3')
  let g:db_adapter_sqlite3 = 'db#adapter#sqlite#'
endif

function! db_ui#schemas#get(scheme) abort
  return get(s:schemas, a:scheme, {})
endfunction

function! s:format_query(db, scheme, query) abort
  let conn = type(a:db) == v:t_string ? a:db : a:db.conn
  let callable = get(a:scheme, 'callable', 'interactive')
  let cmd = db#adapter#dispatch(conn, callable) + get(a:scheme, 'args', [])
  if get(a:scheme, 'requires_stdin', v:false)
    return [cmd, a:query]
  endif
  return [cmd + [a:query], '']
endfunction

function! db_ui#schemas#query(db, scheme, query) abort
  let result = call('db#systemlist', s:format_query(a:db, a:scheme, a:query))
  return map(result, {_, val -> substitute(val, "\r$", "", "")})
endfunction

function! s:error_hint(output, exit_status) abort
  let lines = filter(map(split(a:output, "\n", 1), {_, v -> trim(v)}), '!empty(v:val)')
  for line in lines
    if line =~? '^Msg \d\+\|^Sqlcmd:\|error'
      return 'DB exec error: ' . strcharpart(line, 0, 120)
    endif
  endfor
  if empty(lines)
    return 'DB exec error (exit '.a:exit_status.')'
  endif
  return 'DB exec error: ' . strcharpart(lines[0], 0, 120)
endfunction

" Exit statuses arrive through job callbacks; store them per job id so a
" late callback from a previously killed job cannot be read as this job's.
let s:job_exits = {}

function! s:job_exit_cb(job, status, ...) abort
  let s:job_exits[string(a:job)] = a:status
endfunction

function! s:tempfile_text(file) abort
  return filereadable(a:file) ? join(readfile(a:file), "\n") . "\n" : ''
endfunction

" Run a shell command line as a job whose shell redirects stdout and stderr
" to temp files (sqlcmd reports connection and permission failures on
" stderr, sometimes with a zero exit status). Waits at most a:timeout
" seconds, then kills the job - system() offers no such escape hatch, so an
" unreachable endpoint would otherwise stall expansion for the OS TCP
" connect timeout. Returns [finished, exit_status, stdout, stderr];
" exit_status is -1 when the job was killed or its status never arrived.
function! s:run_with_timeout(cmdstring, input, timeout) abort
  let outfile = tempname()
  let errfile = tempname()
  let redirect = ' >' . outfile . ' 2>' . errfile
  let infile = ''
  if empty(a:input)
    let redirect .= ' </dev/null'
  else
    let infile = tempname()
    call writefile(split(a:input, "\n", 1), infile, 'b')
    let redirect .= ' <' . infile
  endif
  let finished = 0
  let job = 0
  try
    if has('nvim')
      let job = jobstart([&shell, &shellcmdflag, a:cmdstring . redirect],
            \ {'on_exit': function('s:job_exit_cb')})
      let finished = jobwait([job], a:timeout * 1000)[0] != -1
      if !finished
        call jobstop(job)
      endif
    elseif exists('*job_start')
      " job_start(String) runs argv directly without a shell on some Vim
      " builds - pass the shell explicitly so the redirections apply.
      let job = job_start([&shell, &shellcmdflag, a:cmdstring . redirect],
            \ {'in_io': 'null', 'exit_cb': function('s:job_exit_cb')})
      if job_status(job) ==# 'fail'
        throw 'DB: failed to start job'
      endif
      let deadline = reltimefloat(reltime()) + a:timeout
      while job_status(job) ==# 'run' && reltimefloat(reltime()) < deadline
        sleep 10m
      endwhile
      let finished = job_status(job) !=# 'run'
      if !finished
        call job_stop(job, 'kill')
      endif
    else
      throw 'DB: jobs not supported by this Vim version'
    endif
    if !finished
      return [0, -1, '', '']
    endif
    let status = get(s:job_exits, string(job), -1)
    if has_key(s:job_exits, string(job))
      call remove(s:job_exits, string(job))
    endif
    return [1, status, s:tempfile_text(outfile), s:tempfile_text(errfile)]
  finally
    for path in [outfile, errfile, infile]
      if !empty(path)
        call delete(path)
      endif
    endfor
  endtry
endfunction

" Like db_ui#schemas#query, but surfaces execution failures instead of
" silently returning an empty list. Returns [lines, error]. Runs through a
" job with a wait timeout (g:db_ui_query_timeout, default 10 seconds) so a
" hung sqlcmd is killed instead of stalling tree expansion.
function! db_ui#schemas#query_with_error(db, scheme, query) abort
  let [cmd, input] = s:format_query(a:db, a:scheme, a:query)
  " Join to a shell command string: some supported Vim builds do not accept
  " list arguments to system()/systemlist(), and the shell performs the
  " stdout/stderr redirections for the job on every supported platform.
  let cmdstring = join(map(copy(cmd), 'db#shellescape(v:val)'), ' ')
  let timeout = get(g:, 'db_ui_query_timeout', 10)
  try
    let [finished, status, out, err] = s:run_with_timeout(cmdstring, input, timeout)
    if !finished
      return [[], 'DB exec error: timed out after '.timeout.'s (query killed)']
    endif
    " Hints look at stderr first (sqlcmd reports failures there), then
    " stdout - like the previously merged 2>&1 output did.
    let output = err . "\n" . out
    if status
      return [[], s:error_hint(output, status)]
    endif
    let result = split(out, "\n", 1)
    " db#systemlist (used by db_ui#schemas#query) drops one trailing empty
    " line through its job callback; mimic that so both paths parse the same.
    if !empty(result) && result[-1] ==# ''
      call remove(result, -1)
    endif
    " Catch tools that exit 0 while printing only an error: on stderr
    " (whatever stdout says) or as the first non-empty stdout line.
    let errlines = filter(map(split(err, "\n", 1), {_, v -> trim(v)}), '!empty(v:val)')
    if !empty(errlines) && errlines[0] =~? '^Sqlcmd:\s*Error\|^Msg \d\+'
      return [[], s:error_hint(err, 0)]
    endif
    let nonempty = filter(copy(result), '!empty(v:val)')
    if !empty(nonempty) && nonempty[0] =~? '^Sqlcmd:\s*Error\|^Msg \d\+'
      return [[], s:error_hint(out, 0)]
    endif
    return [map(result, {_, val -> substitute(val, "\r$", "", "")}), '']
  catch /.*/
    return [[], v:exception]
  endtry
endfunction

function db_ui#schemas#supports_schemes(scheme, parsed_url)
  let schema_support = !empty(get(a:scheme, 'schemes_query', 0))
  if empty(schema_support)
    return 0
  endif
  let scheme_name = tolower(get(a:parsed_url, 'scheme', ''))
  " Mysql and MariaDB should not show schemas if the path (database name) is
  " defined
  if (scheme_name ==? 'mysql' || scheme_name ==? 'mariadb') && a:parsed_url.path !=? '/'
    return 0
  endif

  return 1
endfunction

" A connection gets a database tree level only when the adapter knows how to
" enumerate databases (db#adapter#supports(conn, 'databases')) and this plugin
" knows how to introspect each one (per-database queries in the scheme dict).
function! db_ui#schemas#supports_databases(scheme, url) abort
  if empty(get(a:scheme, 'database_schemas_query', '')) || empty(get(a:scheme, 'database_tables_query', ''))
    return 0
  endif
  try
    return db#adapter#supports(a:url, 'databases')
  catch /.*/
    return 0
  endtry
endfunction

" Quote a SQL Server database name for use in a three-part name.
function! db_ui#schemas#quote_database(name) abort
  return '[' . substitute(a:name, ']', ']]', 'g') . ']'
endfunction
