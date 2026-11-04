Installation
============

Wyss DBS Annotator is available for iPadOS, Android, Windows, macOS and Linux. It
is published in each platform's app store by the **Wyss Center for Bio and
Neuroengineering**; search for *Wyss DBS Annotator*.

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Platform
     - Where to get it
   * - iPadOS
     - App Store
   * - Android
     - Google Play
   * - Windows
     - Microsoft Store
   * - macOS
     - Mac App Store
   * - Linux
     - Snap Store

Installing from the store is the whole procedure: the store handles signing and
updates. Every platform runs the same application.

Where your data goes
--------------------

Session files are written where you choose to save them, through the platform's
own file picker or share sheet. While you record, the app also keeps a working
copy of the current session inside its own storage, so a crash or a closed
window loses nothing. When you leave a session, the app asks whether to keep that
copy or discard it; it is only ever deleted when you choose to. Preferences
(scale presets, paper size, panel order) are stored in the app's own settings
folder. Nothing is uploaded. See :doc:`privacy` for the details.

Building from source
--------------------

For developers who want to run or modify the code. On every platform you need
`Git <https://git-scm.com>`_ and the
`Flutter SDK <https://docs.flutter.dev/get-started/install>`_ **3.47 or
later**, with Flutter's ``bin`` folder on your ``PATH``. Then get the code:

.. code-block:: bash

   git clone https://github.com/neuromodulation/DBSAnnotator.git
   cd DBSAnnotator
   flutter pub get
   flutter doctor       # lists anything still missing for your platform

Nothing needs generating first: the data contract and the fonts are committed.
``flutter analyze`` and ``flutter test`` check the checkout; neither needs a
device.

Each platform below adds its own tools, how to run the app, and how to build a
release.

Windows
~~~~~~~

* **Tools**: Visual Studio 2022 (the free Community edition is enough) with the
  **Desktop development with C++** workload. VS Code alone is not enough.
* **Run**: ``flutter run -d windows``
* **Release build**: ``flutter build windows --release``. The program is
  ``build\windows\x64\runner\Release\dbs_annotator.exe``; copy the whole
  ``Release`` folder, since it needs the DLLs and the ``data`` folder beside it.
  Windows shows "Windows protected your PC" on first launch of an unsigned
  build: *More info* → *Run anyway*.

macOS
~~~~~

* **Tools**: Xcode from the Mac App Store, then
  ``sudo xcodebuild -runFirstLaunch`` and CocoaPods (``brew install cocoapods``).
* **Run**: ``flutter run -d macos``
* **Release build**: ``flutter build macos --release``. The app is
  ``build/macos/Build/Products/Release/dbs_annotator.app``. An unsigned build is
  blocked on double-click; right-click it → *Open* allows it once.

Linux
~~~~~

* **Tools** (Debian and Ubuntu; other distributions have the same packages):

  .. code-block:: bash

     sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

  The save dialog is drawn by GTK. The open dialog comes from the XDG desktop
  portal of your session; without it, opening a file fails with a message. If a
  save dialog cannot open, the app saves to a fixed folder and tells you where.
* **Run**: ``flutter run -d linux``
* **Release build**: ``flutter build linux --release``. The program is
  ``build/linux/x64/release/bundle/dbs_annotator``; copy the whole ``bundle``
  folder.

Android
~~~~~~~

* **Tools**: Android Studio, which installs the Android SDK. Then accept the SDK
  licences with ``flutter doctor --android-licenses``.
* **Run**: on a device with *USB debugging* turned on in its developer options,
  or on an emulator from Android Studio: ``flutter run``
* **Release build**: ``flutter build apk --release``. The installer is
  ``build/app/outputs/flutter-apk/app-release.apk``; copy it to the device and
  open it, allowing installation from that source when asked. Unless a signing
  key is configured the build is signed with a development key, which cannot
  later be replaced in place by a store build: that needs an uninstall first,
  which removes the app's saved preferences.

iPadOS
~~~~~~

* **Tools**: a Mac with Xcode and CocoaPods, as for macOS.
* **Signing**: open ``ios/Runner.xcworkspace`` in Xcode, select the *Runner*
  target, and under *Signing & Capabilities* choose your team. A free Apple ID
  works for your own iPad.
* **Run**: connect the iPad, trust the Mac on it, then ``flutter run``
* A build signed with a free Apple ID stops opening after seven days and has to
  be installed again; a paid Apple Developer account removes that limit.

Common problems
~~~~~~~~~~~~~~~

* ``flutter`` is not found: the terminal was opened before ``PATH`` changed;
  open a new one.
* ``C1083: Cannot open source file`` on Windows after switching branches: run
  ``flutter clean``, then build again.
* Errors about long paths when cloning on Windows:
  ``git config --global core.longpaths true``.
