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

Use [Nimrod's babel package manager](https://github.com/nimrod-code/babel) to
install the [argument parser module](https://github.com/gradha/argument_parser)
required by this program and the [nake](https://github.com/fowlmouth/nake) tool to run build tasks:

	$ babel install argument_parser
	$ babel install nake

Once you have these modules installed, use nake to list the tasks and run one:

	$ nake
	$ nake [task_name]

The available tasks are:

* ``babel``: uses babel to install the ouroboros module locally.
  At the moment ouroboros is not yet in the public babel but you
  can install locally and use it as if it were. You will need to
  press ``Y`` if you already have a previous ouroboros package
  installed.

* ``bin``: builds the ``alchemy`` binary. Use ``alchemy`` to add, inspect
  and remove arbitrary appended data to binaries (or just about
  anything). Run ``alchemy`` to see its help and available commands.

* ``local_install``: builds and copies ``alchemy`` to your ``~/bin`` path.

* ``docs``: Runs nimdoc on the alchemy and ouroboros modules.


Changes
=======

This is version 0.3.1. For a list of changes see the [CHANGES.md
file](CHANGES.md).


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
