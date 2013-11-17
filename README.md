Nimrod Ouroboros
================

This is a module for the [Nimrod programming language](http://nimrod-code.org).
Its purpose is to provide an API to easily access data appended to the
currently running executable. Appending resources to your binary is not
something you will want to do for really big applications, but it can be useful
to *pack* configuration files or other small resources along your statically
compiled binary for portability if procs like `slurp` or `gorge` from the
[system module](http://nimrod-code.org/system.html) aren't enough for you.

The aim of the module is to be integrated in a future version of the compiler
so that the compiler can be distributed as a single binary to *unsuspecting*
parties with minimal *baggage*, thus lowering the entry barrier for installing
an *additional alien awkward* (triple As!) programming language tool into your
existing non Nimrod projects.  For further discussion see [a thread in the
Nimrod forum discussing the creation of a portable nimrod
compiler](http://forum.nimrod-code.org/t/194).

Not related to this project, there are [cool shirts with
ouroboros](http://www.topatoco.com/merchant.mvc?Screen=PROD&Store_Code=TO&Product_Code=OG-OUROBOROS&Category_Code=OG)
on them.


License
=======

[MIT license](LICENSE.md).


Installation
============

Stable version
--------------

Use [Nimrod's babel package manager](https://github.com/nimrod-code/babel) to
install the package and related tools:

	$ babel update
	$ babel install ouroboros

Development version
-------------------

Use [Nimrod's babel package manager](https://github.com/nimrod-code/babel) to
install locally the github checkout:

	$ git clone https://github.com/gradha/nimrod-ouroboros.git
	$ cd nimrod-ouroboros
	$ git checkout develop
	$ babel install

Usage
=====

Once you have installed the package with babel you can ``import ouroboros`` in
your programs and use it. The ``ouroboros`` module only provides read access
procs. You append data to your binary first with the alchemy tool, which is
installed into your Babel's binary directory:

	$ alchemy --help

At the moment you can either add a set of directories to your binary or remove
them. Future versions will provide finer granularity, like excluding certain
patterns or specifying manually the final virtual path of the added file.

Once your binary has appended data, the following code should work:

	import ouroboros, os
	
	let
	  appFilename = get_app_filename()
	  a = appFilename.getAppendedData
	
	if a.format != noData:
	  # Data found, try to read it!
	  echo "Binary " & appFilename & " has appended data!"
	  echo "File size " & $a.fileSize
	  echo "Data size " & $a.dataSize
	  echo "Content size " & $a.contentSize

At the moment only tests on the macosx platform have been performed. Other
platforms should follow, feel free to report bugs/problems if you find them.

Documentation
=============

The ``ouroboros`` module comes with embedded documentation you need to generate
using the Nimrod compiler. Go to the directory where babel installs the package
(check babel's documentation for the correct path on your platform) and run
Nimrod's doc command. Unix example:

	$ cd ~/.babel/pkgs/ouroboros-x.y.z
	$ nimrod doc ouroboros
	$ open ouroboros.html

You can do the same for the ``alchemy`` module. It is likely that ``alchemy``
will be merged into ``ouroboros`` in the future, but for the moment you can use
it as a programmatic interface to the commandline tool.

Appended data to binaries follows a custom file format which is described in
the [doc/file_format.md](doc/file_format.md) file.


Changes
=======

This is version 0.3.1. For a list of changes see the [CHANGES.md
file](CHANGES.md).


Plans for the future
====================

* Better ``alchemy`` tool.
* Different compression options for appended data.
* Emulation of fs access for macosx' app bundles (which don't really need
  ouroboros).


Git branches
============

This project uses the [git-flow branching
model](https://github.com/nvie/gitflow). Which means the ``master`` default
branch doesn't *see* much movement, development happens in another branch like
``develop``. Most people will be fine using the ``master`` branch, but if you
want to contribute something please check out first the ``develop`` brach and
do pull requests against that.


Feedback
========

You can send me feedback through [github's issue
tracker](https://github.com/gradha/nimrod-ouroboros/issues). I also take a look
from time to time to [Nimrod's forums](http://forum.nimrod-code.org) where you
can talk to other nimrod programmers.
