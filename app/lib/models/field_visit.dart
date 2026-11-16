/// An open "Field Visit" activity (mail.activity) assigned to the logged-in user.
class FieldVisit {
  FieldVisit({
    this.id,
    this.localRef,
    this.partnerId,
    this.partnerRef,
    required this.customerName,
    required this.summary,
    this.note = '',
    required this.deadline,
  });

  /// Odoo activity id; null while the visit was scheduled on the phone and not yet sent.
  int? id;

  /// Reference of the offline "schedule visit" entry.
  String? localRef;

  int? partnerId;
  String? partnerRef;
  String customerName;
  String summary;
  String note;

  /// Due date (date only).
  DateTime deadline;

  bool get isLocal => id == null;

  /// Negative: overdue; 0: today; positive: days ahead.
  int get daysLeft {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(deadline.year, deadline.month, deadline.day).difference(today).inDays;
  }

  String get title => summary.trim().isEmpty ? 'Field visit' : summary.trim();

  Map<String, dynamic> toJson() => {
    'id': id,
    'localRef': localRef,
    'partnerId': partnerId,
    'partnerRef': partnerRef,
    'customerName': customerName,
    'summary': summary,
    'note': note,
    'deadline': deadline.toIso8601String(),
  };

  factory FieldVisit.fromJson(Map<String, dynamic> j) => FieldVisit(
    id: j['id'] as int?,
    localRef: j['localRef'] as String?,
    partnerId: j['partnerId'] as int?,
    partnerRef: j['partnerRef'] as String?,
    customerName: (j['customerName'] ?? '') as String,
    summary: (j['summary'] ?? '') as String,
    note: (j['note'] ?? '') as String,
    deadline: DateTime.tryParse((j['deadline'] ?? '') as String) ?? DateTime.now(),
  );

  /// From an Odoo mail.activity search_read row.
  factory FieldVisit.fromOdoo(Map<String, dynamic> r) => FieldVisit(
    id: r['id'] as int,
    partnerId: r['res_id'] as int?,
    customerName: (r['res_name'] is String) ? r['res_name'] as String : '',
    summary: (r['summary'] is String) ? r['summary'] as String : '',
    note: htmlToText(r['note']),
    deadline: DateTime.tryParse((r['date_deadline'] is String) ? r['date_deadline'] as String : '') ?? DateTime.now(),
  );

  /// Odoo stores activity notes as HTML; the app shows plain text.
  static String htmlToText(Object? html) {
    if (html is! String) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }
}
