import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/product.dart';
import '../domain/wardrobe.dart';
import 'app.dart' show ProductPhoto;
import 'feedback.dart';
import 'paper.dart';

enum _Section { stats, outfits, planner, packing }

/// The wardrobe tab: statistics, outfit boards and moodboards, the day
/// planner and packing lists. Everything is kept on the device.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    super.key,
    required this.repository,
    required this.products,
    this.today,
    this.gutter = 16,
  });
  final CatalogRepository repository;

  /// Every item an outfit may use: the owner's finds and any saved samples.
  final List<Product> products;
  final DateTime? today;
  final double gutter;
  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  _Section _section = _Section.stats;
  Outfit? _editing;
  late final _name = TextEditingController();
  late final _note = TextEditingController();

  CatalogRepository get _repo => widget.repository;
  DateTime get _now => widget.today ?? DateTime.now();
  Map<String, Product> get _byId => {for (final p in widget.products) p.id: p};

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<String?> _ask(String title, String label, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<T?> _pick<T>(String title, List<(T, String)> options) => showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          SimpleDialogOption(onPressed: () => Navigator.pop(context, value), child: Text(label)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(widget.gutter, Space.l, widget.gutter, Space.huge),
      children: [
        const Text(
          'Your wardrobe, kept here.',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6),
        ),
        const SizedBox(height: Space.xs),
        const Text(
          'No item limit, no ads, no account. Backups carry everything on this page.',
          style: TextStyle(color: Tone.inkSoft, fontSize: 12.5),
        ),
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (s, label) in [
              (_Section.stats, 'Statistics'),
              (_Section.outfits, 'Outfits'),
              (_Section.planner, 'Planner'),
              (_Section.packing, 'Packing'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _section == s,
                onSelected: (_) => setState(() {
                  _section = s;
                  _editing = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        switch (_section) {
          _Section.stats => _stats(),
          _Section.outfits => _editing == null ? _outfitList() : _outfitEditor(),
          _Section.planner => _planner(),
          _Section.packing => _packing(),
        },
      ],
    );
  }

  // ---- Statistics ----

  Widget _stats() {
    final owned = _repo.owned();
    final wears = _repo.wearCounts();
    final last = _repo.lastWorn();
    final items = [
      for (final e in owned.entries)
        if (_byId[e.key] != null)
          WornItem(
            productId: e.key,
            name: _byId[e.key]!.name,
            own: e.value,
            wears: wears[e.key] ?? 0,
            last: last[e.key],
          ),
    ];
    if (items.isEmpty) {
      return const Text(
        'Open an item in My catalog and switch on "I own this". Your statistics build from there.',
        style: TextStyle(color: Tone.inkSoft),
      );
    }
    final s = wardrobeStats(items);
    Widget list(String title, List<WornItem> rows, String Function(WornItem) detail) => rows.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title),
                const SizedBox(height: Space.s),
                for (final i in rows) Text('${i.name}: ${detail(i)}'),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${s.count} ${s.count == 1 ? 'item' : 'items'} owned.', style: const TextStyle(fontSize: 18)),
        if (s.spent.isNotEmpty)
          Text('Paid in total: ${s.spent.entries.map((e) => money(e.value, e.key)).join(' and ')}.'),
        list('Most worn', s.mostWorn, (i) => '${i.wears} ${i.wears == 1 ? 'day' : 'days'}'),
        list(
          'Best value so far',
          s.bestValue,
          (i) => '${money(costPerWear(i.own, i.wears)!, i.own.currency)} per wear',
        ),
        list(
          'Never worn',
          s.neverWorn,
          (i) => i.own.price == null
              ? 'no wears logged'
              : '${money(i.own.price!, i.own.currency)} paid, no wears logged',
        ),
      ],
    );
  }

  // ---- Outfits ----

  Widget _outfitList() {
    final outfits = _repo.outfits();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CopperButton(
            label: 'New outfit or moodboard',
            icon: Icons.add,
            compact: true,
            onPressed: () => _edit(const Outfit(name: '')),
          ),
        ),
        const SizedBox(height: Space.l),
        if (outfits.isEmpty)
          const Text(
            'Nothing here yet. Pick items you own, or ones you only want, and name the board.',
            style: TextStyle(color: Tone.inkSoft),
          ),
        for (final o in outfits) _outfitCard(o),
      ],
    );
  }

  Widget _outfitCard(Outfit o) {
    final owned = _repo.owned();
    final items = [for (final id in o.itemIds) _byId[id]].whereType<Product>().toList();
    final wearable = items.where((p) => owned.containsKey(p.id)).map((p) => p.id).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: Space.l),
      padding: const EdgeInsets.all(Space.m),
      decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${o.name}${o.mood ? ' (moodboard)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          if (o.note.isNotEmpty) Text(o.note, style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5)),
          const SizedBox(height: Space.s),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in items)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: Semantics(
                      label: p.name + (owned.containsKey(p.id) ? ', owned' : ', wishlist'),
                      child: SizedBox(width: 76, child: ClipRRect(child: ProductPhoto(p))),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            items.map((p) => owned.containsKey(p.id) ? p.name : '${p.name} (wishlist)').join(', '),
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (wearable.isNotEmpty)
                PaperButton(
                  label: 'Wore it today',
                  icon: Icons.checkroom_outlined,
                  compact: true,
                  onPressed: () {
                    _repo.logWear(wearable, dayKey(_now));
                    FeedbackScope.of(context).play(Cue.success);
                    ToastHost.of(context)
                        .show(ToastKind.success, 'Logged ${wearable.length} items for today.');
                  },
                ),
              PaperButton(label: 'Edit', icon: Icons.edit_outlined, compact: true, onPressed: () => _edit(o)),
              PaperButton(
                label: 'Delete',
                icon: Icons.close,
                compact: true,
                onPressed: () {
                  _repo.deleteOutfit(o.id);
                  _refresh();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Set<String> _chosen = {};
  bool _mood = false;

  void _edit(Outfit o) {
    _name.text = o.name;
    _note.text = o.note;
    _chosen = {...o.itemIds};
    _mood = o.mood;
    setState(() => _editing = o);
  }

  Widget _outfitEditor() {
    final owned = _repo.owned();
    final mine = widget.products.where((p) => !p.sample).toList();
    final samples = widget.products.where((p) => p.sample).toList();
    Widget chips(List<Product> list) => Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final p in list)
          FilterChip(
            label: Text(owned.containsKey(p.id) || p.sample ? p.name : '${p.name} (wishlist)'),
            selected: _chosen.contains(p.id),
            onSelected: (on) => setState(() => on ? _chosen.add(p.id) : _chosen.remove(p.id)),
          ),
      ],
    );
    final o = _editing!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperField(controller: _name, label: 'Name', maxLength: 60, onChanged: (_) => setState(() {})),
        PaperField(controller: _note, label: 'Note (optional)', maxLength: 200),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Moodboard'),
          subtitle: const Text('For inspiration. Outfits and moodboards both take owned and wishlist items.'),
          value: _mood,
          onChanged: (v) => setState(() => _mood = v),
        ),
        const SectionHeader('Pick items'),
        const SizedBox(height: Space.s),
        if (mine.isEmpty && samples.isEmpty) const Text('Add a product link first.'),
        chips(mine),
        if (samples.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          const Text('Inspiration samples', style: TextStyle(color: Tone.inkSoft, fontSize: 12.5)),
          const SizedBox(height: Space.xs),
          chips(samples.take(12).toList()),
        ],
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          children: [
            CopperButton(
              label: 'Save',
              icon: Icons.check,
              onPressed: _name.text.trim().isEmpty || _chosen.isEmpty
                  ? null
                  : () {
                      _repo.saveOutfit(
                        Outfit(
                          id: o.id,
                          name: _name.text.trim(),
                          mood: _mood,
                          note: _note.text.trim(),
                          itemIds: _chosen.toList(),
                        ),
                      );
                      FeedbackScope.of(context).play(Cue.success);
                      setState(() => _editing = null);
                    },
            ),
            PaperButton(label: 'Cancel', compact: true, onPressed: () => setState(() => _editing = null)),
          ],
        ),
      ],
    );
  }

  // ---- Planner ----

  Widget _planner() {
    final outfits = _repo.outfits();
    final byOutfit = {for (final o in outfits) o.id: o};
    final plans = _repo.plans();
    final start = DateTime(_now.year, _now.month, _now.day);
    final days = [for (var i = 0; i < 14; i++) start.add(Duration(days: i))];
    final earlier = plans.where((p) => p.day.compareTo(dayKey(start)) < 0).toList();
    Widget entry(PlanEntry p) {
      final o = byOutfit[p.outfitId];
      if (o == null) return const SizedBox.shrink();
      final owned = _repo.owned();
      final wearable = [
        for (final id in o.itemIds)
          if (owned.containsKey(id)) id,
      ];
      return Row(
        children: [
          Expanded(child: Text(o.name)),
          IconButton(
            tooltip: p.remind ? 'Reminder on. Tap to turn off' : 'Remind me that morning',
            icon: Icon(p.remind ? Icons.notifications_active : Icons.notifications_none, color: Tone.copper),
            onPressed: () {
              _repo.plan(p.day, p.outfitId, remind: !p.remind);
              _refresh();
            },
          ),
          IconButton(
            tooltip: 'Move to another day',
            icon: const Icon(Icons.event_repeat, color: Tone.copper),
            onPressed: () async {
              final to = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(p.day) ?? start,
                firstDate: start.subtract(const Duration(days: 365)),
                lastDate: start.add(const Duration(days: 730)),
              );
              if (to != null) {
                _repo.movePlan(p.day, dayKey(to), p.outfitId);
                _refresh();
              }
            },
          ),
          if (wearable.isNotEmpty && p.day.compareTo(dayKey(start)) <= 0)
            IconButton(
              tooltip: 'I wore this',
              icon: const Icon(Icons.checkroom_outlined, color: Tone.copper),
              onPressed: () {
                _repo.logWear(wearable, p.day);
                ToastHost.of(context)
                    .show(ToastKind.success, 'Logged ${wearable.length} items for ${p.day}.');
              },
            ),
          IconButton(
            tooltip: 'Remove from this day',
            icon: const Icon(Icons.close, color: Tone.inkSoft),
            onPressed: () {
              _repo.unplan(p.day, p.outfitId);
              _refresh();
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outfits.isEmpty)
          const Text('Make an outfit first, then plan it here.', style: TextStyle(color: Tone.inkSoft)),
        for (final d in days)
          Container(
            margin: const EdgeInsets.only(bottom: Space.s),
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
            decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${dayKey(d)}${d == start ? ' (today)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (outfits.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Plan outfit'),
                        onPressed: () async {
                          final id = await _pick<int>('Plan for ${dayKey(d)}', [
                            for (final o in outfits.where((o) => !o.mood)) (o.id, o.name),
                          ]);
                          if (id != null) {
                            _repo.plan(dayKey(d), id);
                            _refresh();
                          }
                        },
                      ),
                  ],
                ),
                for (final p in plans.where((p) => p.day == dayKey(d))) entry(p),
              ],
            ),
          ),
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          const SectionHeader('Earlier'),
          for (final p in earlier.reversed.take(10)) Text('${p.day}: ${byOutfit[p.outfitId]?.name ?? ''}'),
        ],
      ],
    );
  }

  // ---- Packing ----

  Widget _packing() {
    final lists = _repo.packLists();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            CopperButton(
              label: 'New packing list',
              icon: Icons.add,
              compact: true,
              onPressed: () async {
                final name = await _ask('New packing list', 'Trip name');
                if (name != null && name.isNotEmpty) {
                  _repo.savePackList(PackList(name: name));
                  _refresh();
                }
              },
            ),
            PaperButton(
              label: 'From planned days',
              icon: Icons.date_range,
              compact: true,
              onPressed: _packFromPlan,
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        if (lists.isEmpty)
          const Text(
            'A list can start from the outfits you planned for the trip dates.',
            style: TextStyle(color: Tone.inkSoft),
          ),
        for (final l in lists) _packCard(l),
      ],
    );
  }

  Future<void> _packFromPlan() async {
    final start = DateTime(_now.year, _now.month, _now.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: start.subtract(const Duration(days: 30)),
      lastDate: start.add(const Duration(days: 730)),
      initialDateRange: DateTimeRange(start: start, end: start.add(const Duration(days: 3))),
    );
    if (range == null || !mounted) return;
    final from = dayKey(range.start), to = dayKey(range.end);
    final ids = {
      for (final p in _repo.plans().where((p) => p.day.compareTo(from) >= 0 && p.day.compareTo(to) <= 0))
        p.outfitId,
    };
    final outfits = _repo.outfits().where((o) => ids.contains(o.id));
    final seen = <String>{};
    final items = [
      for (final o in outfits)
        for (final id in o.itemIds)
          if (_byId[id] != null && seen.add(id)) PackItem(label: _byId[id]!.name, productId: id),
    ];
    if (items.isEmpty) {
      ToastHost.of(context).show(ToastKind.info, 'No outfits are planned between $from and $to.');
      return;
    }
    _repo.savePackList(PackList(name: 'Trip $from to $to', items: items));
    _refresh();
  }

  Widget _packCard(PackList l) {
    void save(PackList next) {
      _repo.savePackList(next);
      _refresh();
    }

    final done = l.items.where((i) => i.packed).length;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.l),
      padding: const EdgeInsets.all(Space.m),
      decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l.name}: $done of ${l.items.length} packed',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          for (final (i, item) in l.items.indexed)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(item.label),
              value: item.packed,
              secondary: IconButton(
                tooltip: 'Remove ${item.label}',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => save(PackList(id: l.id, name: l.name, items: [...l.items]..removeAt(i))),
              ),
              onChanged: (v) => save(
                PackList(
                  id: l.id,
                  name: l.name,
                  items: [...l.items]..[i] = item.copyWith(packed: v ?? false),
                ),
              ),
            ),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              PaperButton(
                label: 'Add item',
                icon: Icons.add,
                compact: true,
                onPressed: () async {
                  final label = await _ask('Add to ${l.name}', 'Item');
                  if (label != null && label.isNotEmpty) {
                    save(
                      PackList(
                        id: l.id,
                        name: l.name,
                        items: [
                          ...l.items,
                          PackItem(label: label),
                        ],
                      ),
                    );
                  }
                },
              ),
              PaperButton(
                label: 'Add an outfit',
                icon: Icons.checkroom_outlined,
                compact: true,
                onPressed: () async {
                  final outfits = _repo.outfits();
                  if (outfits.isEmpty) return;
                  final o = await _pick<Outfit>('Add which outfit?', [for (final o in outfits) (o, o.name)]);
                  if (o == null) return;
                  final have = {for (final i in l.items) i.productId};
                  save(
                    PackList(
                      id: l.id,
                      name: l.name,
                      items: [
                        ...l.items,
                        for (final id in o.itemIds)
                          if (_byId[id] != null && !have.contains(id))
                            PackItem(label: _byId[id]!.name, productId: id),
                      ],
                    ),
                  );
                },
              ),
              PaperButton(
                label: 'Delete list',
                icon: Icons.delete_outline,
                compact: true,
                onPressed: () {
                  _repo.deletePackList(l.id);
                  _refresh();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
