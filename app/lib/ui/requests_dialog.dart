import 'package:flutter/material.dart';

import '../song_requests.dart';
import '../theme.dart';
import 'common.dart';

/// ☰ Menu → Start song requests (the PC): starts the request list with this
/// library's songs and says how it went.
Future<void> startSongRequestList(BuildContext context) async {
  final s = AppScope.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(
      key: Key('requests-starting'),
      duration: Duration(seconds: 30),
      content: Text('Starting song requests: making the singers\' page from your songs…'),
    ),
  );
  try {
    final n = await s.startRequestList();
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('requests-started'),
        duration: const Duration(seconds: 10),
        content: Text(
          'Song requests are on: $n songs on the singers\' page. The DJ list opens in your browser. '
          'If Windows asks, allow PowerShell on Private networks. The songbook QR code now opens the request page.',
        ),
      ),
    );
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(e is StateError ? e.message : 'Could not start song requests: $e')),
    );
  }
}

/// ☰ Menu → Song requests: the link to the song-request list, so the songs
/// the DJ adds to its singing queue come into Tonight's playlist.
Future<void> showSongRequests(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _RequestsDialog());

class _RequestsDialog extends StatefulWidget {
  const _RequestsDialog();
  @override
  State<_RequestsDialog> createState() => _RequestsDialogState();
}

class _RequestsDialogState extends State<_RequestsDialog> {
  late final link = TextEditingController(text: AppScope.of(context).requestsLink);

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final (text, colour) = switch (s.requestsState) {
          RequestsState.off => ('Off.', context.ez.textDim),
          RequestsState.connecting => ('Connecting…', context.ez.textDim),
          RequestsState.connected => (
              '✓ Connected. Songs you add to the singing queue come into Tonight\'s playlist by themselves.',
              EzColors.green
            ),
          RequestsState.unreachable => (
              'Can\'t reach the request list. Start it on the PC (☰ Menu → Start song requests), and check this device is on the same Wi-Fi.',
              EzColors.brass
            ),
          RequestsState.needsCode => (
              'The request list wants the DJ code: copy the DJ link from its window (the one ending ?key=…).',
              EzColors.brass
            ),
        };
        return AlertDialog(
          title: const Text('Song requests'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Singers send requests from their phones to the song-request list '
                    '(☰ Menu → Start song requests on the PC). Each song you add to its singing queue '
                    'comes into Tonight\'s playlist here, with the singer\'s name.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('requests-link'),
                    controller: link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Request list link',
                      hintText: 'localhost:8080 on the PC, or the DJ link on a tablet',
                    ),
                    onSubmitted: s.setRequestsLink,
                  ),
                  const SizedBox(height: 12),
                  Text(text, key: const Key('requests-state'), style: TextStyle(color: colour)),
                ],
              ),
            ),
          ),
          actions: [
            if (s.requestsLink.isNotEmpty)
              TextButton(
                key: const Key('requests-off'),
                onPressed: () {
                  link.clear();
                  s.setRequestsLink('');
                },
                child: const Text('Turn off'),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            FilledButton(
              key: const Key('requests-connect'),
              onPressed: () => s.setRequestsLink(link.text),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }
}
