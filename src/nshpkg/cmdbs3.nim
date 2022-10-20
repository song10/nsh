import std/[os, osproc, tempfiles]
import std/[algorithm, sugar]
import std/[strutils, strformat]
import std/[sequtils, sets]
import std/[parsecfg]
import helper

type
  Cmds = ref seq[string]

using
  cmds: Cmds
  args: string

proc init_this() =
  # static bool inited = false
  var inited {.global.} = false
  if inited: return
  inited = true

  # default values
  the.default_lib = "mculib"
  the.default_tc = &"nds64le-elf-{the.default_lib}-v5d"
  the.default_tests = @["binutils", "v5_toolmisc_test", "supertest",
      "plumhall", "gcc", "g++", "csmith"]
  the.test_tc = the.default_tc
  the.build_flags = "--shallow-clone-whitelist=binutils --toolchain-dev-mode=yes"
  the.simulator = "gdb" # gdb, sid
  the.compiler = "gcc" # gcc, clang, both

  # pull cfg
  let
    xdefault_lib = the.cfg.getSectionValue("Default", "lib")
    xtest_tc = the.cfg.getSectionValue("Test", "tc")
    xbuild_flags = the.cfg.getSectionValue("Build", "flags")
  if xdefault_lib != "": the.default_lib = xdefault_lib
  if xtest_tc != "": the.test_tc = xtest_tc
  if xbuild_flags != "": the.build_flags = xbuild_flags

# unit test stuff
when not defined(release):
  type
    Ut = ref object
      is_testing: bool
      last_output: string
  var ut = Ut()
  proc ut_set_is_testing*(v: bool) = ut.is_testing = v
  proc ut_get_last_output*(): string = ut.last_output

proc renderCleanCommand(cmds, args): bool =
  let tc = the.cfg.getSectionValue("Test","tc")
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "all": jobs &= ["toolchain all", "test"]
  of "config": jobs &= tc.split(',').map((x) => "toolchain " & x)
  else: jobs &= args.split(',').map((x) => "toolchain " & x)
  for x in jobs:
    cmds[].add &"./build_system_3.py clean {x} -y"
  true

proc renderBuildCommand(cmds, args): bool =
  let tc = the.cfg.getSectionValue("Test","tc")
  let flags = the.cfg.getSectionValue("Build","flags")
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "default":
    jobs &= [&"nds32le-elf-{the.default_lib}-v5,nds64le-elf-{the.default_lib}-v5d"]
  of "config":
    jobs &= [tc];
  else: jobs.add args
  the.test_tc = jobs.join ","
  for x in jobs:
    cmds[].add &"./build_system_3.py build {x} {flags}"
  true

proc renderTestCommand(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "all": jobs &= the.default_tests
  else:
    if args[0] in "-x":
      # xxxxxx bit map to each default test
      for i, x in args[0..min(high(args), high(the.default_tests))]:
        if x == 'x': jobs.add the.default_tests[i]
    elif args[0] == ':':
      # abcdefg key map to each default test
      for x in args[1..^1].toOrderedSet:
        let i = x.ord - 'a'.ord
        if i < the.default_tests.len:
          jobs.add the.default_tests[i]
    else:
      jobs.add args
  if jobs.len > 0:
    let tests = jobs.join ","
    cmds[].add &"./build_system_3.py test {tests} {the.test_tc} --with-sim={the.simulator} --test-with-compiler={the.compiler}"
  true

proc get_latest_bs3_log(path: string): string =
  var
    logfile = ""
    dir = path.normalizedPath().absolutePath()
  while dir.len > 0:
    let paths = walkDirs(os.joinPath(dir, "log")).toSeq
    if paths.len > 0:
      let logdir = paths[0]
      let lst = walkFiles(os.joinPath(logdir, "*.log")).toSeq.sorted
      logfile = lst[^1]
      break
    dir = parentDir(dir)
  return logfile

proc render_state_command(cmds, args): bool =
  let dir = if args == "": getCurrentDir() else: args
  if dir[0] == 'X': return true
  let logfile = get_latest_bs3_log(dir)
  if logfile.is_empty: return true
  let (_, name) = splitPath(logfile)
  let tmpfile = joinPath("/tmp", name) & ".grp"
  cmds[].add &"""
  uptime;python -c 'print("-"*124)';grep -E '(Pass|Fail)' {logfile} > {tmpfile};GREP_COLOR="1;32" grep --color=always Pass {tmpfile}|tail|cut -c -256;python -c 'print("-"*124)';GREP_COLOR="1;31" grep --color=always Fail {tmpfile}|tail|cut -c -256"""
  true

proc render_watch_command(cmds, args): bool =
  var xcmds: Cmds
  new(xcmds)
  var script = ""
  if not render_state_command(xcmds, args): return false
  try:
    let (tmpfile, path) = createTempFile("", ".sh", "/tmp")
    tmpfile.write xcmds[0]
    tmpfile.close()
    script = path
  except OSError:
    echo "Temp file not created!"
  except: raise
  if script.is_empty: return false
  cmds[].add &"""
  watch -cet -n60 'sh {script}'"""
  true

proc render_fail_command(cmds, args): bool =
  let basedir = if args.is_empty: getCurrentDir() else: args
  let dir = find_folder("log", absolutePath(basedir))
  let logs = find_files("*.log", dir)
  if logs.len == 0: return false

  let log = logs[^1]
  cmds[].add &"""
  grep -B1 Fail {log} | grep Config"""
  true

proc bs3*(clean = "", build = "", test = "", state = "$-$", watch = "$-$",
    fail = "$-$", simulator = "gdb", compiler = "gcc", run = false,
    verbose = false, quiet = false, database = "", paths: seq[string]): int =

  # update app (context)
  the.quiet = quiet
  the.verbose = verbose
  if database.len > 0: the.database = database
  if compiler in ["gcc", "clang", "both"]: the.compiler = compiler
  if simulator in ["gdb", "sid", "qemu"]: the.simulator = simulator
  if the.readDatabase():
    result = ExitOK
  else:
    result = ExitNG

  # body
  while result == ExitOK: # once
    var cmds: Cmds; new(cmds)
    if not clean.is_empty: # --clean
      if not render_clean_command(cmds, clean):
        result = ExitNG; break
    if not build.is_empty: # --build
      if not render_build_command(cmds, build):
        result = ExitNG; break
    if not test.is_empty: # --test
      if not render_test_command(cmds, test):
        result = ExitNG; break
    if state != "$-$": # --state
      if not render_state_command(cmds, state):
        result = ExitNG; break
    if watch != "$-$": # --watch
      if not render_watch_command(cmds, watch):
        result = ExitNG; break
    if fail != "$-$": # --fail
      if not render_fail_command(cmds, fail):
        result = ExitNG; break

    # apply now
    for cmd in cmds[]:
      qecho cmd
      if run:
        result = execCmd(cmd)

    break # once

when isMainModule:
  import cligen
  dispatch(bs3)
