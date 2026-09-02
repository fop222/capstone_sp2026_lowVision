import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'grocery_list_screen.dart';
import 'grocery_ui.dart';
import 'profile_setup_screen.dart';
import 'supabase_auth_screen.dart';

/// Top-level home after sign-in: choose Shopping, Cooking, or Eating.
class HomeLandingScreen extends StatelessWidget {
  const HomeLandingScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SupabaseAuthScreen()),
    );
  }

  void _openShopping(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroceryListScreen()),
    );
  }

  void _comingSoon(BuildContext context, String mode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$mode is coming soon.',
          style: const TextStyle(fontSize: 18, color: Color(0xFF232733)),
        ),
        backgroundColor: kAccentMint,
      ),
    );
  }

  Widget _modeButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final glow = accent ?? kBrandPurpleMid;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  glow.withValues(alpha: 0.95),
                  glow.withValues(alpha: 0.72),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, size: 36, color: Colors.white),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 32,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Lumio',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          Tooltip(
            message: 'Edit profile',
            child: IconButton(
              icon: const Icon(Icons.person_outline, size: 32),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProfileSetupScreen(isEditing: true),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Sign out',
            child: IconButton(
              icon: const Icon(Icons.logout, size: 28),
              onPressed: () => _signOut(context),
            ),
          ),
        ],
      ),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: SingleChildScrollView(
                padding: groceryPagePadding(context).add(
                  const EdgeInsets.symmetric(vertical: 32),
                ),
                child: Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'What would you like to do?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _modeButton(
                      context: context,
                      label: 'SHOPPING',
                      icon: Icons.shopping_cart_outlined,
                      onPressed: () => _openShopping(context),
                    ),
                    const SizedBox(height: 18),
                    _modeButton(
                      context: context,
                      label: 'COOKING',
                      icon: Icons.restaurant_menu_outlined,
                      accent: const Color(0xFF3AE4C2),
                      onPressed: () => _comingSoon(context, 'Cooking'),
                    ),
                    const SizedBox(height: 18),
                    _modeButton(
                      context: context,
                      label: 'EATING',
                      icon: Icons.restaurant_outlined,
                      accent: const Color(0xFFFF8C5A),
                      onPressed: () => _comingSoon(context, 'Eating'),
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
