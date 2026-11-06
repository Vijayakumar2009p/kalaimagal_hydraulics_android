import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../config.dart';
import '../models/customer.dart';
import '../models/pending_action.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import 'local_store.dart';
import 'odoo_client.dart';

/// Values typed on the "New customer" screen.
class NewCustomerInput {
  NewCustomerInput({
    required this.name,
    required this.isCompany,
    required this.phone,
    this.email = '',
    this.vat = '',
    this.street = '',
    this.city = '',
    this.zip = '',
    this.parent,
  });

  final String name;
  final bool isCompany;
  final String phone;
  final String email;
  final String vat;
  final String street;
  final String city;
  final String zip;
  final Customer? parent;
}

/// A location captured on the "Set location" screen.
class LocationInput {
  LocationInput({
    required this.customer,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.pinMovedMeters,
    required this.capturedAt,
    this.address,
    this.remark = '',
    this.photoPath,
  });

  final Customer customer;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double pinMovedMeters;
  final DateTime capturedAt;

  /// Only when the user changed the address: street, street2, city, zip,
  /// state (name) and countryCode.
  final Map<String, String>? address;
  final String remark;
  final String? photoPath;
}

class UpdateInfo {
  UpdateInfo({required this.latestVersion, required this.apkUrl, this.notes = ''});
  final String latestVersion;
  final String apkUrl;
  final String notes;
  bool get isNewer => compareVersions(latestVersion, AppConfig.appVersion) > 0;
}

/// Odoo has not created the customer yet; the location waits for it.
class _WaitForCreate implements Exception {}

/// Everything the screens need: login, customers, pending entries and sync.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState._(this.store);

  final LocalStore store;

  // ---- saved settings ----
  String serverUrl = AppConfig.defaultServerUrl;
  String database = AppConfig.defaultDatabase;
  String login = '';
  String userName = '';
  bool rememberMe = true;
  bool loggedIn = false;
  String odooUserName = '';
  Map<String, dynamic> userContext = {};
  Set<String> partnerFields = {};
  bool hasAddon = false;
  DateTime? lastRefresh;
  Map<String, int> refToId = {};
  int _nextLocalId = -1;

  // ---- data ----
  List<Customer> customers = [];
  List<PendingAction> queue = [];

  // ---- live status ----
  bool online = true;
  bool syncing = false;
  bool refreshing = false;
  bool needsLogin = false;
  String? refreshError;
  UpdateInfo? update;
  bool updateDismissed = false;

  OdooClient? _client;
  String? _password;
  Timer? _timer;
  final Map<String, int?> _countryIds = {};
  final Map<String, int?> _stateIds = {};

  static Future<AppState> load() async {
    final state = AppState._(await LocalStore.open());
    await state._restore();
    WidgetsBinding.instance.addObserver(state);
    return state;
  }

  // ======================================================================
  // Derived values
  // ======================================================================

  String get phoneField => partnerFields.contains('mobile') ? 'mobile' : 'phone';
  int get withoutLocationCount => customers.where((c) => !c.hasLocation).length;
  int get waitingCount => queue.length;
  int get blockedCount => queue.where((a) => a.blocked).length;

  /// The current copy of [c] (customers are replaced after each refresh,
  /// and a phone-only customer gets its Odoo id after syncing).
  Customer resolve(Customer c) {
    if (c.localRef != null) {
      final byRef = customers.where((x) => x.localRef == c.localRef);
      if (byRef.isNotEmpty) return byRef.first;
      final newId = refToId[c.localRef];
      if (newId != null) {
        final byId = customers.where((x) => x.id == newId);
        if (byId.isNotEmpty) return byId.first;
      }
    }
    final byId = customers.where((x) => x.id == c.id);
    return byId.isNotEmpty ? byId.first : c;
  }

  List<PendingAction> pendingFor(Customer c) => queue
      .where(
        (a) =>
            (a.partnerId != null && a.partnerId == c.id) ||
            (c.localRef != null && (a.ref == c.localRef || a.partnerRef == c.localRef)),
      )
      .toList();

  // ======================================================================
  // Saving and restoring
  // ======================================================================

  Future<void> _restore() async {
    final s = await store.readJson('settings');
    if (s is Map) {
      serverUrl = (s['serverUrl'] ?? serverUrl) as String;
      database = (s['database'] ?? database) as String;
      login = (s['login'] ?? '') as String;
      userName = (s['userName'] ?? '') as String;
      rememberMe = s['rememberMe'] != false;
      loggedIn = s['loggedIn'] == true;
      odooUserName = (s['odooUserName'] ?? '') as String;
      userContext = Map<String, dynamic>.from((s['userContext'] ?? const {}) as Map);
      partnerFields = Set<String>.from((s['partnerFields'] ?? const []) as List);
      hasAddon = s['hasAddon'] == true;
      lastRefresh = DateTime.tryParse((s['lastRefresh'] ?? '') as String);
      refToId = Map<String, int>.from((s['refToId'] ?? const {}) as Map);
      _nextLocalId = (s['nextLocalId'] ?? -1) as int;
    }
    final c = await store.readJson('customers');
    if (c is List) {
      customers = c.map((e) => Customer.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    final q = await store.readJson('queue');
    if (q is List) {
      queue = q.map((e) => PendingAction.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    if (loggedIn) {
      _password = await store.readSecret('password');
      _client = OdooClient(serverUrl)..sessionId = await store.readSecret('session');
      if (_password == null && _client!.sessionId == null) {
        loggedIn = false;
      } else {
        _startTimer();
      }
    }
  }

  Future<void> _saveSettings() => store.writeJson('settings', {
    'serverUrl': serverUrl,
    'database': database,
    'login': login,
    'userName': userName,
    'rememberMe': rememberMe,
    'loggedIn': loggedIn,
    'odooUserName': odooUserName,
    'userContext': userContext,
    'partnerFields': partnerFields.toList(),
    'hasAddon': hasAddon,
    'lastRefresh': lastRefresh?.toIso8601String(),
    'refToId': refToId,
    'nextLocalId': _nextLocalId,
  });

  Future<void> _saveCustomers() => store.writeJson('customers', customers.map((c) => c.toJson()).toList());

  Future<void> _saveQueue() => store.writeJson('queue', queue.map((a) => a.toJson()).toList());

  Future<void> setUserName(String name) async {
    userName = name.trim();
    await _saveSettings();
    notifyListeners();
  }

  // ======================================================================
  // Login
  // ======================================================================

  /// Database names on [url]; throws when the server hides them.
  Future<List<String>> listDatabases(String url) async {
    final client = OdooClient(url);
    try {
      return await client.listDatabases();
    } finally {
      client.close();
    }
  }

  Future<void> logIn({
    required String url,
    required String db,
    required String user,
    required String password,
    required bool remember,
  }) async {
    final client = OdooClient(url);
    final info = await client.authenticate(db, user, password);
    if (info == null) {
      client.close();
      throw OdooException(
        'This Odoo user has two-factor authentication switched on. '
        'Use a login without two-factor authentication for the app.',
      );
    }
    final changedServer = client.baseUrl != serverUrl || db != database || user != login;
    _client?.close();
    _client = client;
    _password = password;
    serverUrl = client.baseUrl;
    database = db;
    login = user;
    rememberMe = remember;
    odooUserName = (info['name'] ?? info['username'] ?? user).toString();
    final ctx = info['user_context'];
    userContext = ctx is Map ? Map<String, dynamic>.from(ctx) : {};
    needsLogin = false;
    online = true;

    if (changedServer) {
      customers = [];
      queue = [];
      refToId = {};
      lastRefresh = null;
      _countryIds.clear();
      _stateIds.clear();
      await _saveQueue();
      await _saveCustomers();
    }

    await _loadServerFeatures();
    loggedIn = true;
    await store.writeSecret('password', remember ? password : null);
    await store.writeSecret('session', remember ? client.sessionId : null);
    await _saveSettings();
    _startTimer();
    notifyListeners();

    // In the background: pending entries first, then the customer list.
    unawaited(() async {
      await syncNow();
      await refreshCustomers();
      await checkForUpdate();
    }());
  }

  Future<void> logOut() async {
    _timer?.cancel();
    final client = _client;
    _client = null;
    if (client != null) {
      // Tell Odoo in the background; do not wait (the phone may be offline).
      unawaited(client.logout().whenComplete(client.close));
    }
    final photos = queue.map((a) => a.payload['photo'] as String?).toList();
    _password = null;
    loggedIn = false;
    needsLogin = false;
    customers = [];
    queue = [];
    refToId = {};
    lastRefresh = null;
    update = null;
    notifyListeners();
    await store.writeSecret('password', null);
    await store.writeSecret('session', null);
    await _saveQueue();
    await _saveCustomers();
    await _saveSettings();
    for (final p in photos) {
      await store.deletePhoto(p);
    }
  }

  Future<void> _loadServerFeatures() async {
    final fields = await _call(
      'res.partner',
      'fields_get',
      [],
      kwargs: {
        'attributes': ['type'],
      },
    );
    if (fields is Map) partnerFields = fields.keys.map((k) => k.toString()).toSet();
    hasAddon = partnerFields.contains('vv_gps_captured');
  }

  /// Calls Odoo; logs in again by itself when the session has ended.
  Future<dynamic> _call(
    String model,
    String method,
    List<dynamic> args, {
    Map<String, dynamic>? kwargs,
  }) async {
    final client = _client ??= OdooClient(serverUrl);
    final kw = <String, dynamic>{...?kwargs};
    kw['context'] = {...userContext, ...?(kwargs?['context'] as Map<String, dynamic>?)};
    try {
      final result = await client.callKw(model, method, args, kwargs: kw);
      _setOnline(true);
      return result;
    } on OdooNetworkException {
      _setOnline(false);
      rethrow;
    } on OdooException catch (e) {
      if (!e.isSessionExpired) {
        _setOnline(true);
        rethrow;
      }
      await _renewSession();
      final result = await client.callKw(model, method, args, kwargs: kw);
      _setOnline(true);
      return result;
    }
  }

  Future<void> _renewSession() async {
    final client = _client!;
    if (_password == null || login.isEmpty) {
      _markNeedsLogin();
      throw OdooException('Your session has ended. Please log in again.', name: 'SessionExpired');
    }
    Map<String, dynamic>? info;
    try {
      info = await client.authenticate(database, login, _password!);
    } on OdooException catch (e) {
      if (e.isAccessDenied) {
        _markNeedsLogin();
        throw OdooException(
          'The saved password no longer works. Please log in again.',
          name: 'SessionExpired',
        );
      }
      rethrow;
    }
    if (info == null) {
      _markNeedsLogin();
      throw OdooException('Please log in again.', name: 'SessionExpired');
    }
    if (rememberMe) await store.writeSecret('session', client.sessionId);
  }

  void _markNeedsLogin() {
    needsLogin = true;
    notifyListeners();
  }

  void _setOnline(bool value) {
    if (online != value) {
      online = value;
      notifyListeners();
    }
  }

  // ======================================================================
  // Customers
  // ======================================================================

  List<String> get _readFields {
    final wanted = [
      'name',
      'is_company',
      'parent_id',
      'phone',
      'mobile',
      'email',
      'vat',
      'street',
      'street2',
      'city',
      'zip',
      'state_id',
      'country_id',
      'partner_latitude',
      'partner_longitude',
      'date_localization',
    ];
    if (partnerFields.isEmpty) {
      return wanted.where((f) => f != 'mobile' && f != 'date_localization').toList();
    }
    return wanted.where(partnerFields.contains).toList();
  }

  /// Downloads all contacts so search works offline.
  Future<void> refreshCustomers() async {
    if (refreshing || !loggedIn) return;
    refreshing = true;
    refreshError = null;
    notifyListeners();
    final started = DateTime.now();
    try {
      const batch = 500;
      final rows = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final result = await _call(
          'res.partner',
          'search_read',
          [],
          kwargs: {
            'domain': AppConfig.customerDomain,
            'fields': _readFields,
            'offset': offset,
            'limit': batch,
            'order': 'name asc, id asc',
          },
        );
        final page = (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        rows.addAll(page);
        if (page.length < batch) break;
        offset += batch;
      }
      final fresh = rows.map((r) => Customer.fromOdoo(r, phoneField: phoneField)).toList();
      // Keep phone-only customers, and customers created while this download
      // was running (the downloaded pages may not include them yet).
      final freshIds = fresh.map((c) => c.id).toSet();
      fresh.addAll(
        customers.where(
          (c) => c.isLocal || (!freshIds.contains(c.id) && (_linkedAt[c.id]?.isAfter(started) ?? false)),
        ),
      );
      customers = fresh;
      _applyPendingToCustomers();
      lastRefresh = DateTime.now();
      await _saveCustomers();
      await _saveSettings();
    } on OdooNetworkException catch (e) {
      refreshError = e.message;
    } on OdooException catch (e) {
      refreshError = e.message;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  /// Puts locations that are still waiting onto the customer list.
  void _applyPendingToCustomers() {
    for (final c in customers) {
      c.pending = false;
    }
    for (final a in queue) {
      final matches = customers.where(
        (c) =>
            (a.partnerId != null && c.id == a.partnerId) ||
            (a.partnerRef != null && c.localRef == a.partnerRef) ||
            (a.kind == PendingAction.create && c.localRef == a.ref),
      );
      for (final c in matches) {
        c.pending = true;
        if (a.kind == PendingAction.location) _applyLocation(c, a.payload);
      }
    }
  }

  void _applyLocation(Customer c, Map<String, dynamic> p) {
    c.latitude = (p['lat'] as num).toDouble();
    c.longitude = (p['lng'] as num).toDouble();
    final captured = DateTime.tryParse((p['capturedAt'] ?? '') as String) ?? DateTime.now();
    c.locationDate = odooDate(captured);
    final addr = p['address'];
    if (addr is Map) {
      c.street = (addr['street'] ?? '') as String;
      c.street2 = (addr['street2'] ?? '') as String;
      c.city = (addr['city'] ?? '') as String;
      c.zip = (addr['zip'] ?? '') as String;
      if ((addr['state'] ?? '').toString().isNotEmpty) c.stateName = addr['state'] as String;
    }
  }

  /// Customers already in Odoo (or on this phone) with the same mobile or GSTIN.
  Future<List<Customer>> findDuplicates(String phone, String gstin) async {
    final mobile = Validators.mobileDigits(phone);
    final gst = Validators.cleanGstin(gstin);
    final found = <int, Customer>{};
    bool same(Customer c) =>
        (mobile.length == 10 && Validators.mobileDigits(c.phone) == mobile) ||
        (gst.isNotEmpty && Validators.cleanGstin(c.vat) == gst);
    for (final c in customers.where(same)) {
      found[c.id] = c;
    }
    try {
      final domain = <dynamic>[];
      if (mobile.length == 10 && gst.isNotEmpty) domain.add('|');
      if (mobile.length == 10) domain.add([phoneField, 'ilike', mobile.substring(5)]);
      if (gst.isNotEmpty) domain.add(['vat', '=ilike', gst]);
      if (domain.isNotEmpty) {
        final rows = await _call(
          'res.partner',
          'search_read',
          [],
          kwargs: {'domain': domain, 'fields': _readFields, 'limit': 20},
        );
        for (final r in (rows as List)) {
          final c = Customer.fromOdoo(Map<String, dynamic>.from(r as Map), phoneField: phoneField);
          if (same(c)) found.putIfAbsent(c.id, () => c);
        }
      }
    } catch (_) {
      // Offline: the phone's own list was checked above.
    }
    return found.values.toList();
  }

  /// Companies for the "works at" field of a new individual.
  List<Customer> companies(String query) =>
      customers.where((c) => c.isCompany && !c.isLocal && c.matches(query)).take(20).toList();

  // ======================================================================
  // Changes made in the field
  // ======================================================================

  String _newRef() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  Future<Customer> addCustomer(NewCustomerInput input) async {
    final ref = _newRef();
    final vals = <String, dynamic>{
      'name': input.name.trim(),
      'is_company': input.isCompany,
      phoneField: Validators.formatMobile(input.phone),
      if (input.email.trim().isNotEmpty) 'email': input.email.trim(),
      if (input.vat.trim().isNotEmpty) 'vat': Validators.cleanGstin(input.vat),
      if (input.street.trim().isNotEmpty) 'street': input.street.trim(),
      if (input.city.trim().isNotEmpty) 'city': input.city.trim(),
      if (input.zip.trim().isNotEmpty) 'zip': input.zip.trim(),
      if (!input.isCompany && input.parent != null && !input.parent!.isLocal) 'parent_id': input.parent!.id,
      if (partnerFields.contains('customer_rank')) 'customer_rank': 1,
    };
    final gstState = input.vat.trim().isEmpty ? null : Validators.gstinState(input.vat);
    final parent = input.isCompany ? null : input.parent;
    queue.add(
      PendingAction(
        ref: ref,
        kind: PendingAction.create,
        createdAt: DateTime.now(),
        customerName: input.name.trim(),
        payload: {
          'vals': vals,
          'countryCode': 'IN',
          if (gstState != null) 'state': gstState,
          if (parent != null && parent.isLocal) 'parentRef': parent.localRef,
          'userName': userName,
        },
      ),
    );
    final customer = Customer(
      id: _nextLocalId--,
      localRef: ref,
      name: input.name.trim(),
      isCompany: input.isCompany,
      parentId: input.parent?.id,
      parentName: input.parent?.name ?? '',
      phone: Validators.formatMobile(input.phone),
      email: input.email.trim(),
      vat: Validators.cleanGstin(input.vat),
      street: input.street.trim(),
      city: input.city.trim(),
      zip: input.zip.trim(),
      stateName: gstState ?? '',
      pending: true,
    );
    customers.insert(0, customer);
    await _saveQueue();
    await _saveCustomers();
    await _saveSettings();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return resolve(customer);
  }

  /// Saves the location on the phone, then tries to send it to Odoo.
  /// Returns the entry's reference: use [pendingByRef] to see whether it
  /// reached Odoo (no entry), still waits, or was refused.
  Future<String> saveLocation(LocationInput input) async {
    final ref = _newRef();
    String? photo;
    if (input.photoPath != null) photo = await store.keepPhoto(input.photoPath!, ref);
    final c = resolve(input.customer);
    final action = PendingAction(
      ref: ref,
      kind: PendingAction.location,
      createdAt: DateTime.now(),
      customerName: c.name,
      partnerId: c.isLocal ? null : c.id,
      partnerRef: c.isLocal ? c.localRef : null,
      payload: {
        'lat': input.latitude,
        'lng': input.longitude,
        'accuracy': input.accuracy,
        'pinMoved': input.pinMovedMeters,
        'capturedAt': input.capturedAt.toIso8601String(),
        if (input.address != null) 'address': input.address,
        'remark': input.remark.trim(),
        if (photo != null) 'photo': photo,
        'userName': userName,
      },
    );
    // A newer location replaces one still waiting for the same customer.
    bool sameCustomer(PendingAction a) => c.isLocal
        ? a.partnerRef == c.localRef
        : (a.partnerId == c.id || (a.partnerRef != null && refToId[a.partnerRef] == c.id));
    final older = queue.where((a) => a.kind == PendingAction.location && sameCustomer(a)).toList();
    for (final a in older) {
      queue.remove(a);
      await store.deletePhoto(a.payload['photo'] as String?);
    }
    queue.add(action);
    _applyLocation(c, action.payload);
    c.pending = true;
    await _saveQueue();
    await _saveCustomers();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return ref;
  }

  PendingAction? pendingByRef(String ref) {
    for (final a in queue) {
      if (a.ref == ref) return a;
    }
    return null;
  }

  // ======================================================================
  // Sync
  // ======================================================================

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.autoSyncInterval, (_) {
      if (queue.any((a) => !a.blocked)) syncNow();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && loggedIn && !needsLogin) {
      refreshAll(onlyIfOld: true);
    }
  }

  /// Sends waiting entries, then reloads the customer list.
  Future<void> refreshAll({bool onlyIfOld = false}) async {
    await syncNow();
    final old = lastRefresh == null || DateTime.now().difference(lastRefresh!) > const Duration(minutes: 10);
    if (!onlyIfOld || old) await refreshCustomers();
  }

  Future<void>? _syncRun;
  bool _syncAgain = false;

  /// Sends waiting entries. If a sync is already running, the caller waits
  /// for it, and anything added meanwhile is sent in the same run.
  Future<void> syncNow() {
    if (!loggedIn || needsLogin || queue.isEmpty) return Future<void>.value();
    final running = _syncRun;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    final run = _syncLoop();
    _syncRun = run;
    return run.whenComplete(() => _syncRun = null);
  }

  Future<void> _syncLoop() async {
    syncing = true;
    notifyListeners();
    try {
      var reachedServer = true;
      do {
        _syncAgain = false;
        reachedServer = await _syncPass();
      } while (_syncAgain && reachedServer && !needsLogin);
    } finally {
      syncing = false;
      _applyPendingToCustomers();
      await _saveQueue();
      await _saveCustomers();
      await _saveSettings();
      notifyListeners();
    }
  }

  /// One pass over the queue. Returns false when it stopped because the
  /// server could not be reached.
  Future<bool> _syncPass() async {
    for (final action in List<PendingAction>.of(queue)) {
      if (action.blocked || !queue.contains(action)) continue;
      try {
        if (action.kind == PendingAction.create) {
          await _sendCreate(action);
        } else {
          await _sendLocation(action);
        }
        queue.remove(action);
        await store.deletePhoto(action.payload['photo'] as String?);
      } on _WaitForCreate {
        continue;
      } on OdooNetworkException catch (e) {
        action.lastError = e.message;
        await _saveQueue();
        return false; // offline: try again later
      } on OdooException catch (e) {
        if (needsLogin) return false;
        action.attempts++;
        action.lastError = e.message;
        action.blocked = true; // Odoo refused it; needs a person to look
      } on FileSystemException {
        action.payload.remove('photo'); // photo file lost: send without it
      } catch (e) {
        // Anything unexpected: keep the entry and try again later.
        action.attempts++;
        action.lastError = e.toString();
        await _saveQueue();
        return false;
      }
      await _saveQueue();
    }
    return true;
  }

  Future<void> retry(PendingAction action) async {
    action.blocked = false;
    action.lastError = '';
    await _saveQueue();
    notifyListeners();
    await syncNow();
  }

  Future<void> discard(PendingAction action) async {
    final removed = [action];
    if (action.kind == PendingAction.create) {
      customers.removeWhere((c) => c.localRef == action.ref);
      removed.addAll(queue.where((a) => a.partnerRef == action.ref && a.partnerId == null));
    }
    for (final a in removed) {
      queue.remove(a);
      await store.deletePhoto(a.payload['photo'] as String?);
    }
    _applyPendingToCustomers();
    await _saveQueue();
    await _saveCustomers();
    notifyListeners();
  }

  /// Customers created in Odoo during this app session, with the time.
  final Map<int, DateTime> _linkedAt = {};

  void _linkCreated(PendingAction a, int newId) {
    refToId[a.ref] = newId;
    _linkedAt[newId] = DateTime.now();
    for (final c in customers.where((c) => c.localRef == a.ref)) {
      c.id = newId;
      c.localRef = null;
    }
    for (final other in queue.where((x) => x.partnerRef == a.ref)) {
      other.partnerId = newId;
    }
  }

  /// After a timeout the customer may already be in Odoo: look for it.
  Future<int?> _findCreated(Map<String, dynamic> vals, DateTime createdAt) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = createdAt.toUtc().subtract(const Duration(hours: 1));
    final since = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final rows = await _call(
      'res.partner',
      'search_read',
      [],
      kwargs: {
        'domain': [
          ['name', '=', vals['name']],
          [phoneField, '=', vals[phoneField]],
          ['create_date', '>=', since],
        ],
        'fields': ['id'],
        'limit': 1,
        'order': 'id desc',
      },
    );
    final list = rows as List;
    return list.isEmpty ? null : (list.first as Map)['id'] as int;
  }

  Future<void> _sendCreate(PendingAction a) async {
    // Already created (the app stopped right after): just link it again.
    final known = refToId[a.ref];
    if (known != null) {
      _linkCreated(a, known);
      return;
    }
    final vals = Map<String, dynamic>.from(a.payload['vals'] as Map);
    final ids = await _stateAndCountry(
      (a.payload['state'] ?? '') as String,
      (a.payload['countryCode'] ?? '') as String,
    );
    vals.addAll(ids);
    // The company may itself have been created offline: wait for it.
    final parentRef = a.payload['parentRef'] as String?;
    if (parentRef != null) {
      final parentId = refToId[parentRef];
      if (parentId == null) throw _WaitForCreate();
      vals['parent_id'] = parentId;
    }

    // An earlier try may have reached Odoo even though no answer came back.
    int? newId;
    if (a.payload['sent'] == true) newId = await _findCreated(vals, a.createdAt);
    if (newId == null) {
      a.payload['sent'] = true;
      await _saveQueue();
      final result = await _call('res.partner', 'create', [vals]);
      newId = result is int ? result : (result as List).first as int;
    }
    _linkCreated(a, newId);
    await _saveSettings();
    try {
      await _postNote(
        newId,
        'Customer created with VeeVee Field Locator by '
        '${_by(a)} on ${formatDateTime(a.createdAt)}.',
      );
    } catch (_) {
      // The customer exists; a missing note is not worth a duplicate.
    }
  }

  Future<void> _sendLocation(PendingAction a) async {
    final partnerId = a.partnerId ?? (a.partnerRef != null ? refToId[a.partnerRef] : null);
    if (partnerId == null) throw _WaitForCreate();
    a.partnerId = partnerId;

    final p = a.payload;
    final lat = (p['lat'] as num).toDouble();
    final lng = (p['lng'] as num).toDouble();
    final accuracy = (p['accuracy'] as num).toDouble();
    final captured = DateTime.tryParse((p['capturedAt'] ?? '') as String) ?? a.createdAt;

    // Latitude/longitude must be in the same write as any address change,
    // otherwise Odoo resets them to 0.
    final vals = <String, dynamic>{
      'partner_latitude': lat,
      'partner_longitude': lng,
      if (partnerFields.contains('date_localization')) 'date_localization': odooDate(captured),
      if (hasAddon) 'vv_gps_captured': true,
      if (hasAddon) 'vv_gps_accuracy': accuracy,
      if (hasAddon) 'vv_gps_by': _by(a),
    };
    final addr = p['address'];
    if (addr is Map) {
      for (final f in ['street', 'street2', 'city', 'zip']) {
        vals[f] = (addr[f] ?? '').toString();
      }
      vals.addAll(
        await _stateAndCountry((addr['state'] ?? '').toString(), (addr['countryCode'] ?? '').toString()),
      );
    }
    await _call('res.partner', 'write', [
      [partnerId],
      vals,
    ]);

    final attachments = <int>[];
    final photo = p['photo'] as String?;
    if (photo != null && photo.isNotEmpty) {
      final bytes = await File(photo).readAsBytes();
      final attId = await _call('ir.attachment', 'create', [
        {
          'name': 'Site photo ${formatDate(captured)}.jpg',
          'datas': base64Encode(bytes),
          'mimetype': 'image/jpeg',
          'res_model': 'mail.compose.message',
          'res_id': 0,
        },
      ]);
      attachments.add(attId is int ? attId : (attId as List).first as int);
    }

    final moved = (p['pinMoved'] as num? ?? 0).toDouble();
    final remark = (p['remark'] ?? '').toString();
    final late = DateTime.now().difference(captured) > const Duration(minutes: 5);
    final note = StringBuffer()
      ..write(
        'Location set on site with VeeVee Field Locator by ${_by(a)} '
        'on ${formatDateTime(captured)}. ',
      )
      ..write('Lat ${formatCoord(lat)}, Long ${formatCoord(lng)}. ')
      ..write('GPS accuracy ${accuracy.round()} m.');
    if (moved >= 5) note.write(' Pin moved ${formatMeters(moved)} from the GPS point.');
    if (addr is Map) note.write(' Address updated from site.');
    if (remark.isNotEmpty) note.write(' Remark: $remark');
    if (late) note.write(' (Saved offline, sent ${formatDateTime(DateTime.now())}.)');
    await _postNote(partnerId, note.toString(), attachmentIds: attachments);
  }

  String _by(PendingAction a) {
    final n = (a.payload['userName'] ?? '').toString();
    return n.isNotEmpty ? n : (userName.isNotEmpty ? userName : odooUserName);
  }

  Future<void> _postNote(int partnerId, String text, {List<int> attachmentIds = const []}) {
    return _call(
      'res.partner',
      'message_post',
      [
        [partnerId],
      ],
      kwargs: {
        'body': text,
        'message_type': 'comment',
        'subtype_xmlid': 'mail.mt_note',
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
  }

  /// Odoo ids for a state name (e.g. "Tamil Nadu") and country code ("IN").
  Future<Map<String, dynamic>> _stateAndCountry(String state, String countryCode) async {
    final result = <String, dynamic>{};
    if (countryCode.isEmpty) return result;
    if (!_countryIds.containsKey(countryCode)) {
      final rows = await _call(
        'res.country',
        'search_read',
        [],
        kwargs: {
          'domain': [
            ['code', '=', countryCode],
          ],
          'fields': ['id'],
          'limit': 1,
        },
      );
      _countryIds[countryCode] = (rows as List).isEmpty ? null : (rows.first as Map)['id'] as int;
    }
    final countryId = _countryIds[countryCode];
    if (countryId == null) return result;
    result['country_id'] = countryId;
    if (state.isEmpty) return result;
    final key = '$countryCode/${state.toLowerCase()}';
    if (!_stateIds.containsKey(key)) {
      final rows = await _call(
        'res.country.state',
        'search_read',
        [],
        kwargs: {
          'domain': [
            ['country_id', '=', countryId],
            '|',
            ['name', '=ilike', state],
            ['code', '=ilike', state],
          ],
          'fields': ['id'],
          'limit': 1,
        },
      );
      _stateIds[key] = (rows as List).isEmpty ? null : (rows.first as Map)['id'] as int;
    }
    final stateId = _stateIds[key];
    if (stateId != null) result['state_id'] = stateId;
    return result;
  }

  // ======================================================================
  // App updates (needs the VeeVee Field Locator Odoo module)
  // ======================================================================

  Future<UpdateInfo?> checkForUpdate() async {
    if (!hasAddon || !loggedIn) return null;
    try {
      final r = await _call('veevee.field.locator', 'get_app_info', []);
      if (r is! Map) return null;
      final info = UpdateInfo(
        latestVersion: (r['latest_version'] ?? '').toString(),
        apkUrl: (r['apk_url'] ?? '').toString(),
        notes: (r['release_notes'] ?? '').toString(),
      );
      update = info;
      notifyListeners();
      return info;
    } catch (_) {
      return null;
    }
  }

  void dismissUpdate() {
    updateDismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _client?.close();
    super.dispose();
  }
}
