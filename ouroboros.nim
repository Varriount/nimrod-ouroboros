## Code to read data from your own binary
##
## This module provides basic tools to manipulate binary files to append random
## data to them. End user procs are provided to read this data later from your
## binary. In the future this proc may be used for things like
## http://forum.nimrod-code.org/t/194.
##
## Source code for this module may be found at
## https://github.com/gradha/ouroboros.

import os, unsigned

const
  version_str* = "0.3.1" ## Module version as a string.
  version_int* = (major: 0, minor: 3, maintenance: 1) ## \
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

  magicMarker: array[4, uint8] = [uint8(0xF3), 0x6C, 0x68, 0xFB] ## \
  ## Magic signature found at the end of the file - 9 bytes.
  metadataSize = 9 ## Length of the magicMarker plus version and offset.

type
  AppendedFormat* = enum
    noData = 0, ## No appended data or unsupported file format.
    rawFormat = 1, ## Simple BLOB, ouroboros doesn't touch it in any way.

  AppendedData* = object ## Information on a binary
    fileSize*: int64 ## Total file size reported by the OS.
    contentSize*: int64 ## Amount of bytes for the original binary.
    dataSize*: int32 ## Length of the payload without metadataSize
    format*: AppendedFormat ## Type of appended data.


# TODO: add to system.nim
proc `==` *[I, T](x, y: array[I, T]): bool =
  for f in low(x)..high(x):
    if x[f] != y[f]:
      return
  result = true

proc write_int32_m(FILE: var TFile, value: int) =
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
  let result = FILE.write_buffer(addr(T), 4) == 4
  if not result:
    raise new_exception(EIO, "Could not write motorola int32 to file")


proc read_int32_m(FILE: var TFile): int32 =
  ## Returns an int32 from the file, or negative if there was an error.
  ##
  ## The integer is expected to be in motorola byte ordering (big endian),
  ## meaning first the MSB is read from the file.
  var B: array[4, uint8]
  let read_bytes = FILE.read_buffer(addr(B), 4)
  if read_bytes != 4:
    raise new_exception(EIO, "Could not read 4 bytes for motorola int32")
  else:
    result = int32(B[3]) or (int32(B[2]) shl 8) or
      (int32(B[1]) shl 16) or (cast[int8](B[0]) shl 24)


proc getAppendedData*(binary_filename: string): AppendedData =
  ## Reads the specified filename and fills in the AppendedData object.
  ##
  ## If the binary doesn't contain any appended data format will equal noData
  ## contentSize will equal fileSize.
  var F: TFile = open(binary_filename)
  finally: F.close
  RESULT.fileSize = F.get_file_size
  RESULT.contentSize = RESULT.fileSize
  if RESULT.fileSize > metadataSize:
    var
      BYTES: array[4, uint8]
      READ_BYTES: int

    F.set_file_pos(RESULT.fileSize - metadataSize)
    READ_BYTES = F.read_buffer(addr(BYTES), 4)
    # Abort if we don't find the magic marker.
    if READ_BYTES != 4 or BYTES != magicMarker:
      return

    READ_BYTES = F.read_buffer(addr(BYTES), 1)
    let format = AppendedFormat(BYTES[0])
    case format
    of rawFormat:
      RESULT.format = rawFormat
    else:
      RESULT.format = noData
      return

    let offset = F.read_int32_m
    if offset > metadataSize:
      assert offset - metadataSize < high(int32)
      RESULT.dataSize = offset - metadataSize
      RESULT.contentSize -= offset
    else:
      RESULT.format = noData


proc fabricate_test_data(src, dest: string) =
  ## Overwrites dest with the content of src plus appended data.
  let
    appended_data = "Hello appended data!"
    total_data_size = len(appended_data) + metadataSize
  var F = open(dest, fm_write)
  finally: F.close
  var A = magicMarker # Duplicate so we can get its address.
  F.write(read_file(src))
  F.write(appended_data)
  discard F.write_buffer(addr(A), 4)
  A[0] = uint8(rawFormat)
  discard F.write_buffer(addr(A), 1)
  F.write_int32_m(total_data_size)
  setFilePermissions(dest, getFilePermissions(src))

  echo "Generated binary with appended data at " & dest
  echo "Added " & $total_data_size & " bytes to the executable"


proc test1() =
  ## Tests the get_binary_data_info proc.
  ##
  ## The test will look at the current binary, if it contains appended data it
  ## will try to read the data and display it. If the binary doesn't contain
  ## data, a new one will be created with the appended data and metadata size.
  let
    app_filename = get_app_filename()
    a = app_filename.getAppendedData

  if a.format == rawFormat:
    # Data found, try to read it!
    echo "Binary " & app_filename & " has appended data!"
    echo "File size " & $a.fileSize
    echo "Data size " & $a.dataSize
    echo "Content size " & $a.contentSize

    var F = open(app_filename, fm_read)
    finally: F.close()

    F.set_file_pos(a.contentSize)
    assert a.dataSize < high(int)
    var BUF = newString(a.dataSize)
    let read_len = F.read_buffer(addr(BUF[0]), int(a.dataSize))
    echo "Did read extra content '" & BUF & "'"
  else:
    # No data, create new binary with some appended data.
    var (DIR, NAME, EXT) = app_filename.split_file()
    let target_filename = DIR / "compressed_" & NAME & EXT
    fabricate_test_data(app_filename, target_filename)

when isMainModule:
  test1()
