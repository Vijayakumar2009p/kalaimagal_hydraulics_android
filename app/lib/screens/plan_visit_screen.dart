import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'visits_screen.dart';

/// Plans a Field Visit for yourself on a customer (e.g. "come back Monday").
class PlanVisitScreen extends StatefulWidget {
  const PlanVisitScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<PlanVisitScreen> createState() => _PlanVisitScreenState();
}

class _PlanVisitScreenState extends State<PlanVisitScreen> {
  static const _quick = ['Calendar distribution', 'Support visit', 'Payment collection', 'Demo', 'Training'];

  final _form = GlobalKey<FormState>();
  final _summary = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day + 1);
  }

  @override
  void dispose() {
    _summary.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365)),
      helpText: 'Visit date',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final ref = await AppScope.read(
        context,
      ).scheduleVisit(widget.customer, summary: _summary.text, date: _date, note: _note.text);
      if (!mounted) return;
      showVisitResult(context, 'Field visit planned for ${formatDate(_date)}.', ref);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dayChip(String label, DateTime d) {
    final selected = _date == d;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _busy ? null : (_) => setState(() => _date = d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).resolve(widget.customer);
    final tomorrow = _today.add(const Duration(days: 1));
    final isOther = _date != _today && _date != tomorrow;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan field visit')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  children: [
                    Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'The visit is added to this customer in Odoo, assigned to you.',
                      style: TextStyle(color: VV.inkMuted),
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('What is the visit for?', required: true),
                    TextFormField(
                      controller: _summary,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'e.g. Calendar distribution'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Write what the visit is for.' : null,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final q in _quick)
                          ActionChip(label: Text(q), onPressed: _busy ? null : () => setState(() => _summary.text = q)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('When?', required: true),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _dayChip('Today', _today),
                        _dayChip('Tomorrow', tomorrow),
                        ChoiceChip(
                          avatar: const Icon(Icons.event, size: 18),
                          label: Text(isOther ? formatDate(_date) : 'Pick a date'),
                          selected: isOther,
                          onSelected: _busy ? null : (_) => _pickDate(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('Note', optional: true),
                    TextField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'e.g. Ask for Mr. Kumar, after 4 pm'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.event_available),
                    label: const Text('Save visit', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
