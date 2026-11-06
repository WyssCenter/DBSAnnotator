import 'package:flutter/material.dart';

import '../app_info.dart';
import 'annotations_screen.dart';
import 'reports_screen.dart';
import 'session_screen.dart';
import 'theme.dart';

/// Launcher mirroring the desktop Step 0 mode selection, touch-first.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: AppLogo(size: 30),
        ),
        leadingWidth: 54,
        title: const Text(appName),
        actions: const [TextSizeButtons(), HelpButton(), ThemeToggleButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              // Two labelled sections, because the four entries answer two
              // different questions. The first pair RECORD a session as it
              // happens; the second pair READ a file that already exists. They
              // were a flat list of three, which put "review last year's
              // visits" next to "start seeing a patient now".
              const _SectionHeading('Record'),
              _WorkflowCard(
                // Both recording entries carry the annotate icon: they differ
                // by how much they capture, not by what kind of act they are.
                icon: Icons.edit_note,
                title: 'Complete workflow',
                subtitle: 'Stimulation, electrodes, scales and notes',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SessionScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _WorkflowCard(
                icon: Icons.edit_note,
                title: 'Annotations only',
                subtitle: 'Timestamped notes, nothing else',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AnnotationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeading('Read'),
              // One entry rather than two, because which of the old pair you
              // needed depended on how many files you had, so the choice came
              // before the information needed to make it.
              _WorkflowCard(
                icon: Icons.description_outlined,
                title: 'Reports and datasets',
                subtitle: 'Upload TSVs → reports, combined table, BIDS dataset',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReportsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, size: 36),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// A section label above a group of cards.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
