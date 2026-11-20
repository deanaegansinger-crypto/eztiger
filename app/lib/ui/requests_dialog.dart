import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../song_requests.dart';
import '../theme.dart';
import 'common.dart';

/// ☰ Menu → Start song requests (the PC): starts the request list with this
/// library's songs and says how it went.
Future<void> startSongRequestList(BuildContext context) async {
  final s = AppScope.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final online = s.requestsOnline;
  messenger?.showSnackBar(
    SnackBar(
      key: const Key('requests-starting'),
      duration: const Duration(seconds: 60),
      content: Text(online
          ? 'Starting song requests online: sending your song list…'
          : 'Starting song requests: making the singers\' page from your songs…'),
    ),
  );
  try {
    final n = await s.startRequestList();
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('requests-started'),
        duration: const Duration(seconds: 10),
        content: Text(online
            ? 'Song requests are on online: $n songs on the singers\' page. Singers scan the QR code on their own phone data. '
                'The DJ list opens in your browser.'
            : 'Song requests are on: $n songs on the singers\' page. The DJ list opens in your browser. '
                'If Windows asks, tick both Private and Public networks for PowerShell and Allow. The songbook QR code now opens the request page.'),
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
  bool _busy = false;

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
                      hintText: 'localhost:8080 on the PC, the online DJ link, or the DJ link on a tablet',
                    ),
                    onSubmitted: s.setRequestsLink,
                  ),
                  const SizedBox(height: 12),
                  Text(text, key: const Key('requests-state'), style: TextStyle(color: colour)),
                  const SizedBox(height: 8),
                  Text(
                    s.requestsOnline
                        ? '🌐 Online: singers use their own phone data. This PC needs the internet (the venue Wi-Fi or your phone\'s hotspot).'
                        : '📶 On the Wi-Fi: singers join the same Wi-Fi or router as this PC.',
                    style: TextStyle(color: context.ez.textDim),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (Platform.isWindows && s.requestsOnline)
                        TextButton(
                          key: const Key('requests-open-dj'),
                          onPressed: () => s.openInBrowser(RequestServer.parse(s.requestsLink)!.djList),
                          child: const Text('Open the DJ list'),
                        ),
                      if (Platform.isWindows && s.requestsOnline)
                        TextButton(
                          key: const Key('requests-use-pc'),
                          onPressed: () {
                            link.text = 'localhost:8080';
                            s.setRequestsLink('localhost:8080');
                          },
                          child: const Text('Use this PC instead (no internet)'),
                        ),
                      if (s.requestsOnline)
                        TextButton(
                          key: const Key('requests-copy-dj'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: RequestServer.parse(s.requestsLink)!.djList));
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                                content: Text('DJ link copied. Keep it somewhere safe: it opens your DJ list on any device.')));
                          },
                          child: const Text('Copy the DJ link'),
                        ),
                      if (!s.requestsOnline && s.onlineRequestsLink.isNotEmpty)
                        TextButton(
                          key: const Key('requests-use-online'),
                          onPressed: () {
                            link.text = s.onlineRequestsLink;
                            s.setRequestsLink(s.onlineRequestsLink);
                          },
                          child: const Text('Use the online request list'),
                        ),
                    ],
                  ),
                  if (Platform.isWindows && !s.requestsOnline && s.onlineRequestsLink.isEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      key: const Key('requests-get-online'),
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              final messenger = ScaffoldMessenger.maybeOf(context);
                              try {
                                await s.getOnlineRequestPage();
                                link.text = s.requestsLink;
                                messenger?.showSnackBar(const SnackBar(
                                  duration: Duration(seconds: 10),
                                  content: Text('Your online request page is ready. Now ☰ Menu → Start song requests puts your songs on it.'),
                                ));
                              } on StateError catch (e) {
                                messenger?.showSnackBar(SnackBar(content: Text(e.message)));
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      child: Text(_busy ? 'Getting your page…' : '🌐 Get my online request page'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your own request page on EZTiger\'s online service: singers request on their own phone data, with no Wi-Fi to join.',
                      style: TextStyle(color: context.ez.textDim, fontSize: 12),
                    ),
                  ],
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
