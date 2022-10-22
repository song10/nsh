import std/[os, sequtils, strformat, strutils, tables]
import yaml/serialization
import global

# unit test stuff
when not defined(release):
  type
    Ut = ref object
      is_testing: bool
      last_output: string
  var ut = Ut()
  proc ut_set_is_testing*(v: bool) = ut.is_testing = v
  proc ut_get_last_output*(): string = ut.last_output

# fish
#   alias xcd 'nsh xcd $argv 1>/tmp/xcd && . /tmp/xcd'
#
proc mask_key*(db: var Database, mask: string): seq[string] =
  # [key key ...: path:path, ...]
  while true: # once
    # read mask spec.
    var pairs: Database
    try:
      load("[" & mask & "]", pairs)
    except:
      qecho &"Mask '{mask}' failed!"
      break
    # collect mask pathes
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

proc xpath*(add = "", cut = "", mask = "", list = false, reset = false,
  remove = false, verbose = false, quiet = false, format = "fish",
      database = "", paths: seq[string]): int =
  # global context stuff
  the.quiet = quiet
  the.verbose = verbose
  # body
  result = ExitOK
  while true: # once
    var
      dbname = get_effect_name(database, "xpath.yaml")
      db: Database
      masks: seq[string]
    if remove:
      if not remove_database(dbname): result = ExitNG
      break # stop here for unit test
    if not read_yaml(dbname, db):
      result = ExitNG; break
    # DB ready now
    if not add.is_empty: # add
      if add_path(add, db, dbname) and write_yaml(dbname, db): discard
      else: result = ExitNG; break
    if not cut.is_empty: # cut
      if cut_path(cut, db, dbname) and write_yaml(dbname, db): discard
      else: result = ExitNG; break
    if not mask.is_empty: # mask
      masks = mask_key(db, mask)
    if list: # list
      list_keys(db)
    if reset: # reset
      if reset_db(dbname) == false:
        result = ExitNG; break
    # apply now
    var pth: seq[string]
    for x in paths:
      if x in db: pth.add(db[x])
    if pth.len > 0 or masks.len > 0:
      pth &= getEnv("PATH").split(':')
      pth = deduplicate(pth)
      pth = pth.filterIt(it notin masks)
      case format:
      of "fish":
        let p = pth.join(" ")
        let cmd = &"set -x PATH {p}"
        when not defined(release): ut.last_output = cmd
        echo cmd
      else:
        let p = pth.join($PathSep)
        let cmd = &"export PATH={p}"
        when not defined(release): ut.last_output = cmd
        echo cmd
      # "PATH".putEnv pth
    break # once

when isMainModule:
  import cligen
  dispatch(xpath)
