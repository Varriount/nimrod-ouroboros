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
