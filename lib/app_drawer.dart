/// Global navigation drawer — shown as a hamburger menu on all main screens.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'grocery_list_screen.dart';
import 'grocery_ui.dart';
import 'home_landing_screen.dart';
import 'profile_setup_screen.dart';
import 'recipe_list_screen.dart';
import 'supabase_auth_screen.dart';
import 'surprise_me_state.dart';

/// Navigation drawer with Home, Grocery Lists, Recipes, Profile, Log Out.
///
/// Attach this to any [Scaffold] as its [Scaffold.drawer].  Flutter
/// automatically shows a hamburger (≡) icon in the [AppBar.leading]
/// position whenever a [Scaffold] has a drawer.
class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({super.key});

  Future<void> _signOut(BuildContext context) async {
    clearRecommendedRecipes();
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const SupabaseAuthScreen(),
      ),
      (_) => false,
    );
  }

  /// Pop the drawer, then push [destination] as the root of the stack.
  void _goRoot(BuildContext context, Widget destination) {
    Navigator.of(context).pop(); // close drawer
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => destination),
      (_) => false,
    );
  }

  /// Pop the drawer, then push [destination] on top of the current stack
  /// (used for Profile since the user expects to be able to go back).
  void _goPush(BuildContext context, Widget destination) {
    Navigator.of(context).pop(); // close drawer
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      backgroundColor: const Color(0xFF14162A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── App identity header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Row(
                children: [
                  const GroceryProfilePersonBadge(size: 52),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lumio',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Low Vision Daily Companion',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 4),

            // ── Navigation items ─────────────────────────────────────────
            _DrawerNavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              onTap: () => _goRoot(context, const HomeLandingScreen()),
            ),
            _DrawerNavItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Grocery Lists',
              onTap: () => _goRoot(context, const GroceryListScreen()),
            ),
            _DrawerNavItem(
              icon: Icons.soup_kitchen_outlined,
              label: 'Recipes',
              onTap: () => _goRoot(context, const RecipeListScreen()),
            ),
            _DrawerNavItem(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
              onTap: () => _goPush(
                context,
                const ProfileSetupScreen(isEditing: true),
              ),
            ),

            const Spacer(),
            Divider(color: Colors.white.withValues(alpha: 0.1)),

            // ── Log Out (bottom) ──────────────────────────────────────────
            _DrawerNavItem(
              icon: Icons.logout_rounded,
              label: 'Log Out',
              color: const Color(0xFFFF6B6B),
              onTap: () => _signOut(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── _DrawerNavItem ───────────────────────────────────────────────────────────

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: ListTile(
        leading: Icon(icon, color: c, size: 28),
        title: Text(
          label,
          style: TextStyle(
            color: c,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        minLeadingWidth: 32,
      ),
    );
  }
}
