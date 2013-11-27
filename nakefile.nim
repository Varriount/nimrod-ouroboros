import nake, os, times, osproc

const
  alchemy_exe = "alchemy"

let
  alchemy_dest = getHomeDir() / "bin" / alchemy_exe & ExeExt
  modules = @["alchemy", "ouroboros"]
  rst_files = @["docs"/"file_format", "docs"/"release_steps",
    "LICENSE", "README", "CHANGES", "docindex"]

task "babel", "Uses babel to install ouroboros locally":
  if shell("babel install"):
    echo "Now you can 'import ouroboros' and consume yourself."

task "bin", "Compiles alchemy tool":
  if shell("nimrod c", alchemy_exe):
    echo "Tool alchemy built"

proc needs_refresh(target: string, src: varargs[string]): bool =
  assert len(src) > 0, "Pass some parameters to check for"
  var targetTime: float
  try:
    targetTime = toSeconds(getLastModificationTime(target))
  except EOS:
    return true

  for s in src:
    let srcTime = toSeconds(getLastModificationTime(s))
    if srcTime > targetTime:
      return true


iterator all_rst_files(): tuple[src, dest: string] =
  for rst_name in rst_files:
    var r: tuple[src, dest: string]
    r.src = rst_name & ".rst"
    # Ignore files if they don't exist, babel version misses some.
    if not r.src.existsFile:
      echo "Ignoring missing ", r.src
      continue
    r.dest = rst_name & ".html"
    yield r

task "doc", "Generates export API docs for for the modules":
  # Generate documentation for the nim modules.
  for module in modules:
    let
      nim_file = module & ".nim"
      html_file = module & ".html"
    if not html_file.needs_refresh(nim_file): continue
    if not shell("nimrod doc --verbosity:0", module):
      quit("Could not generate module for " & module)
    else:
      echo "Generated " & module & ".html"

  # Generate html files from the rst docs.
  for rst_file, html_file in all_rst_files():
    if not html_file.needs_refresh(rst_file): continue
    if not shell("nimrod rst2html --verbosity:0", rst_file):
      quit("Could not generate html doc for " & rst_file)
    else:
      echo rst_file & " -> " & html_file
  echo "All done"

task "check_doc", "Validates rst format for a subset of documentation":
  for rst_file, html_file in all_rst_files():
    echo "Testing ", rst_file
    let (output, exit) = execCmdEx("rst2html.py " & rst_file & " > /dev/null")
    if output.len > 0 or exit != 0:
      echo "Failed python processing of " & rst_file
      echo output

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
