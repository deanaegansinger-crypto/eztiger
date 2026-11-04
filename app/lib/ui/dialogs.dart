import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

Future<String?> askText(BuildContext context, {required String title, required String label, String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK')),
      ],
    ),
  );
}

Future<Track?> pickVersion(BuildContext context, SearchGroup group) => showDialog<Track>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Versions of ${group.primary.title}'),
        children: [
          for (final t in group.versions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: Text('${t.type.label}  ${t.version ?? ''}  ·  ${t.fileName}', style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );

/// "✏️ Edit tags…": Title, Artist, Type, with the location shown read-only.
Future<void> showEditTags(BuildContext context, Track t) async {
  final s = AppScope.of(context);
  final title = TextEditingController(text: t.title);
  final artist = TextEditingController(text: t.artist ?? '');
  var type = t.type;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('✏️ Edit tags'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(key: const Key('edit-title'), controller: title, decoration: const InputDecoration(labelText: 'Title')),
            TextField(key: const Key('edit-artist'), controller: artist, decoration: const InputDecoration(labelText: 'Artist')),
            const SizedBox(height: 12),
            const Text('Type', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Segmented<TrackType>(
              options: {for (final v in TrackType.values) v: v.label},
              value: type,
              onChanged: (v) => setState(() => type = v),
            ),
            const SizedBox(height: 12),
            const Text('Location', style: TextStyle(fontSize: 12)),
            SelectableText(t.path, style: TextStyle(fontFamily: vfdFont, fontSize: 11, color: context.ez.textDim)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (save == true) await s.editTags(t, title: title.text, artist: artist.text, type: type);
}
