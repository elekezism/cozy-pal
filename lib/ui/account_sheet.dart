import 'package:flutter/material.dart';

import '../pet_controller.dart';
import '../services/account_service.dart';
import 'doodle.dart';

const _hand = TextStyle(fontFamily: handFont, color: ink, fontSize: 18, height: 1.2);

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Today's free AI time as a little bar: "7 min left of 10".
class AiTimeBar extends StatelessWidget {
  const AiTimeBar({super.key, required this.quota});
  final AiQuota quota;

  @override
  Widget build(BuildContext context) {
    final left = 1 - quota.fraction;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.timer_outlined, color: ink, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text('${quota.leftLabel} of ${(quota.limitSec / 60).round()} today', style: _hand.copyWith(fontSize: 17))),
      ]),
      const SizedBox(height: 6),
      Container(
        height: 14,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: ink, width: 1.8)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: left.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: left > 0.25 ? Pal.sageDark : (left > 0 ? Pal.mustard : Pal.tomato),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text('Refills at ${_clock(quota.resetsAt)}. Only the time the AI spends answering counts.',
          style: _hand.copyWith(fontSize: 13, color: ink.withValues(alpha: 0.6))),
    ]);
  }
}

/// Small "⏱ 7 min" chip for the top bar. Tap → account sheet.
class AiTimeChip extends StatelessWidget {
  const AiTimeChip({super.key, required this.pet});
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pet.account,
      builder: (context, _) {
        final q = pet.account.quota;
        if (q == null) return const SizedBox.shrink();
        // round up: 9:58 left still reads "10 min"
        final mins = q.remainingSec >= 60 ? '${(q.remainingSec / 60).ceil()} min' : '${q.remainingSec.ceil()} s';
        return Semantics(
          button: true,
          label: 'AI time left today: $mins',
          child: GestureDetector(
            onTap: () => showAccountSheet(context, pet),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: q.empty ? Pal.pink : Pal.note,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ink, width: 2),
                boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 2))],
              ),
              child: Text('⏱ $mins', style: _hand.copyWith(fontSize: 16)),
            ),
          ),
        );
      },
    );
  }
}

/// Free AI time, and signing up / in / out.
Future<void> showAccountSheet(BuildContext context, PetController pet) {
  pet.account.refresh();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Pal.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: ink, width: 2.4),
    ),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: AccountPanel(pet: pet, inSheet: true),
    ),
  );
}

/// Used in the sheet and in Settings.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.pet, this.inSheet = false});
  final PetController pet;
  final bool inSheet;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _newAccount = true;
  bool _show = false;
  String? _error;

  AccountService get a => widget.pet.account;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    try {
      if (_newAccount) {
        await a.register(_email.text, _pass.text);
      } else {
        await a.login(_email.text, _pass.text);
      }
      _pass.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_newAccount ? 'Welcome! You now have 20 minutes of AI a day.' : 'Signed in.', style: _hand.copyWith(color: Colors.white)),
        ));
        if (widget.inSheet) Navigator.of(context).maybePop();
      }
    } on AccountException catch (e) {
      setState(() => _error = e.message);
    }
  }

  InputDecoration _box(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        labelStyle: _hand.copyWith(color: ink.withValues(alpha: 0.7)),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
        enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: ink, width: 2)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFF4E7A3E), width: 2.6)),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final q = a.quota;
        final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.inSheet) ...[
            Center(
              child: Container(width: 44, height: 5, decoration: BoxDecoration(color: ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: ink),
              const SizedBox(width: 8),
              Text('FREE AI TIME', style: _hand.copyWith(fontSize: 24, letterSpacing: 1.1)),
            ]),
            const SizedBox(height: 8),
          ],
          if (q != null) AiTimeBar(quota: q) else if (a.lastError != null)
            Text(a.lastError!, style: _hand.copyWith(fontSize: 15, color: Pal.tomato))
          else
            const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))),
          const SizedBox(height: 12),
          if (a.signedIn) ...[
            Row(children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF4E7A3E)),
              const SizedBox(width: 8),
              Expanded(child: Text('Signed in as ${a.email}', style: _hand, overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: a.logout, child: Text('Sign out', style: _hand.copyWith(fontSize: 16))),
            ]),
          ] else ...[
            Text(
              _newAccount
                  ? 'You\'re a guest: 10 minutes of AI a day. Make a free account for 20 minutes a day, on any device.'
                  : 'Welcome back! Sign in to get your 20 minutes a day.',
              style: _hand.copyWith(fontSize: 16, color: ink.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              style: _hand,
              decoration: _box('Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [_newAccount ? AutofillHints.newPassword : AutofillHints.password],
              style: _hand,
              onSubmitted: (_) => _submit(),
              decoration: _box(
                _newAccount ? 'Password (8+ characters)' : 'Password',
                suffix: IconButton(
                  tooltip: _show ? 'Hide password' : 'Show password',
                  icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: ink),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: _hand.copyWith(fontSize: 15, color: Pal.tomato)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              TextButton(
                onPressed: () => setState(() {
                  _newAccount = !_newAccount;
                  _error = null;
                }),
                child: Text(_newAccount ? 'I have an account' : 'Make a new account', style: _hand.copyWith(fontSize: 16)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: a.busy ? null : _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Pal.sage,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: ink, width: 2.4),
                    boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
                  ),
                  child: a.busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))
                      : Text(_newAccount ? 'Sign up' : 'Sign in', style: _hand.copyWith(fontSize: 19)),
                ),
              ),
            ]),
          ],
        ]);
        if (!widget.inSheet) return content;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 16), child: content),
        );
      },
    );
  }
}
