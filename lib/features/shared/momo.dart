import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/auth_repo.dart';
import '../../data/booking_repo.dart';
import '../../widgets/common.dart';

/// MTN MoMo / Airtel Money checkout (simulated in this offline version: the
/// payment is recorded in `transactions` exactly like a real gateway would).
Future<MomoPayment?> askMomo(BuildContext context, {required double amount, required String purpose}) async {
  final userId = context.session.user!.id;
  final settings = await AuthRepo.settings(userId);
  if (!context.mounted) return null;
  final payment = await showModalBottomSheet<MomoPayment>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MomoSheet(
      amount: amount,
      purpose: purpose,
      phone: settings['momo_number']?.toString() ?? context.session.user!.phone,
      network: settings['momo_network']?.toString() ?? 'MTN MoMo',
    ),
  );
  if (payment == null || !context.mounted) return null;
  await AuthRepo.saveSettings(userId, momo: payment.phone, network: payment.network);
  if (!context.mounted) return null;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ApproveDialog(payment: payment, amount: amount),
  );
  return ok == true ? payment : null;
}

class _MomoSheet extends StatefulWidget {
  const _MomoSheet({required this.amount, required this.purpose, required this.phone, required this.network});
  final double amount;
  final String purpose;
  final String phone;
  final String network;

  @override
  State<_MomoSheet> createState() => _MomoSheetState();
}

class _MomoSheetState extends State<_MomoSheet> {
  late String _network = widget.network.startsWith('Airtel') ? 'Airtel Money' : 'MTN MoMo';
  late final _phone = TextEditingController(text: Fmt.phone(widget.phone));

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    Widget net(String name, Color color) {
      final sel = _network == name;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _network = name),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: sel ? fade(color, 0.16) : (kv.isDark ? Kv.s950 : Kv.s50),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sel ? color : kv.border, width: sel ? 1.6 : 1),
            ),
            child: Column(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text(name.startsWith('MTN') ? 'MTN' : 'airtel',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: name.startsWith('MTN') ? Kv.s950 : Colors.white)),
              ),
              const SizedBox(height: 6),
              Text(name, style: TextStyle(fontWeight: FontWeight.w800, color: kv.text, fontSize: 13)),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Mobile Money Checkout', icon: Icons.phone_iphone_rounded, color: Kv.amber),
        const SizedBox(height: 14),
        KvCard(
          color: kv.isDark ? Kv.s950 : Kv.s50,
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(widget.purpose, textAlign: TextAlign.center, style: TextStyle(color: kv.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Text(Fmt.money(widget.amount),
                style: const TextStyle(fontFamily: Kv.mono, fontSize: 28, fontWeight: FontWeight.w900, color: Kv.emerald)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [net('MTN MoMo', Kv.yellow), const SizedBox(width: 10), net('Airtel Money', Kv.red)]),
        const SizedBox(height: 14),
        KvField(
          label: '$_network number:',
          controller: _phone,
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          mono: true,
        ),
        const SizedBox(height: 18),
        KvButton(
          label: 'Pay ${Fmt.money(widget.amount)}',
          icon: Icons.lock_rounded,
          onPressed: () {
            if (Fmt.phoneKey(_phone.text).length != 9) {
              showSnack(context, 'Enter a valid $_network number', error: true);
              return;
            }
            Navigator.pop(context, MomoPayment(network: _network, phone: '+250${Fmt.phoneKey(_phone.text)}'));
          },
        ),
        const SizedBox(height: 8),
        Text('You will approve the payment with your MoMo PIN on your phone.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: kv.faint)),
      ]),
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.payment, required this.amount});
  final MomoPayment payment;
  final double amount;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _step = i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final steps = [
      'Sending request to ${widget.payment.network}',
      'Approve on ${Fmt.phone(widget.payment.phone)} with your PIN',
      'Payment confirmed',
    ];
    return AlertDialog(
      title: const Text('Waiting for approval', style: TextStyle(fontWeight: FontWeight.w900)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Fmt.money(widget.amount), style: const TextStyle(fontFamily: Kv.mono, fontSize: 22, fontWeight: FontWeight.w900, color: Kv.emerald)),
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 22,
                height: 22,
                child: _step > i
                    ? const Icon(Icons.check_circle_rounded, color: Kv.emerald, size: 22)
                    : (_step == i ? const CircularProgressIndicator(strokeWidth: 2.4) : Icon(Icons.circle_outlined, color: kv.faint, size: 20)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(steps[i], style: TextStyle(color: _step >= i ? kv.text : kv.faint, fontSize: 13.5))),
            ]),
          ),
      ]),
      actions: [
        if (_step < 2) TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      ],
    );
  }
}
