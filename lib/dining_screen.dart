import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'dining_scan_screen.dart';
import 'grocery_ui.dart';

/// Dining home. Matches the grocery and recipe hubs, then opens a buffet scan.
class DiningScreen extends StatelessWidget {
  const DiningScreen({super.key});

  void _openScan(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DiningScanScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: const AppNavigationDrawer(),
      appBar: AppBar(title: const Text('Dining')),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: SingleChildScrollView(
                padding: groceryPagePadding(
                  context,
                ).add(const EdgeInsets.symmetric(vertical: 28)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Dining',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan a buffet, dining hall station, tray, or plate. Lumio lists each food and where it is in the photo.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Semantics(
                      button: true,
                      label: 'Scan buffet or food',
                      child: GroceryGlowButton(
                        onPressed: () => _openScan(context),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_camera_outlined, size: 28),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Scan Buffet / Food',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'A sign is used when Lumio can read it. If there is no sign, names and allergens are estimates. Please confirm with dining staff before you eat.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
