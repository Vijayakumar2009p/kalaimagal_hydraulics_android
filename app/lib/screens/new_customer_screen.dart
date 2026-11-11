import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import 'customer_screen.dart';
import 'set_location_screen.dart';

/// New customer with basic details only.
class NewCustomerScreen extends StatefulWidget {
  const NewCustomerScreen({super.key});

  @override
  State<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends State<NewCustomerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _gstin = TextEditingController();
  final _email = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();

  bool _isCompany = true;
  Customer? _parent;
  bool _busy = false;
  String? _photoPath;

  @override
  void dispose() {
    for (final c in [_name, _mobile, _gstin, _email, _street, _city, _zip]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({required bool thenSetLocation}) async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final app = AppScope.read(context);
    try {
      final dups = await app.findDuplicates(_mobile.text, _gstin.text);
      if (!mounted) return;
      if (dups.isNotEmpty) {
        final choice = await _showDuplicates(dups);
        if (!mounted || choice == null) return;
        if (choice is Customer) {
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute(builder: (_) => CustomerScreen(customer: choice)));
          return;
        }
      }
      final customer = await app.addCustomer(
        NewCustomerInput(
          name: _name.text,
          isCompany: _isCompany,
          phone: _mobile.text,
          email: _email.text,
          vat: _gstin.text,
          street: _street.text,
          city: _city.text,
          zip: _zip.text,
          parent: _parent,
          photoPath: _photoPath,
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
          builder: (_) =>
              thenSetLocation ? SetLocationScreen(customer: customer) : CustomerScreen(customer: customer),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(VV.radiusLg)),
      ),
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
                    decoration: BoxDecoration(
                      color: VV.goldSoft,
                      borderRadius: BorderRadius.circular(VV.radiusMd),
                    ),
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

  Future<void> _pickCompany() async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => const _CompanyPicker(),
    );
    if (picked != null) setState(() => _parent = picked);
  }

  /// Camera or gallery, chosen in a small sheet.
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Add customer photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: VV.blue, size: 28),
              title: const Text('Take photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              subtitle: const Text('Use the camera now'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: VV.blue, size: 28),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Pick a photo already on this phone'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );
      if (photo != null && mounted) setState(() => _photoPath = photo.path);
    } on PlatformException catch (e) {
      if (mounted) {
        final where = source == ImageSource.camera ? 'camera' : 'gallery';
        showMessage(context, 'Could not open $where: ${e.message ?? e.code}', error: true);
      }
    }
  }

  Widget _photoField() {
    final path = _photoPath;
    if (path == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
        onPressed: _pickPhoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add photo'),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(VV.radiusMd),
          child: Image.file(File(path), width: 96, height: 72, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Photo added',
                style: TextStyle(fontWeight: FontWeight.w600, color: VV.success),
              ),
              const Text(
                'It will be attached to the log note in Odoo.',
                style: TextStyle(fontSize: 12, color: VV.inkMuted),
              ),
              Row(
                children: [
                  TextButton(onPressed: _pickPhoto, child: const Text('Change')),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: VV.danger),
                    onPressed: () => setState(() => _photoPath = null),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gstState = Validators.gstinError(_gstin.text) == null && _gstin.text.trim().isNotEmpty
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
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Company'),
                          icon: Icon(Icons.apartment_outlined),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Individual'),
                          icon: Icon(Icons.person_outline),
                        ),
                      ],
                      selected: {_isCompany},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _isCompany = s.first),
                    ),
                    const SizedBox(height: 20),
                    FieldLabel(_isCompany ? 'Company name' : 'Full name', required: true),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the name.' : null,
                    ),
                    if (!_isCompany) ...[
                      const SizedBox(height: 16),
                      const FieldLabel('Works at (company)', optional: true),
                      InkWell(
                        onTap: _pickCompany,
                        borderRadius: BorderRadius.circular(VV.radiusSm),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            suffixIcon: _parent == null
                                ? const Icon(Icons.search)
                                : IconButton(
                                    tooltip: 'Remove company',
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setState(() => _parent = null),
                                  ),
                          ),
                          child: Text(
                            _parent?.name ?? 'Choose an existing company',
                            style: TextStyle(color: _parent == null ? VV.inkMuted : VV.ink, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: VV.success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    const FieldLabel('Customer photo', optional: true),
                    _photoField(),
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

class _CompanyPicker extends StatefulWidget {
  const _CompanyPicker();

  @override
  State<_CompanyPicker> createState() => _CompanyPickerState();
}

class _CompanyPickerState extends State<_CompanyPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final results = AppScope.of(context).companies(_q);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    hintText: 'Search company',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? const Center(
                        child: Text('No company found', style: TextStyle(color: VV.inkMuted)),
                      )
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (_, i) => ListTile(
                          leading: CustomerAvatar(results[i], size: 36),
                          title: Text(results[i].name),
                          subtitle: Text(results[i].city),
                          onTap: () => Navigator.pop(context, results[i]),
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
