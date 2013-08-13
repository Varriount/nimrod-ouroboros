Nimrod Ouroboros
================

This is a new module in progress for the [Nimrod programming
language](http://nimrod-code.org). It's purpose is to provide an API which in
the future can be used to access easily data appended to the currently running
executable. Likely this will be done through the [zipfiles
module](http://nimrod-code.org/zipfiles.html) to provide a read only file
system like access to the data.

For further discussion see [a thread in the Nimrod forum discussing the
creation of a portable nimrod compiler](http://forum.nimrod-code.org/t/194).


License
=======

[MIT license](LICENSE.md).


Installation and usage
======================

At the moment the module doesn't do much, it's in alpha state. Could you please
test it for me on your platform? If yes, to test it please run:

	$ nimrod c -r ouroboros.nim

This command will compile and run the binary. The program should detect that it
doesn't have any appended data and create a ``compressed_`` variant of it. When
you run this second version you should get a message similar to:

	Binary /foo/bar/compressed_ouroboros has appended data!
	File size 237468
	Data size 28
	Content size 237440
	Did read extra content 'Hello appended data!'

Does this work on your platform? I'm interested in hearing if it works or not
for other platforms out of the box, or not at all.


Changes
=======

This is version 0.1.1. For a list of changes see the [CHANGES.md
file](CHANGES.md).


Feedback
========

You can send me feedback through [github's issue
tracker](https://github.com/gradha/nimrod-ouroboros/issues). I also take a look
from time to time to [Nimrod's forums](http://forum.nimrod-code.org) where you
can talk to other nimrod programmers.
