import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Asked once per phone: everyone shares one Odoo login, so the person's
/// name is written into each Odoo note.
class YourNameScreen extends StatefulWidget {
  const YourNameScreen({super.key, this.editing = false});

  /// Opened from Settings to change the name.
  final bool editing;

  @override
  State<YourNameScreen> createState() => _YourNameScreenState();
}

class _YourNameScreenState extends State<YourNameScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: AppScope.read(context).userName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await AppScope.read(context).setUserName(_name.text);
    if (mounted && widget.editing) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('Your name')) : null,
      body: SafeArea(
        child: Form(
          key: _form,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: VV.blueSoft, borderRadius: BorderRadius.circular(VV.radiusMd)),
                  child: const Icon(Icons.person_outline, color: VV.blue, size: 28),
                ),
                const SizedBox(height: 24),
                const Text('Who is using this phone?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  'Everyone shares one Odoo login, so your name is added to the Odoo note '
                  'each time you set a location.',
                  style: TextStyle(fontSize: 16, height: 1.5, color: VV.inkMuted),
                ),
                const SizedBox(height: 24),
                const FieldLabel('Your name'),
                TextFormField(
                  controller: _name,
                  autofocus: !widget.editing,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name.' : null,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Saved on this phone only. Change it any time in Settings.',
                  style: TextStyle(fontSize: 12, color: VV.inkMuted),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _save, child: Text(widget.editing ? 'Save' : 'Continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
