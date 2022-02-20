import std/strutils, strformat, osproc
import helper

# shell
#   alias vii 'nsh vii'
#
proc vii*(paths: seq[string]): int =
  let
    spec = paths[0]
    words = spec.split({':', ',', ' ', '(', ')'})
    file = words[0]
  var line = "1"
  if words.len > 1 and words[1].len > 0:
    # file:num
    line = words[1]
  elif paths.len > 1:
    # file :num
    line = paths[1]
    if not line[0].isDigit:
      # :num -> num
      line = line[1..^1]
  let cmd = &"vim {file} +{line}"
  vecho $paths
  qecho cmd
  result = execCmd(cmd)

when isMainModule:
  import cligen
  dispatch(vii)
