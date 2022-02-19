import unittest
import std/os, strutils
import nsh

# test context
var the = App()
var paths: seq[string]
the.dbf = "xpath-test.yaml"

test "xpath reset":
  check xpath(reset = true, db = the.dbf, paths = paths) == 0
  check the.dbf.fileExists # to test remove

test "xpath remove":
  check xpath(remove = true, db = the.dbf, paths = paths) == 0
  check not the.dbf.fileExists

test "xpath list":
  check xpath(list = true, db = the.dbf, quiet = true, paths = paths) == 0
  check the.dbf.fileExists
  check list_db(the) == "pathes:\n"

test "xpath add":
  check xpath(add = "a: /aa, b: /bb, c: /cc, x: /xx, y: /yy, z: /zz",
      db = the.dbf, quiet = true, paths = paths) == 0
  check read_db(the, the.db)
  check list_db(the) == "pathes:\n  a\n  b\n  c\n  x\n  y\n  z\n"

test "xpath cut":
  check xpath(cut = "a c: /bb:/xx", db = the.dbf, quiet = true,
      paths = paths) == 0
  check read_db(the, the.db)
  check list_db(the) == "pathes:\n  y\n  z\n"

test "xpath [apply]":
  check xpath(db = the.dbf, quiet = true, paths = @["x", "y", "z"]) == 0
  check "set -x PATH /yy /zz" == get_unit_test()[0..18]

test "xpath mask":
  check xpath(mask = "z y: /usr/local/bin", db = the.dbf, quiet = true,
      paths = @["x", "y", "z"]) == 0
  let msg = get_unit_test()
  for x in ["/yy", "/zz", "/usr/local/bin"]:
    check x notin msg
