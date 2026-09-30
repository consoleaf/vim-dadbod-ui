let s:drawer_instance = {}
let s:drawer = {}

" Databases SQL Server groups into a "System Databases" folder,
" like SSMS and Azure Data Studio do.
let s:system_databases = ['master', 'model', 'msdb', 'tempdb']

function! s:is_system_database(name) abort
  return index(s:system_databases, a:name) >= 0
endfunction

function db_ui#drawer#new(dbui)
  let s:drawer_instance = s:drawer.new(a:dbui)
  return s:drawer_instance
endfunction
function db_ui#drawer#get()
  return s:drawer_instance
endfunction

function! s:drawer.new(dbui) abort
  let instance = copy(self)
  let instance.dbui = a:dbui
  let instance.show_details = 0
  let instance.show_help = 0
  let instance.show_dbout_list = 0
  let instance.content = []
  let instance.query = {}
  let instance.connections = {}

  return instance
endfunction

function! s:drawer.open(...) abort
  if self.is_opened()
    silent! exe self.get_winnr().'wincmd w'
    return
  endif
  let mods = get(a:, 1, '')
  if !empty(mods)
    silent! exe mods.' new dbui'
  else
    let win_pos = g:db_ui_win_position ==? 'left' ? 'topleft' : 'botright'
    silent! exe 'vertical '.win_pos.' new dbui'
    silent! exe 'vertical '.win_pos.' resize '.g:db_ui_winwidth
  endif
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap nospell nomodifiable winfixwidth nonumber norelativenumber signcolumn=no
  setlocal filetype=dbui

  call self.render()
  nnoremap <silent><buffer> <Plug>(DBUI_SelectLine) :call <sid>method('toggle_line', 'edit')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_DeleteLine) :call <sid>method('delete_line')<CR>
  let query_win_pos = g:db_ui_win_position ==? 'left' ? 'botright' : 'topleft'
  silent! exe "nnoremap <silent><buffer> <Plug>(DBUI_SelectLineVsplit) :call <sid>method('toggle_line', 'vertical ".query_win_pos." split')<CR>"
  nnoremap <silent><buffer> <Plug>(DBUI_Redraw) :call <sid>method('redraw')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_AddConnection) :call <sid>method('add_connection')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_ToggleDetails) :call <sid>method('toggle_details')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_RenameLine) :call <sid>method('rename_line')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_Quit) :call <sid>method('quit')<CR>

  nnoremap <silent><buffer> <Plug>(DBUI_GotoFirstSibling) :call <sid>method('goto_sibling', 'first')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_GotoNextSibling) :call <sid>method('goto_sibling', 'next')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_GotoPrevSibling) :call <sid>method('goto_sibling', 'prev')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_GotoLastSibling) :call <sid>method('goto_sibling', 'last')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_GotoParentNode) :call <sid>method('goto_node', 'parent')<CR>
  nnoremap <silent><buffer> <Plug>(DBUI_GotoChildNode) :call <sid>method('goto_node', 'child')<CR>

  nnoremap <silent><buffer> ? :call <sid>method('toggle_help')<CR>
  augroup db_ui
    autocmd! * <buffer>
    autocmd BufEnter <buffer> call s:method('render')
  augroup END
  silent! doautocmd User DBUIOpened
endfunction

function! s:drawer.is_opened() abort
  return self.get_winnr() > -1
endfunction

function! s:drawer.get_winnr() abort
  for nr in range(1, winnr('$'))
    if getwinvar(nr, '&filetype') ==? 'dbui'
      return nr
    endif
  endfor
  return -1
endfunction

function! s:drawer.redraw() abort
  let item = self.get_current_item()
  if item.level ==? 0
    return self.render({ 'dbs': 1, 'queries': 1 })
  endif
  return self.render({'db_key_name': item.dbui_db_key_name, 'queries': 1 })
endfunction

function! s:drawer.toggle() abort
  if self.is_opened()
    return self.quit()
  endif
  return self.open()
endfunction

function! s:drawer.quit() abort
  if self.is_opened()
    silent! exe 'bd'.winbufnr(self.get_winnr())
  endif
endfunction

function! s:method(method_name, ...) abort
  if a:0 > 0
    return s:drawer_instance[a:method_name](a:1)
  endif

  return s:drawer_instance[a:method_name]()
endfunction

function! s:drawer.goto_sibling(direction)
  let index = line('.') - 1
  let last_index = len(self.content) - 1
  let item = self.content[index]
  let current_level = item.level
  let is_up = a:direction ==? 'first' || a:direction ==? 'prev'
  let is_down = !is_up
  let is_edge = a:direction ==? 'first' || a:direction ==? 'last'
  let is_prev_or_next = !is_edge
  let last_index_same_level = index

  while ((is_up && index >= 0) || (is_down && index < last_index))
    let adjacent_index = is_up ? index - 1 : index + 1
    let is_on_edge = (is_up && adjacent_index ==? 0) || (is_down && adjacent_index ==? last_index)
    let adjacent_item = self.content[adjacent_index]
    if adjacent_item.level ==? 0 && adjacent_item.label ==? ''
      return cursor(index + 1, col('.'))
    endif

    if is_prev_or_next
      if adjacent_item.level ==? current_level
        return cursor(adjacent_index + 1, col('.'))
      endif
      if adjacent_item.level < current_level
        return
      endif
    endif

    if is_edge
      if adjacent_item.level ==? current_level
        let last_index_same_level = adjacent_index
      endif
      if adjacent_item.level < current_level || is_on_edge
        return cursor(last_index_same_level + 1, col('.'))
      endif
    endif
    let index = adjacent_index
  endwhile
endfunction

function! s:drawer.goto_node(direction)
  let index = line('.') - 1
  let item = self.content[index]
  let last_index = len(self.content) - 1
  let is_up = a:direction ==? 'parent'
  let is_down = !is_up
  let Is_correct_level = {adj-> a:direction ==? 'parent' ? adj.level ==? item.level - 1 : adj.level ==? item.level + 1}
  if is_up
    while index >= 0
      let index = index - 1
      let adjacent_item = self.content[index]
      if adjacent_item.level < item.level
        break
      endif
    endwhile
    return cursor(index + 1, col('.'))
  endif

  if item.action !=? 'toggle'
    return
  endif

  if !item.expanded
    call self.toggle_line('')
  endif
  norm! j
endfunction

function s:drawer.get_current_item() abort
  return self.content[line('.') - 1]
endfunction

function! s:drawer.rename_buffer(buffer, db_key_name, is_saved_query) abort
  let bufnr = bufnr(a:buffer)
  let current_win = winnr()
  let current_ft = &filetype

  if !filereadable(a:buffer)
    return db_ui#notifications#error('Only written queries can be renamed.')
  endif

  if empty(a:db_key_name)
    return db_ui#notifications#error('Buffer not attached to any database')
  endif

  let bufwin = bufwinnr(bufnr)
  let db = self.dbui.dbs[a:db_key_name]
  let db_slug = db_ui#utils#slug(db.name)
  let is_saved = a:is_saved_query || !self.dbui.is_tmp_location_buffer(db, a:buffer)
  let old_name = self.get_buffer_name(db, a:buffer)

  try
    let new_name = db_ui#utils#input('Enter new name: ', old_name)
  catch /.*/
    return db_ui#notifications#error(v:exception)
  endtry

  if empty(new_name)
    return db_ui#notifications#error('Valid name must be provided.')
  endif

  if is_saved
    let new = printf('%s/%s', fnamemodify(a:buffer, ':p:h'), new_name)
  else
    let new = printf('%s/%s', fnamemodify(a:buffer, ':p:h'), db_slug.'-'.new_name)
    call add(db.buffers.tmp, new)
  endif

  call rename(a:buffer, new)
  let new_bufnr = -1

  if bufwin > -1
    call self.get_query().open_buffer(db, new, 'edit')
    let new_bufnr = bufnr('%')
  elseif bufnr > -1
    exe 'badd '.new
    let new_bufnr = bufnr(new)
    call add(db.buffers.list, new)
  elseif index(db.buffers.list, a:buffer) > -1
    call insert(db.buffers.list, new, index(db.buffers.list, a:buffer))
  endif

  call filter(db.buffers.list, 'v:val !=? a:buffer')

  if new_bufnr > - 1
    call setbufvar(new_bufnr, 'dbui_db_key_name', db.key_name)
    call setbufvar(new_bufnr, 'db', db.conn)
    call setbufvar(new_bufnr, 'dbui_db_table_name', getbufvar(a:buffer, 'dbui_db_table_name'))
    call setbufvar(new_bufnr, 'dbui_bind_params', getbufvar(a:buffer, 'dbui_bind_params'))
  endif

  silent! exe 'bw! '.a:buffer
  if winnr() !=? current_win
    wincmd p
  endif

  return self.render({ 'queries': 1 })
endfunction

function! s:drawer.rename_line() abort
  let item = self.get_current_item()
  if item.type ==? 'buffer'
    return self.rename_buffer(item.file_path, item.dbui_db_key_name, get(item, 'saved', 0))
  endif

  if item.type ==? 'db'
    return self.get_connections().rename(self.dbui.dbs[item.dbui_db_key_name])
  endif

  return
endfunction

function! s:drawer.add_connection() abort
  return self.get_connections().add()
endfunction

function! s:drawer.toggle_dbout_queries() abort
  let self.show_dbout_list = !self.show_dbout_list
  return self.render()
endfunction

function! s:drawer.delete_connection(db) abort
  return self.get_connections().delete(a:db)
endfunction

function! s:drawer.get_connections() abort
  if empty(self.connections)
    let self.connections = db_ui#connections#new(self)
  endif

  return self.connections
endfunction

function! s:drawer.toggle_help() abort
  let self.show_help = !self.show_help
  return self.render()
endfunction

function! s:drawer.toggle_details() abort
  let self.show_details = !self.show_details
  return self.render()
endfunction

function! s:drawer.focus() abort
  if &filetype ==? 'dbui'
    return 0
  endif

  let winnr = self.get_winnr()
  if winnr > -1
    exe winnr.'wincmd w'
    return 1
  endif
  return 0
endfunction

function! s:drawer.render(...) abort
  let opts = get(a:, 1, {})
  let restore_win = self.focus()

  if &filetype !=? 'dbui'
    return
  endif

  if get(opts, 'dbs', 0)
    let query_time = reltime()
    call db_ui#notifications#info('Refreshing all databases...')
    call self.dbui.populate_dbs()
    call db_ui#notifications#info('Refreshed all databases after '.split(reltimestr(reltime(query_time)))[0].' sec.')
  endif

  if !empty(get(opts, 'db_key_name', ''))
    let db = self.dbui.dbs[opts.db_key_name]
    call db_ui#notifications#info('Refreshing database '.db.name.'...')
    let query_time = reltime()
    let self.dbui.dbs[opts.db_key_name] = self.populate(db)
    call db_ui#notifications#info('Refreshed database '.db.name.' after '.split(reltimestr(reltime(query_time)))[0].' sec.')
  endif

  redraw!
  let view = winsaveview()
  let self.content = []

  call self.render_help()

  for db in self.dbui.dbs_list
    if get(opts, 'queries', 0)
      call self.load_saved_queries(self.dbui.dbs[db.key_name])
    endif
    call self.add_db(self.dbui.dbs[db.key_name])
  endfor

  if empty(self.dbui.dbs_list)
    call self.add('" No connections', 'noaction', 'help', '', '', 0)
    call self.add('Add connection', 'call_method', 'add_connection', g:db_ui_icons.add_connection, '', 0)
  endif


  if !empty(self.dbui.dbout_list)
    call self.add('', 'noaction', 'help', '', '', 0)
    call self.add('Query results ('.len(self.dbui.dbout_list).')', 'call_method', 'toggle_dbout_queries', self.get_toggle_icon('saved_queries', {'expanded': self.show_dbout_list}), '', 0)

    if self.show_dbout_list
      let entries = sort(keys(self.dbui.dbout_list), function('s:sort_dbout'))
      for entry in entries
        let content = ''
        if !empty(self.dbui.dbout_list[entry])
          let content = printf(' (%s)', self.dbui.dbout_list[entry].content)
        endif
        call self.add(fnamemodify(entry, ':t').content, 'open', 'dbout', g:db_ui_icons.tables, '', 1, { 'file_path': entry })
      endfor
    endif
  endif

  let content = map(copy(self.content), 'repeat(" ", shiftwidth() * v:val.level).v:val.icon.(!empty(v:val.icon) ? " " : "").v:val.label')

  setlocal modifiable
  silent 1,$delete _
  call setline(1, content)
  setlocal nomodifiable
  call winrestview(view)

  if restore_win
    wincmd p
  endif
endfunction

function! s:drawer.render_help() abort
  if g:db_ui_show_help
    call self.add('" Press ? for help', 'noaction', 'help', '', '', 0)
    call self.add('', 'noaction', 'help', '', '', 0)
  endif

  if self.show_help
    call self.add('" o - Open/Toggle selected item', 'noaction', 'help', '', '', 0)
    call self.add('" S - Open/Toggle selected item in vertical split', 'noaction', 'help', '', '', 0)
    call self.add('" d - Delete selected item', 'noaction', 'help', '', '', 0)
    call self.add('" R - Redraw', 'noaction', 'help', '', '', 0)
    call self.add('" A - Add connection', 'noaction', 'help', '', '', 0)
    call self.add('" H - Toggle database details', 'noaction', 'help', '', '', 0)
    call self.add('" r - Rename/Edit buffer/connection/saved query', 'noaction', 'help', '', '', 0)
    call self.add('" q - Close drawer', 'noaction', 'help', '', '', 0)
    call self.add('" <C-j>/<C-k> - Go to last/first sibling', 'noaction', 'help', '', '', 0)
    call self.add('" K/J - Go to prev/next sibling', 'noaction', 'help', '', '', 0)
    call self.add('" <C-p>/<C-n> - Go to parent/child node', 'noaction', 'help', '', '', 0)
    call self.add('" <Leader>W - (sql) Save currently opened query', 'noaction', 'help', '', '', 0)
    call self.add('" <Leader>E - (sql) Edit bind parameters in opened query', 'noaction', 'help', '', '', 0)
    call self.add('" <Leader>S - (sql) Execute query in visual or normal mode', 'noaction', 'help', '', '', 0)
    call self.add('" <C-]> - (.dbout) Go to entry from foreign key cell', 'noaction', 'help', '', '', 0)
    call self.add('" <motion>ic - (.dbout) Operator pending mapping for cell value', 'noaction', 'help', '', '', 0)
    call self.add('" <Leader>R - (.dbout) Toggle expanded view', 'noaction', 'help', '', '', 0)
    call self.add('', 'noaction', 'help', '', '', 0)
  endif
endfunction

function! s:drawer.add(label, action, type, icon, dbui_db_key_name, level, ...)
  let opts = extend({'label': a:label, 'action': a:action, 'type': a:type, 'icon': a:icon, 'dbui_db_key_name': a:dbui_db_key_name, 'level': a:level }, get(a:, '1', {}))
  call add(self.content, opts)
endfunction

function! s:drawer.add_db(db) abort
  let db_name = a:db.name

  if !empty(a:db.conn_error)
    let db_name .= ' '.g:db_ui_icons.connection_error
  elseif !empty(a:db.conn)
    let db_name .= ' '.g:db_ui_icons.connection_ok
  endif

  if self.show_details
    let db_name .= ' ('.a:db.scheme.' - '.a:db.source.')'
  endif

  call self.add(db_name, 'toggle', 'db', self.get_toggle_icon('db', a:db), a:db.key_name, 0, { 'expanded': a:db.expanded })
  if !a:db.expanded
    return a:db
  endif

  " Render sections based on g:db_ui_drawer_sections configuration
  for section in g:db_ui_drawer_sections
    if section ==# 'new_query'
      call self._render_new_query_section(a:db)
    elseif section ==# 'buffers' && !empty(a:db.buffers.list)
      call self._render_buffers_section(a:db)
    elseif section ==# 'saved_queries'
      call self._render_saved_queries_section(a:db)
    elseif section ==# 'schemas'
      call self._render_schemas_section(a:db)
    endif
  endfor
endfunction

function! s:drawer.render_tables(tables, db, path, level, schema, ...) abort
  if !a:tables.expanded
    return
  endif
  let extra = get(a:, 1, {})
  if type(g:Db_ui_table_name_sorter) ==? type(function('tr'))
    let tables_list = call(g:Db_ui_table_name_sorter, [a:tables.list])
  else
    let tables_list = a:tables.list
  endif
  for table in tables_list
    call self.add(table, 'toggle', a:path.'->'.table, self.get_toggle_icon('table', a:tables.items[table]), a:db.key_name, a:level, extend({ 'expanded': a:tables.items[table].expanded }, extra))
    if a:tables.items[table].expanded
      for [helper_name, helper] in items(a:db.table_helpers)
        call self.add(helper_name, 'open', 'table', g:db_ui_icons.tables, a:db.key_name, a:level + 1, extend({'table': table, 'content': helper, 'schema': a:schema }, extra))
      endfor
    endif
  endfor
endfunction

function! s:drawer.toggle_line(edit_action) abort
  let item = self.get_current_item()
  if item.action ==? 'noaction'
    return
  endif

  if item.action ==? 'call_method'
    return s:method(item.type)
  endif

  if item.type ==? 'dbout'
    call self.get_query().focus_window()
    silent! exe 'pedit' item.file_path
    return
  endif

  if item.action ==? 'open'
    return self.get_query().open(item, a:edit_action)
  endif

  let db = self.dbui.dbs[item.dbui_db_key_name]

  let tree = db
  if item.type !=? 'db'
    let tree = self.get_nested(db, item.type)
  endif

  let tree.expanded = !tree.expanded

  if !empty(get(item, 'database', '')) && tree.expanded && !get(tree, 'loaded', 1)
    call self.populate_database(db, item.database)
  endif

  if item.type ==? 'db'
    call self.toggle_db(db)
  endif

  return self.render()
endfunction

function! s:drawer.get_query() abort
  if empty(self.query)
    let self.query = db_ui#query#new(self)
  endif
  return self.query
endfunction

function! s:drawer.delete_line() abort
  let item = self.get_current_item()

  if item.action ==? 'noaction'
    return
  endif

  if item.action ==? 'toggle' && item.type ==? 'db'
    let db = self.dbui.dbs[item.dbui_db_key_name]
    if db.source !=? 'file'
      return db_ui#notifications#error('Cannot delete this connection.')
    endif
    return self.delete_connection(db)
  endif

  if item.action !=? 'open' || item.type !=? 'buffer'
    return
  endif

  let db = self.dbui.dbs[item.dbui_db_key_name]

  if has_key(item, 'saved')
    let choice = confirm('Are you sure you want to delete this saved query?', "&Yes\n&No")
    if choice !=? 1
      return
    endif

    call delete(item.file_path)
    call remove(db.saved_queries.list, index(db.saved_queries.list, item.file_path))
    call filter(db.buffers.list, 'v:val !=? item.file_path')
    call db_ui#notifications#info('Deleted.')
  endif

  if self.dbui.is_tmp_location_buffer(db, item.file_path)
    let choice = confirm('Are you sure you want to delete query?', "&Yes\n&No")
    if choice !=? 1
      return
    endif

    call delete(item.file_path)
    call filter(db.buffers.list, 'v:val !=? item.file_path')
    call db_ui#notifications#info('Deleted.')
  endif

  let win = bufwinnr(item.file_path)
  if  win > -1
    silent! exe win.'wincmd w'
    silent! exe 'b#'
  endif

  silent! exe 'bw!'.bufnr(item.file_path)
  call self.focus()
  call self.render()
endfunction

function! s:drawer.toggle_db(db) abort
  if !a:db.expanded
    return a:db
  endif

  call self.load_saved_queries(a:db)

  call self.dbui.connect(a:db)

  if !empty(a:db.conn)
    call self.populate(a:db)
  endif
endfunction

function! s:drawer.populate(db) abort
  if empty(a:db.conn) && a:db.conn_tried
    call self.dbui.connect(a:db)
  endif
  if a:db.database_support
    return self.populate_databases(a:db)
  endif
  if a:db.schema_support
    return self.populate_schemas(a:db)
  endif
  return self.populate_tables(a:db)
endfunction

function! s:drawer.load_saved_queries(db) abort
  if !empty(a:db.save_path)
    let a:db.saved_queries.list = split(glob(printf('%s/*', a:db.save_path)), "\n")
  endif
endfunction

function! s:drawer.populate_tables(db) abort
  let a:db.tables.list = []
  if empty(a:db.conn)
    return a:db
  endif

  let tables = db#adapter#call(a:db.conn, 'tables', [a:db.conn], [])

  let a:db.tables.list = tables
  " Fix issue with sqlite tables listing as strings with spaces
  if a:db.scheme =~? '^sqlite' && len(a:db.tables.list) >=? 0
    let temp_table_list = []

    for table_index in a:db.tables.list
      let temp_table_list += map(split(copy(table_index)), 'trim(v:val)')
    endfor

    let a:db.tables.list = sort(temp_table_list)
  endif

  if a:db.scheme =~? '^mysql'
    call filter(a:db.tables.list, 'v:val !~? "mysql: [Warning\\]" && v:val !~? "Tables_in_"')
  endif

  call self.populate_table_items(a:db.tables)
  return a:db
endfunction

function! s:drawer.populate_table_items(tables) abort
  for table in a:tables.list
    if !has_key(a:tables.items, table)
      let a:tables.items[table] = {'expanded': 0 }
    endif
  endfor
endfunction

function! s:drawer.populate_schemas(db) abort
  let a:db.schemas.list = []
  if empty(a:db.conn)
    return a:db
  endif
  let scheme = db_ui#schemas#get(a:db.scheme)
  let schemas = scheme.parse_results(db_ui#schemas#query(a:db, scheme, scheme.schemes_query), 1)
  let tables = scheme.parse_results(db_ui#schemas#query(a:db, scheme, scheme.schemes_tables_query), 2)
  let [schemas, tables_by_schema] = self.group_tables_by_schema(schemas, tables)
  for [scheme_name, table] in tables
    if !self._is_schema_ignored(scheme_name)
      call add(a:db.tables.list, table)
    endif
  endfor
  let a:db.schemas.list = schemas
  for schema in schemas
    if !has_key(a:db.schemas.items, schema)
      let a:db.schemas.items[schema] = {
            \ 'expanded': 0,
            \ 'tables': {
            \   'expanded': 1,
            \   'list': [],
            \   'items': {},
            \ },
            \ }

    endif
    let a:db.schemas.items[schema].tables.list = sort(get(tables_by_schema, schema, []))
    call self.populate_table_items(a:db.schemas.items[schema].tables)
  endfor
  return a:db
endfunction

" Filter ignored schemas out of both lists and group table rows by schema.
" Shared between the schema-level and database-level tree population.
function! s:drawer.group_tables_by_schema(schemas, tables) abort
  let schemas = filter(copy(a:schemas), {i, v -> !self._is_schema_ignored(v)})
  let tables_by_schema = {}
  for [scheme_name, table] in a:tables
    if self._is_schema_ignored(scheme_name)
      continue
    endif
    if !has_key(tables_by_schema, scheme_name)
      let tables_by_schema[scheme_name] = []
    endif
    call add(tables_by_schema[scheme_name], table)
  endfor
  return [schemas, tables_by_schema]
endfunction

" Enumerate all databases on the server (one query), and remember which one
" the connection URL itself points at so it can be marked in the tree.
function! s:drawer.populate_databases(db) abort
  let a:db.databases.list = []
  if empty(a:db.conn)
    return a:db
  endif
  try
    let databases = db#adapter#dispatch(a:db.conn, 'databases')
  catch /.*/
    let databases = []
  endtry
  let a:db.databases.list = filter(copy(databases), '!empty(v:val)')

  let current = substitute(get(db#url#parse(a:db.conn), 'path', ''), '^/', '', '')
  if empty(current)
    let scheme = db_ui#schemas#get(a:db.scheme)
    let current = get(scheme.parse_results(
          \ db_ui#schemas#query(a:db, scheme, get(scheme, 'database_current_query', 'SELECT DB_NAME()')), 1), 0, '')
  endif
  let a:db.current_database = current

  for database in a:db.databases.list
    if !has_key(a:db.databases.items, database)
      let a:db.databases.items[database] = {
            \ 'expanded': 0,
            \ 'loaded': 0,
            \ 'error': '',
            \ 'current': 0,
            \ 'schemas': { 'expanded': 0, 'items': {}, 'list': [] },
            \ }
    endif
    let a:db.databases.items[database].current = database ==? current ? 1 : 0
  endfor
  return a:db
endfunction

" Introspect a single database on first expansion, using three-part names
" against the existing connection. On failure the database node gets an
" error hint and the rest of the tree stays intact.
function! s:drawer.populate_database(db, name) abort
  let item = get(a:db.databases.items, a:name, {})
  if empty(item) || item.loaded
    return item
  endif
  let scheme = db_ui#schemas#get(a:db.scheme)
  let quoted = db_ui#schemas#quote_database(a:name)
  let [schemas_result, schemas_error] = db_ui#schemas#query_with_error(a:db, scheme,
        \ printf(scheme.database_schemas_query, quoted))
  let [tables_result, tables_error] = db_ui#schemas#query_with_error(a:db, scheme,
        \ printf(scheme.database_tables_query, quoted))
  let item.loaded = 1
  if !empty(schemas_error) || !empty(tables_error)
    let item.error = !empty(schemas_error) ? schemas_error : tables_error
    return item
  endif
  let schemas = scheme.parse_results(schemas_result, 1)
  let tables = scheme.parse_results(tables_result, 2)
  let [schemas, tables_by_schema] = self.group_tables_by_schema(schemas, tables)
  let item.schemas.list = schemas
  for schema in schemas
    if !has_key(item.schemas.items, schema)
      let item.schemas.items[schema] = {
            \ 'expanded': 0,
            \ 'tables': {
            \   'expanded': 1,
            \   'list': [],
            \   'items': {},
            \ },
            \ }
    endif
    let item.schemas.items[schema].tables.list = sort(get(tables_by_schema, schema, []))
    call self.populate_table_items(item.schemas.items[schema].tables)
  endfor
  return item
endfunction

function! s:drawer.get_toggle_icon(type, item) abort
  if a:item.expanded
    return get(g:db_ui_icons.expanded, a:type, g:db_ui_icons.expanded.schema)
  endif

  return get(g:db_ui_icons.collapsed, a:type, g:db_ui_icons.collapsed.schema)
endfunction

function! s:drawer.get_nested(obj, val, ...) abort
  let default = get(a:, '1', 0)
  let items = split(a:val, '->')
  let result = copy(a:obj)

  for item in items
    if !has_key(result, item)
      let result = default
      break
    endif
    let result = result[item]
  endfor

  return result
endfunction

function! s:drawer.get_buffer_name(db, buffer)
  let name = fnamemodify(a:buffer, ':t')
  let is_tmp = self.dbui.is_tmp_location_buffer(a:db, a:buffer)

  if !is_tmp
    return name
  endif

  if fnamemodify(name, ':r') ==? 'db_ui'
    let name = fnamemodify(name, ':e')
  endif

  return substitute(name, '^'.db_ui#utils#slug(a:db.name).'-', '', '')
endfunction

function! s:drawer._render_new_query_section(db) abort
  call self.add('New query', 'open', 'query', g:db_ui_icons.new_query, a:db.key_name, 1)
endfunction

function! s:drawer._render_buffers_section(db) abort
  call self.add('Buffers ('.len(a:db.buffers.list).')', 'toggle', 'buffers', self.get_toggle_icon('buffers', a:db.buffers), a:db.key_name, 1, { 'expanded': a:db.buffers.expanded })
  if a:db.buffers.expanded
    for buf in a:db.buffers.list
      let buflabel = self.get_buffer_name(a:db, buf)
      if self.dbui.is_tmp_location_buffer(a:db, buf)
        let buflabel .= ' *'
      endif
      call self.add(buflabel, 'open', 'buffer', g:db_ui_icons.buffers, a:db.key_name, 2, { 'file_path': buf })
    endfor
  endif
endfunction

function! s:drawer._render_saved_queries_section(db) abort
  call self.add('Saved queries ('.len(a:db.saved_queries.list).')', 'toggle', 'saved_queries', self.get_toggle_icon('saved_queries', a:db.saved_queries), a:db.key_name, 1, { 'expanded': a:db.saved_queries.expanded })
  if a:db.saved_queries.expanded
    for saved_query in a:db.saved_queries.list
      call self.add(fnamemodify(saved_query, ':t'), 'open', 'buffer', g:db_ui_icons.saved_query, a:db.key_name, 2, { 'file_path': saved_query, 'saved': 1 })
    endfor
  endif
endfunction

function! s:drawer._render_schemas_section(db) abort
  if a:db.database_support
    return self._render_databases_section(a:db)
  endif
  if a:db.schema_support
    call self.add('Schemas ('.len(a:db.schemas.items).')', 'toggle', 'schemas', self.get_toggle_icon('schemas', a:db.schemas), a:db.key_name, 1, { 'expanded': a:db.schemas.expanded })
    if a:db.schemas.expanded
      for schema in a:db.schemas.list
        let schema_item = a:db.schemas.items[schema]
        let tables = schema_item.tables
        call self.add(schema.' ('.len(tables.items).')', 'toggle', 'schemas->items->'.schema, self.get_toggle_icon('schema', schema_item), a:db.key_name, 2, { 'expanded': schema_item.expanded })
        if schema_item.expanded
          call self.render_tables(tables, a:db,'schemas->items->'.schema.'->tables->items', 3, schema)
        endif
      endfor
    endif
  else
    call self.add('Tables ('.len(a:db.tables.items).')', 'toggle', 'tables', self.get_toggle_icon('tables', a:db.tables), a:db.key_name, 1, { 'expanded': a:db.tables.expanded })
    call self.render_tables(a:db.tables, a:db, 'tables->items', 2, '')
  endif
endfunction

function! s:drawer._render_databases_section(db) abort
  let user_databases = filter(copy(a:db.databases.list), {_, v -> !s:is_system_database(v)})
  let system_databases = filter(copy(a:db.databases.list), {_, v -> s:is_system_database(v)})
  call self.add('Databases ('.len(user_databases).')', 'toggle', 'databases', self.get_toggle_icon('schemas', a:db.databases), a:db.key_name, 1, { 'expanded': a:db.databases.expanded })
  if !a:db.databases.expanded
    return
  endif
  for database in user_databases
    call self._render_database_node(a:db, database, 2)
  endfor
  if !empty(system_databases)
    call self.add('System Databases ('.len(system_databases).')', 'toggle', 'databases->system', self.get_toggle_icon('schemas', a:db.databases.system), a:db.key_name, 2, { 'expanded': a:db.databases.system.expanded })
    if a:db.databases.system.expanded
      for database in system_databases
        call self._render_database_node(a:db, database, 3)
      endfor
    endif
  endif
endfunction

function! s:drawer._render_database_node(db, database, level) abort
  let item = a:db.databases.items[a:database]
  let label = a:database . (item.current ? ' *' : '')
  if !empty(item.error)
    let label .= ' '.g:db_ui_icons.connection_error
  endif
  call self.add(label, 'toggle', 'databases->items->'.a:database, self.get_toggle_icon('database', item), a:db.key_name, a:level, { 'expanded': item.expanded, 'database': a:database })
  if !item.expanded
    return
  endif
  if !empty(item.error)
    call self.add('('.item.error.')', 'noaction', 'database_error', '', a:db.key_name, a:level + 1)
  elseif item.loaded
    for schema in item.schemas.list
      let schema_item = item.schemas.items[schema]
      let tables = schema_item.tables
      call self.add(schema.' ('.len(tables.items).')', 'toggle', 'databases->items->'.a:database.'->schemas->items->'.schema, self.get_toggle_icon('schema', schema_item), a:db.key_name, a:level + 1, { 'expanded': schema_item.expanded, 'database': a:database })
      if schema_item.expanded
        call self.render_tables(tables, a:db, 'databases->items->'.a:database.'->schemas->items->'.schema.'->tables->items', a:level + 2, schema, { 'database': a:database })
      endif
    endfor
  endif
endfunction

function! s:drawer._is_schema_ignored(schema_name)
  for ignored_schema in g:db_ui_hide_schemas
    if match(a:schema_name, ignored_schema) > -1
      return 1
    endif
  endfor
  return 0
endfunction

function! s:sort_dbout(a1, a2)
  let l:result = str2nr(fnamemodify(a:a1, ':t:r')) - str2nr(fnamemodify(a:a2, ':t:r'))
  return g:db_ui_dbout_list_sort ==? 'desc' ? -l:result : l:result
endfunction
