import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../models/field_visit.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'customer_screen.dart';
import 'visit_done_screen.dart';

/// "Field visits": this user's open Field Visit activities from Odoo.
class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) AppScope.read(context).refreshVisits();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.openVisits;
    final overdue = all.where((v) => v.daysLeft < 0).toList();
    final today = all.where((v) => v.daysLeft == 0).toList();
    final upcoming = all.where((v) => v.daysLeft > 0).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Field visits')),
      body: RefreshIndicator(
        color: VV.blue,
        onRefresh: () async {
          await app.syncNow();
          await app.refreshVisits();
        },
        child: all.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.event_available_outlined, size: 56, color: VV.inkMuted),
                  const SizedBox(height: 12),
                  Text(
                    app.refreshingVisits ? 'Loading field visits…' : 'No field visits for you right now.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Visits planned for you in Odoo (activity type "Field Visit") show here. '
                    'You can also plan one from a customer page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VV.inkMuted),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (overdue.isNotEmpty) ..._group('Overdue', overdue, VV.danger),
                  if (today.isNotEmpty) ..._group('Today', today, VV.goldText),
                  if (upcoming.isNotEmpty) ..._group('Upcoming', upcoming, VV.inkMuted),
                ],
              ),
      ),
    );
  }

  List<Widget> _group(String title, List<FieldVisit> list, Color color) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        '$title (${list.length})',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
      ),
    ),
    for (final v in list) VisitTile(visit: v),
  ];
}

/// One visit: customer, job, due date, and the main buttons.
class VisitTile extends StatelessWidget {
  const VisitTile({super.key, required this.visit, this.showCustomer = true});
  final FieldVisit visit;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final customer = _customerOf(app.customers, visit);
    final d = visit.daysLeft;
    final due = d < 0
        ? 'Overdue · ${formatDate(visit.deadline)}'
        : d == 0
        ? 'Today'
        : d == 1
        ? 'Tomorrow'
        : formatDate(visit.deadline);
    final dueColor = d < 0 ? VV.danger : (d == 0 ? VV.goldText : VV.inkMuted);
    return Card(
      margin: showCustomer ? const EdgeInsets.fromLTRB(16, 6, 16, 6) : const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VV.radiusLg),
        side: const BorderSide(color: VV.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.location_on, color: VV.blue, size: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showCustomer)
                        Text(
                          visit.customerName,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: VV.ink),
                        ),
                      Text(
                        visit.title,
                        style: TextStyle(
                          fontSize: showCustomer ? 15 : 16,
                          fontWeight: showCustomer ? FontWeight.w500 : FontWeight.w700,
                          color: VV.ink,
                        ),
                      ),
                      if (showCustomer && customer != null && customer.addressLine.isNotEmpty)
                        Text(customer.addressLine, style: const TextStyle(fontSize: 13, color: VV.inkMuted)),
                      if (visit.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(visit.note, style: const TextStyle(fontSize: 13, color: VV.inkMuted)),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.event, size: 15, color: dueColor),
                          const SizedBox(width: 4),
                          Text(
                            due,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dueColor),
                          ),
                          if (visit.isLocal) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.cloud_upload_outlined, size: 15, color: VV.goldText),
                            const SizedBox(width: 3),
                            const Text('Not synced yet', style: TextStyle(fontSize: 12, color: VV.goldText)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: VV.success, minimumSize: const Size(0, 44)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VisitDoneScreen(visit: visit, customer: customer),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Mark done'),
                ),
                if (customer != null && customer.hasLocation)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://www.google.com/maps/dir/?api=1&destination=${customer.latitude},${customer.longitude}',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Directions'),
                  ),
                if (showCustomer && customer != null)
                  TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => CustomerScreen(customer: customer))),
                    child: const Text('Open customer'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Customer? _customerOf(List<Customer> customers, FieldVisit v) {
    for (final c in customers) {
      if ((v.partnerId != null && c.id == v.partnerId) || (v.partnerRef != null && c.localRef == v.partnerRef)) {
        return c;
      }
    }
    return null;
  }
}

/// Banner on the home screen: open visits, tap to see them.
class VisitsBanner extends StatelessWidget {
  const VisitsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.visitsEnabled) return const SizedBox.shrink();
    final open = app.visits.length;
    final due = app.visitsDueCount;
    final text = open == 0
        ? 'No field visits planned for you'
        : due > 0
        ? '$due field ${due == 1 ? 'visit' : 'visits'} due today${open > due ? ' · ${open - due} upcoming' : ''}'
        : '$open field ${open == 1 ? 'visit' : 'visits'} planned';
    return Material(
      color: due > 0 ? VV.goldSoft : VV.blueSoft,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VisitsScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.event_note_outlined, color: due > 0 ? VV.goldText : VV.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontWeight: FontWeight.w600, color: due > 0 ? VV.goldText : VV.blue),
                ),
              ),
              Icon(Icons.chevron_right, color: due > 0 ? VV.goldText : VV.blue),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small helper for other screens.
void openVisits(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VisitsScreen()));

/// Shows a short result after saving a visit entry.
void showVisitResult(BuildContext context, String okText, String ref) {
  final waiting = AppScope.read(context).pendingByRef(ref);
  showMessage(
    context,
    waiting == null
        ? okText
        : waiting.blocked
        ? 'Odoo refused it: ${waiting.lastError}'
        : 'Saved on this phone. It will be sent to Odoo when online.',
    error: waiting?.blocked ?? false,
  );
}
