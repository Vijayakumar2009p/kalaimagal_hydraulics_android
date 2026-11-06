import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../theme.dart';

enum Tone { neutral, blue, sky, gold, success, danger }

({Color bg, Color fg}) _toneColors(Tone t) => switch (t) {
  Tone.neutral => (bg: VV.surfaceRaised, fg: VV.inkMuted),
  Tone.blue => (bg: VV.blueSoft, fg: VV.blue),
  Tone.sky => (bg: VV.skySoft, fg: VV.skyText),
  Tone.gold => (bg: VV.goldSoft, fg: VV.goldText),
  Tone.success => (bg: VV.successSoft, fg: VV.success),
  Tone.danger => (bg: VV.dangerSoft, fg: VV.danger),
};

/// One or two words of status. Always a word; colour only supports it.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(VV.radiusSm),
        border: tone == Tone.neutral ? Border.all(color: VV.line) : null,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: c.fg),
      ),
    );
  }
}

/// Location status badge for a customer.
class LocationBadge extends StatelessWidget {
  const LocationBadge(this.customer, {super.key});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    if (customer.pending) return const StatusBadge('Waiting', tone: Tone.gold);
    if (customer.hasLocation) return const StatusBadge('Located', tone: Tone.success);
    return const StatusBadge('No location');
  }
}

/// Square icon for a company, round icon for an individual.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar(this.customer, {super.key, this.size = 40});
  final Customer customer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final company = customer.isCompany;
    return Semantics(
      label: company ? 'Company' : 'Individual',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: company ? VV.blueSoft : VV.skySoft,
          borderRadius: BorderRadius.circular(company ? VV.radiusMd : size / 2),
        ),
        child: Icon(
          company ? Icons.apartment_outlined : Icons.person_outline,
          size: size * 0.5,
          color: company ? VV.blue : VV.skyText,
        ),
      ),
    );
  }
}

/// A short boxed message with a coloured bar.
class Callout extends StatelessWidget {
  const Callout(this.text, {super.key, this.tone = Tone.blue, this.title, this.icon, this.action});

  final String text;
  final String? title;
  final Tone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = _toneColors(tone);
    return Container(
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(VV.radiusMd)),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: c.fg),
            const SizedBox(width: 10),
          ] else ...[
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(color: c.fg, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      title!,
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.fg, fontSize: 14),
                    ),
                  ),
                Text(text, style: TextStyle(color: c.fg, fontSize: 14, height: 1.4)),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width coloured strip under the app bar (offline, log in again...).
class InfoStrip extends StatelessWidget {
  const InfoStrip({super.key, required this.text, required this.icon, this.tone = Tone.gold, this.onTap});

  final String text;
  final IconData icon;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = _toneColors(tone);
    return Material(
      color: c.bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: c.fg, fontSize: 14)),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: c.fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label above a form field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false, this.optional = false});
  final String text;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: VV.danger),
              ),
            if (optional)
              const TextSpan(
                text: ' (optional)',
                style: TextStyle(color: VV.inkMuted, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small grey heading for a group (e.g. "WAITING TO SYNC").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: VV.inkMuted,
      ),
    ),
  );
}

/// Bordered list of label/value rows.
class InfoTable extends StatelessWidget {
  const InfoTable(this.rows, {super.key, this.stacked = false});

  final List<(String, String)> rows;

  /// Label above value (true) or label left, value right (false).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    return Container(
      decoration: BoxDecoration(
        color: VV.surface,
        border: Border.all(color: VV.line),
        borderRadius: BorderRadius.circular(VV.radiusMd),
      ),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: i == visible.length - 1 ? null : const Border(bottom: BorderSide(color: VV.line)),
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visible[i].$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: VV.inkMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(visible[i].$2, style: const TextStyle(fontSize: 16, height: 1.4)),
                      ],
                    )
                  : Row(
                      children: [
                        Text(visible[i].$1, style: const TextStyle(fontSize: 14, color: VV.inkMuted)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            visible[i].$2,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// Round tinted icon used on result screens.
class BigIcon extends StatelessWidget {
  const BigIcon(this.icon, {super.key, this.tone = Tone.success, this.round = true});
  final IconData icon;
  final Tone tone;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final c = _toneColors(tone);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(round ? 36 : VV.radiusLg)),
      child: Icon(icon, size: 36, color: c.fg),
    );
  }
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? VV.danger : VV.ink));
}
