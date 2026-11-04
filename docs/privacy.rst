Privacy
=======

Wyss DBS Annotator collects nothing, transmits nothing, and requires no account.

This page is the privacy statement for the published app, and it is written to be
checkable rather than reassuring: everything below is a property of the software
that you can verify from the source, not a promise about how data is handled on a
server. There is no server.

What leaves the device
----------------------

Nothing. The application makes **no network connection of any kind**: no
telemetry, no crash reporting, no analytics, no licence check, no update check.
It contains no HTTP client and opens no sockets. The repository URL and contact
address shown in the *About* dialog are rendered as selectable text specifically so
that the app has no reason to open a browser.

The practical consequence: the app works in a room with no network, and there is no
data-processing agreement to sign, because no data is processed anywhere but on
your own device.

What is stored, and where
-------------------------

Four things, all local.

**Your session data**, in the files you create. Session and notes files are written
only where you choose to save them, through the operating system's own file picker
or share sheet. If you delete the file, the data is gone.

**A working copy of the session in progress**, inside the app's own storage. Every
entry is written to it as well as to your file, so a crash or a closed window loses
nothing; the next time you open the workflow the app offers it back. When you
leave a session the app asks whether to keep this copy or discard it, and it is
deleted only if you choose to discard it. The app never uploads it. Uninstalling
the app removes it on Android, iOS, iPadOS and the Windows Store (MSIX) build; on
the other desktop builds see the table below for where the folder is.

**Temporary copies for sharing and exporting.** Sharing or exporting a file first
writes a copy to the app's cache folder. The app deletes that copy right after the
file is saved or the share finishes. A copy left behind by a crash, or one that
could not be deleted, is removed at the next export once it is more than an hour
old. Two helper libraries keep copies of their own, outside the app's control:

- On Android, the file picker copies a file you open into the app's cache, and the
  share sheet copies a shared file into its own cache folder, which is cleared at
  the next share.
- On iOS and iPadOS, the share sheet uses the export copy without copying it, and
  the file picker copies a file you open into the app's temporary folder. The
  header file of a new session is also written there, named after the session,
  and is not deleted.

On iOS and Android, entries you record after opening a file are autosaved into
the picker's copy of that file in the app's cache or temporary folder, not into
the file you opened.

The operating system clears these folders when it needs the space, and they are
removed when the app is uninstalled.

**Your preferences**, in a single small JSON file: the scale and stimulation presets
you have customised, your program names, the report page size and section
selection, and the order of the panels in the entry chart. No patient data is
stored in it. It lives in the per-user application-support directory for the
platform:

.. list-table::
   :header-rows: 1
   :widths: 22 78

   * - Platform
     - Location
   * - Windows
     - the app's private application-data folder under ``%LOCALAPPDATA%\Packages\``
       (Store build), or ``%APPDATA%\ch.wysscenter\dbs_annotator`` (zip build)
   * - macOS
     - ``~/Library/Containers/ch.wysscenter.dbsAnnotator/Data/Library/Application Support/``
   * - Linux
     - ``~/.local/share/``
   * - iOS, iPadOS, Android
     - the app's private sandbox, removed when the app is uninstalled

On Windows the Store (MSIX) build removes its data on uninstall. The zip build has no
uninstaller, so delete ``%APPDATA%\ch.wysscenter\dbs_annotator`` by hand, and the
cache folder ``%LOCALAPPDATA%\ch.wysscenter\dbs_annotator`` as well. The first of
these is a roaming folder, so on a domain with roaming profiles it is copied to the
server with the rest of your profile. On macOS the app is sandboxed, so the folders
live in a container that stays after the app is moved to the Trash; its cache folder
is under ``~/Library/Containers/ch.wysscenter.dbsAnnotator/Data/Library/Caches/``. On Linux
nothing is removed by deleting the extracted tarball, and the cache folder is under
``~/.cache/``. Delete the folders in the table, and these cache folders, yourself.

Backups follow the platform, for the app's own storage. On Android the app disables
backup and device-to-device transfer, so the working copy and preferences do not
leave the device that way. On iOS and iPadOS the app does not exclude its storage
from an iCloud or computer backup, so they can appear in those backups. On desktop,
your own backup software sees whatever it is configured to see.

Patient data
------------

The app records clinical information: stimulation parameters, scale ratings, side
effects, free-text notes, and whatever subject identifier you type. **You choose
what identifier to use, and the app never requires a real one.** Use a study code
rather than a name or a hospital number wherever your protocol allows; the BIDS
naming the app follows is designed for exactly that.

Because the data never leaves the device, the responsibility for it is the same as
for any file on that device: your institution's rules on encryption, backup,
retention and disposal apply, and the app neither helps nor hinders them. Full-disk
encryption is worth having on any device carried between clinics.

If you report a bug
-------------------

Please do not attach a real session file, screenshot or report to a public issue.
The repository includes a **synthetic** example session for exactly this
purpose, under ``test/fixtures/`` and generated by
``tool/generate_fixtures.dart``, and it reproduces most format questions. The
same request is made in the project's
`code of conduct <https://github.com/neuromodulation/DBSAnnotator/blob/main/.github/CODE_OF_CONDUCT.md>`_.

Changes
-------

This statement is versioned with the software. Its history is the file's history in
the repository, so any change to it is visible in the commit log.

Questions: lucia.poma@wysscenter.ch
