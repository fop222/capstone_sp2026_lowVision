import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'dining_history_screen.dart';
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

  // Paddle OCR scan is hidden for now.
  // void _openPaddleScan(BuildContext context) {
  //   Navigator.of(context).push(
  //     MaterialPageRoute<void>(
  //       builder: (_) => const DiningScanScreen(paddleOnly: true),
  //     ),
  //   );
  // }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DiningHistoryScreen()),
    );
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
                    // Paddle OCR scan is hidden for now.
                    // const SizedBox(height: 14),
                    // Semantics(
                    //   button: true,
                    //   label: 'Scan with Paddle OCR',
                    //   hint: 'Reads the food signs only',
                    //   excludeSemantics: true,
                    //   child: GroceryGlowButton(
                    //     onPressed: () => _openPaddleScan(context),
                    //     child: const Row(
                    //       mainAxisAlignment: MainAxisAlignment.center,
                    //       children: [
                    //         Icon(Icons.text_snippet_outlined, size: 28),
                    //         SizedBox(width: 12),
                    //         Flexible(
                    //           child: Text(
                    //             'Scan with Paddle OCR',
                    //             textAlign: TextAlign.center,
                    //           ),
                    //         ),
                    //       ],
                    //     ),
                    //   ),
                    // ),
                    const SizedBox(height: 14),
                    Semantics(
                      button: true,
                      label: 'See scan history',
                      hint: 'Recent scans with the time each was made',
                      excludeSemantics: true,
                      child: OutlinedButton(
                        onPressed: () => _openHistory(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: kBrandPurpleLight.withValues(alpha: 0.8),
                            width: 2,
                          ),
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded, size: 28),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'See scan history',
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
