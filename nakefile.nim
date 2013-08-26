import nake, os

const
  alchemy_exe = "alchemy"

let
  alchemy_dest = getHomeDir() / "bin" / alchemy_exe & ExeExt
  modules = @["alchemy", "ouroboros"]

task "babel", "Uses babel to install ouroboros locally":
  if shell("babel install"):
    echo "Now you can 'import ouroboros' and consume yourself."

task "bin", "Compiles alchemy tool":
  if shell("nimrod c", alchemy_exe):
    echo "Tool alchemy built"

task "docs", "Generates export API docs for for the modules":
  for module in modules:
    if not shell("nimrod doc", module):
      quit("Could not generate module for " & module)
    else:
      echo "Generated " & module & ".html"

task "local_install", "Copies " & alchemy_exe & " to " & alchemy_dest:
  if shell("nimrod c", alchemy_exe):
    copyFileWithPermissions(alchemy_exe, alchemy_dest)

task "gradha_test", "Random tests, likely useless unlee you are gradha":
  #direShell("nimrod c", alchemy_exe)
  #let
  #  nimrod_exe = findExe("nimrod")
  #  test_exe = "tests" / "1" / "nimrod"
  #copyFileWithPermissions(nimrod_exe, test_exe)
  #direShell("./alchemy", "-o", test_exe, "-v", "../root/lib")
  #direShell("./alchemy", "-l", test_exe)
  direShell("nimrod", "c", "-r", "ouroboros")
