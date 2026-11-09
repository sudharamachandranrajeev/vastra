import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../data/look_service.dart';
import '../domain/look.dart';
import '../domain/product.dart';
import '../domain/tag_suggestions.dart';
import 'app.dart' show ProductPhoto;
import 'feedback.dart';
import 'paper.dart';

/// Finds catalog items whose photos share the colours and pattern of a query
/// photo. Everything is worked out on this device.
class LookSearchSheet extends StatefulWidget {
  const LookSearchSheet({
    super.key,
    required this.query,
    required this.label,
    required this.candidates,
    required this.service,
    required this.onOpen,
  });

  /// Reads the query photo; throws a FormatException it cannot.
  final Future<LookDescriptor> Function() query;

  /// What the query is, as in "Similar to <label>".
  final String label;
  final List<Product> candidates;
  final LookService service;
  final void Function(Product) onOpen;
  @override
  State<LookSearchSheet> createState() => _LookSearchSheetState();
}

class _LookSearchSheetState extends State<LookSearchSheet> {
  int _done = 0, _total = 0;
  String? _error;
  List<(Product, double)>? _results;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final query = await widget.query();
      final looks = await widget.service.prepare(
        widget.candidates,
        progress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
      final byId = {for (final p in widget.candidates) p.id: p};
      if (mounted) {
        setState(() => _results = [for (final (id, d) in rankByLook(query, looks)) (byId[id]!, d)]);
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'That photo could not be read.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return PaperSheet(
      maxWidth: 720,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Similar to ${widget.label}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Space.xs),
          const Text(
            'Matched by colour and pattern, worked out on this device. It does not see shape or cut.',
            style: TextStyle(color: Tone.inkSoft, fontSize: 12.5),
          ),
          const SizedBox(height: Space.l),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Tone.copper))
          else if (results == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                const SizedBox(height: Space.s),
                Text(
                  _total == 0 ? 'Reading the photo…' : 'Reading catalog photos: $_done of $_total',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            )
          else if (results.isEmpty)
            const Text('Nothing in your catalog or the samples looks close enough.')
          else
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: Space.m,
                  runSpacing: Space.m,
                  children: [
                    for (final (p, d) in results)
                      SizedBox(
                        width: 150,
                        height: 230,
                        child: Pressable(
                          onTap: () => widget.onOpen(p),
                          cue: Cue.open,
                          padding: const EdgeInsets.all(Space.s),
                          semanticLabel: 'View ${p.name}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(Radii.xs),
                                  child: ProductPhoto(p),
                                ),
                              ),
                              const SizedBox(height: Space.s),
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              Text(closeness(d), style: const TextStyle(fontSize: 11.5, color: Tone.copper)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.l),
          Align(
            alignment: Alignment.centerRight,
            child: PaperButton(label: 'Close', compact: true, onPressed: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

/// Colour, material and pattern for an item, with suggestions for the ones
/// the store left out. Suggestions are kept apart from what the store
/// published until the owner accepts, edits or dismisses them.
class DetailsPanel extends StatefulWidget {
  const DetailsPanel({
    super.key,
    required this.product,
    required this.repository,
    required this.service,
    required this.onChanged,
  });
  final Product product;
  final CatalogRepository repository;
  final LookService service;
  final void Function(Product) onChanged;
  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  late Product _p = widget.product;
  String? _editing;
  bool _reading = false;
  final _edit = TextEditingController();

  @override
  void dispose() {
    _edit.dispose();
    super.dispose();
  }

  LookDescriptor? get _look {
    final hit = widget.repository.looks()[_p.id];
    return hit != null && hit.image == LookService.imageOf(_p) ? hit.look : null;
  }

  List<TagSuggestion> _suggestions(Map<String, bool> choices) {
    final look = _look;
    final merged = <String, TagSuggestion>{};
    for (final s in [...suggestFromText(_p), if (look != null) ...suggestFromLook(_p, look)]) {
      if (choices.containsKey(s.key)) continue;
      final had = merged[s.key];
      merged[s.key] = had == null
          ? s
          : TagSuggestion(s.field, s.value, had.source, '${had.reason} ${s.reason}');
    }
    return merged.values.toList();
  }

  void _changed(Product p, Cue cue) {
    FeedbackScope.of(context).play(cue);
    setState(() {
      _p = p;
      _editing = null;
    });
    widget.onChanged(p);
  }

  Future<void> _readPhoto() async {
    setState(() => _reading = true);
    await widget.service.prepare([_p]);
    if (mounted) setState(() => _reading = false);
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.repository.tagChoices(_p.id);
    final suggestions = _suggestions(choices);
    final json = _p.toJson();
    final cachedLook = widget.repository.looks()[_p.id];
    final canRead =
        LookService.imageOf(_p) != null &&
        (cachedLook == null || cachedLook.image != LookService.imageOf(_p));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Details'),
        const SizedBox(height: Space.m),
        for (final field in tagFields)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(fieldLabel(field), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(switch (json[field] as String?) {
                    null || '' => 'Not stated',
                    final v when choices['$field|$v'] == true => '$v (you chose)',
                    final v => '$v (from the store)',
                  }, style: const TextStyle(fontSize: 13)),
                ),
                if (choices['$field|${json[field]}'] == true)
                  PaperIconButton(
                    icon: Icons.close,
                    tooltip: 'Clear ${fieldLabel(field).toLowerCase()}',
                    onPressed: () => _changed(widget.repository.clearTag(_p, field), Cue.toggle),
                  ),
              ],
            ),
          ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          const Text('Suggested', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: Space.xs),
          for (final s in suggestions)
            Container(
              margin: const EdgeInsets.only(bottom: Space.s),
              padding: const EdgeInsets.all(Space.m),
              decoration: paperDecoration(surface: Surface.inset, radius: Radii.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fieldLabel(s.field)}: ${s.value}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${s.reason} ${s.source == 'photo' ? 'From the photo.' : 'From the item text.'}',
                    style: const TextStyle(color: Tone.inkSoft, fontSize: 12),
                  ),
                  const SizedBox(height: Space.s),
                  if (_editing == s.key) ...[
                    PaperField(controller: _edit, label: fieldLabel(s.field), maxLength: 40),
                    Wrap(
                      spacing: Space.s,
                      children: [
                        CopperButton(
                          label: 'Save',
                          icon: Icons.check,
                          compact: true,
                          onPressed: () {
                            final v = _edit.text.trim();
                            if (v.isEmpty) return;
                            _changed(widget.repository.acceptTag(_p, s.field, v), Cue.success);
                          },
                        ),
                        PaperButton(
                          label: 'Cancel',
                          compact: true,
                          onPressed: () => setState(() => _editing = null),
                        ),
                      ],
                    ),
                  ] else
                    Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        CopperButton(
                          label: 'Use it',
                          icon: Icons.check,
                          compact: true,
                          onPressed: () =>
                              _changed(widget.repository.acceptTag(_p, s.field, s.value), Cue.success),
                        ),
                        PaperButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          compact: true,
                          onPressed: () => setState(() {
                            _editing = s.key;
                            _edit.text = s.value;
                          }),
                        ),
                        PaperButton(
                          label: 'Not right',
                          icon: Icons.close,
                          compact: true,
                          onPressed: () {
                            widget.repository.dismissTag(_p.id, s.field, s.value);
                            FeedbackScope.of(context).play(Cue.toggle);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
        if (canRead && tagFields.any((f) => (json[f] as String? ?? '').isEmpty))
          Align(
            alignment: Alignment.centerLeft,
            child: PaperButton(
              label: _reading ? 'Reading the photo…' : 'Suggest from the photo',
              icon: Icons.palette_outlined,
              compact: true,
              onPressed: _reading ? null : _readPhoto,
            ),
          ),
        const SizedBox(height: Space.xs),
        const Text(
          'Suggestions are worked out on this device from the item’s words and photo. Nothing is sent anywhere, and nothing changes until you choose.',
          style: TextStyle(color: Tone.inkSoft, fontSize: 11.5),
        ),
      ],
    );
  }
}
