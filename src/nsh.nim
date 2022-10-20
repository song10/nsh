when isMainModule:
  import nshpkg/[cmdvii, cmdxcd, cmdycd, cmdxpath, cmdbs3]
  import cligen, tables
  const short = {"compiler": 'C', "simulator": 'S'}.toTable()
  dispatchMulti([xcd], [ycd], [vii], [xpath], [bs3, short=short])
