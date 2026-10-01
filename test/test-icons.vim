let s:suite = themis#suite('Icons')
let s:expect = themis#helper('expect')

" The plugin must source cleanly in every icon mode, including when the
" user's g:db_ui_use_nerd_fonts is set (a malformed dictionary continuation
" there breaks startup with E723).
function! s:suite.should_load_plugin_with_nerd_fonts() abort
  let saved = get(g:, 'db_ui_use_nerd_fonts', 0)
  let saved_icons = deepcopy(g:db_ui_icons)
  unlet! g:loaded_dbui
  unlet! g:db_ui_icons
  let g:db_ui_use_nerd_fonts = 1
  try
    runtime plugin/db_ui.vim
    call s:expect(g:db_ui_icons.expanded.database).to_match('󰆼')
    call s:expect(g:db_ui_icons.collapsed.database).to_match('󰆼')
  finally
    let g:db_ui_icons = saved_icons
    let g:db_ui_use_nerd_fonts = saved
  endtry
endfunction

function! s:suite.should_fall_back_to_schema_icon_for_custom_sets() abort
  unlet! g:loaded_dbui
  let saved_icons = get(g:, 'db_ui_icons', {})
  let g:db_ui_icons = {'expanded': {'db': '[+]'}, 'saved_query': '*'}
  try
    runtime plugin/db_ui.vim
    call s:expect(g:db_ui_icons.expanded.database).to_equal(g:db_ui_icons.expanded.schema)
    call s:expect(g:db_ui_icons.expanded.db).to_equal('[+]')
  finally
    unlet! g:db_ui_icons
    if !empty(saved_icons)
      let g:db_ui_icons = saved_icons
    endif
  endtry
endfunction

" vim:ft=vim
