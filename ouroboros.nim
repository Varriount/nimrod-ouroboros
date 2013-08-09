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
  version_str* = "0.0.1" ## Module version as a string.
  version_int* = (major: 0, minor: 0, maintenance: 1) ## \
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
  magic_marker: array[4, uint8] = [uint8(0x73), 0x6C, 0x68, 0x2B]
  metadata_size = 8 ## Length of the magic_marker plus offset.

# TODO: add to system.nim
proc `==` *[I, T](x, y: array[I, T]): bool =
  for f in low(x)..high(x):
    if x[f] != y[f]:
      return
  result = true

proc save_int32(FILE: var TFile, value: int): bool =
  assert value >= 0, "Negative values not supported"
  var T: array[4, uint8]
  T[0] = value and 0xFF
  T[1] = (value shr 8) and 0xFF
  T[2] = (value shr 16) and 0xFF
  T[3] = (value shr 24) and 0xFF
  result = FILE.write_buffer(addr(T), 4) == 4


proc read_int32(FILE: var TFile): int32 =
  ## Returns an int32 from the file, or negative if there was an error.
  var B: array[4, uint8]
  let read_bytes = FILE.read_buffer(addr(B), 4)
  if read_bytes != 4:
    result = -1
  else:
    # Last byte should not contain its eight bit on.
    if (B[3] and 0xA0) != 0:
      result = -1
    else:
      result = int32(B[0]) or (int32(B[1]) shl 8) or
        (int32(B[2]) shl 16) or (int32(B[3]) shl 24)


proc get_binary_data_info(binary_filename: string,
    FILE_SIZE: var int64, DATA_SIZE: var int32): bool {. discardable .} =
  ## Reads the specified filename and fills in the file size and data size.
  ##
  ## The returned FILE_SIZE includes any appended data, it is the same as you
  ## would call getFileSize on the binary. The DATA_SIZE includes the magic
  ## file markers to detect the appended data. Hence, DATA_SIZE will either be
  ## zero or bigger than metadata_size. FILE_SIZE - DATA_SIZE gives you the
  ## offset to the data, and DATA_SIZE - metadata_size gives you the total
  ## size.
  ##
  ## The proc returns true only if the file contains appended data.
  var F: TFile = open(binary_filename)
  finally: F.close
  FILE_SIZE = F.get_file_size
  DATA_SIZE = 0
  if FILE_SIZE > metadata_size:
    var BYTES: array[4, uint8]
    F.set_file_pos(FILE_SIZE - metadata_size)
    let read_bytes = F.read_buffer(addr(BYTES), 4)
    # Abort if we don't find the magic marker.
    if BYTES != magic_marker:
      return
    let size = F.read_int32
    if size > 0:
      DATA_SIZE = size
      result = true


proc replace_binary_data(binary_filename, data_filename: string) =
  ## Appends content from data_filename to the end of binary_filename.
  ##
  ## If the binary_filename already contains appended data, it will be
  ## replaced. If you pass the empty string for data_filename, binary_filename
  ## will be stripped from any appended data.
  var DATA = ""
  if data_filename.len > 0:
    DATA = readFile(data_filename)
  assert DATA.len < high(int32) - metadata_size, "Data to append too big"


proc fabricate_test_data(src, dest: string) =
  ## Overwrites dest with the content of src plus appended data.
  let
    appended_data = "Hello appended data!"
    total_data_size = len(appended_data) + metadata_size
  var F = open(dest, fm_write)
  finally: F.close
  var A = magic_marker # Duplicate so we can get its address.
  F.write(read_file(src))
  F.write(appended_data)
  discard F.write_buffer(addr(A), 4)
  doAssert F.save_int32(total_data_size)
  setFilePermissions(dest, getFilePermissions(src))

  echo "Generated binary with appended data at " & dest
  echo "Added " & $total_data_size & " bytes to the executable"


proc test1() =
  ## Tests the get_binary_data_info proc.
  ##
  ## The test will look at the current binary, if it contains appended data it
  ## will try to read the data and display it. If the binary doesn't contain
  ## data, a new one will be created with the appended data and metadata size.
  let app_filename = get_app_filename()
  var
    FILE_SIZE: int64
    DATA_SIZE: int32

  app_filename.get_binary_data_info(FILE_SIZE, DATA_SIZE)
  if DATA_SIZE > 0:
    # Data found, try to read it!
    let payload_len = DATA_SIZE - metadata_size
    echo "Binary " & app_filename & " has appended data!"
    echo "File size " & $FILE_SIZE
    echo "Data size " & $DATA_SIZE
    echo "Content size " & $(FILE_SIZE - DATA_SIZE)

    var F = open(app_filename, fm_read)
    finally: F.close()

    F.set_file_pos(FILE_SIZE - DATA_SIZE)
    var BUF = new_string(payload_len)
    let read_len = F.read_buffer(addr(BUF[0]), payload_len)
    echo "Did read extra content '" & BUF & "'"
  else:
    # No data, create new binary with some appended data.
    var (DIR, NAME, EXT) = app_filename.split_file()
    let target_filename = DIR / "compressed_" & NAME & EXT
    fabricate_test_data(app_filename, target_filename)

when isMainModule:
  test1()
