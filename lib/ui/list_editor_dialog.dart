import 'package:flutter/material.dart';

import '../app_info.dart';

/// Add, remove and edit a picklist of short strings, such as the programs.
/// Restore defaults puts back [defaults], the list the app comes with, shown
/// in [section] of the user guide; [addLabel] names the button that adds a
/// row. Returns the edited list with blanks dropped on Save, or null on Cancel.
class ListEditorDialog extends StatefulWidget {
  const ListEditorDialog({
    super.key,
    required this.title,
    required this.items,
    required this.defaults,
    required this.section,
    required this.addLabel,
  });

  final String title;
  final List<String> items;
  final List<String> defaults;
  final String section;
  final String addLabel;

  @override
  State<ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<ListEditorDialog> {
  late final List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = [for (final s in widget.items) TextEditingController(text: s)];
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _restore() => setState(() {
    for (final c in _ctrls) {
      c.dispose();
    }
    _ctrls
      ..clear()
      ..addAll([
        for (final s in widget.defaults) TextEditingController(text: s),
      ]);
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: DefaultsTitle(widget.title, section: widget.section),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _ctrls.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrls[i],
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove',
                        onPressed: () =>
                            setState(() => _ctrls.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _ctrls.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: Text(widget.addLabel),
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: picklistActions(
        context,
        onRestore: _restore,
        onSave: () => Navigator.pop(context, [
          for (final c in _ctrls)
            if (c.text.trim().isNotEmpty) c.text.trim(),
        ]),
      ),
    );
  }
}
