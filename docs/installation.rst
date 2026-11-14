Installation
============

Wyss DBS Annotator runs on iPadOS, Android, Windows, macOS and Linux, and is
published by the **Wyss Center for Bio and Neuroengineering**. Every platform runs
the same application and writes the same files.

.. raw:: html

   <div class="dbs-dl">
     <div class="dbs-dl-head">
       <img src="_static/app_icon.png" alt="" width="64" height="64">
       <div>
         <div class="dbs-dl-name">Wyss DBS Annotator</div>
         <div class="dbs-dl-meta">Wyss Center for Bio and Neuroengineering &middot; Free</div>
       </div>
     </div>
     <a id="dbs-dl-main" class="dbs-dl-main" href="#get-the-app">Download</a>
     <p id="dbs-dl-note" class="dbs-dl-note">Choose your platform below.</p>
     <div class="dbs-dl-label">All platforms</div>
     <div id="get-the-app" class="dbs-dl-grid"></div>
   </div>
   <script>
   (function () {
     var apple = null;
     var platforms = {
       windows: { name: "Windows", store: "Microsoft Store",
         web: "https://apps.microsoft.com/detail/9PD9QFRXZLLL",
         app: "ms-windows-store://pdp/?ProductId=9PD9QFRXZLLL" },
       macos: { name: "macOS", store: "Mac App Store",
         web: apple && "https://apps.apple.com/app/id" + apple,
         app: apple && "macappstore://apps.apple.com/app/id" + apple },
       linux: { name: "Linux", store: "Terminal command", web: "#install-on-linux" },
       ipados: { name: "iPadOS", store: "App Store",
         web: apple && "https://apps.apple.com/app/id" + apple },
       android: { name: "Android", store: "Google Play",
         web: "https://play.google.com/store/apps/details?id=ch.wysscenter.dbsannotator" }
     };

     var grid = document.getElementById("get-the-app");
     Object.keys(platforms).forEach(function (key) {
       var p = platforms[key];
       var el = document.createElement(p.web ? "a" : "span");
       el.className = "dbs-dl-platform" + (p.web ? "" : " is-soon");
       if (p.web) el.href = p.web;
       el.innerHTML = "<strong>" + p.name + "</strong><span>" +
         (p.web ? p.store : "Coming soon") + "</span>";
       grid.appendChild(el);
     });

     var ua = navigator.userAgent;
     var os = /Android/.test(ua) ? "android"
       : /iPad|iPhone/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) ? "ipados"
       : /Windows/.test(ua) ? "windows"
       : /Macintosh/.test(ua) ? "macos"
       : /Linux|X11/.test(ua) ? "linux"
       : null;
     if (!os) return;

     var p = platforms[os];
     var main = document.getElementById("dbs-dl-main");
     var note = document.getElementById("dbs-dl-note");
     if (!p.web) {
       main.textContent = "Coming soon for " + p.name;
       main.removeAttribute("href");
       main.className += " is-soon";
       note.textContent = "Other platforms are available below.";
       return;
     }
     main.textContent = "Download for " + p.name;
     main.href = p.app || p.web;
     if (os === "linux") {
       note.textContent = "Shows the one-line install command.";
     } else if (p.app) {
       note.innerHTML = "Opens the " + p.store + " app. Not opening? " +
         "<a href=\"" + p.web + "\">View it in your browser</a>.";
     } else {
       note.textContent = "Opens " + p.store + ".";
     }
   })();
   </script>

The Download button recognises the device you are reading this on. On Windows it
opens the Microsoft Store app itself, which shows whether Wyss DBS Annotator is
already installed and keeps it up to date; on iPadOS and Android the store page
opens in the store app as usual. On Linux it shows the install command below. To
install on a different device, pick it under *All platforms*.

On the store platforms, installing from the store is the whole procedure: the
store checks the app's signature and installs updates for you. On a computer
managed by your hospital or institution, the store may be blocked; your IT
department can install the app from the same listing. If a link does not open,
search the store for *Wyss DBS Annotator*.

.. _install-on-linux:

Install on Linux
----------------

On Linux the app is not in a store. Paste this into a terminal; it downloads the
latest release from
`GitHub <https://github.com/WyssCenter/DBSAnnotator/releases/latest>`_,
unpacks it into your home folder and adds a ``dbs-annotator`` command. It needs no
administrator rights.

.. code-block:: bash

   mkdir -p ~/.local/share/dbs-annotator ~/.local/bin
   curl -fsSL https://github.com/WyssCenter/DBSAnnotator/releases/latest/download/dbs-annotator-linux-x64.tar.gz \
     | tar -xz -C ~/.local/share/dbs-annotator
   ln -sf ~/.local/share/dbs-annotator/dbs_annotator ~/.local/bin/dbs-annotator

Then start it with ``dbs-annotator``. If the shell says the command is not found,
``~/.local/bin`` is not on your ``PATH`` yet: open a new terminal, or run
``~/.local/share/dbs-annotator/dbs_annotator`` directly.

* **Requirements**: a 64-bit (x86-64) desktop with GTK 3, which every mainstream
  desktop distribution already has. The open dialog comes from the XDG desktop
  portal of your session; without it, opening a file fails with a message.
* **Updating**: run the same command again. It replaces the program files; your
  sessions and preferences are kept.
* **Uninstalling**: ``rm -rf ~/.local/share/dbs-annotator ~/.local/bin/dbs-annotator``.
  This removes the program only; see :doc:`privacy` for where preferences and the
  working copy are kept.

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
