import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import '../widgets/photo_strip.dart';
import '../widgets/tag_picker.dart';
import 'customer_screen.dart';
import 'set_location_screen.dart';

/// New customer: one form. Company name is optional; when it is filled a
/// company is created with this person as its contact.
class NewCustomerScreen extends StatefulWidget {
  const NewCustomerScreen({super.key});

  @override
  State<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends State<NewCustomerScreen> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _companyFocus = FocusNode();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _gstin = TextEditingController();
  final _email = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();

  /// Existing Odoo company picked from the suggestions.
  Customer? _parent;
  Set<int> _tags = {};
  bool _busy = false;
  final _photos = PhotoSelection();
  final List<_ContactRow> _contacts = [];

  @override
  void dispose() {
    for (final c in [_company, _name, _mobile, _gstin, _email, _street, _city, _zip]) {
      c.dispose();
    }
    _companyFocus.dispose();
    for (final r in _contacts) {
      r.dispose();
    }
    super.dispose();
  }

  String get _companyText => _company.text.trim();

  /// Picked an existing company (and did not change its name afterwards).
  bool get _existingCompany => _parent != null && _parent!.name == _companyText;

  /// A new company will be created.
  bool get _newCompany => _companyText.isNotEmpty && !_existingCompany;

  void _addContact() {
    final row = _ContactRow();
    setState(() => _contacts.add(row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.focus.requestFocus();
    });
  }

  void _removeContact(_ContactRow row) {
    setState(() => _contacts.remove(row));
    row.dispose();
  }

  Widget _contactCard(int index, _ContactRow row) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        border: Border.all(color: VV.inkMuted.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 20, color: VV.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Contact ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              IconButton(
                tooltip: 'Remove contact',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeContact(row),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Name', required: true),
                TextFormField(
                  controller: row.name,
                  focusNode: row.focus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Contact person name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the contact name, or remove this contact.' : null,
                ),
                const SizedBox(height: 12),
                const FieldLabel('Mobile', optional: true),
                TextFormField(
                  controller: row.phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  decoration: const InputDecoration(prefixText: '+91  ', hintText: '98765 43210'),
                  validator: (v) => (v ?? '').trim().isEmpty ? null : Validators.mobileError(v!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save({required bool thenSetLocation}) async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final app = AppScope.read(context);
    try {
      final dups = await app.findDuplicates(_mobile.text, _newCompany ? _gstin.text : '');
      if (!mounted) return;
      if (dups.isNotEmpty) {
        final choice = await _showDuplicates(dups);
        if (!mounted || choice == null) return;
        if (choice is Customer) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CustomerScreen(customer: choice)));
          return;
        }
      }
      final extra = [for (final r in _contacts) ContactInput(name: r.name.text, phone: r.phone.text)];
      final newCompany = _newCompany;
      final customer = await app.addCustomer(
        NewCustomerInput(
          // New company: the company is the customer, the person its first contact.
          name: newCompany ? _companyText : _name.text,
          isCompany: newCompany,
          phone: _mobile.text,
          email: _email.text,
          vat: newCompany ? _gstin.text : '',
          street: _street.text,
          city: _city.text,
          zip: _zip.text,
          parent: _existingCompany ? _parent : null,
          photoPaths: List.of(_photos.paths),
          profilePhoto: _photos.profileIndex,
          tagIds: _tags.toList(),
          contacts: [
            if (newCompany) ContactInput(name: _name.text, phone: _mobile.text),
            ...extra,
          ],
        ),
      );
      if (!mounted) return;
      final synced = !customer.isLocal;
      showMessage(
        context,
        synced ? 'Customer saved in Odoo.' : 'Customer saved on this phone. It will sync when online.',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => thenSetLocation ? SetLocationScreen(customer: customer) : CustomerScreen(customer: customer),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns the existing customer to open, `true` to create anyway, or null.
  Future<Object?> _showDuplicates(List<Customer> dups) {
    final mobile = Validators.mobileDigits(_mobile.text);
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(VV.radiusLg))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: VV.goldSoft, borderRadius: BorderRadius.circular(VV.radiusMd)),
                    child: const Icon(Icons.warning_amber_rounded, color: VV.goldText),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This customer may already exist',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'The same mobile number or GSTIN is already saved for:',
                          style: TextStyle(color: VV.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in dups)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: VV.surfaceRaised,
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(color: VV.line),
                            borderRadius: BorderRadius.circular(VV.radiusMd),
                          ),
                          child: ListTile(
                            leading: CustomerAvatar(d),
                            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                if (d.city.isNotEmpty) d.city,
                                mobile.length == 10 && Validators.mobileDigits(d.phone) == mobile
                                    ? 'matched on mobile'
                                    : 'matched on GSTIN',
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(c, d),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(c, dups.first),
                child: Text(dups.length == 1 ? 'Open existing customer' : 'Open first match'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create new anyway')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final gstState = _newCompany && Validators.gstinError(_gstin.text) == null && _gstin.text.trim().isNotEmpty
        ? Validators.gstinState(_gstin.text)
        : null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New customer'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const FieldLabel('Company name', optional: true),
                    RawAutocomplete<Customer>(
                      textEditingController: _company,
                      focusNode: _companyFocus,
                      displayStringForOption: (c) => c.name,
                      optionsBuilder: (v) => v.text.trim().length < 2 ? const <Customer>[] : app.companies(v.text),
                      onSelected: (c) => setState(() => _parent = c),
                      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                        controller: controller,
                        focusNode: focus,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Leave empty for an individual',
                          suffixIcon: _companyText.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() {
                                    _company.clear();
                                    _parent = null;
                                  }),
                                ),
                        ),
                      ),
                      optionsViewBuilder: (context, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(VV.radiusMd),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: 240,
                              maxWidth: MediaQuery.sizeOf(context).width - 32,
                            ),
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                                  child: Text(
                                    'Already in Odoo',
                                    style: TextStyle(fontSize: 12, color: VV.inkMuted),
                                  ),
                                ),
                                for (final c in options)
                                  ListTile(
                                    dense: true,
                                    leading: CustomerAvatar(c, size: 32),
                                    title: Text(c.name),
                                    subtitle: c.city.isEmpty ? null : Text(c.city),
                                    onTap: () => onSelected(c),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_companyText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _existingCompany
                              ? 'Existing company. This person will be added as its contact.'
                              : 'A new company will be created, with this person as its contact.',
                          style: const TextStyle(fontSize: 12, color: VV.inkMuted),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const FieldLabel('Name', required: true),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'Customer / contact person name'),
                      validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the name.' : null,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Tags', optional: true),
                    TagPicker(
                      tree: app.tagTree,
                      selected: _tags,
                      enabled: !_busy,
                      onChanged: (t) => setState(() => _tags = t),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Mobile', required: true),
                    TextFormField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
                        LengthLimitingTextInputFormatter(16),
                      ],
                      decoration: const InputDecoration(prefixText: '+91  ', hintText: '98765 43210'),
                      validator: (v) => Validators.mobileError(v ?? ''),
                    ),
                    for (var i = 0; i < _contacts.length; i++) _contactCard(i, _contacts[i]),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addContact,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(_contacts.isEmpty ? 'Add another contact person' : 'Add one more contact person'),
                      ),
                    ),
                    if (_newCompany) ...[
                      const SizedBox(height: 16),
                      const FieldLabel('GSTIN', optional: true),
                      TextFormField(
                        controller: _gstin,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                          LengthLimitingTextInputFormatter(15),
                          _UpperCase(),
                        ],
                        onChanged: (_) => setState(() {}),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(hintText: '33AAFCK5678M1ZZ'),
                        validator: (v) => Validators.gstinError(v ?? ''),
                      ),
                      if (gstState != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.check, size: 14, color: VV.success),
                              const SizedBox(width: 4),
                              Text(
                                'Valid GSTIN · $gstState (${_gstin.text.substring(0, 2)})',
                                style: const TextStyle(fontSize: 12, color: VV.success, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    const FieldLabel('Email', optional: true),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'name@company.com'),
                      validator: (v) => Validators.emailError(v ?? ''),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Customer photos', optional: true),
                    PhotoStrip(selection: _photos, enabled: !_busy, onChanged: () => setState(() {})),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text('Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text(
                      'Filled in from GPS when you set the location. You can edit it.',
                      style: TextStyle(fontSize: 13, color: VV.inkMuted),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Street'),
                    TextFormField(
                      controller: _street,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Door no., street, area'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('City'),
                              TextFormField(controller: _city, textCapitalization: TextCapitalization.words),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('PIN code'),
                              TextFormField(
                                controller: _zip,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                validator: (v) => Validators.pinError(v ?? ''),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: VV.line)),
                ),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => _save(thenSetLocation: false),
                      child: const Text('Save'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _save(thenSetLocation: true),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: const Text('Save & set location'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// One extra contact person typed on the New customer page.
class _ContactRow {
  final name = TextEditingController();
  final phone = TextEditingController();
  final focus = FocusNode();

  void dispose() {
    name.dispose();
    phone.dispose();
    focus.dispose();
  }
}
