import std/json
import std/os
import std/strformat

# fish
#   alias zcd '/local/song10/prj/nim/nsh/nsh xcd $argv 1>/tmp/zcd && . /tmp/zcd'
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

when isMainModule:
  import cligen
  dispatchMulti([xcd], [ycd])
