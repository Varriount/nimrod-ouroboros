import argument_parser, tables, strutils, parseutils, ouroboros, os, algorithm

## Tool to create and append files to binaries.

const
  paramVerbose = @["-v", "--verbose"]
  helpVerbose = "Be verbose about actions and print performance statistics."

  paramHelp = @["-h", "--help"]
  helpHelp = "Displays commandline help and exits."

  paramVersion = @["-V", "--version"]
  helpVersion = "Displays the current version and exists."

  paramOverwrite = @["-o", "--overwrite"]
  helpOverwrite = "Adds the specified directories as appended data to the " &
    "binary overwriting any previous appended data."

  paramRemove = @["-r", "--remove"]
  helpRemove = "Removes any appended data from the binary."

  paramList = @["-l", "--list"]
  helpList = "Lists the appended data and its attributes."

var
  DID_USE_COMMAND = false
  VERBOSE = false


proc validateUniqueCommand(parameter: string;
    VALUE: var Tparsed_parameter): string =
  ## Validates unique commands.
  ##
  ## The command will be valid only it points to a valid file and no other
  ## command has been used previously.
  if DID_USE_COMMAND:
    return "Can't use more than a single command at the same time."
  DID_USE_COMMAND = true

  if not VALUE.strVal.exists_file:
    return VALUE.strVal & " doesn't seem to be a valid file."


proc process_commandline(): Tcommandline_results =
  ## Parses the commandline.
  ##
  ## Returns a Tcommandline_results with at least one positional parameter.
  var PARAMS: seq[Tparameter_specification] = @[]

  PARAMS.add(newParameterSpecification(PK_EMPTY,
    helpText = helpHelp, names = paramHelp))

  PARAMS.add(newParameterSpecification(PK_EMPTY,
    helpText = helpVerbose, names = paramVerbose))

  PARAMS.add(newParameterSpecification(PK_EMPTY,
    helpText = helpVersion, names = paramVersion))

  PARAMS.add(newParameterSpecification(PK_STRING,
    helpText = helpOverwrite, names = paramOverwrite,
    custom_validator = validateUniqueCommand))

  PARAMS.add(newParameterSpecification(PK_STRING,
    helpText = helpRemove, names = paramRemove,
    custom_validator = validateUniqueCommand))

  PARAMS.add(newParameterSpecification(PK_STRING,
    helpText = helpList, names = paramList,
    custom_validator = validateUniqueCommand))

  RESULT = parse(PARAMS)

  if RESULT.options.hasKey(paramVerbose[0]):
    VERBOSE = true

  if RESULT.options.hasKey(paramVersion[0]):
    echo "Alchemy version " & ouroboros.versionStr
    quit()

  for pathParam in RESULT.positionalParameters:
    if not (pathParam.strVal.existsDir or pathParam.strVal.existsFile):
      echo pathParam.strVal & " does not seem to be a valid directory or file."
      quit(4)

  if RESULT.options.hasKey(paramOverwrite[0]):
    if RESULT.positionalParameters.len < 1:
      echo "You need to pass the name of the directories you want to append."
      echoHelp(PARAMS)
      quit(1)

  if not DID_USE_COMMAND:
    if RESULT.positionalParameters.len > 0:
      echo "Specified positional parameters, but no command?"
      echoHelp(PARAMS)
      quit(2)
    else:
      echo "You need to specify a command."
      echoHelp(PARAMS)
      quit(3)


proc removeAppendedData(filename: string) =
  ## Removes previously appended binary data from the specified file.
  ##
  ## If a serious error happens the proc will quit the process.
  let a = filename.getAppendedData
  if a.format == noData:
    echo "No appended data found in " & filename
    return

  if VERBOSE:
    echo "Removing " & $a.dataSize & " bytes of appended data from " & filename

  var
    BUF = newString(int(a.contentSize))
    INPUT = open(filename, fmRead)
  let readLen = INPUT.readBuffer(addr(BUF[0]), int(a.contentSize))
  INPUT.close

  if readLen != a.contentSize:
    echo "Error reading bytes from binary! $1 vs $2" % [$readLen,
      $a.contentSize]
    quit(1)

  INPUT = open(filename, fmWrite)
  finally: INPUT.close
  let writtenBytes = INPUT.writeBuffer(addr(BUF[0]), int(a.contentSize))
  if writtenBytes != a.contentSize:
    echo "Error writing " & filename
    echo "Careful, the file might have been left in a corrupted state!"
    quit(1)

  if VERBOSE:
    echo "Left $1 bytes on $2" % [$a.contentSize, filename]

type
  DiskEntry = object ## Holds the results of scanning a file from disk.
    diskPath: string ## Path to the file on disk.
    virtualPath: string ## Path that will be generated on the appended fs.
    size: biggestInt ## Size of the file to be added, always zero or bigger.


proc `$`(d: DiskEntry): string =
  ## Returns a string representation of the DiskEntry for debugging/logging.
  return "vpath:$3 from $1, size:$2" % [d.diskPath, $d.size, d.virtualPath]


proc sortCmp(x, y: DiskEntry): int =
  ## Wrapper around system.cmp for the virtualPath field.
  return cmp(x.virtualPath, y.virtualPath)


proc newDiskEntry(path, vpath: string): DiskEntry =
  ## Returns a properly filled DiskEntry object.
  ##
  ## The size will be taken from the path. Only files lesser than 2GiB will be
  ## accepted.
  result.diskPath = path
  result.virtualPath = vpath
  result.size = path.getFileSize
  if result.size >= high(int32):
    echo "File sizes can't be bigger than 2GiB, $1 is $2 bytes" % [
      result.diskPath, $result.size]
    quit(1)


proc overwriteAppendedData(filename: string, inputFiles: seq[string]) =
  ## Overwrites the specified filename appended data with files under dirs.
  removeAppendedData(filename)
  var diskEntries: seq[DiskEntry] = @[]

  for path in inputFiles:
    if path.existsFile:
      if VERBOSE:
        echo "Adding file ", path
      diskEntries.add(newDiskEntry(path, "/" & path.extractFilename))

    else:
      # Clean up the directory path removing trailing slashes.
      var path = path
      if path[len(path) - 1] in { DirSep, AltSep }:
        path = path.substr(0, len(path) - 2)

      let
        virtualBase = "/" & path.extractFilename
      if VERBOSE:
        echo "Adding recursively dir ", path, " as ", virtualBase

      # Ok, now iterate recursively over all the files adding them.
      for subPath in walkDirRec(path):
        if VERBOSE:
          echo "Adding file ", subPath
        diskEntries.add(newDiskEntry(subPath,
          virtualBase / subPath.substr(len(path))))

  sort(diskEntries, sortCmp)
  for d in diskEntries: echo($d)


when isMainModule:
  let args = processCommandline()

  if args.options.hasKey(paramRemove[0]):
    removeAppendedData(args.options[paramRemove[0]].strVal)
  elif args.options.hasKey(paramOverwrite[0]):
    overwriteAppendedData(args.options[paramOverwrite[0]].strVal,
      map(args.positionalParameters,
        proc(x: Tparsed_parameter): string = x.strVal))
