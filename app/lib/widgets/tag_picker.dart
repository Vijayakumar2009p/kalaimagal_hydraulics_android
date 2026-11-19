import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../models/partner_tag.dart';
import '../models/pending_action.dart';
import '../theme.dart';

/// Odoo tag colours (index 1–11); 0 = no colour.
Color tagColor(int index) => switch (index) {
  1 => const Color(0xFFD9534F),
  2 => const Color(0xFFE67E22),
  3 => const Color(0xFFC9A100),
  4 => const Color(0xFF3FA7D6),
  5 => const Color(0xFF8E44AD),
  6 => const Color(0xFFD35C7C),
  7 => const Color(0xFF16A085),
  8 => const Color(0xFF2E5AAC),
  9 => const Color(0xFFB0306A),
  10 => const Color(0xFF2E8B57),
  11 => const Color(0xFF6C4FB3),
  _ => VV.blue,
};

/// Main tags (Borewell, Hydraulics…) as chips. Picking a main tag shows its
/// sub-tags; several sub-tags can be picked. Unpicking a main tag clears its
/// sub-tags.
class TagPicker extends StatelessWidget {
  const TagPicker({super.key, required this.tree, required this.selected, required this.onChanged, this.enabled = true});

  final TagTree tree;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool enabled;

  void _toggleMain(PartnerTag main) {
    final next = Set<int>.of(selected);
    if (next.contains(main.id)) {
      next.remove(main.id);
      next.removeAll(tree.children[main.id]!.map((k) => k.id));
    } else {
      next.add(main.id);
    }
    onChanged(next);
  }

  void _toggleSub(PartnerTag main, PartnerTag sub) {
    final next = Set<int>.of(selected)..add(main.id);
    if (!next.remove(sub.id)) next.add(sub.id);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (tree.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: VV.surfaceRaised, borderRadius: BorderRadius.circular(VV.radiusMd)),
        child: const Text(
          'No tags yet. Your Odoo admin can add them in Contacts → Configuration → Contact Tags '
          '(with a Parent Tag for the sub-tags).',
          style: TextStyle(color: VV.inkMuted, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in tree.mains)
              FilterChip(
                label: Text(m.name, style: const TextStyle(fontSize: 15)),
                selected: selected.contains(m.id),
                onSelected: enabled ? (_) => _toggleMain(m) : null,
                selectedColor: tagColor(m.color).withValues(alpha: 0.18),
                checkmarkColor: tagColor(m.color),
                side: BorderSide(color: selected.contains(m.id) ? tagColor(m.color) : VV.line),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              ),
          ],
        ),
        for (final m in tree.mains.where((m) => selected.contains(m.id)))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: tagColor(m.color).withValues(alpha: 0.06),
              border: Border.all(color: tagColor(m.color).withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(VV.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: m.name,
                        style: TextStyle(fontWeight: FontWeight.w600, color: tagColor(m.color)),
                      ),
                      const TextSpan(
                        text: '  ·  choose one or more',
                        style: TextStyle(color: VV.inkMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in tree.children[m.id]!)
                      FilterChip(
                        label: Text(k.name),
                        selected: selected.contains(k.id),
                        onSelected: enabled ? (_) => _toggleSub(m, k) : null,
                        selectedColor: tagColor(m.color).withValues(alpha: 0.18),
                        checkmarkColor: tagColor(m.color),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: selected.contains(k.id) ? tagColor(m.color) : VV.line),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The customer's tags as read-only chips (customer page).
class TagChips extends StatelessWidget {
  const TagChips({super.key, required this.tree, required this.tagIds});

  final TagTree tree;
  final List<int> tagIds;

  @override
  Widget build(BuildContext context) {
    final set = tagIds.toSet();
    final chips = <Widget>[];
    for (final m in tree.mains) {
      final subs = tree.children[m.id]!.where((k) => set.contains(k.id)).toList();
      if (!set.contains(m.id) && subs.isEmpty) continue;
      final color = tagColor(m.color);
      Widget chip(String text, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: strong ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 13, fontWeight: strong ? FontWeight.w700 : FontWeight.w500),
        ),
      );
      chips.add(chip(m.name, strong: true));
      chips.addAll(subs.map((k) => chip(k.name)));
    }
    if (chips.isEmpty) {
      return const Text('No tags', style: TextStyle(color: VV.inkMuted));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

/// Bottom sheet to change a customer's tags.
Future<void> showTagEditor(BuildContext context, Customer customer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TagEditor(customer: customer),
  );
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({required this.customer});
  final Customer customer;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late Set<int> _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final managed = app.tagTree.managedIds;
    _selected = app.resolve(widget.customer).tagIds.where(managed.contains).toSet();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await app.setTags(widget.customer, _selected.toList());
    nav.pop();
    final waiting = app.pendingFor(app.resolve(widget.customer)).any((a) => a.kind == PendingAction.tags && !a.blocked);
    messenger.showSnackBar(
      SnackBar(content: Text(waiting ? 'Tags saved on this phone. They will sync when online.' : 'Tags saved in Odoo.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = AppScope.of(context).tagTree;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tags', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(widget.customer.name, style: const TextStyle(color: VV.inkMuted)),
              const SizedBox(height: 16),
              TagPicker(
                tree: tree,
                selected: _selected,
                enabled: !_busy,
                onChanged: (s) => setState(() => _selected = s),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy || tree.isEmpty ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save tags'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
