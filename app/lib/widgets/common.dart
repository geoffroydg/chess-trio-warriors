import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../theme.dart';

/// Fond dégradé commun à tous les écrans.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.3,
            colors: [Color(0xFF1C2850), kBg],
          ),
        ),
        child: SafeArea(child: child),
      );
}

/// Gros bouton principal (orange) ou secondaire (bleu).
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.danger = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = danger
        ? [const Color(0xFFE53935), const Color(0xFFB71C1C)]
        : secondary
            ? [kBlue, const Color(0xFF1E6FD9)]
            : [kOrange, const Color(0xFFE5541B)];
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: colors.first.withAlpha(90), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 26), const SizedBox(width: 10)],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String yes = 'Oui', String no = 'Non'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r ?? false;
}

/// Badge 🤖 + niveau affiché à côté du nom d'un bot.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key, required this.level, this.small = false});
  final String? level;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final label = botLevelLabel(level);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: small ? 0 : 2),
      decoration: BoxDecoration(
        color: kBlue.withAlpha(60),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBlue.withAlpha(160)),
      ),
      child: Text('🤖 $label',
          style: TextStyle(fontSize: small ? 10 : 13, fontWeight: FontWeight.w700)),
    );
  }
}
