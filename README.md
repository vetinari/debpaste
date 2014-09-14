# NAME

debpaste - http://paste.debian.net/ XML-RPC client

# SYNOPSIS

__debpaste__ ACTION \[OPTIONS\] \[CODE|ID\]

# ACTIONS

- add

Usage: debpaste add \[OPTIONS\] \[CODE\]

Adds a new paste to [http://paste.debian.net/](http://paste.debian.net/). If no code is given on the
command line, it will read from stdin.

Your paste infos are saved to _~/.debpaste.history_

- del

Usage: debpaste del \[OPTIONS\] ID

Deletes paste with id ID. This must be an ID which you have pasted before
(and is in your history file)

- get

Usage: debpaste get \[OPTIONS\] ID

Fetches the paste with id ID from [http://paste.debian.net](http://paste.debian.net). To `download`
a paste use something like

    debpaste get --noheader ID > OUTFILE

- lang

Usage: debpaste lang \[OPTIONS\]

Dumps the list of available languages for syntax highlighting, use the
__\--lang=LANG__ option when __add__ing a paste.

- edit

Usage: debpaste edit \[OPTIONS\] ID

Downloads the paste with id ID, spawns an editor, and sends the edited file
as new paste.

- expire

Usage: debpaste expire \[OPTIONS\] \[ID\]

Removes the entry ID from history file. If no ID is given it removes all
entries which are expired.

# OPTIONS

- \--user=USERNAME

paste as USERNAME instead of `anonymous`

- \--server=URL

use URL instead of http://paste.debian.net/server.pl

- \--hidden

post as hidden entry

- \--noproxy

do not use the http proxy given in the environment variable `http_proxy`

- \--lang=LANG

use LANG for syntax highlight ('debpaste lang' for available languages)

- \--expires=SEC

expires in SEC seconds (default: 259200 = 72h)

- \--encoding=ENC

when adding new paste, use ENC as encoding of file, default: UTF-8

- \--noheader

when __get__ting entries, don't print header, just dump the paste to stdout.

- \--version

print version and exit

# FILES

- ~/.debpaste.rc

The right place for setting default options like the username or expire values.
Format is `KeyInAnYCase: value`, example:

    User: Vetinari
    Expires: 86400

- ~/.debpaste.history

All info about pastes done with __debpaste__ are recorded here. This file
is used to keep a record for __del__eting entries after pasting. Use
__debpaste expire__ to remove old entries.

# NOTES

Renamed to `debpaste` at svn Rev. 20

# AUTHOR

Hanno Hecker <vetinari@ankh-morp.org>
