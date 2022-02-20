import unittest
import std/os, strutils
import nshpkg/[helper, cmdxpath]

# test context
var db: Database
var paths: seq[string]
let dbname = "ut-xpath.yaml"

test "xpath reset":
  check xpath(reset = true, database = dbname, paths = paths) == 0
  check fileExists(dbname) # to test remove

test "xpath remove":
  check xpath(remove = true, database = dbname, paths = paths) == 0
  check not fileExists(dbname)

test "xpath list":
  check xpath(list = true, database = dbname, quiet = true, paths = paths) == 0
  check read_yaml(dbname, db)
  check list_keys(db) == "pathes:\n"

test "xpath add":
  check xpath(add = "a: /aa, b: /bb, c: /cc, x: /xx, y: /yy, z: /zz",
      database = dbname, quiet = true, paths = paths) == 0
  check read_yaml(dbname, db)
  check list_keys(db) == "pathes:\n  a\n  b\n  c\n  x\n  y\n  z\n"

test "xpath cut":
  check xpath(cut = "a c: /bb:/xx", database = dbname, quiet = true,
      paths = paths) == 0
  check read_yaml(dbname, db)
  check list_keys(db) == "pathes:\n  y\n  z\n"

test "xpath [apply]":
  check xpath(database = dbname, quiet = true, paths = @["x", "y", "z"]) == 0
  check "set -x PATH /yy /zz" == ut_get_last_output()[0..18]

test "xpath mask":
  check xpath(mask = "z y: /usr/local/bin", database = dbname, quiet = true,
      paths = @["x", "y", "z"]) == 0
  let msg = ut_get_last_output()
  for x in ["/yy", "/zz", "/usr/local/bin"]:
    check x notin msg

# clean up
removeFile(dbname)
