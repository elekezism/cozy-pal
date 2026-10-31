import 'package:flutter/material.dart';

import '../pet_controller.dart';
import '../services/actions_service.dart';
import 'doodle.dart';

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

/// The letter card: who it's going to, how (Text / WhatsApp / Email), and
/// the words, all editable. Send opens the user's own app with everything
/// filled in; nothing is sent without that tap.
Future<void> showMessageSheet(BuildContext context, PetController pet, MessageDraft draft) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    barrierColor: ink.withValues(alpha: 0.15),
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _MessageBody(pet: pet, draft: draft),
    ),
  );
}

class _MessageBody extends StatefulWidget {
  const _MessageBody({required this.pet, required this.draft});
  final PetController pet;
  final MessageDraft draft;

  @override
  State<_MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<_MessageBody> {
  late final _body = TextEditingController(text: widget.draft.body);
  late final _subject = TextEditingController(text: widget.draft.subject);
  late final _to = TextEditingController(text: widget.draft.to ?? '');
  List<ContactMatch>? _choices;
  bool _polishing = false;
  bool _sending = false;
  bool _cloud = false;

  MessageDraft get d => widget.draft;
  PetController get pet => widget.pet;

  @override
  void initState() {
    super.initState();
    pet.llm.isConfigured().then((v) {
      if (mounted) setState(() => _cloud = v);
    });
    if (d.contact == null && d.recipientName.isNotEmpty) _lookUp();
  }

  @override
  void dispose() {
    _body.dispose();
    _subject.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    try {
      final m = await pet.actions.findContacts(d.recipientName.replaceFirst(RegExp(r'^my\s+', caseSensitive: false), ''));
      if (!mounted) return;
      if (m.length == 1) {
        _use(m.first);
      } else {
        setState(() => _choices = m);
      }
    } catch (e) {
      if (mounted) setState(() => _choices = const []);
    }
  }

  void _use(ContactMatch c) {
    setState(() {
      pet.applyContact(d, c);
      _to.text = d.to ?? '';
      _choices = null;
    });
  }

  Future<void> _pick() async {
    try {
      final c = await pet.actions.pickContact();
      if (c != null) _use(c);
    } catch (e) {
      _toast('$e');
    }
  }

  void _setChannel(MessageChannel ch) {
    setState(() {
      d.channel = ch;
      final c = d.contact;
      if (c != null) {
        final list = ch == MessageChannel.email ? c.emails : c.phones;
        d.to = list.isEmpty ? null : list.first.value;
        _to.text = d.to ?? '';
      }
    });
  }

  Future<void> _polish() async {
    setState(() => _polishing = true);
    try {
      final r = await pet.llm.polishMessage(
        recipient: d.recipientName,
        said: _body.text.trim().isEmpty ? _subject.text : _body.text,
        email: d.channel == MessageChannel.email,
      );
      _body.text = r.body;
      if (d.channel == MessageChannel.email && r.subject.isNotEmpty) _subject.text = r.subject;
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  Future<void> _send() async {
    d
      ..body = _body.text.trim()
      ..subject = _subject.text.trim()
      ..to = _to.text.trim();
    if (d.to!.isEmpty) {
      _toast(d.channel == MessageChannel.email ? 'Add an email address first.' : 'Add a phone number first.');
      return;
    }
    if (d.body.isEmpty) {
      _toast('Write something to send.');
      return;
    }
    setState(() => _sending = true);
    final nav = Navigator.of(context);
    try {
      await pet.sendDraft(d);
      nav.pop();
    } catch (e) {
      _toast('$e');
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: _hand.copyWith(color: Colors.white))));

  InputDecoration _box(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        labelStyle: _hand.copyWith(color: ink.withValues(alpha: 0.7)),
        hintStyle: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.45)),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
        enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFF4E7A3E), width: 2.6)),
      );

  @override
  Widget build(BuildContext context) {
    final email = d.channel == MessageChannel.email;
    final routes = d.contact == null ? const <ContactRoute>[] : (email ? d.contact!.emails : d.contact!.phones);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(width: 44, height: 5, decoration: BoxDecoration(color: ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.mail_rounded, color: ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                d.recipientName.isEmpty ? 'NEW MESSAGE' : 'TO ${d.recipientName.toUpperCase()}',
                style: _hand.copyWith(fontSize: 24, letterSpacing: 1.1),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (ActionsService.hasContacts)
              TextButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.contacts_rounded, color: ink, size: 18),
              label: Text(d.contact == null ? 'Pick' : 'Change', style: _hand.copyWith(fontSize: 16)),
            ),
          ]),
          if (_choices != null && _choices!.length > 1) ...[
            Text('Which ${d.recipientName}?', style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _choices!)
                ActionChip(
                  label: Text(c.name, style: _hand.copyWith(fontSize: 16)),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: ink, width: 1.6),
                  onPressed: () => _use(c),
                ),
            ]),
            const SizedBox(height: 8),
          ] else if (_choices != null && _choices!.isEmpty && d.contact == null) ...[
            Text(
              d.recipientName.isEmpty
                  ? 'Pick someone from your contacts, or type their number or email.'
                  : ActionsService.hasContacts
                      ? "I couldn't find ${d.recipientName} in your contacts. Pick them, or type their number or email."
                      : "Type ${d.recipientName}'s number or email (the browser can't see your contacts).",
              style: _hand.copyWith(fontSize: 15, color: ink.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
          ],
          // how to send
          Row(children: [
            for (final ch in MessageChannel.values) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => _setChannel(ch),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: d.channel == ch ? Pal.mustard : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ink, width: d.channel == ch ? 2.6 : 1.6),
                    ),
                    alignment: Alignment.center,
                    child: Text(ch.label, style: _hand.copyWith(fontSize: 17)),
                  ),
                ),
              ),
              if (ch != MessageChannel.values.last) const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 10),
          if (routes.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                for (final r in routes)
                  ChoiceChip(
                    label: Text('${r.label}: ${r.value}', style: _hand.copyWith(fontSize: 15)),
                    selected: _to.text == r.value,
                    selectedColor: Pal.note,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: ink, width: 1.4),
                    onSelected: (_) => setState(() => _to.text = d.to = r.value),
                  ),
              ]),
            ),
          TextField(
            controller: _to,
            keyboardType: email ? TextInputType.emailAddress : TextInputType.phone,
            autocorrect: false,
            style: _hand,
            decoration: _box(email ? 'Email address' : 'Phone number'),
          ),
          if (email) ...[
            const SizedBox(height: 10),
            TextField(controller: _subject, style: _hand, decoration: _box('Subject')),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            style: _hand.copyWith(fontSize: 19),
            minLines: 3,
            maxLines: 8,
            decoration: _box(
              'Message',
              suffix: _cloud
                  ? IconButton(
                      tooltip: 'Polish the wording',
                      onPressed: _polishing ? null : _polish,
                      icon: _polishing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
                          : const Icon(Icons.auto_fix_high_rounded, color: ink),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send opens ${switch (d.channel) {
              MessageChannel.text => 'Messages',
              MessageChannel.whatsapp => 'WhatsApp',
              MessageChannel.email => 'your mail app',
            }} with this filled in. You press send there.',
            style: _hand.copyWith(fontSize: 14, color: ink.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: _hand),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: Pal.sage,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: ink, width: 2.4),
                  boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
                      : const Icon(Icons.send_rounded, color: ink, size: 20),
                  const SizedBox(width: 8),
                  Text('Send', style: _hand.copyWith(fontSize: 20)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
