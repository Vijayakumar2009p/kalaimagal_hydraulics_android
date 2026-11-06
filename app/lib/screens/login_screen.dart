import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../config.dart';
import '../services/odoo_client.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Login. With [relogin] it is pushed over the app when the session ended,
/// and closes itself after a successful login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.relogin = false});
  final bool relogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _DbStatus { idle, loading, found, hidden, failed }

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _db;
  late final TextEditingController _user;
  final _password = TextEditingController();

  bool _showPassword = false;
  bool _remember = true;
  bool _advanced = false;
  bool _busy = false;
  String? _error;

  List<String> _databases = [];
  _DbStatus _dbStatus = _DbStatus.idle;
  String _dbMessage = '';
  Timer? _debounce;
  int _dbRequest = 0;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _url = TextEditingController(text: app.serverUrl);
    _db = TextEditingController(text: app.database);
    _user = TextEditingController(text: app.login);
    _remember = app.rememberMe;
    Future.microtask(_fetchDatabases); // after the first build (it calls setState)
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _url.dispose();
    _db.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _urlChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _fetchDatabases);
  }

  Future<void> _fetchDatabases() async {
    final url = OdooClient.normalizeUrl(_url.text);
    if (url.isEmpty) return;
    final request = ++_dbRequest;
    setState(() {
      _dbStatus = _DbStatus.loading;
      _dbMessage = 'Looking for databases…';
    });
    try {
      final list = await AppScope.read(context).listDatabases(url);
      if (!mounted || request != _dbRequest) return;
      setState(() {
        _databases = list;
        if (list.isEmpty) {
          _dbStatus = _DbStatus.hidden;
          _dbMessage = 'No database list on this server. Type the database name.';
        } else {
          _dbStatus = _DbStatus.found;
          _dbMessage = list.length == 1
              ? 'Found 1 database on this server'
              : 'Found ${list.length} databases on this server';
          if (!list.contains(_db.text)) _db.text = list.first;
        }
      });
    } on OdooNetworkException catch (e) {
      if (!mounted || request != _dbRequest) return;
      setState(() {
        _databases = [];
        _dbStatus = _DbStatus.failed;
        _dbMessage = e.message;
      });
    } catch (_) {
      if (!mounted || request != _dbRequest) return;
      setState(() {
        _databases = [];
        _dbStatus = _DbStatus.hidden;
        _dbMessage = 'This server hides its database list. Type the database name.';
      });
    }
    if (_db.text.trim().isEmpty && _dbStatus != _DbStatus.found) {
      setState(() => _advanced = true);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_db.text.trim().isEmpty) {
      // The database field may be hidden under Advanced settings.
      setState(() {
        _advanced = true;
        _error = 'Enter the database name under Advanced settings.';
      });
      return;
    }
    final app = AppScope.read(context);
    final changingServer =
        app.queue.isNotEmpty &&
        (OdooClient.normalizeUrl(_url.text) != app.serverUrl ||
            _db.text.trim() != app.database ||
            _user.text.trim() != app.login);
    if (changingServer) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Unsent entries will be lost'),
          content: Text(
            '${app.queue.length} entries on this phone have not reached Odoo yet. '
            'Logging in to a different server, database or login removes them.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.logIn(
        url: _url.text,
        db: _db.text.trim(),
        user: _user.text.trim(),
        password: _password.text,
        remember: _remember,
      );
      if (mounted && widget.relogin) Navigator.of(context).pop();
    } on OdooNetworkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.isAccessDenied
            ? 'Wrong login or password.'
            : (e.message.contains('Database not found') || e.message.contains('does not exist'))
            ? 'Database "${_db.text.trim()}" was not found on this server.'
            : e.message,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.relogin ? AppBar(title: const Text('Log in again')) : null,
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            children: [
              if (!widget.relogin) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset('assets/images/logo_lockup.png', width: 150),
                ),
                const SizedBox(height: 24),
              ],
              const Text('Log in to Odoo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Use the field login given by your office.',
                style: TextStyle(fontSize: 14, color: VV.inkMuted),
              ),
              const SizedBox(height: 24),
              const FieldLabel('Login (email)'),
              TextFormField(
                controller: _user,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your login.' : null,
              ),
              const SizedBox(height: 16),
              const FieldLabel('Password'),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
                title: const Text('Keep me logged in', style: TextStyle(fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),
              _advancedPanel(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Callout(_error!, tone: Tone.danger, icon: Icons.error_outline),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Log in'),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Need help? Call ${AppConfig.supportPhone}',
                  style: TextStyle(fontSize: 12, color: VV.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _advancedPanel() {
    return Container(
      decoration: BoxDecoration(
        color: VV.surfaceRaised,
        border: Border.all(color: VV.line),
        borderRadius: BorderRadius.circular(VV.radiusMd),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _advanced = !_advanced),
            borderRadius: BorderRadius.circular(VV.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Advanced settings',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Icon(_advanced ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_advanced)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Odoo server URL'),
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: _urlChanged,
                    validator: (v) {
                      final u = Uri.tryParse(OdooClient.normalizeUrl(v ?? ''));
                      return (u == null || u.host.isEmpty) ? 'Enter the server address.' : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: FieldLabel('Database')),
                      if (_dbStatus != _DbStatus.loading)
                        TextButton.icon(
                          onPressed: _fetchDatabases,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Find'),
                        ),
                    ],
                  ),
                  if (_dbStatus == _DbStatus.found && _databases.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _databases.contains(_db.text) ? _db.text : _databases.first,
                      items: [for (final d in _databases) DropdownMenuItem(value: d, child: Text(d))],
                      onChanged: (v) => _db.text = v ?? '',
                    )
                  else
                    TextFormField(
                      controller: _db,
                      autocorrect: false,
                      readOnly: _dbStatus == _DbStatus.found,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the database name.' : null,
                    ),
                  const SizedBox(height: 6),
                  _dbStatusLine(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dbStatusLine() {
    final (IconData icon, Color color) = switch (_dbStatus) {
      _DbStatus.found => (Icons.check, VV.success),
      _DbStatus.failed => (Icons.cloud_off_outlined, VV.danger),
      _DbStatus.loading => (Icons.hourglass_empty, VV.inkMuted),
      _ => (Icons.info_outline, VV.inkMuted),
    };
    if (_dbMessage.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _dbMessage,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}
