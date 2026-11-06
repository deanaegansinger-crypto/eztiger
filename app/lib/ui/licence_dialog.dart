import 'dart:io';

import 'package:flutter/material.dart';

import '../licence.dart';
import '../theme.dart';

/// EZTiger Pro: the trial's days left, and the box for the licence key.
Future<void> showLicenceDialog(BuildContext context, Licence l, {bool trialJustEnded = false}) => showDialog<void>(
  context: context,
  builder: (_) => _LicenceDialog(l, trialJustEnded: trialJustEnded),
);

/// Once, the first time EZTiger starts after the trial has ended.
Future<void> showTrialEndedOnce(BuildContext context, Licence l) async {
  if (!l.trialEnded || await l.db.getMeta('trial_end_shown') != null) return;
  await l.db.setMeta('trial_end_shown', DateTime.now().toIso8601String());
  if (context.mounted) await showLicenceDialog(context, l, trialJustEnded: true);
}

class _LicenceDialog extends StatefulWidget {
  const _LicenceDialog(this.l, {this.trialJustEnded = false});
  final Licence l;
  final bool trialJustEnded;

  @override
  State<_LicenceDialog> createState() => _LicenceDialogState();
}

class _LicenceDialogState extends State<_LicenceDialog> {
  final _key = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final why = await widget.l.activate(_key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = why;
    });
    if (why == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Thank you! EZTiger Pro is on.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final ended = widget.trialJustEnded || l.trialEnded;
    return AlertDialog(
      key: const Key('licence-dialog'),
      title: Text(l.licensed ? 'EZTiger Pro' : (ended ? 'Your Pro trial has ended' : 'EZTiger Pro trial')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (l.licensed)
              const Text('This copy is licensed. Thank you for buying EZTiger Pro!')
            else ...[
              Text(
                ended
                    ? 'EZTiger carries on as EZTiger Basic: your library, playlists and Tonight\'s playlist are all '
                          'still here. Enter a licence key to switch the Pro features back on.'
                    : 'Every Pro feature is on for ${l.trialDaysLeft} more '
                          'day${l.trialDaysLeft == 1 ? '' : 's'}. After that EZTiger carries on as EZTiger Basic '
                          'until a licence key is entered.',
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('licence-key'),
                controller: _key,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Licence key',
                  hintText: 'Paste the key from your email',
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _activate(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!l.licensed && Licence.buyUrl.isNotEmpty)
          TextButton(onPressed: () => _open(Licence.buyUrl), child: const Text('Buy EZTiger Pro')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.licensed ? 'Close' : (ended ? 'Carry on with Basic' : 'Later')),
        ),
        if (!l.licensed)
          FilledButton(
            key: const Key('licence-activate'),
            style: FilledButton.styleFrom(backgroundColor: EzColors.brass, foregroundColor: EzColors.onBrass),
            onPressed: _busy ? null : _activate,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Activate'),
          ),
      ],
    );
  }
}

void _open(String url) {
  if (Platform.isWindows) Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
}
