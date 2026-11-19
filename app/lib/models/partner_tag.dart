/// An Odoo contact tag (res.partner.category).
///
/// The app shows only "main" tags that have sub-tags (Odoo "Parent Tag"),
/// e.g. Borewell → Influencer, Old Customer, Agent, Josiyar.
class PartnerTag {
  const PartnerTag({required this.id, required this.name, this.parentId, this.color = 0});

  final int id;
  final String name;
  final int? parentId;

  /// Odoo colour index (0 = none, 1–11).
  final int color;

  factory PartnerTag.fromOdoo(Map<String, dynamic> r) {
    final p = r['parent_id'];
    return PartnerTag(
      id: r['id'] as int,
      name: (r['name'] is String) ? r['name'] as String : '',
      parentId: (p is List && p.isNotEmpty && p[0] is int) ? p[0] as int : null,
      color: r['color'] is int ? r['color'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parentId': parentId, 'color': color};

  factory PartnerTag.fromJson(Map<String, dynamic> j) => PartnerTag(
    id: j['id'] as int,
    name: (j['name'] ?? '') as String,
    parentId: j['parentId'] as int?,
    color: (j['color'] ?? 0) as int,
  );
}

/// The tags the app works with: main tags and their sub-tags.
class TagTree {
  TagTree(List<PartnerTag> all) {
    final byParent = <int, List<PartnerTag>>{};
    for (final t in all) {
      if (t.parentId != null) byParent.putIfAbsent(t.parentId!, () => []).add(t);
    }
    for (final t in all.where((t) => t.parentId == null)) {
      final kids = byParent[t.id];
      if (kids != null && kids.isNotEmpty) {
        kids.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        mains.add(t);
        children[t.id] = kids;
      }
    }
    mains.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final m in mains) {
      byId[m.id] = m;
      for (final k in children[m.id]!) {
        byId[k.id] = k;
      }
    }
  }

  final List<PartnerTag> mains = [];
  final Map<int, List<PartnerTag>> children = {};
  final Map<int, PartnerTag> byId = {};

  bool get isEmpty => mains.isEmpty;

  /// Ids of every tag the app manages (main tags and sub-tags).
  Set<int> get managedIds => byId.keys.toSet();

  /// Readable labels for [ids], e.g. "Borewell: Influencer, Agent".
  List<String> labels(Iterable<int> ids) {
    final set = ids.toSet();
    final out = <String>[];
    for (final m in mains) {
      final subs = children[m.id]!.where((k) => set.contains(k.id)).map((k) => k.name).toList();
      if (subs.isNotEmpty) {
        out.add('${m.name}: ${subs.join(', ')}');
      } else if (set.contains(m.id)) {
        out.add(m.name);
      }
    }
    return out;
  }
}
