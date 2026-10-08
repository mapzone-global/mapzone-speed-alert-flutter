import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vietmap_search.dart';

/// A place the user has picked before. Kept in memory only — the MapZone Android
/// app persists its history, but that would pull a storage dependency into an
/// example whose point is the alert engine.
class SearchHistoryEntry {
  const SearchHistoryEntry({required this.refId, required this.display});
  final String refId;
  final String display;
}

/// Destination search over the VietMap autocomplete/place v4 API.
///
/// Typing is debounced by 400 ms and needs two characters, matching the MapZone
/// Android app — without it every keystroke fires a request.
class DestinationSearchBar extends StatefulWidget {
  const DestinationSearchBar({
    super.key,
    required this.destinationLabel,
    required this.onSelected,
    required this.onCleared,
  });

  /// Currently chosen destination, or null when navigating on GPS alone.
  final String? destinationLabel;
  final ValueChanged<SearchResult> onSelected;
  final VoidCallback onCleared;

  @override
  State<DestinationSearchBar> createState() => _DestinationSearchBarState();
}

class _DestinationSearchBarState extends State<DestinationSearchBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<SearchHistoryEntry> _history = [];

  Timer? _debounce;
  List<SearchResult> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final r = await VietmapSearch.autocomplete(text);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    });
  }

  void _pick(SearchResult r) {
    _text.text = r.display;
    _focus.unfocus();
    setState(() {
      _results = const [];
      _history
        ..removeWhere((h) => h.refId == r.refId)
        ..insert(0, SearchHistoryEntry(refId: r.refId, display: r.display));
      if (_history.length > 10) _history.removeLast();
    });
    widget.onSelected(r);
  }

  void _clear() {
    _text.clear();
    setState(() => _results = const []);
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final showHistory = _focus.hasFocus &&
        _text.text.isEmpty &&
        _results.isEmpty &&
        _history.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(28),
          color: Theme.of(context).colorScheme.surface,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tìm địa chỉ, điểm đến…',
              prefixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search),
              suffixIcon: _text.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clear,
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_results.isNotEmpty)
          _dropdown(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                leading: Icon(Icons.location_on,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(_results[i].display,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _pick(_results[i]),
              ),
            ),
            maxHeight: 320,
          )
        else if (showHistory)
          _dropdown(
            maxHeight: 200,
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text('Lịch sử tìm kiếm',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
                ..._history.map(
                  (h) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, color: Colors.grey),
                    title: Text(h.display,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(
                        SearchResult(refId: h.refId, display: h.display)),
                  ),
                ),
              ],
            ),
          )
        else if (widget.destinationLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 16),
            child: Text(
              'Điểm đến: ${widget.destinationLabel}',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.white, blurRadius: 4)],
              ),
            ),
          ),
      ],
    );
  }

  Widget _dropdown({required Widget child, required double maxHeight}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
