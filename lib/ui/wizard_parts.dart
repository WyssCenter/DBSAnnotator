import 'package:flutter/material.dart';

/// The wizard's fixed bottom bar: Back on the left, the current step's name in
/// the middle, Next on the right. A null callback disables that button.
class StepControls extends StatelessWidget {
  const StepControls({super.key, this.onBack, this.onNext, this.label = ''});

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String label;

  @override
  Widget build(BuildContext context) {
    const size = Size(120, 48);
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(minimumSize: size),
                child: const Text('Back'),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(minimumSize: size),
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where new files are created, with a button to choose or change the folder.
class SaveFolderRow extends StatelessWidget {
  const SaveFolderRow({
    super.key,
    required this.folder,
    required this.onChoose,
  });

  final String? folder;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final chosen = folder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chosen == null
                  ? 'Choose the folder where session files are saved.'
                  : 'Session files are saved in $chosen',
            ),
          ),
          OutlinedButton(
            onPressed: onChoose,
            child: Text(chosen == null ? 'Choose folder' : 'Change'),
          ),
        ],
      ),
    );
  }
}

/// Whose session is open, shown above every step after the first. Tapping it
/// returns to the first step.
class SessionStrip extends StatelessWidget {
  const SessionStrip({super.key, required this.parts, required this.onTap});

  final List<String> parts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(parts.join('  ·  '), overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
