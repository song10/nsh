import std/[os, sequtils, streams, strformat, strutils, tables]
import std/[parsecfg]
import yaml/serialization

const
  ExitOK* = 0
  ExitNG* = 1

type
  Database* = OrderedTable[string, string]
  App* = ref object
    verbose*: bool
    quiet*: bool

var the = App()

# sugars
template get_app*(): App = the
template is_empty*(x: string): bool = isEmptyOrWhitespace(x)
template is_existed(x: string): bool = fileExists(x)

proc qecho*(args: varargs[string, `$`]): void =
  if not the.quiet:
    stderr.writeLine args.join(" ")

proc vecho*(args: varargs[string, `$`]): void =
  if the.verbose:
    stderr.writeLine args.join(" ")

proc get_effect_name*(name, default: string): string =
  if name.is_empty:
    result = getAppDir().joinPath(default)
  else:
    result = name

proc read_yaml*(fn: string, db: var Database): bool =
  while true: # once
    # ensure db existed
    if not fn.is_existed:
      try:
        let s = newFileStream(fn, fmWrite)
        dump(db, s)
        close(s)
      except: break
    # read db now
    try:
      let s = newFileStream(fn)
      load(s, db)
      close(s)
      result = true
    except: break
    break # once
  if result == false:
    qecho &"Read DB '{fn}' failed!"

proc write_yaml*(fn: string, db: Database): bool =
  while true: # once
    # write db now
    try:
      let s = newFileStream(fn, fmWrite)
      dump(db, s)
      close(s)
      result = true
    except: break
    break # once
  if result == false:
    qecho &"Write DB '{fn}' failed!"

proc remove_database*(fn: string): bool {.discardable.} =
  vecho &"remove database '{fn}'!"
  result = true
  try:
    removeFile(fn)
  except:
    result = false

proc add_key*(db: var Database, add: string, paths: seq[
    string]): bool {.discardable.} =
  while true: # once
    if paths.len == 0: break
    let (key, val) = (add, paths[0])
    if key in db and db[key] == val:
      qecho &"Key '{key}' redefined!"
      break
    # update DB now
    db[key] = val
    result = true
    break # once

proc cut_key*(db: var Database, cut: string): bool {.discardable.} =
  while true: # once
    let key = cut
    if key notin db:
      qecho &"Key '{key}' not found!"
      break
    # update DB now
    del(db, key)
    result = true
    break # once

proc list_keys*(db: Database): string {.discardable.} =
  result &= "pathes:\n"
  if the.verbose:
    for k, v in db:
      result &= &"  {k:5}: {v}\n"
  else:
    for k in db.keys:
      result &= &"  {k}\n"
  qecho result

proc reset_db*(fn: string): bool {.discardable.} =
  result = true
  var db: Database
  try:
    let s = newFileStream(fn, fmWrite)
    dump(db, s)
    close(s)
  except:
    result = false

proc add_path*(code: string, db: var Database, fn: string): bool =
  # [key: value,...]
  while true: # once
    var pairs: Database
    let origin_size = db.len
    try: load("[" & code & "]", pairs)
    except:
      qecho &"Bad code '{code}'!"
      break
    for k, v in pairs:
      if k in db and db[k] == v:
        qecho &"Key '{k}' redefined!"
      else:
        db[k] = v
    result = db.len > origin_size
    break # once

proc cut_path*(code: string, db: var Database, fn: string): bool =
  # [key key ...: path:path:..., ...]
  while true: # once
    var pairs: Database
    let origin_size = db.len
    try: load("[" & code & "]", pairs)
    except:
      qecho &"Bad code '{code}'!"
      break
    var key, pth: seq[string]
    for k, v in pairs:
      key &= k.splitWhitespace
      pth &= v.split(':')
    key = key.deduplicate
    pth = pth.deduplicate
    # cut keys
    for k in key: db.del k
    # convert path to key
    key.setLen(0)
    for k, v in db:
      if v in pth: key.add k
    # cut path keys
    for k in key: db.del k
    result = db.len < origin_size
    break # once

proc read_ini*(fn: string, cfg: var Config): bool =
  while true: # once
    var xfn: string
    if fn.is_empty:
      xfn = joinPath(getAppDir(), "bs3.ini")
    else:
      xfn = fn
    if not xfn.is_existed:
      vecho &"Config '{xfn}' not found!"
      return false
    cfg = loadConfig(xfn)
    break # once
  return true
