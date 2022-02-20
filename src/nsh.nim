# import std/[strutils]
# import std/[tables]

#[
type
  Database = OrderedTable[string, string]
  App* = ref object
    dbf*: string
    is_db_init: bool
    db*: Database
    verbose*: bool
    quiet*: bool
    unit_test*: string # last output

var the: App
]#
#[
# xpath
proc read_db*(the: App, db: var Database): bool =
  var go_on = true
  if not the.dbf.fileExists: go_on = reset_db(the.dbf)
  if not go_on:
    qecho &"read DB '{the.dbf}' failed!"
  else:
    let s = newFileStream(the.dbf)
    s.load the.db
    s.close
    the.is_db_init = true
    result = true

proc ensure_db(the: App, db: var Database): bool =
  if the.is_db_init:
    result = true
  else:
    result = read_db(the, the.db)

proc list_db*(the: App): string {.discardable.} =
  if ensure_db(the, the.db):
    result &= "pathes:\n"
    for k in the.db.keys: result &= "  " & k & "\n"
    qecho result
]#

when isMainModule:
  import nshpkg/[cmdvii, cmdxcd, cmdycd, cmdxpath]
  import cligen
  dispatchMulti([xcd], [ycd], [vii], [xpath])
