Ouroboros appended data file format
===================================

A normal binary is read from the beginning and trailing bytes are discarded by
the operating system. What follows is the payload plus an informative *footer*
(the inverse of a file header). Tools or programs willing to detect if a binary
contains appended data have to open the binary and read the last few bytes of
the footer.

* Binary data
* Payload data
* Footer meta data


Footer format
-------------

The footer length is always 9 bytes long. If you position the stream at the end
of the file size minus 9 bytes, you should read a 4 bytes magic marker, a
format/version byte, and 4 bytes length value:

1. 0xF3
2. 0x6C
3. 0x68
4. 0xFB
5. Payload format/version
6. Payload length fragment (MSB)
7. Payload length fragment
8. Payload length fragment
9. Payload length fragment (LSB)

Note that the footer can't have a payload length of negative or zero value.
This translates into a maximum payload length of 2GiB. If a payload is zero or
negative you should consider the file corrupt or without appended data.

The payload length is stored in Motorola byte ordering (big endian), where the
first byte contains the most significant byte of the value.


Payload format
--------------

The payload format allows different formats and expansion for the future.


Payload format 0x00, unsupported
++++++++++++++++++++++++++++++++

This value will never be present in any file. If a reader of appended data
reads an unknown file format, it should be treated as zero, meaning the reader
won't be able to handle the payload and operations on the binary should be
avoided.


Payload format 0x01, raw BLOB
+++++++++++++++++++++++++++++

This value means that the payload is treated as a single large binary object.
It is the most simple way of handling data, but it is usually limited to
retrieving the whole binary data at once.


Payload format 0x02, indexed format
+++++++++++++++++++++++++++++++++++

This format is used for appending several files to the binary. The files'
contents are concatenated and put after an index. The index contains the
original filename paths and sizes to recover the correct pieces::

    payload = index packets + file1 content +
        ... + fileN content

The *index packets* are just a sequence of *commands* which build up in memory
the original file paths of the payload. A reader should parse completely all
index packets in one go and keep in memory the tree they generate to know where
each file starts/ends. The packets create in memory a read only replica of a
virtual file system structure with its own directories and filenames. When you
start to read the information think of an empty file system at the root
(``/``).  Packets are found one after another, with the first byte indicating
the type of content following it.

There is not much point in forward compatibility, so if you find an unknown
packet type just abort and give up parsing the file.


Index packet 0x00, end of index
*******************************

If a packet header is zero it means there are no more packets to process.


Index packet 0x01, directory prefix
***********************************

This packet means that the current virtual file system has to change to another
directory. A single bytes will specify the length in bytes of the absolute path
filename, which will be used for the following files. All directory prefix
packets are required to have a length of 1, because all paths have to start
with a starting slash. The path can optionally have a trailing slash.

On disk the official path separator is the forward slash ``/`` but paths read
into memory should be filtered through the os.UnixToNativePath proc for end
user code. Paths are case sensitive. Path components like ``.`` or ``..``
**will not** be resolved. The encoding of the paths is UTF8.  Examples:

* Byte length 6, string value ``/home/``
* Byte length 16, string value ``/españa/level01``
* Byte length 18, string value ``/gallery/티아라``
* Byte length 1, string value ``/``

It is perfectly valid to alternate between directories between packets going
back and forth, though that's a little bit wasteful.


Index packet 0x02, long directory prefix
****************************************

The format of this packet is exactly the same as 0x01 except that the length
byte is replaced with two bytes in Motorola byte ordering (big endian) to
specify the length in bytes of the absolute path filename.

The two byte directory prefix is separate because most of the time path
prefixes will likely fit into a single byte.


Index packet 0x03, file
***********************

This packet means that a file will be *placed* at the current filesystem
virtual path previously specified through directory packets. If no directory
packets have been specified, files are to be placed at the root of the virtual
filesystem. This packet has the format::

    packet = filename length + filename +
        offset + length

The filename length is stored in a single byte, and it contains the length in
bytes of the UTF filename. Both the offset and length are specified as four
bytes in Motorola byte ordering (big endian). The offset is measured as the
number of bytes since the beginning of the appended data. It is therefore
impossible to have an offset smaller than a few bytes since the index of
filenames contributes to it.


Index packet 0x04, long name file
*********************************

The format of this packet is exactly the same as 0x03 except that the length
byte is replaced with two bytes in Motorola byte ordering (big endian) to
specify the length in bytes of the filename.

The two byte directory prefix is separate because most of the time filenames
will likely fit into a single byte.
