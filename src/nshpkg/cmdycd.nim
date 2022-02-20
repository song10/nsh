import std/os, strformat
import helper

# fish
#   alias ycd 'nsh ycd $argv 1>/tmp/ycd && . /tmp/ycd'
#
proc ycd_cut(dir: string, force: bool): int =
  result = ExitOK
  while true: # once
    if not force:
      write(stderr, &"cut {dir}? [y/N] -> ")
      var input = readLine(stdin)
      if input != "y": break
    try:
      removeDir(dir)
    except:
      result = ExitNG
    break # once

proc ycd_ycd(dir: string): int =
  result = ExitOK
  if not dirExists(dir):
    try:
      createDir(dir)
    except:
      result = ExitNG
  if result == ExitOK:
    echo &"cd '{dir}'"
    setCurrentDir(dir)
  else:
    qecho &"dir '{dir}' cannot be found/created."

proc ycd*(cut = false, force = false, paths: seq[string]): int =
  let dir = paths[0]
  if cut:
    result = ycd_cut(dir, force)
  else:
    result = ycd_ycd(dir)

when isMainModule:
  import cligen
  dispatch(ycd)
