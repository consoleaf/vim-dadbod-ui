# NOTES — SQL Server multi-database tree

Design decisions for this feature (two repos, branch `feat/sqlserver-db-tree`).

## Why two repos

vim-dadbod owns the connection/adapter layer; vim-dadbod-ui owns the drawer
tree. The split follows each project's existing boundaries:

* **vim-dadbod** gets one new adapter function,
  `db#adapter#sqlserver#databases(url)`, which enumerates online databases.
  This mirrors the existing `complete_database()` (cmdline completion) and is
  reusable by any UI.
* **vim-dadbod-ui** renders the extra tree level and per-database
  introspection queries, which is where every other tree query already lives
  (`autoload/db_ui/schemas.vim`).

## Capability gating

There is no new flag type. The capability is the function itself, checked with
dadbod's own `db#adapter#supports(conn, 'databases')`. DBUI additionally
requires per-database queries (`database_schemas_query` / 
`database_tables_query`) in its scheme dict, so the feature activates only
when **both** sides are new. Version matrix:

| dadbod  | dadbod-ui | behavior                                   |
|---------|-----------|--------------------------------------------|
| new     | new       | database tree for sqlserver                |
| old     | new       | old schema tree (capability missing)       |
| new     | old       | unchanged (UI never asks)                  |

Only `sqlserver` implements `databases()` today, so no other adapter is
affected. An adapter gains the level by implementing `databases()` plus DBUI
scheme-dict entries — no DBUI code changes needed.

## Enumeration query

`SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name` —
`sys.databases` over legacy `sys.sysdatabases` (richer state metadata, lets us
skip offline/restoring databases that cannot be expanded). The URL's database
segment is stripped with the same regex pattern `complete_database()` uses,
hardened to also accept URLs without a trailing slash.

`complete_database()` itself was left untouched (scope discipline; its
sysdatabases behavior is upstream's to change).

Names are parsed with `SET NOCOUNT ON;` + `-h-1 -W` and trimmed as whole
lines — the pre-existing `s:complete()` helper truncates at the first
whitespace, which would mangle database names containing spaces.

## When queries run (laziness)

* Startup / `:DBUI` open: nothing new runs for any adapter. The sqlserver
  enumeration happens only when the connection node is first expanded — the
  same moment the old code ran its schema queries (so "expand connection"
  costs one enumeration query instead of two schema/table queries).
* Each database node is introspected on **first expansion only** (lazy), one
  `INFORMATION_SCHEMA.SCHEMATA` + one `INFORMATION_SCHEMA.TABLES` query per
  database. Instances with many databases never pay for unexplored ones.
* The current-database mark uses the URL path segment when present; otherwise
  one `SELECT DB_NAME()` query resolves the login's default database (run at
  most once per connection expansion, only when the URL has no segment).

## Per-database introspection mechanism

Three-part names (`[OtherDb].INFORMATION_SCHEMA.TABLES`) executed through the
connection's normal `interactive()` command — i.e. the same sqlcmd invocation
path, same credentials, no N separate connections. dadbod is process-per-query
anyway (each query spawns sqlcmd); three-part names keep the *connection
definition* singular while targeting the right database.

## Query buffers target the database

Opening a table/helper under a database subtree sets `b:db` to the connection
URL with its database segment swapped (`db_ui#utils#database_url()`), so
execution, `:DB` bindings and vim-dadbod-completion all target that database.
The swap is done by surgical regex on the canonicalized URL (parse+format
would re-encode spaces — `sqlcmd -d` receives the raw name — and reorder
params). `{optional_schema}` in table helpers is prefixed with the
bracket-quoted database (`[OtherDb].dbo.posts` when schema is non-default,
`[OtherDb].[projects]`-style via the helper's own `[{table}]` otherwise).
`b:dbui_database_name` is set for statusline use (`'database'` token).

## Error handling

`db#systemlist` swallows failures (returns `[]`), which is fine for the happy
path but cannot distinguish "no tables" from "no permission". The new
`db_ui#schemas#query_with_error()` runs the same command via a shell-escaped
string (some supported Vim builds reject list argv for `system()`/`systemlist()`
— found the hard way) and returns `[lines, error]`. A failing database node
renders `✕` plus an error hint line; sibling databases are unaffected.

One subtlety: dadbod's job-based `db#systemlist` drops exactly one trailing
empty line via its callback; `query_with_error` mimics that so both paths see
the same line shape and the sqlserver parser (`results[0:-3]`) behaves
identically.

## Tree state & rendering

`db.databases = {expanded, list, items: {name: {expanded, loaded, error,
current, schemas}}}` mirrors the existing `db.schemas` structure, so
`get_nested()` path navigation (`databases->items->X->schemas->items->Y->...`)
works unchanged, and `render_tables()` gained an optional extra-opts argument
(to stamp `database` on schema/table items) without touching existing callers.
The section renders in the existing `schemas` drawer-section slot — no new
`g:db_ui_drawer_sections` entry needed. `populate_schemas()` was refactored
only to share the schema-filtering/table-grouping helper; its observable
behavior (including the flat `db.tables.list` side effect) is preserved and
covered by the untouched pre-existing test suite.

## Icons

New `database` icon key (defaults + nerd fonts) with a `get()`-based fallback
to the `schema` icon in `get_toggle_icon()`, so users with custom partial
`g:db_ui_icons` dicts don't break.

## Verification summary

* 8 new themis tests (`test/test-sqlserver-databases.vim`) with a mock sqlcmd:
  section rendering, current-db marking (with and without URL segment), lazy
  schema/table expansion, error hint, query-buffer targeting + content,
  old-dadbod fallback, capability gating for other schemes.
* Full suite: 63/63 in Vim 9.1 **and** Neovim 0.9.5 (zero regression).
* Real SQL Server 2022 smoke test in Docker: see the report.

## Known gaps / future work

* Expansion state of database subtrees resets on connection refresh (`R`),
  same as the existing schema level — pre-existing drawer behavior.
* A database that goes offline after enumeration still appears; expanding it
  shows the error hint (arguably correct).
* The tree marks the login's default database via `DB_NAME()`; if a login has
  an unusual default the mark follows it faithfully.
* `db_ui#get_conn_info()` does not expose `databases` (nobody consumes it
  today; left untouched to keep the diff minimal).
