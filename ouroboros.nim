## Code to read data from your own binary
##
## This module provides basic tools to manipulate binary files to append random
## data to them. End user procs are provided to read this data later from your
## binary. In the future this proc may be used for things like
## http://forum.nimrod-code.org/t/194.
##
## Source code for this module may be found at
## https://github.com/gradha/ouroboros.

import os, unsigned, tables

const
  versionStr* = "0.3.1" ## Module version as a string.
  versionInt* = (major: 0, minor: 3, maintenance: 1) ## \
  ## Module version as an integer tuple.
  ##
  ## Major versions changes mean a break in API backwards compatibility, either
  ## through removal of symbols or modification of their purpose.
  ##
  ## Minor version changes can add procs (and maybe default parameters). Minor
  ## odd versions are development/git/unstable versions. Minor even versions
  ## are public stable releases.
  ##
  ## Maintenance version changes mean I'm not perfect yet despite all the kpop
  ## I watch.

  magicMarker*: array[4, uint8] = [uint8(0xF3), 0x6C, 0x68, 0xFB] ## \
  ## Magic signature found at the end of the file - 9 bytes.
  metadataSize* = 9 ## Length of the magicMarker plus version and offset.

type
  AppendedFormat* = enum
    noData = 0, ## No appended data or unsupported file format.
    rawFormat = 1, ## Simple BLOB, ouroboros doesn't touch it in any way.
    indexFormat = 2, ## Custom file tree index.

  AppendedData* = object ## Information on a binary
    path*: string ## Path to the binary with the appended data.
    fileSize*: int64 ## Total file size reported by the OS.
    contentSize*: int64 ## Amount of bytes for the original binary.
    dataSize*: int32 ## Length of the payload without metadataSize
    format*: AppendedFormat ## Type of appended data.
    files: seq[AppendedFileInfo] ## List of files for indexFormat and above.
    fileTable: TTable[string, int] ## Maps vpath to files index.

  AppendedFileInfo* = object of Tobject ## \
    ## Provides information about an appended file.
    name*: string ## Full virtual path inside the appended data.
    offset*: int32 ## Offset of the file's payload inside the data.
    len*: int32 ## Length of the file.

  PacketType* = enum ## Different packet types for the index.
    endOfPackets = 0, ## The end of it all. Noooooooo!
    dirPacket = 1, ## Short directory packet follows.
    longDirPacket = 2, ## Long directory packet follows.
    filePacket = 3 ## File packet follows.
    longFilePacket = 4 ## Long file packet follows.


# TODO: add to system.nim
proc `==` *[I, T](x, y: array[I, T]): bool =
  for f in low(x)..high(x):
    if x[f] != y[f]:
      return
  result = true

proc writeInt32M*(file: TFile, value: int) =
  ## Saves an int32 to the file. Raises EIO if the write had problems.
  ##
  ## The integer is saved in motorola byte ordering (big endian), meaning first
  ## the MSB is written to the file.
  assert value >= 0, "Negative values not supported"
  var T: array[4, uint8]
  T[0] = (value shr 24) and 0xFF
  T[1] = (value shr 16) and 0xFF
  T[2] = (value shr 8) and 0xFF
  T[3] = value and 0xFF
  let result = file.writeBuffer(addr(T), 4) == 4
  if not result:
    raise newException(EIO, "Could not write motorola int32 to file")


proc readInt32M*(file: TFile): int32 =
  ## Returns an int32 from the file.
  ##
  ## The integer is expected to be in motorola byte ordering (big endian),
  ## meaning first the MSB is read from the file. Raises EIO if there was any
  ## problem.
  var B: array[4, uint8]
  let readBytes = file.readBuffer(addr(B), 4)
  if readBytes != 4:
    raise newException(EIO, "Could not read 4 bytes for motorola int32")
  else:
    result = int32(B[3]) or (int32(B[2]) shl 8) or
      (int32(B[1]) shl 16) or (cast[int8](B[0]) shl 24)


proc readInt16M*(file: TFile): int =
  ## Returns an int16 from the file, or negative if there was an error.
  ##
  ## The integer is expected to be in motorola byte ordering (big endian),
  ## meaning first the MSB is read from the file. Raises EIO if there was any
  ## problem.
  var B: array[2, uint8]
  let readBytes = file.readBuffer(addr(B), 2)
  if readBytes != 2:
    raise newException(EIO, "Could not read 2 bytes for motorola int16")
  else:
    result = int32(B[1]) or (cast[int8](B[0]) shl 8)


proc readInt8*(file: TFile): int =
  ## Returns an int8 from the file.
  ##
  ## Raises EIO if there was any problem.
  var B: array[1, int8]
  let readBytes = file.readBuffer(addr(B), 1)
  if readBytes != 1:
    raise newException(EIO, "Could not read byte for int8")
  else:
    result = B[0]


proc readIndexFiles(f: TFile, DATA: var AppendedData) =
  ## Reads any index files into the files field.
  ##
  ## The files field is first set to nil, then if the datafile contains valid
  ## info the files field will be populated with it.
  assert DATA.format == indexFormat
  assert DATA.dataSize > 0
  DATA.files = @[]
  DATA.fileTable = initTable[string, int]()
  f.setFilePos(DATA.contentSize)

  var
    VPATH = UnixToNativePath("/")
    SIZE = 0 # Holds the length of the variable strings being read.

  while true:
    let packet = PacketType(f.readInt8)
    case packet
    of endOfPackets: break
    of dirPacket: SIZE = f.readInt8
    of longDirPacket: SIZE = f.readInt16M
    of filePacket: SIZE = f.readInt8
    of longFilePacket: SIZE = f.readInt16M
    else: raise newException(EIO, "Unknown packet type in stream")
    assert SIZE > 0

    var NAME = newString(SIZE)
    let readBytes = f.readBuffer(addr(NAME[0]), SIZE)
    assert readBytes == SIZE
    NAME = UnixToNativePath(NAME)

    if packet == dirPacket or packet == longDirPacket:
      VPATH = NAME
    else:
      var i: AppendedFileInfo
      i.name = VPATH / NAME
      i.offset = f.readInt32M
      i.len = f.readInt32M
      DATA.fileTable[i.name] = DATA.files.len
      DATA.files.add(i)

  assert DATA.files.len > 0


proc fileInfoList*(data: AppendedData): seq[AppendedFileInfo] =
  ## Returns the list of files in the appended data.
  ##
  ## May return nil if the AppendedData structure is not initialized or doesn't
  ## correspond to a file with indexFormat like content.
  ##
  ## The files are returned in the same sequential order as they were read from
  ## the appended data index, the sort order is not guaranteed.
  return data.files


proc getAppendedData*(binaryFilename: string): AppendedData =
  ## Reads the specified filename and fills in the AppendedData object.
  ##
  ## If the binary doesn't contain any appended data format will equal noData
  ## contentSize will equal fileSize. This proc will also load all the
  ## necessary index structures to access more complex file formats like
  ## indexFormat.
  var F: TFile = open(binaryFilename)
  finally: F.close
  RESULT.path = binaryFilename
  RESULT.fileSize = F.getFileSize
  RESULT.contentSize = RESULT.fileSize
  if RESULT.fileSize < metadataSize + 1:
    return

  var
    BYTES: array[4, uint8]
    READ_BYTES: int

  F.setFilePos(RESULT.fileSize - metadataSize)
  READ_BYTES = F.readBuffer(addr(BYTES), 4)
  # Abort if we don't find the magic marker.
  if READ_BYTES != 4 or BYTES != magicMarker:
    return

  READ_BYTES = F.readBuffer(addr(BYTES), 1)
  let format = AppendedFormat(BYTES[0])
  case format
  of rawFormat: RESULT.format = rawFormat
  of indexFormat: RESULT.format = indexFormat
  else:
    RESULT.format = noData
    return

  # There is appended data. Get the total length.
  let offset = F.readInt32M
  if offset > metadataSize:
    assert offset - metadataSize < high(int32)
    RESULT.dataSize = offset - metadataSize
    RESULT.contentSize -= offset
  else:
    RESULT.format = noData

  if format == indexFormat:
    F.readIndexFiles(RESULT)


proc fabricateTestData(src, dest: string) =
  ## Overwrites dest with the content of src plus appended data.
  let
    data = "Hello appended data!"
    totalDataSize = len(data) + metadataSize
  var F = open(dest, fm_write)
  finally: F.close
  var A = magicMarker # Duplicate so we can get its address.
  F.write(readFile(src))
  F.write(data)
  discard F.writeBuffer(addr(A), 4)
  A[0] = uint8(rawFormat)
  discard F.writeBuffer(addr(A), 1)
  F.writeInt32M(totalDataSize)
  setFilePermissions(dest, getFilePermissions(src))

  echo "Generated binary with appended data at " & dest
  echo "Added " & $totalDataSize & " bytes to the executable"


proc readString(filename: string, offset, len: int): string =
  ## Helper proc which reads a string of specific size from inside a file.
  var F = open(filename, fmRead)
  finally: F.close()

  F.setFilePos(offset)
  RESULT = newString(len)
  let readBytes = F.readBuffer(addr(RESULT[0]), len)
  if readBytes != len:
    raise newException(EIO, "Couldn't read all the necessary bytes!")


proc existsFile(data: AppendedData, path: string): bool =
  ## Returns true if the path is listed in the appendeda data.
  if not data.files.isNil():
    RESULT = data.fileTable.hasKey(path)


proc string*(data: AppendedData, filename: string): string =
  ## Retrieves a string from the appended data.
  ##
  ## If the AppendedData doesn't contain any valid appended data, this proc
  ## raises EInvalidValue. If the specified filename is not found, it returns
  ## nil.
  ##
  ## If the AppendedData.format is rawFormat the filename parameter is ignored
  ## and the whole data is always returned, so you can pass nil.
  if data.format == rawFormat:
    assert data.dataSize < high(int)
    RESULT = readString(data.path, int(data.contentSize), int(data.dataSize))
    return

  assert data.format == indexFormat
  if data.fileTable.hasKey(filename):
    let info = data.files[data.fileTable[filename]]
    RESULT = readString(data.path, int(data.contentSize + info.offset),
      int(info.len))


proc test1() =
  ## Tests the get_binary_data_info proc.
  ##
  ## The test will look at the current binary, if it contains appended data it
  ## will try to read the data and display it. If the binary doesn't contain
  ## data, a new one will be created with the appended data and metadata size.
  let
    appFilename = get_app_filename()
    a = appFilename.getAppendedData

  if a.format == rawFormat:
    # Data found, try to read it!
    echo "Binary " & appFilename & " has appended data!"
    echo "File size " & $a.fileSize
    echo "Data size " & $a.dataSize
    echo "Content size " & $a.contentSize

    let extra_content = a.string(nil)
    echo "Did read extra content '" & extra_content & "'"
  else:
    # No data, create new binary with some appended data.
    var (DIR, NAME, EXT) = appFilename.splitFile()
    let targetFilename = DIR / "compressed_" & NAME & EXT
    fabricateTestData(appFilename, targetFilename)

proc test2() =
  let
    appFilename = "compressed_ouroboros"
    a = appFilename.getAppendedData
    files = a.fileInfoList

  for file in files:
    echo file.name
  #echo a.string("/Cobralation/build.py")


#when isMainModule:
#  #test1()
#  test2()
