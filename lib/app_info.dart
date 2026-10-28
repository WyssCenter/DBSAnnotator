import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

/// App identity, mirroring the desktop `config.py` values.
const String appName = 'Wyss DBS Annotator';

/// Restates `version:` from pubspec.yaml, the source of truth; reading the
/// pubspec at runtime would need a native plugin. The value reaches report
/// footers and document metadata, so `version_parity_test.dart` guards it
/// against drift.
const String appVersion = '0.6.0';
const String repoUrl = 'https://github.com/neuromodulation/DBSAnnotator';
const String issuesUrl = '$repoUrl/issues';
const String docsUrl = 'https://dbs-annotator.readthedocs.io/';
const String contactEmail = 'lucia.poma@wysscenter.ch';

/// The same addresses as [Uri]s, for the About dialog's links. Parsed
/// once here rather than at every tap, and `mailto:` so the contact opens a
/// mail client instead of a browser.
final Uri repoUri = Uri.parse(repoUrl);
final Uri issuesUri = Uri.parse(issuesUrl);
final Uri docsUri = Uri.parse(docsUrl);
final Uri contactUri = Uri(scheme: 'mailto', path: contactEmail);

const String publisher = 'Wyss Center for Bio and Neuroengineering';
const String copyrightHolders =
    '$publisher, Massachusetts General Hospital, and Harvard Medical School';

/// The launcher master: the full-bleed square, without the rounded corners.
const String appIconAsset = 'assets/icon/app_icon.png';

/// The rounded app icon, the same in both themes, drawn in the AppBar and the
/// About dialog and used for the desktop window.
const String appLogoAsset = 'assets/icon/desktop_icon.png';

/// The Wyss Center lockup, mark plus wordmark, in the two official variants.
const String lockupBlackAsset = 'assets/icon/wyss_lockup_black.png';
const String lockupWhiteAsset = 'assets/icon/wyss_lockup_white.png';

/// The app icon as a widget, [size] logical pixels square. A missing asset
/// degrades to a Material glyph rather than a red error box.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    appLogoAsset,
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => Icon(Icons.psychology_outlined, size: size),
  );
}

/// The full lockup, picking the variant the current theme can show: the black
/// artwork disappears on a dark scaffold and the white on a light one.
class WyssLockup extends StatelessWidget {
  const WyssLockup({super.key, this.height = 28});

  /// Logical height; the lockup is 6.4 times as wide.
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    Theme.of(context).brightness == Brightness.dark
        ? lockupWhiteAsset
        : lockupBlackAsset,
    height: height,
    filterQuality: FilterQuality.medium,
    // A packaging slip should cost the lockup, not the dialog.
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

/// One `label: value` line whose value opens [uri] when tapped and stays
/// selectable, so the text can still be copied.
///
/// If nothing on the machine handles the scheme, the URL goes to the clipboard
/// and a snackbar says so, rather than the tap doing nothing at all.
class _LinkLine extends StatefulWidget {
  const _LinkLine({required this.label, required this.text, required this.uri});

  final String label;
  final String text;
  final Uri uri;

  @override
  State<_LinkLine> createState() => _LinkLineState();
}

class _LinkLineState extends State<_LinkLine> {
  // Held so it can be disposed: a recognizer inside a TextSpan leaks otherwise.
  late final TapGestureRecognizer _tap = TapGestureRecognizer()..onTap = _open;

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        widget.uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: widget.text));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not open the link. Copied it to the clipboard.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectableText.rich(
      TextSpan(
        style: theme.textTheme.bodyMedium,
        children: [
          TextSpan(text: '${widget.label}: '),
          TextSpan(
            text: widget.text,
            style: TextStyle(
              // Not the scheme's primary: the brand green is 1.64:1 on a light
              // surface. The underline is what marks this as a link.
              color: theme.colorScheme.onSurface,
              decoration: TextDecoration.underline,
            ),
            recognizer: _tap,
          ),
        ],
      ),
    );
  }
}

/// Help/About dialog. The links open in the browser or mail client, and remain
/// selectable so they can be copied on a machine with no handler.
void showAppAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: appName,
    applicationVersion: 'v$appVersion',
    applicationIcon: const AppLogo(size: 48),
    children: [
      const SizedBox(height: 8),
      const Text(
        'Document DBS programming visits, the appointments at which '
        'stimulation configurations are tested and optimised. The complete '
        'workflow runs in four steps: file setup, initial configuration, '
        'session-scales configuration, active recording. Writes BIDS '
        'behavioural TSV with a JSON sidecar documenting every column, and '
        'exports PDF and Word reports.',
      ),
      const SizedBox(height: 12),
      const Text('Links:', style: TextStyle(fontWeight: FontWeight.w600)),
      _LinkLine(label: 'User guide', text: docsUrl, uri: docsUri),
      _LinkLine(label: 'Repository', text: repoUrl, uri: repoUri),
      _LinkLine(label: 'Issues', text: issuesUrl, uri: issuesUri),
      _LinkLine(label: 'Contact', text: contactEmail, uri: contactUri),
      const SizedBox(height: 12),
      const Text('© 2026 $copyrightHolders'),
      const Text('MIT License. Publisher: $publisher.'),
      const SizedBox(height: 12),
      const WyssLockup(),
    ],
  );
}

/// Shared AppBar action opening [showAppAbout].
class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.help_outline),
    iconSize: 28,
    tooltip: 'Help / about',
    onPressed: () => showAppAbout(context),
  );
}
