import unittest
import std/os, strutils
import nshpkg/[helper, cmdxcd]

# test context
var db: Database
var paths: seq[string]
let dbname = "ut-xcd.yaml"
removeFile(dbname)

# test "xcd reset":
#   check xcd(reset = true, database = dbname, paths = paths) == 0
#   check fileExists(dbname) # to test remove

# test "xcd remove":
#   check xcd(remove = true, database = dbname, paths = paths) == 0
#   check not fileExists(dbname)

test "xcd list":
  check xcd(list = true, database = dbname, quiet = true, paths = paths) == 0
  check read_yaml(dbname, db)
  check list_keys(db) == "pathes:\n"

test "xcd add":
  check xcd(add = "abc", database = dbname, quiet = true, paths = @["/aaa/bb/c"]) == 0
  check read_yaml(dbname, db)
  check list_keys(db) == "pathes:\n  abc\n"

# test "xcd cut":
#   check xcd(cut = "a c: /bb:/xx", database = dbname, quiet = true,
#       paths = paths) == 0
#   check read_yaml(dbname, db)
#   check list_keys(db) == "pathes:\n  y\n  z\n"

# test "xcd [apply]":
#   check xcd(database = dbname, quiet = true, paths = @["x", "y", "z"]) == 0
#   check "set -x PATH /yy /zz" == ut_get_last_output()[0..18]

# test "xcd mask":
#   check xcd(mask = "z y: /usr/local/bin", database = dbname, quiet = true,
#       paths = @["x", "y", "z"]) == 0
#   let msg = ut_get_last_output()
#   for x in ["/yy", "/zz", "/usr/local/bin"]:
#     check x notin msg

# # clean up
# removeFile(dbname)
