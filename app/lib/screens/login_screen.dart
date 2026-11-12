import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../config.dart';
import '../services/odoo_client.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Login in three pages: 1 server URL → 2 database → 3 login and password.
///
/// With [relogin] it is pushed over the app when the session ended: it opens
/// on page 3 with the saved server and database, and closes after login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.relogin = false});
  final bool relogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { server, database, login }

class _LoginScreenState extends State<LoginScreen> {
  final _serverForm = GlobalKey<FormState>();
  final _dbForm = GlobalKey<FormState>();
  final _loginForm = GlobalKey<FormState>();

  late final TextEditingController _url;
  late final TextEditingController _dbName;
  late final TextEditingController _user;
  final _password = TextEditingController();

  _Step _step = _Step.server;
  List<String> _databases = [];
  bool _dbListHidden = false;
  String? _selectedDb;

  bool _showPassword = false;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  /// Chosen in the dropdown before the address box.
  String _scheme = 'https://';

  static String _stripScheme(String url) => url.replaceFirst(RegExp(r'^\s*https?://', caseSensitive: false), '');

  /// Full server address: dropdown + typed part.
  String get _fullUrl => OdooClient.normalizeUrl('$_scheme${_stripScheme(_url.text).trim()}');

  /// If a full address is pasted, move "http://" or "https://" into the dropdown.
  void _onUrlChanged(String v) {
    final m = RegExp(r'^\s*(https?://)', caseSensitive: false).firstMatch(v);
    if (m == null) return;
    final rest = v.substring(m.end);
    setState(() => _scheme = m.group(1)!.toLowerCase());
    _url.value = TextEditingValue(
      text: rest,
      selection: TextSelection.collapsed(offset: rest.length),
    );
  }

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _scheme = app.serverUrl.startsWith('http://') ? 'http://' : 'https://';
    _url = TextEditingController(text: _stripScheme(app.serverUrl));
    final savedDb = app.database.isNotEmpty ? app.database : AppConfig.defaultDatabase;
    _dbName = TextEditingController(text: savedDb);
    _user = TextEditingController(text: app.login);
    _remember = app.rememberMe;
    if (widget.relogin && app.database.isNotEmpty) {
      _selectedDb = app.database;
      _step = _Step.login;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _dbName.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _database => _dbListHidden ? _dbName.text.trim() : (_selectedDb ?? '');

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  // ---- page 1: server ----
  Future<void> _findServer() async {
    FocusScope.of(context).unfocus();
    if (!_serverForm.currentState!.validate()) return;
    final url = _fullUrl;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.read(context);
    try {
      final list = await app.listDatabases(url);
      if (!mounted) return;
      _databases = list;
      _dbListHidden = list.isEmpty;
    } on OdooNetworkException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${e.message}\n\nCheck the address and that the phone has internet or is on the same Wi-Fi.';
        });
      }
      return;
    } catch (_) {
      // The server answered but hides its database list: type the name.
      _databases = [];
      _dbListHidden = true;
    }
    if (!mounted) return;
    _url.text = _stripScheme(url);
    final previous = _selectedDb ?? app.database;
    _selectedDb = _databases.contains(previous) ? previous : (_databases.length == 1 ? _databases.first : null);
    setState(() => _busy = false);
    _go(_Step.database);
  }

  // ---- page 2: database ----
  void _chooseDatabase() {
    if (_dbListHidden) {
      if (!_dbForm.currentState!.validate()) return;
    } else if (_selectedDb == null) {
      setState(() => _error = 'Choose a database.');
      return;
    }
    _go(_Step.login);
  }

  // ---- page 3: login ----
  Future<void> _logIn() async {
    FocusScope.of(context).unfocus();
    if (!_loginForm.currentState!.validate()) return;
    final app = AppScope.read(context);
    final url = _fullUrl;
    final db = _database;
    final changingServer =
        app.queue.isNotEmpty && (url != app.serverUrl || db != app.database || _user.text.trim() != app.login);
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
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.logIn(url: url, db: db, user: _user.text.trim(), password: _password.text, remember: _remember);
      if (mounted && widget.relogin) Navigator.of(context).pop();
    } on OdooNetworkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.isAccessDenied
            ? 'Wrong login or password.'
            : (e.message.contains('Database not found') || e.message.contains('does not exist'))
            ? 'Database "$db" was not found on this server. Go back and choose another.'
            : e.message,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------

  void _back() {
    if (_busy) return;
    switch (_step) {
      case _Step.login:
        // Opened straight on page 3 ("Log in again"): no list loaded yet.
        _go(_databases.isEmpty && !_dbListHidden ? _Step.server : _Step.database);
      case _Step.database:
        _go(_Step.server);
      case _Step.server:
        if (widget.relogin) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = _step == _Step.server;
    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: (_step != _Step.server || widget.relogin)
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _step == _Step.server ? () => Navigator.of(context).pop() : _back,
                ),
                title: Text(widget.relogin ? 'Log in again' : 'Log in'),
              )
            : null,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            children: [
              if (_step == _Step.server && !widget.relogin) ...[
                Align(alignment: Alignment.centerLeft, child: Image.asset('assets/images/logo_lockup.png', width: 150)),
                const SizedBox(height: 24),
              ],
              _StepBar(current: _step.index),
              const SizedBox(height: 24),
              switch (_step) {
                _Step.server => _serverPage(),
                _Step.database => _databasePage(),
                _Step.login => _loginPage(),
              },
              if (_error != null) ...[
                const SizedBox(height: 16),
                Callout(_error!, tone: Tone.danger, icon: Icons.error_outline),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(fontSize: 15, height: 1.4, color: VV.inkMuted)),
      const SizedBox(height: 24),
    ],
  );

  Widget _nextButton(String label, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
      onPressed: _busy ? null : onPressed,
      child: _busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : Text(label, style: const TextStyle(fontSize: 16)),
    ),
  );

  Widget _serverPage() => Form(
    key: _serverForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Odoo server', 'Choose https:// or http://, then type the rest of the address.'),
        const FieldLabel('Odoo server URL'),
        TextFormField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onChanged: _onUrlChanged,
          onFieldSubmitted: (_) => _findServer(),
          decoration: InputDecoration(
            hintText: 'www.veeveeinfotech.com',
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _scheme,
                  borderRadius: BorderRadius.circular(VV.radiusMd),
                  style: const TextStyle(fontSize: 16, color: VV.ink, fontWeight: FontWeight.w600),
                  items: const [
                    DropdownMenuItem(value: 'https://', child: Text('https://')),
                    DropdownMenuItem(value: 'http://', child: Text('http://')),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _scheme = v ?? 'https://'),
                ),
              ),
            ),
          ),
          validator: (v) {
            final u = Uri.tryParse(_fullUrl);
            if (u == null || u.host.isEmpty) return 'Enter the server address.';
            if (kReleaseMode && _scheme == 'http://') {
              return 'This app needs https:// (http:// works only in the test app).';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),
        _nextButton('Next', _findServer),
      ],
    ),
  );

  Widget _databasePage() => Form(
    key: _dbForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          'Choose database',
          _dbListHidden
              ? 'This server hides its database list. Type the database name.'
              : 'Server: ${Uri.tryParse(_fullUrl)?.host ?? _url.text}',
        ),
        if (_dbListHidden) ...[
          const FieldLabel('Database name'),
          TextFormField(
            controller: _dbName,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _chooseDatabase(),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.storage_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the database name.' : null,
          ),
        ] else
          for (final db in _databases)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChoiceTile(
                label: db,
                selected: _selectedDb == db,
                onTap: () => setState(() {
                  _selectedDb = db;
                  _error = null;
                }),
              ),
            ),
        const SizedBox(height: 16),
        _nextButton('Next', _chooseDatabase),
      ],
    ),
  );

  Widget _loginPage() {
    final host = Uri.tryParse(_fullUrl)?.host ?? _url.text;
    return Form(
      key: _loginForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Log in', 'Use the field login given by your office.'),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: VV.surfaceRaised,
              border: Border.all(color: VV.line),
              borderRadius: BorderRadius.circular(VV.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, size: 20, color: VV.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$host · $_database',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(onPressed: _busy ? null : () => _go(_Step.server), child: const Text('Change')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Login (email)'),
          TextFormField(
            controller: _user,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
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
            onFieldSubmitted: (_) => _logIn(),
            validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
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
          const SizedBox(height: 16),
          _nextButton('Log in', _logIn),
        ],
      ),
    );
  }
}

/// ① Server — ② Database — ③ Login
class _StepBar extends StatelessWidget {
  const _StepBar({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    const labels = ['Server', 'Database', 'Login'];
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final done = i < current;
      final active = i == current;
      children.add(
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? VV.success : (active ? VV.blue : VV.surfaceRaised),
                border: Border.all(color: done ? VV.success : (active ? VV.blue : VV.line)),
              ),
              child: done
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: active ? Colors.white : VV.inkMuted),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              labels[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? VV.blue : VV.inkMuted,
              ),
            ),
          ],
        ),
      );
      if (i < labels.length - 1) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(top: 15, left: 6, right: 6),
              color: done ? VV.success : VV.line,
            ),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// A large tappable option with a radio circle (database list).
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? VV.blueSoft : VV.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VV.radiusMd),
        side: BorderSide(color: selected ? VV.blue : VV.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(VV.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? VV.blue : VV.inkMuted,
              ),
              const SizedBox(width: 12),
              const Icon(Icons.storage_outlined, size: 20, color: VV.inkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
