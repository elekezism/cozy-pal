import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../pet_controller.dart';
import '../platform/platform.dart';
import '../services/actions_service.dart';
import 'doodle.dart';

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

/// "Download Spotify": on iPhone the pet shows the matching App Store apps
/// so you pick the right one; on Android it opens the Play Store search.
/// Phones only let *you* press Get / Install, so that last tap is yours.
Future<void> showAppSheet(BuildContext context, PetController pet, String name) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    barrierColor: ink.withValues(alpha: 0.15),
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => _AppBody(pet: pet, name: name),
  );
}

class _AppBody extends StatefulWidget {
  const _AppBody({required this.pet, required this.name});
  final PetController pet;
  final String name;

  @override
  State<_AppBody> createState() => _AppBodyState();
}

class _AppBodyState extends State<_AppBody> {
  List<StoreApp>? _apps;

  @override
  void initState() {
    super.initState();
    widget.pet.actions.searchApps(widget.name).then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  Future<void> _open(Future<void> Function() go) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await go();
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e', style: _hand.copyWith(color: Colors.white))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.pet.actions;
    final store = kIsWeb ? 'app store' : (isIOS ? 'App Store' : 'Play Store');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(width: 44, height: 5, decoration: BoxDecoration(color: ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.download_rounded, color: ink),
            const SizedBox(width: 8),
            Expanded(child: Text('GET ${widget.name.toUpperCase()}', style: _hand.copyWith(fontSize: 24, letterSpacing: 1.1))),
          ]),
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? 'Apps install on your phone, not in the browser. Here are matches from the App Store, and a Play Store search for Android.'
                : 'I\'ll open the $store for you. Phones only let you press ${isIOS ? 'Get' : 'Install'} yourself, to keep you safe.',
            style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 12),
          if (!isAndroid && _apps == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: ink))),
            ),
          if (_apps != null)
            for (final app in _apps!) ...[
              _AppCard(app: app, onTap: () => _open(() => a.openStoreApp(app))),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _open(() => a.openStoreSearch(widget.name)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: (_apps?.isEmpty ?? true) ? Pal.sage : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ink, width: 2.4),
                boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.search_rounded, color: ink),
                const SizedBox(width: 8),
                Text('Search "${widget.name}" in the $store', style: _hand.copyWith(fontSize: 18)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.onTap});
  final StoreApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: ink, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: app.iconUrl == null
                  ? Container(width: 52, height: 52, color: Pal.note)
                  : Image.network(app.iconUrl!, width: 52, height: 52, errorBuilder: (_, __, ___) => Container(width: 52, height: 52, color: Pal.note)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.name, style: _hand.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  [app.seller, if (app.rating != null) '★ ${app.rating!.toStringAsFixed(1)}', if (app.price != null) app.price!].join(' · '),
                  style: _hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.65)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Pal.sage, borderRadius: BorderRadius.circular(20), border: Border.all(color: ink, width: 2)),
              child: Text('Open', style: _hand.copyWith(fontSize: 16)),
            ),
          ]),
        ),
      ),
    );
  }
}
