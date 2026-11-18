import 'package:flutter/material.dart';

import '../services/zone_service.dart';
import 'theme.dart';

/// Type-ahead picker over the IANA zone database.
///
/// Dialog on tablet and desktop, full-height sheet on a phone, sharing one
/// body so the search behaves identically everywhere.
class ZoneSearchDialog extends StatefulWidget {
  const ZoneSearchDialog({
    super.key,
    required this.existing,
    required this.service,
  });

  final Set<String> existing;
  final ZoneService service;

  static Future<String?> show(
    BuildContext context, {
    required Set<String> existing,
    required ZoneService service,
  }) {
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.compactMax;
    Widget body(BuildContext sheetContext) =>
        ZoneSearchDialog(existing: existing, service: service);

    if (compact) {
      return showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: body(context),
          ),
        ),
      );
    }

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        content: SizedBox(width: 380, child: body(context)),
      ),
    );
  }

  @override
  State<ZoneSearchDialog> createState() => _ZoneSearchDialogState();
}

class _ZoneSearchDialogState extends State<ZoneSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<String> _results = const <String>[];
  String _query = '';

  ZoneService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _results = _suggest();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A few familiar zones make the dialog useful before typing anything.
  List<String> _suggest() => const <String>[
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Tokyo',
    'Asia/Kolkata',
    'Australia/Sydney',
    'Europe/Berlin',
    'Asia/Shanghai',
  ];

  void _onChanged(String value) {
    final trimmed = value.trim();
    setState(() {
      _query = trimmed;
      _results = trimmed.isEmpty
          ? _suggest()
          : _service.search(trimmed).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = _results
        .where((name) => !widget.existing.contains(name))
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Add a city', style: theme.textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('zone-search'),
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Tokyo, Berlin, New York…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
          onSubmitted: (value) {
            final match = available.isNotEmpty ? available.first : null;
            if (match != null) Navigator.of(context).pop(match);
          },
        ),
        const SizedBox(height: 12),
        if (available.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              _query.isEmpty
                  ? 'Timezone data is still loading.'
                  : 'No match for "$_query".',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: available.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final name = available[index];
                  return ListTile(
                    title: Text(_service.cityOf(name)),
                    subtitle: Text(
                      _service.regionOf(name).isEmpty
                          ? name
                          : _service.regionOf(name).replaceAll('_', ' '),
                    ),
                    leading: Icon(
                      Icons.language_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    trailing: Icon(
                      Icons.add_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => Navigator.of(context).pop(name),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
