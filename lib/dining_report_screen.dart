import 'dart:async';

import 'package:flutter/material.dart';

import 'dining_food.dart';
import 'dining_history.dart';
import 'grocery_ui.dart';

typedef DiningReportSender =
    Future<void> Function({
      required DiningFood food,
      required List<String> problems,
      String note,
      String? scanId,
    });

/// Lets the user flag a food Lumio identified wrongly. Reports land in the
/// Supabase `dining_reports` table.
class DiningReportScreen extends StatefulWidget {
  const DiningReportScreen({
    super.key,
    required this.food,
    this.scanId,
    this.send = reportIncorrectDiningFood,
  });

  final DiningFood food;
  final Future<String?>? scanId;
  final DiningReportSender send;

  @override
  State<DiningReportScreen> createState() => _DiningReportScreenState();
}

class _DiningReportScreenState extends State<DiningReportScreen> {
  final Set<String> _problems = {};
  final TextEditingController _note = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_problems.isEmpty) {
      setState(() => _error = 'Choose at least one thing that looks wrong.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      String? scanId;
      try {
        scanId = await widget.scanId?.timeout(const Duration(seconds: 5));
      } catch (_) {
        scanId = null;
      }
      await widget.send(
        food: widget.food,
        problems: [
          for (final problem in kDiningReportProblems)
            if (_problems.contains(problem)) problem,
        ],
        note: _note.text,
        scanId: scanId,
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (error) {
      debugPrint('Dining report not sent: $error');
      if (!mounted) return;
      setState(
        () => _error =
            'Could not send the report. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Report incorrect result')),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: ListView(
                padding: groceryPagePadding(
                  context,
                ).add(const EdgeInsets.only(top: 20, bottom: 32)),
                children: _sent ? _thanks(theme) : _form(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _thanks(ThemeData theme) => [
    Semantics(
      header: true,
      liveRegion: true,
      child: Text(
        'Thank you. Your report was sent.',
        style: theme.textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    const SizedBox(height: 12),
    const Text(
      'It helps Lumio get better. Please confirm this food with dining staff before you eat.',
      style: TextStyle(color: Colors.white, fontSize: 20, height: 1.4),
    ),
    const SizedBox(height: 24),
    GroceryGlowButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Done'),
    ),
  ];

  List<Widget> _form(ThemeData theme) => [
    Semantics(
      header: true,
      child: Text(
        'What looks wrong?',
        style: theme.textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    const SizedBox(height: 8),
    Text(
      'Lumio said: ${widget.food.dishName}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 16),
    for (final problem in kDiningReportProblems)
      GroceryListCardShell(
        // The card's colour would hide the tile's ink without its own Material.
        child: Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            value: _problems.contains(problem),
            onChanged: _sending
                ? null
                : (checked) => setState(() {
                    checked == true
                        ? _problems.add(problem)
                        : _problems.remove(problem);
                    _error = null;
                  }),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              problem,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    const SizedBox(height: 8),
    TextField(
      controller: _note,
      enabled: !_sending,
      maxLines: 3,
      maxLength: 500,
      style: const TextStyle(color: Colors.white, fontSize: 20),
      decoration: const InputDecoration(
        labelText: 'What is it really? (optional)',
        labelStyle: TextStyle(color: Colors.white, fontSize: 20),
        hintText: 'For example: it is cornbread, it has milk',
        hintStyle: TextStyle(color: Colors.white60, fontSize: 18),
        border: OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white70, width: 2),
        ),
      ),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Text(
          _error!,
          style: const TextStyle(
            color: Color(0xFFFFB4A8),
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
    const SizedBox(height: 16),
    Semantics(
      button: true,
      label: _sending ? 'Sending report' : 'Send report',
      excludeSemantics: true,
      child: GroceryGlowButton(
        onPressed: _sending ? null : _submit,
        child: Text(_sending ? 'Sending…' : 'Send report'),
      ),
    ),
  ];
}
