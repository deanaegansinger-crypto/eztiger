import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../promos.dart';
import '../theme.dart';
import '../venue.dart';

/// Picks a picture file; replaced in tests.
typedef PickImage = Future<String?> Function(String title);

Future<String?> _pickImage(String title) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: title,
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  );
  return files.isEmpty ? null : files.first.xFile.path;
}

/// ☰ Menu → Venue branding: set up the venues this show plays at (name,
/// tagline, colour, logo, photos) and their food, drink and activity promos.
/// While a venue is switched on, the second screen and the singers' request
/// page show it, and EZTiger shrinks to "Powered by EZTiger Entertainment".
///
/// Works on its own, and shares the venues with Music Bingo and Quiz Night
/// when they're on this PC too.
Future<void> showVenueBranding(BuildContext context, {VenueStore? store, PickImage pickImage = _pickImage}) =>
    showDialog<void>(
      context: context,
      builder: (_) => VenueDialog(store: store ?? VenueStore(), pickImage: pickImage),
    );

/// A few venue colours to choose from (the hex box takes any other).
const venueSwatches = ['#0c6f8a', '#880c7e', '#c4560b', '#1f7a3a', '#b3122e', '#2a3f9e', '#d4a017', '#222222'];

class VenueDialog extends StatefulWidget {
  const VenueDialog({super.key, required this.store, this.pickImage = _pickImage});
  final VenueStore store;
  final PickImage pickImage;

  @override
  State<VenueDialog> createState() => _VenueDialogState();
}

class _VenueDialogState extends State<VenueDialog> {
  VenueStore get store => widget.store;

  /// The venue being edited ('' = none yet).
  String editing = '';
  final name = TextEditingController(), tagline = TextEditingController(), hex = TextEditingController();
  String colour = Venue.defaultColour;
  String message = '';

  @override
  void initState() {
    super.initState();
    final a = store.activeSetting();
    final first = store.read(a.venue) ?? store.list().firstOrNull;
    if (first != null) _load(first);
  }

  @override
  void dispose() {
    name.dispose();
    tagline.dispose();
    hex.dispose();
    super.dispose();
  }

  void _load(Venue? v) {
    editing = v?.id ?? '';
    name.text = v?.name ?? '';
    tagline.text = v?.tagline ?? '';
    colour = v?.colour ?? Venue.defaultColour;
    hex.text = colour;
    message = '';
  }

  /// The line at the bottom (callers redraw the box).
  void _say(String m) => message = m;

  /// Saves the name, tagline and colour; makes the venue when it's new.
  bool _saveVenue() {
    final r = store.save(id: editing, name: name.text, tagline: tagline.text, colour: colour);
    if (!r.ok) {
      _say(r.error);
      return false;
    }
    final wasActive = store.activeSetting().venue == editing;
    editing = r.venue!.id;
    // A brand new venue (or the only one) becomes the chosen one.
    if (wasActive || store.activeSetting().venue.isEmpty) store.setActive(editing, store.activeSetting().on);
    _say('✓ Saved ${r.venue!.name}.');
    return true;
  }

  Future<void> _addImage({required bool logo}) async {
    if (editing.isEmpty && !_saveVenue()) return;
    final path = await widget.pickImage(logo ? 'Choose the venue\'s logo' : 'Choose a photo of the venue');
    if (path == null) return;
    final r = store.addImage(editing, logo: logo, from: path);
    _say(r.ok ? (logo ? '✓ Logo added.' : '✓ Photo added.') : r.error);
  }

  Future<void> _addPromoPicture() async {
    final path = await widget.pickImage('Choose a poster or photo for a promo slide');
    if (path == null) return;
    final r = store.addPromoImage(path);
    _say(r.ok ? '✓ Picture slide added.' : r.error);
  }

  Future<void> _addTextPromo() async {
    final s = await showDialog<Map<String, String>>(context: context, builder: (_) => const _TextSlideDialog());
    if (s == null) return;
    store.addTextPromo(top: s['top']!, main: s['main']!, detail: s['detail']!, theme: s['theme']!);
    _say('✓ Text slide added.');
  }

  @override
  Widget build(BuildContext context) {
    final venues = store.list();
    final a = store.activeSetting();
    final current = editing.isEmpty ? null : store.read(editing);
    return AlertDialog(
      key: const Key('venue-dialog'),
      title: const Text('🏨  Venue branding'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Put the venue\'s name, logo and photos on the second screen and the singers\' request page, with its '
                'food, drink and activity offers between singers. EZTiger shrinks to "Powered by EZTiger Entertainment".',
                style: TextStyle(fontSize: 13, color: EzColors.vfdSub),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('venue-on'),
                contentPadding: EdgeInsets.zero,
                title: Text(a.on && a.venue.isNotEmpty ? 'Showing ${store.read(a.venue)?.name ?? a.venue}' : 'Branding off: EZTiger\'s own look'),
                value: a.on && a.venue.isNotEmpty,
                onChanged: venues.isEmpty && editing.isEmpty
                    ? null
                    : (on) {
                        if (editing.isEmpty && !_saveVenue()) return;
                        store.setActive(a.venue.isNotEmpty ? a.venue : editing, on);
                        setState(() {});
                      },
              ),
              _heading('VENUES'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in venues)
                    ChoiceChip(
                      key: Key('venue-chip-${v.id}'),
                      avatar: CircleAvatar(backgroundColor: Color(v.colourValue), radius: 7),
                      label: Text(v.id == a.venue ? '${v.name}  ★' : v.name),
                      selected: v.id == editing,
                      onSelected: (_) => setState(() {
                        _load(v);
                        // Choosing a venue makes it the one shown (in every EZTiger app).
                        store.setActive(v.id, store.activeSetting().on);
                      }),
                    ),
                  ActionChip(
                    key: const Key('venue-new'),
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('New venue'),
                    onPressed: () => setState(() => _load(null)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _venueEditor(current),
              _heading('PROMOS BETWEEN SINGERS${current != null && a.venue == current.id ? ' · ${current.name}' : a.venue.isEmpty ? ' · any venue' : ''}'),
              _promos(),
              _heading('EZTIGER APPS ON THIS PC'),
              _apps(),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(message, key: const Key('venue-message'), style: TextStyle(color: message.startsWith('✓') ? EzColors.green : EzColors.brass)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (Platform.isWindows)
          TextButton(
            onPressed: () {
              Directory(store.root).createSync(recursive: true);
              Process.run('explorer', [store.root]);
            },
            child: const Text('Open the venues folder'),
          ),
        FilledButton(key: const Key('venue-close'), onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(t, style: TextStyle(fontSize: 11, letterSpacing: 1, color: EzColors.cyan)),
  );

  Widget _venueEditor(Venue? v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('venue-name'),
              controller: name,
              decoration: const InputDecoration(labelText: 'Venue name', isDense: true),
              onSubmitted: (_) => setState(_saveVenue),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('venue-tagline'),
              controller: tagline,
              decoration: const InputDecoration(labelText: 'Tagline (optional)', hintText: 'Karaoke every Friday', isDense: true),
              onSubmitted: (_) => setState(_saveVenue),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          for (final c in venueSwatches)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => setState(() {
                  colour = c;
                  hex.text = c;
                }),
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: Color(0xFF000000 | int.parse(c.substring(1), radix: 16)),
                  child: colour == c ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
              ),
            ),
          const SizedBox(width: 6),
          SizedBox(
            width: 100,
            child: TextField(
              key: const Key('venue-colour'),
              controller: hex,
              decoration: const InputDecoration(labelText: 'Colour', isDense: true),
              onChanged: (t) => setState(() => colour = cleanColour(t)),
            ),
          ),
          const Spacer(),
          FilledButton.tonal(
            key: const Key('venue-save'),
            onPressed: () => setState(_saveVenue),
            child: Text(v == null ? 'Add venue' : 'Save'),
          ),
        ],
      ),
      if (v != null) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _picture(v.logoPath, 'Logo', key: const Key('venue-logo'), onRemove: () => setState(() => store.removeImage(v.id, v.logo))),
            if (v.logo.isEmpty)
              OutlinedButton.icon(
                key: const Key('venue-add-logo'),
                onPressed: () async {
                  await _addImage(logo: true);
                  setState(() {});
                },
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('Logo…'),
              ),
            for (final (i, p) in v.photos.indexed)
              _picture(v.photoPaths[i], 'Photo ${i + 1}', onRemove: () => setState(() => store.removeImage(v.id, p))),
            if (v.photos.length < maxVenuePhotos)
              OutlinedButton.icon(
                key: const Key('venue-add-photo'),
                onPressed: () async {
                  await _addImage(logo: false);
                  setState(() {});
                },
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: Text('Photo… (${v.photos.length}/$maxVenuePhotos)'),
              ),
            TextButton(
              key: const Key('venue-delete'),
              onPressed: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Delete ${v.name}?'),
                    content: const Text('Its logo, photos and promos go too, in every EZTiger app on this PC.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
                      FilledButton(key: const Key('venue-delete-yes'), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (yes != true) return;
                store.delete(v.id);
                setState(() => _load(store.list().firstOrNull));
              },
              child: const Text('Delete venue'),
            ),
          ],
        ),
      ],
    ],
  );

  Widget _picture(String? path, String label, {Key? key, required VoidCallback onRemove}) {
    if (path == null) return const SizedBox.shrink();
    return Stack(
      key: key,
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: label,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(File(path), width: 72, height: 54, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 54)),
          ),
        ),
        Positioned(
          right: -8,
          top: -8,
          child: IconButton(
            tooltip: 'Remove',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _promos() {
    final j = store.readPromoFile();
    final slides = (j['slides'] as List).cast<Map<String, dynamic>>();
    void save() => setState(() => store.savePromoFile(j));
    final full = j['mix'] == 'full';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Switch(
              key: const Key('promos-on'),
              value: j['on'] != false,
              onChanged: (on) {
                j['on'] = on;
                save();
              },
            ),
            const Text('Show them'),
            DropdownButton<bool>(
              key: const Key('promos-mix'),
              value: full,
              items: const [
                DropdownMenuItem(value: false, child: Text('Take turns with "Up next"')),
                DropdownMenuItem(value: true, child: Text('Fill the screen')),
              ],
              onChanged: (v) {
                j['mix'] = v == true ? 'full' : 'turns';
                save();
              },
            ),
            DropdownButton<int>(
              key: const Key('promos-seconds'),
              value: ((j['seconds'] as num?)?.toInt() ?? 8).clamp(3, 60),
              items: [
                for (final s in {5, 8, 10, 15, 20, 30, ((j['seconds'] as num?)?.toInt() ?? 8).clamp(3, 60)}.toList()..sort())
                  DropdownMenuItem(value: s, child: Text('${s}s each')),
              ],
              onChanged: (v) {
                j['seconds'] = v;
                save();
              },
            ),
          ],
        ),
        if (slides.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('No slides yet. Add a drinks offer, food deal or tonight\'s activity.', style: TextStyle(fontSize: 13, color: EzColors.vfdSub)),
          ),
        for (final (i, s) in slides.indexed)
          Row(
            key: Key('promo-${s['id']}'),
            children: [
              Checkbox(
                value: s['on'] != false,
                onChanged: (on) {
                  s['on'] = on;
                  save();
                },
              ),
              Expanded(
                child: Text(
                  s['kind'] == 'image'
                      ? '🖼  ${s['file']}'
                      : '${promoThemeNames[s['theme']] ?? ''}  ${[s['top'], s['main'], s['detail']].where((t) => '${t ?? ''}'.isNotEmpty).join(' · ')}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Earlier',
                iconSize: 18,
                onPressed: i == 0
                    ? null
                    : () {
                        slides.insert(i - 1, slides.removeAt(i));
                        save();
                      },
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Later',
                iconSize: 18,
                onPressed: i == slides.length - 1
                    ? null
                    : () {
                        slides.insert(i + 1, slides.removeAt(i));
                        save();
                      },
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Remove',
                iconSize: 18,
                onPressed: () => setState(() => store.removePromo('${s['id']}')),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('promo-add-text'),
              onPressed: () async {
                await _addTextPromo();
                setState(() {});
              },
              icon: const Icon(Icons.text_fields, size: 16),
              label: const Text('Text slide…'),
            ),
            OutlinedButton.icon(
              key: const Key('promo-add-picture'),
              onPressed: () async {
                await _addPromoPicture();
                setState(() {});
              },
              icon: const Icon(Icons.image_outlined, size: 16),
              label: const Text('Poster or photo…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _apps() {
    final found = {for (final a in store.apps()) a.key: a};
    return Column(
      key: const Key('venue-apps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final MapEntry(:key, :value) in ezAppNames.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text(key == 'karaoke' || found.containsKey(key) ? '✅' : '➖'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    key == 'karaoke'
                        ? '$value (this one)'
                        : found.containsKey(key)
                        ? '$value: found, sharing these venues${_seen(found[key]!.seen)}'
                        : '$value: not on this PC. It picks these venues up by itself if you add it later.',
                    key: Key('venue-app-$key'),
                    style: TextStyle(fontSize: 13, color: key == 'karaoke' || found.containsKey(key) ? null : EzColors.vfdSub),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _seen(DateTime? t) {
    if (t == null) return ' (not opened since it was updated)';
    final days = DateTime.now().difference(t.toLocal()).inDays;
    return days <= 0 ? ' (used today)' : days == 1 ? ' (used yesterday)' : ' (used $days days ago)';
  }
}

/// A new text slide: a script top line, a big main line, a details line and a look.
class _TextSlideDialog extends StatefulWidget {
  const _TextSlideDialog();
  @override
  State<_TextSlideDialog> createState() => _TextSlideDialogState();
}

class _TextSlideDialogState extends State<_TextSlideDialog> {
  final top = TextEditingController(), main = TextEditingController(), detail = TextEditingController();
  String theme = 'cocktails';

  @override
  void dispose() {
    top.dispose();
    main.dispose();
    detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Text slide'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const Key('slide-top'), controller: top, maxLength: 40, decoration: const InputDecoration(labelText: 'Top line', hintText: 'Happy hour')),
          TextField(key: const Key('slide-main'), controller: main, maxLength: 48, decoration: const InputDecoration(labelText: 'Main line', hintText: '2 for 1 cocktails')),
          TextField(key: const Key('slide-detail'), controller: detail, maxLength: 70, decoration: const InputDecoration(labelText: 'Details', hintText: 'At the pool bar till 10pm')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final MapEntry(:key, :value) in promoThemeNames.entries)
                ChoiceChip(
                  label: Text(value),
                  selected: theme == key,
                  selectedColor: promoThemes[key]![1],
                  onSelected: (_) => setState(() => theme = key),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('slide-add'),
        onPressed: () {
          // An empty slide isn't added.
          if ((top.text + main.text + detail.text).trim().isEmpty) return;
          Navigator.pop(context, {'top': top.text, 'main': main.text, 'detail': detail.text, 'theme': theme});
        },
        child: const Text('Add slide'),
      ),
    ],
  );
}
