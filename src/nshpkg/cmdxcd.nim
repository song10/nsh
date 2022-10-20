import std/[strformat, tables]
import helper

# fish
#   alias xcd 'nsh xcd $argv 1>/tmp/xcd && . /tmp/xcd'
#
proc apply_key(paths: seq[string], db: Database): bool =
  while true: # once
    var target: string
    if paths.len > 0:
      let key = paths[0]
      if key in db:
        target = &"'{db[key]}'"
      else:
        qecho &"Key '{key}' not found!"
        break
    echo &"cd {target}"
    result = true
    break # once

proc xcd*(add = "", cut = "", list = false, quiet = false, verbose = false,
    database = "", paths: seq[string]): int =
  # global context stuff
  the.quiet = quiet
  the.verbose = verbose
  # body
  result = ExitOK
  while true: # once
    var
      dbname = get_effect_name(database, "xcd.yaml")
      db: Database
    if not read_yaml(dbname, db): result = ExitNG; break
    # DB ready now
    if not add.is_empty: # add
      if add_key(db, add, paths) and write_yaml(dbname, db): discard
      else: result = ExitNG
      break
    if not cut.is_empty: # cut
      if cut_key(db, cut) and write_yaml(dbname, db): discard
      else: result = ExitNG
      break
    if list: # list
      list_keys(db)
      break
    # apply xcd now
    if not apply_key(paths, db):
      result = ExitNG
    break # once

when isMainModule:
  import cligen
  dispatch(xcd)
