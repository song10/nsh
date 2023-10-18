import global
import os

# determine the database path
# and ensure it is existed
proc get_database_path*(name, default:string): string =
  if name.is_empty:
    result = joinPath(getAppDir(), default)
  else:
    result = name

  if not fileExists(result):
    let db = Database()
    discard write_yaml(result, db)
