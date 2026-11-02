import 'package:flutter/material.dart';

import 'dining_food.dart';
import 'dining_history.dart';
import 'dining_results_screen.dart';
import 'grocery_ui.dart';

/// Recent dining scans, newest first, each with when it was made.
class DiningHistoryScreen extends StatefulWidget {
  const DiningHistoryScreen({
    super.key,
    this.load = loadDiningScans,
    this.delete = deleteDiningScan,
  });

  final Future<List<DiningScan>> Function() load;
  final Future<void> Function(String id) delete;

  @override
  State<DiningHistoryScreen> createState() => _DiningHistoryScreenState();
}

class _DiningHistoryScreenState extends State<DiningHistoryScreen> {
  List<DiningScan>? _scans;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scans = await widget.load();
      if (!mounted) return;
      setState(() => _scans = scans);
    } catch (error) {
      debugPrint('Dining scan history not loaded: $error');
      if (!mounted) return;
      setState(
        () => _error = error is StateError
            ? error.message
            : 'Could not load scan history. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(DiningScan scan) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiningResultsScreen(
          foods: scan.foods,
          scanId: Future.value(scan.id),
          scannedAt: formatDiningScanTime(scan.createdAt),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(DiningScan scan) async {
    final when = formatDiningScanTime(scan.createdAt);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: Text(
          'The scan from $when will be removed from your history.',
          style: const TextStyle(fontSize: 20, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.delete(scan.id);
      if (!mounted) return;
      setState(() => _scans?.removeWhere((item) => item.id == scan.id));
      messenger.showSnackBar(const SnackBar(content: Text('Scan deleted.')));
    } catch (error) {
      debugPrint('Dining scan not deleted: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete the scan. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: RefreshIndicator(
                onRefresh: _fetch,
                child: ListView(
                  padding: groceryPagePadding(
                    context,
                  ).add(const EdgeInsets.only(top: 20, bottom: 32)),
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Scan history',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your recent dining scans, newest first. Tap a scan to see its foods again.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._body(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_loading && _scans == null) {
      return [
        Semantics(
          liveRegion: true,
          label: 'Loading scan history',
          child: const Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: const TextStyle(
              color: Color(0xFFFFB4A8),
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        GroceryGlowButton(onPressed: _fetch, child: const Text('Try again')),
      ];
    }
    final scans = _scans ?? const [];
    if (scans.isEmpty) {
      return [
        Semantics(
          liveRegion: true,
          child: const Text(
            'No scans yet. Foods you scan will show up here.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < scans.length; i++)
        _DiningScanCard(
          index: i + 1,
          total: scans.length,
          scan: scans[i],
          onTap: () => _open(scans[i]),
          onDelete: () => _confirmDelete(scans[i]),
        ),
    ];
  }
}

/// "3 foods: Cornbread, Falafel, Brussels Sprout Salad".
String diningScanSummary(List<DiningFood> foods) {
  final count = foods.length == 1 ? '1 food' : '${foods.length} foods';
  final names = [
    for (final food in foods)
      if (food.dishName.trim().isNotEmpty) food.dishName.trim(),
  ];
  return names.isEmpty ? count : '$count: ${names.join(', ')}';
}

class _DiningScanCard extends StatelessWidget {
  const _DiningScanCard({
    required this.index,
    required this.total,
    required this.scan,
    required this.onTap,
    required this.onDelete,
  });

  final int index;
  final int total;
  final DiningScan scan;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when = formatDiningScanTime(scan.createdAt);
    final summary = diningScanSummary(scan.foods);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GroceryListCardShell(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Scan $index of $total. $when. $summary.',
                hint: 'Opens the foods from this scan',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          when,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          summary,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete scan from $when',
              iconSize: 30,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              color: Colors.white,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
