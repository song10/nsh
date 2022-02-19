import std/json
import std/os
import std/strutils, strformat
import std/sequtils
import std/osproc
import std/tables
import yaml/serialization, streams

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

proc xecho(args: varargs[string, `$`]): void =
  if not the.quiet:
    stderr.writeLine args.join(" ")

proc xxecho(args: varargs[string, `$`]): void =
  if the.verbose:
    stderr.writeLine args.join(" ")

proc get_unit_test*(): string = the.unit_test

# fish
#   alias zcd 'nsh xcd $argv 1>/tmp/zcd && . /tmp/zcd'
#
proc xcd(add = "", del = "", db = "", paths: seq[string]): int =
  var dbf = db
  if dbf.len == 0:
    dbf = getAppDir().joinPath "xcd.json"
    if not dbf.fileExists:
      let f = open(dbf, fmWrite)
      f.write("{}")
      f.close
  if not dbf.fileExists:
    stderr.writeLine &"DB '{dbf}' is not found!"
    result = 1
  else:
    let db = parseFile(dbf)
    # add key value
    if add != "":
      let (key, val) = (add, paths[0])
      if key in db and db[key].getStr == val:
        stderr.writeLine &"key '{key}' is duplicated!"
      else:
        db[key] = %val
        let f = open(dbf, fmWrite)
        f.write(db.pretty)
        f.close
    # del key
    if del != "":
      let key = del
      if key notin db:
        stderr.writeLine &"key '{key}' not found!"
      else:
        db.delete key
        let f = open(dbf, fmWrite)
        f.write(db.pretty)
        f.close
    # xcd path
    if add == "" and paths.len > 0:
      let key = paths[0]
      if key in db:
        echo &"cd '{db[key].getStr}'"
      else:
        stderr.writeLine &"key '{key}' is not defined!"

proc ycd(del = false, paths: seq[string]): int =
  let dir = paths[0]
  if del:
    try:
      dir.removeDir
    except OSError:
      echo "OS error!"
      result = 1
    except:
      echo "Unknown exception!"
      raise
    finally:
      discard
  else:
    if not dir.dirExists:
      try:
        dir.createDir
      except OSError:
        echo "OS error!"
        result = 1
      except:
        echo "Unknown exception!"
        raise
      finally:
        discard
    if result == 0:
      echo &"cd '{dir}'"
    else:
      stderr.writeLine &"dir '{dir}' cannot be found/created."

# fish
#   alias vii 'nsh vii $argv'
#
proc vii(paths: seq[string]): int =
  let spec = paths[0]
  let words = spec.split({':', ',', ' ', '(', ')'})
  let file = words[0]
  var line = "0"
  if words.len > 1 and words[1].len > 0:
    line = words[1]
  elif paths.len > 1:
    line = paths[1]
    if not line[0].isDigit:
      line = line[1..^1]
  let cmd = &"vim {file} +{line}"
  # stderr.writeLine $paths
  # stderr.writeLine cmd
  result = execCmd(cmd)

# xpath
proc reset_db(f: string, init: var bool): bool {.discardable.} =
  result = true
  var db: Database
  try:
    var s = newFileStream(f, fmWrite)
    db.dump s
    s.close()
  except:
    result = false
  init = result

proc read_db*(the: App, db: var Database): bool =
  var go_on = true
  if not the.dbf.fileExists: go_on = reset_db(the.dbf, the.is_db_init)
  if not go_on:
    xecho &"read DB '{the.dbf}' failed!"
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
    xecho result

proc xpath*(add = "", cut = "", mask = "", list = false, reset = false,
  remove = false, verbose = false, quiet = false, format = "fish", db = "",
      paths: seq[string]): int =
  the = App(verbose: verbose, quiet: quiet)

  template todo(x: string): bool = x != ""

  proc remove_db(f: string) =
    xxecho &"remove database '{f}'!"
    removeFile(f)

  proc write_db(f: string, db: Database) =
    var s = newFileStream(f, fmWrite)
    db.dump s
    s.close

  proc determine_db_name(f: string): string =
    if f == "":
      result = getAppDir().joinPath "xpath.yaml"
    else:
      result = f

  proc add_path(dbf: string, db: var Database) =
    # [key: value,...]
    var
      pairs: Database
      to_add = true
      to_write: bool
    try:
      load("[" & add & "]", pairs)
    except:
      to_add = false
      xecho &"add '{add}' failed!"
    while to_add: # once
      if not ensure_db(the, the.db): break
      for k, v in pairs:
        if k in db and db[k] == v:
          stderr.writeLine &"add '{k}' duplicated!"
        else:
          db[k] = v
          to_write = true
      if to_write:
        write_db(dbf, db)
      break # once

  proc cut_path(dbf: string, db: var Database) =
    # [key key ...: path path ...]
    var
      pairs: Database
      go_ahead = true
      size: int
    try:
      load("[" & cut & "]", pairs)
    except:
      go_ahead = false
      xecho &"cut '{cut}' failed!"
    while go_ahead: # once
      if not ensure_db(the, the.db): break
      size = db.len
      var key, pth: seq[string]
      for k, v in pairs:
        key &= k.splitWhitespace
        pth &= v.split(':')
      key = key.deduplicate
      pth = pth.deduplicate
      for k in key: db.del k
      key.setLen(0)
      for k, v in db:
        if v in pth: key.add k
      for k in key: db.del k
      if db.len != size:
        write_db(dbf, db)
      break # once

  proc mask_path(db: var Database): seq[string] =
    # [key key ...: path path ...]
    var
      pairs: Database
      go_ahead = true
    try:
      load("[" & mask & "]", pairs)
    except:
      go_ahead = false
      xecho &"mask '{mask}' failed!"
    while go_ahead: # once
      if not ensure_db(the, the.db): break
      var key, pth: seq[string]
      for k, v in pairs:
        key &= k.splitWhitespace
        pth &= v.split(':')
      key = key.deduplicate
      for k in key:
        if k in db: pth.add db[k]
      pth = pth.deduplicate
      result = pth
      break # once

  # body
  while true: # once
    var rz: bool
    the.dbf = determine_db_name db
    if remove: remove_db(the.dbf)
    if reset: reset_db(the.dbf, rz)
    if todo add: add_path(the.dbf, the.db)
    if todo cut: cut_path(the.dbf, the.db)
    if list: list_db(the)
    # xpath path
    var pth: seq[string]
    if paths.len > 0 or todo mask:
      if not ensure_db(the, the.db): break
      for x in paths:
        if x in the.db: pth.add(the.db[x])
        else: xecho &"Key '{x}' not found!"
    if pth.len > 0 or todo mask:
      pth &= "PATH".getEnv.split(':')
      pth = pth.deduplicate
      if todo mask:
        let msk = mask_path(the.db)
        pth = pth.filterIt(it notin msk)
      case format:
      of "fish":
        let p = pth.join(" ")
        the.unit_test = &"set -x PATH {p}"
        echo the.unit_test
      else:
        let p = pth.join($PathSep)
        the.unit_test = &"export PATH={p}"
        echo the.unit_test
      # "PATH".putEnv pth
    break # once

when isMainModule:
  import cligen
  dispatchMulti([xcd], [ycd], [vii], [xpath])
