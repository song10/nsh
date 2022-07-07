import std/[os, osproc, tempfiles]
import std/[algorithm, sugar]
import std/[strutils, strformat]
import std/[sequtils]
import std/[parsecfg]
import helper

type Cmds = ref seq[string]
using
  cmds: Cmds
  args: string

type This = object
  db: Database
  cfg: Config
  default_lib: string
  default_tc: string
  default_tests: seq[string]
  test_tc: string
  build_flags: string
  simulator, compiler: string

var this = This()

proc init_this() =
  # static bool inited = false
  var inited {.global.} = false
  if inited: return
  inited = true

  # default values
  this.default_lib = "mculib"
  this.default_tc = &"nds64le-elf-{this.default_lib}-v5d"
  this.default_tests = @["binutils", "v5_toolmisc_test", "supertest",
      "plumhall", "gcc", "g++"]
  this.test_tc = this.default_tc
  this.build_flags = "--shallow-clone-whitelist=binutils --toolchain-dev-mode=yes"
  this.simulator = "gdb" # gdb, sid
  this.compiler = "gcc" # gcc, clang, both

  # pull cfg
  let
    xdefault_lib = this.cfg.getSectionValue("Default", "lib")
    xtest_tc = this.cfg.getSectionValue("Test", "tc")
    xbuild_flags = this.cfg.getSectionValue("Build", "flags")
  if xdefault_lib != "": this.default_lib = xdefault_lib
  if xtest_tc != "": this.test_tc = xtest_tc
  if xbuild_flags != "": this.build_flags = xbuild_flags

# unit test stuff
when not defined(release):
  type
    Ut = ref object
      is_testing: bool
      last_output: string
  var ut = Ut()
  proc ut_set_is_testing*(v: bool) = ut.is_testing = v
  proc ut_get_last_output*(): string = ut.last_output

proc render_clean_command(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "all": jobs &= ["toolchain all", "test"]
  of "config": jobs &= this.test_tc.split(',').map((x) => "toolchain " & x)
  else: jobs &= args.split(',').map((x) => "toolchain " & x)
  for x in jobs:
    cmds[].add &"./build_system_3.py -y clean {x}"
  true

proc render_build_command(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "default":
    jobs &= [&"nds32le-elf-{this.default_lib}-v5,nds64le-elf-{this.default_lib}-v5d"]
  of "config":
    jobs &= [this.test_tc];
  else: jobs.add args
  this.test_tc = jobs.join ","
  for x in jobs:
    cmds[].add &"./build_system_3.py build {x} {this.build_flags}"
  true

proc render_test_command(cmds, args): bool =
  if args[0] == 'X': return true
  var jobs: seq[string]
  case args
  of "all": jobs &= this.default_tests
  else:
    if args[0] in "-x":
      # xxxxxx bit map to each default test
      for i, x in args[0..min(high(args), high(this.default_tests))]:
        if x == 'x': jobs.add this.default_tests[i]
    else:
      jobs.add args
  if jobs.len > 0:
    let tests = jobs.join ","
    cmds[].add &"./build_system_3.py test {tests} {this.test_tc} --with-sim={this.simulator} --test-with-compiler={this.compiler}"
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
  if args[0] == 'X': return true
  let logfile = get_latest_bs3_log(args)
  if logfile.is_empty: return true
  let (_, name) = splitPath(logfile)
  let tmpfile = joinPath("/tmp", name) & ".grp"
  cmds[].add &"""
  uptime;python -c 'print("-"*124)';grep -E '(Pass|Fail)' {logfile} > {tmpfile};GREP_COLOR="1;32" grep --color=always Pass {tmpfile}|tail;python -c 'print("-"*124)';GREP_COLOR="1;31" grep --color=always Fail {tmpfile}|tail"""
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

proc bs3*(clean = "", build = "", test = "", state = "", watch = "",
    simulator = "gdb", compiler = "gcc", run = false, verbose = false,
        quiet = false, database = "", paths: seq[string]): int =
  # global context stuff
  var the = get_app()
  the.quiet = quiet
  the.verbose = verbose

  # body
  result = ExitOK
  while true: # once
    # read config
    let dbname = get_effect_name(database, "bs3.yaml")
    if dbname.is_empty or not read_yaml(dbname, this.db):
      result = ExitNG; break
    let iname = get_effect_name(database, "bs3.ini")
    if iname.is_empty or not read_ini(iname, this.cfg):
      result = ExitNG; break
    init_this()
    if compiler in ["gcc", "clang", "both"]: this.compiler = compiler
    if simulator in ["gdb", "sid"]: this.simulator = simulator
    # config ready now

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
    if not state.is_empty: # --state
      if not render_state_command(cmds, state):
        result = ExitNG; break
    if not watch.is_empty: # --watch
      if not render_watch_command(cmds, watch):
        result = ExitNG; break

    # apply now
    for cmd in cmds[]:
      qecho cmd
      if run:
        result = execCmd(cmd)

    break # once

when isMainModule:
  import cligen
  dispatch(bs3, short = Short)
