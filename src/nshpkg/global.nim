import std/[os, sequtils, streams, strformat, strutils, tables]
import std/[parsecfg]
import yaml/serialization

const
  ExitOK* = 0
  ExitNG* = 1

type
  Database* = OrderedTable[string, string]
  App* = object
    verbose*: bool
    quiet*: bool
    cfgpath: string
    cfg*: Config

let
  d4Cfg = loadConfig(newStringStream("""
[Default]
lib="mculib"
tc="nds32le-elf-mculib-v5d"
[Release]
branch=
[Build]
flags="--shallow-clone-whitelist=binutils --toolchain-dev-mode=yes"
tc=
[Test]
tests="binutils,v5_toolmisc_test,supertest,plumhall,gcc,g++,csmith"
cflags=
ldflags="-fuse-ld=bfd"
simulator="sid"
compiler="gcc"
"""))

proc readCfg*(app: var App, cfgname: string): App {.discardable.} =
  var path = absolutePath(cfgname)
  var parent = parentDir(path)
  while true:
    if not path.fileExists:
      if parent.isRootDir:
        break
      parent = parentDir(parent)
      path = joinPath(parent, cfgname)
      continue

    app.cfg = loadConfig(path)
    if app.cfg.getSectionValue("Default", "lib") == "":
      app.cfg = d4Cfg
    break

  app

var the* = App()

# sugars
template is_empty*(x: string): bool = isEmptyOrWhitespace(x)
template is_existed(x: string): bool = fileExists(x)

proc qecho*(args: varargs[string, `$`]): void =
  if not the.quiet:
    stderr.writeLine args.join(" ")

proc vecho*(args: varargs[string, `$`]): void =
  if the.verbose:
    stderr.writeLine args.join(" ")

proc find_folder*(name: string, path = ""): string =
  var basedir = if path == "": getCurrentDir() else: path
  while basedir != "":
    let test = joinPath(basedir, name)
    if dirExists(test): result = test; break
    basedir = parentDir(basedir)

proc find_files*(name: string, path = ""): seq[string] =
  var basedir = if path == "": getCurrentDir() else: path
  while basedir != "":
    let pattern = joinPath(basedir, name)
    result = toSeq(walkFiles(pattern))
    if result.len > 0: break
    basedir = parentDir(basedir)

proc found_config_file*(name: string, at = ""): string =
  var path = if at != "": joinPath(at, "x") else: getAppFilename()
  while true:
    let pa = parentDir(path)
    if pa == "": break
    let pat = joinPath(pa, name)
    if fileExists(pat):
      result = pat
      break
    path = pa

  # if not found, try application path
  if result == "" and at != "":
    let pat = joinPath(getAppDir(), name)
    if fileExists(pat):
      result = pat

proc get_effect_name*(name, default: string): string =
  if name.is_empty:
    result = found_config_file(default, getCurrentDir())
  elif fileExists(name):
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

proc write_yaml*(filename: string, db: Database): bool =
  while true: # once
    # write db now
    try:
      let s = newFileStream(filename, fmWrite)
      dump(db, s)
      close(s)
      result = true
    except: break
    break # once
  if result == false:
    qecho &"Write DB '{filename}' failed!"

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

when isMainModule:
  echo d4_cfg["Release"]

  let x = loadConfig(newStringStream("""
[Default]
lib=newlib
[XXX]
aa=bb
"""))

  var y = d4Cfg
  y.merge(x)
  echo y

