import std/[os, osproc, tempfiles]
import std/[algorithm, sugar]
import std/[strutils, strformat]
import std/[sequtils, sets]
import std/[parsecfg]
import global

type
  Cmds = ref seq[string]

using
  cmds: Cmds
  args: string

proc renderCleanCommand(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "all": jobs &= ["toolchain all", "test"]
  of "config":
    let tc = the.cfg.getSectionValue("Default", "tc")
    jobs &= tc.split(',').map((x) => "toolchain " & x)
  else: jobs &= args.split(',').map((x) => "toolchain " & x)
  for x in jobs:
    cmds[].add &"./build_system_3.py clean {x} -y"
  true

proc renderBuildCommand(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "default":
    let lib = the.cfg.getSectionValue("Default", "lib")
    jobs &= [&"nds32le-elf-{lib}-v5,nds64le-elf-{lib}-v5d"]
  of "config":
    let tc = the.cfg.getSectionValue("Default", "tc")
    jobs &= [tc];
  else: jobs.add args

  the.cfg.setSectionKey("Build", "tc", jobs.join ",")
  let flags = the.cfg.getSectionValue("Build", "flags")
  var branch = the.cfg.getSectionValue("Release", "branch")
  if branch != "":
    branch = &"--release-branch={branch}"
  for x in jobs:
    cmds[].add &"./build_system_3.py build {x} {flags} {branch}"
  true

proc renderTestCommand(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  let d4Tests = the.cfg.getSectionValue("Test", "tests")
  let tests = d4Tests.split(',')
  case args
  of "all":
    jobs &= d4Tests
  else:
    if args[0] in "-x":
      # xxxxxx bit map to each default test
      for i, x in args[0..min(high(args), high(tests))]:
        if x == 'x': jobs.add tests[i]
    elif args[0] == ':':
      # abcdefg key map to each default test
      for x in args[1..^1].toOrderedSet:
        let i = x.ord - 'a'.ord
        if i < tests.len:
          jobs.add tests[i]
    else:
      jobs.add args
  if jobs.len > 0:
    let tests = jobs.join ","
    let simulator = the.cfg.getSectionValue("Test", "simulator")
    let compiler = the.cfg.getSectionValue("Test", "compiler")
    var cflags = the.cfg.getSectionValue("Test", "cflags")
    var ldflags = the.cfg.getSectionValue("Test", "ldflags")
    var branch = the.cfg.getSectionValue("Release", "branch")
    var tc = the.cfg.getSectionValue("Build", "tc")
    if cflags != "":
      cflags = &"--with-extra-cflags='{cflags}'"
    if ldflags != "":
      ldflags = &"--with-extra-ldflags='{ldflags}'"
    if branch != "":
      branch = &"--release-branch={branch}"
    if tc == "":
      tc = the.cfg.getSectionValue("Default", "tc")
    cmds[].add &"./build_system_3.py test {tests} {tc} --with-sim={simulator} --test-with-compiler={compiler} {cflags} {ldflags} {branch}"
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
  uptime;python -c 'print("-"*124)';grep -E '(Pass|Fail)' {logfile} > {tmpfile};GREP_COLORS="mt=1;32" grep --color=always Pass {tmpfile}|tail|cut -c -256;python -c 'print("-"*124)';GREP_COLORS="mt=1;31" grep --color=always Fail {tmpfile}|tail|cut -c -256"""
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

proc setupDefault(simulator, compiler: string): int =
  result = ExitNG
  while true:
    # CLI
    var
      sim = simulator
      com = compiler
    # CFG if not CLI
    if sim == "":
      sim = the.cfg.getSectionValue("Test", "simulator")
    if com == "":
      com = the.cfg.getSectionValue("Test", "compiler")
    # default if not CFG neither
    if sim == "": sim = "gdb"
    if com == "": com = "gcc"
    # validate and update
    if sim notin ["gdb", "sid", "qemu"]:
      echo &"Bad simulate '{sim}'!"
      break
    if com notin ["gcc", "clang", "both"]:
      echo &"Bad compiler '{com}'!"
      break

    the.cfg.setSectionKey("Test", "simulator", sim)
    the.cfg.setSectionKey("Test", "compiler", com)

    result = ExitOK
    break # once

proc bs3*(clean = "", build = "", test = "", state = "", watch = "",
    fail = "", simulator = "", compiler = "", run = false,
    verbose = false, quiet = false, cfg = "bs3.ini", paths: seq[string]): int =

  # update app (context)
  the.quiet = quiet
  the.verbose = verbose
  the.readCfg(cfg)
  result = setupDefault(simulator, compiler)

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
    if state != "": # --state
      if not render_state_command(cmds, state):
        result = ExitNG; break
    if watch != "": # --watch
      if not render_watch_command(cmds, watch):
        result = ExitNG; break
    if fail != "": # --fail
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
