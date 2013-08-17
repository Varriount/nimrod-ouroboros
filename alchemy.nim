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
  RESULT.diskPath = path
  RESULT.virtualPath = vpath
  RESULT.size = path.getFileSize
  if RESULT.size >= high(int32):
    echo "File sizes can't be bigger than 2GiB, $1 is $2 bytes" % [
      RESULT.diskPath, $RESULT.size]
    quit(1)


type
  IndexPacket = object #of AppendedFileInfo
    name: string ## Path to store in the packet.
    offset, len: int32 ## Offset and length, only used for file packets.
    kind: PacketType ## Type of the packet.

  BuildInfo = tuple[packet: IndexPacket, file: DiskEntry] ## \
  ## Simple wrapper relating packets with disk entries (if necessary).


proc newIndexPacket(kind: PacketType,
    name = "", offset = 0, length = 0): IndexPacket =
  ## Creates a new index packet.
  ##
  ## Pass at least the type, and optionally other info.
  assert offset < high(int32)
  assert length < high(int32)
  RESULT.kind = kind
  RESULT.name = name
  RESULT.offset = int32(offset)
  RESULT.len = int32(length)

proc diskSize(packet: IndexPacket): int =
  ## Returns the expected disk size for this IndexPacket.
  case packet.kind:
  of endOfPackets: RESULT = 1
  of dirPacket: RESULT = 2 + packet.name.len
  of longDirPacket: RESULT = 3 + packet.name.len
  of filePacket: RESULT = 10 + packet.name.len
  of longFilePacket: RESULT = 11 + packet.name.len


proc processDiskEntries(diskEntries: seq[DiskEntry]): seq[BuildInfo] =
  ## Returns the list of building blocks to create a valid header.
  ##
  ## This proc first creates a temporary list of BuildInfo objects, these will
  ## contain IndexPacket with an offset relative to zero. Once the list is
  ## created its size is calculated, and it is added to all offsets.
  var EMPTY_DISK_ENTRY: DiskEntry
  EMPTY_DISK_ENTRY.diskPath = ""
  EMPTY_DISK_ENTRY.virtualPath = ""
  EMPTY_DISK_ENTRY.size = 0
  RESULT = @[]
  var
    VPATH = "/"
    OFFSET = 0

  for diskEntry in diskEntries:
    # Check if we have to change virtual path with this entry.
    var PARENT = diskEntry.virtualPath.parentDir
    # Files at the root of the virtual path will return empty parent dir.
    if PARENT.len < 1:
      PARENT = "/"

    if PARENT != VPATH:
      var I = newIndexPacket(dirPacket, parent)
      if I.name.len > 255:
        I.kind = longDirPacket
      RESULT.add((I, EMPTY_DISK_ENTRY))
      VPATH = parent

    # Add the file packet, increase our offset.
    var I = newIndexPacket(filePacket, diskEntry.virtualPath.extractFilename,
      OFFSET, int(diskEntry.size))
    if I.name.len > 255:
      I.kind = longFilePacket
    RESULT.add((I, diskEntry))
    OFFSET += int(diskEntry.size)

  # Add terminating endOfPackets entry.
  RESULT.add((newIndexPacket(endOfPackets), EMPTY_DISK_ENTRY))

  var TOTAL: int32
  for indexEntry in RESULT:
    let (packet, entry) = indexEntry
    TOTAL += int32(packet.diskSize)

  if VERBOSE:
    echo "The index of the appended data will be sized ", $TOTAL, " bytes"

  # Cool, now offset all those offsets!
  for f in 0..RESULT.len()-1:
    var (PACKET, ENTRY) = RESULT[f]
    PACKET.offset += TOTAL
    RESULT[f] = (PACKET, ENTRY)


proc write(O: var TFile, p: IndexPacket) =
  ## Writes to the file F the specified IndexPacket.
  var
    B: array[4, uint8]
    success: bool

  when not defined(release):
    let startOffset = O.getFilePos

  block action:
    if p.kind == filePacket or p.kind == longFilePacket:
      B[0] = uint8(p.kind)
      if p.kind == filePacket:
        B[1] = uint8(p.name.len)
        if O.writeBuffer(addr(B), 2) != 2:
          break action
      else:
        B[1] = (p.name.len shr 8) and 0xFF
        B[2] = p.name.len and 0xFF
        if O.writeBuffer(addr(B), 3) != 3:
          break action
      O.write(p.name)
      O.writeInt32M(p.offset)
      O.writeInt32M(p.len)
      success = true

    elif p.kind == dirPacket or p.kind == longDirPacket:
      B[0] = uint8(p.kind)
      if p.kind == dirPacket:
        B[1] = uint8(p.name.len)
        if O.writeBuffer(addr(B), 2) != 2:
          break action
      else:
        B[1] = (p.name.len shr 8) and 0xFF
        B[2] = p.name.len and 0xFF
        if O.writeBuffer(addr(B), 3) != 3:
          break action
      O.write(p.name)
      success = true

    elif p.kind == endOfPackets:
      success = (1 == O.writeBuffer(addr(B), 1))
    else:
      assert(false, "Should not reach this!")

  when not defined(release):
    let
      endOffset = O.getFilePos
      wrote = endOffset - startOffset
    assert wrote == p.diskSize

  if not success:
    raise newException(EIO, "Could not append index entry properly")


proc writeFileContents(O: var TFile, indexEntry: BuildInfo) =
  ## Writes to the file F the contents of the file specified by the DiskEntry
  ##
  ## If the DiskEntry is not a file it will be skipped.
  if not (indexEntry.packet.kind == filePacket or
      indexEntry.packet.kind == longFilePacket):
    return

  if VERBOSE:
    echo "Adding contents of ", indexEntry.file.diskPath

  let contents = readFile(indexEntry.file.diskPath)
  assert contents.len == indexEntry.packet.len
  O.write(contents)


proc writeMagicMarker(O: var TFile, dataSize: int) =
  ## Writes the terminating magic marker and other metadata.
  var
    B = magicMarker
    SIZE = O.writeBuffer(addr(B), 4)
  assert SIZE == 4
  B[0] = uint8(indexFormat)
  SIZE = O.writeBuffer(addr(B), 1)
  assert SIZE == 1
  O.writeInt32M(dataSize + 9)


proc overwriteAppendedData(filename: string, inputFiles: seq[string]) =
  ## Overwrites the specified filename appended data with files under dirs.
  removeAppendedData(filename)
  var diskEntries: seq[DiskEntry] = @[]

  for path in inputFiles:
    if path.existsFile:
      if VERBOSE:
        echo "Scanning file ", path
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
          echo "Scanning file ", subPath
        diskEntries.add(newDiskEntry(subPath,
          virtualBase / subPath.substr(len(path))))

  sort(diskEntries, sortCmp)
  let
    indexEntries = processDiskEntries(diskEntries)
    lastPacket = indexEntries[indexEntries.len - 1].packet

  echo "Appending file index"

  var O = open(filename, fmAppend)
  finally: O.close

  # Mark the current file position to figure out the total data size later.
  let contentSize = O.getFilePos
  for indexEntry in indexEntries: O.write(indexEntry.packet)

  # Verify that the written index entries match the header offset, which due to
  # how the list is built is stored in the last entry's offset.
  assert O.getFilePos - contentSize == lastPacket.offset

  echo "Appending files"

  for indexEntry in indexEntries.items: O.writeFileContents(indexEntry)
  O.writeMagicMarker(int(O.getFilePos - contentSize))
  let totalBytes = O.getFilePos
  echo "Added ", $(totalBytes - contentSize), " bytes, total ", $totalBytes


proc listAppendedData(filename: string) =
  ## Lists the appended data found in the specified file.
  let data = filename.getAppendedData
  case data.format
  of noData:
    echo "The file $1 doesn't seem to contain appended data" % [filename]
  of rawFormat:
    echo "The file $1 contains a binary blob, sized $2 bytes" %
      [filename, $data.dataSize]
  of indexFormat:
    echo "Listing contents of ", filename

    # First search what is the longest string of appended bytes.
    var
      W = len("bytes")
      TOTAL = 0
    for file in data.fileInfoList:
      W = max(W, len($file.len))
      TOTAL += file.len

    # Now properly display a header, content and footer.
    echo align("bytes", W) & " path"
    let separator = align("---", W) & " ---"
    echo separator

    for file in data.fileInfoList:
      echo(align(($file.len), W) & " " & file.name)
    echo separator

    echo "$1 bytes in $2 files" % [$TOTAL, $data.fileInfoList.len]


when isMainModule:
  let args = processCommandline()

  if args.options.hasKey(paramRemove[0]):
    removeAppendedData(args.options[paramRemove[0]].strVal)
  elif args.options.hasKey(paramOverwrite[0]):
    overwriteAppendedData(args.options[paramOverwrite[0]].strVal,
      map(args.positionalParameters,
        proc(x: Tparsed_parameter): string = x.strVal))
  elif args.options.hasKey(paramList[0]):
    listAppendedData(args.options[paramList[0]].strVal)
