import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'feedback.dart';
import 'paper.dart';

/// Web links in a note, in the order written, without repeats.
List<String> linksIn(String text) => {
  for (final m in RegExp(r'https?://[^\s<>"]+', caseSensitive: false).allMatches(text))
    m.group(0)!.replaceAll(RegExp(r'[.,;:!?)\]]+$'), ''),
}.toList();

/// The owner's note on a find, and their corrections to its details. Both
/// are kept apart from what the store published, so a refresh never loses
/// them and the store's own value is one tap away.
class NotesPanel extends StatefulWidget {
  const NotesPanel({
    super.key,
    required this.product,
    required this.repository,
    required this.onChanged,
    required this.onOpenLink,
  });
  final Product product;
  final CatalogRepository repository;
  final void Function(Product) onChanged;
  final void Function(String) onOpenLink;
  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  late Product _p = widget.product;
  late final _note = TextEditingController(text: widget.repository.noteFor(_p.id));
  late String _savedNote = _note.text;
  String? _editing;
  String? _error;
  final _edit = TextEditingController();

  static const _labels = {
    'name': 'Name',
    'brand': 'Brand',
    'color': 'Colour',
    'material': 'Material',
    'sizes': 'Sizes (comma separated)',
    'description': 'Description',
  };

  @override
  void dispose() {
    _note.dispose();
    _edit.dispose();
    super.dispose();
  }

  void _saveNote() {
    try {
      widget.repository.setNote(_p.id, _note.text);
      FeedbackScope.of(context).play(Cue.toggle);
      setState(() {
        _savedNote = _note.text.trim();
        _error = null;
      });
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    } on Object {
      setState(() => _error = 'Your note could not be saved. Please try again.');
    }
  }

  String _show(Object? value) => switch (value) {
    null => '(empty)',
    List v when v.isEmpty => '(empty)',
    List v => v.join(', '),
    String v when v.isEmpty => '(empty)',
    _ => '$value',
  };

  void _apply(Product Function() change) {
    try {
      final next = change();
      FeedbackScope.of(context).play(Cue.toggle);
      setState(() {
        _p = next;
        _editing = null;
        _error = null;
      });
      widget.onChanged(next);
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    } on Object {
      setState(() => _error = 'Your change could not be saved. Please try again.');
    }
  }

  void _startEdit(String field) {
    final value = _p.toJson()[field];
    _edit.text = value is List ? value.join(', ') : (value as String? ?? '');
    setState(() {
      _editing = field;
      _error = null;
    });
  }

  void _commit(String field) => _apply(
    () => widget.repository.correct(
      _p,
      field,
      field == 'sizes' ? _edit.text.split(',').map((s) => s.trim()).toList() : _edit.text,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final edits = widget.repository.editsFor(_p.id);
    final links = linksIn(_savedNote);
    final dirty = _note.text.trim() != _savedNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Your notes'),
        const SizedBox(height: Space.s),
        const Text(
          'Sizes to ask about, a discount code, links. Only on your devices; refreshes never change it.',
          style: TextStyle(fontSize: 12.5, color: Tone.inkSoft),
        ),
        const SizedBox(height: Space.m),
        PaperField(
          controller: _note,
          label: 'Note',
          maxLines: 5,
          maxLength: maxNoteLength,
          onChanged: (_) => setState(() {}),
        ),
        if (dirty || links.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (dirty)
                CopperButton(label: 'Save note', icon: Icons.check, compact: true, onPressed: _saveNote),
              for (final link in links)
                PaperButton(
                  label: Uri.tryParse(link)?.host ?? link,
                  icon: Icons.north_east,
                  compact: true,
                  onPressed: () => widget.onOpenLink(link),
                ),
            ],
          ),
        ],
        const SizedBox(height: Space.xl),
        const SectionHeader('Correct the details'),
        const SizedBox(height: Space.s),
        const Text(
          'Fix what the store got wrong. Your version is kept when the item is refreshed. Prices and stock stay as the store reports them.',
          style: TextStyle(fontSize: 12.5, color: Tone.inkSoft),
        ),
        const SizedBox(height: Space.s),
        for (final field in editableFields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: _editing == field
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PaperField(
                        controller: _edit,
                        label: _labels[field]!,
                        autofocus: true,
                        maxLines: field == 'description' ? 6 : 1,
                        onSubmitted: field == 'description' ? null : (_) => _commit(field),
                      ),
                      const SizedBox(height: Space.s),
                      Wrap(
                        spacing: Space.s,
                        children: [
                          CopperButton(
                            label: 'Save',
                            icon: Icons.check,
                            compact: true,
                            onPressed: () => _commit(field),
                          ),
                          PaperButton(
                            label: 'Cancel',
                            compact: true,
                            onPressed: () => setState(() => _editing = null),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _labels[field]!.split(' (').first,
                              style: const TextStyle(color: Tone.inkSoft, fontSize: 12.5),
                            ),
                            Text(
                              _show(_p.toJson()[field]),
                              maxLines: field == 'description' ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (edits.containsKey(field))
                              Text(
                                'Edited by you · the store says: ${_show(edits[field])}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Tone.copper),
                              ),
                          ],
                        ),
                      ),
                      if (edits.containsKey(field))
                        PaperIconButton(
                          icon: Icons.undo,
                          tooltip: 'Use the store’s ${_labels[field]!.split(' (').first.toLowerCase()}',
                          size: 34,
                          onPressed: () => _apply(() => widget.repository.useStoreValue(_p, field)),
                        ),
                      PaperIconButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit ${_labels[field]!.split(' (').first.toLowerCase()}',
                        size: 34,
                        onPressed: () => _startEdit(field),
                      ),
                    ],
                  ),
          ),
        if (_error != null) ...[
          const SizedBox(height: Space.s),
          Text(_error!, style: const TextStyle(color: Tone.error, fontSize: 12.5)),
        ],
      ],
    );
  }
}
