import '../widgets/password_gate.dart';
import 'package:flutter/material.dart';

import '../widgets/app_background.dart';
import '../widgets/sync_status_bar.dart';
import '../services/school_settings_service.dart';
import 'about_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _schoolName = SchoolSettingsService.defaultSchoolName;

  @override
  void initState() {
    super.initState();
    _loadSchoolName();
  }

  Future<void> _loadSchoolName() async {
    final schoolName = await SchoolSettingsService.instance.getSchoolName();

    if (!mounted) return;

    setState(() {
      _schoolName = schoolName;
    });
  }

  Future<void> _open(
    BuildContext context,
    String route,
  ) async {
    final allowed = await PasswordGate.request(context);

    if (allowed && context.mounted) {
      await Navigator.pushNamed(context, route);

      if (context.mounted) {
        await _loadSchoolName();
      }
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.pushNamed(context, '/settings');
  }

  void _openAbout(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const AboutScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 680,
                          ),
                          child: _buildHomePanel(context),
                        ),
                      ),
                    ),
                  ),
                  const SyncStatusBar(),
                ],
              ),

              // About and Settings buttons
              Positioned(
                top: 12,
                right: 16,
                child: Row(
                  children: [
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.90),
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        tooltip: 'About',
                        icon: const Icon(Icons.info_outline_rounded),
                        color: Theme.of(context).colorScheme.primary,
                        iconSize: 25,
                        onPressed: () => _openAbout(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.90),
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings_rounded),
                        color: Theme.of(context).colorScheme.primary,
                        iconSize: 25,
                        onPressed: () => _openSettings(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomePanel(
    BuildContext context,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 36,
        vertical: 40,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(
          alpha: 0.88,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colors.outline.withValues(
            alpha: 0.35,
          ),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(
              alpha: 0.12,
            ),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Developer-controlled application branding.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primary.withValues(
                alpha: 0.12,
              ),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/about/app_logo.png',
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              semanticLabel: 'Holistic Anecdotal Records logo',
            ),
          ),

          const SizedBox(height: 20),

          Text(
            _schoolName.toUpperCase(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                  letterSpacing: 0.5,
                ),
          ),

          const SizedBox(height: 6),

          Text(
            'Holistic Educational Anecdotal '
            'Record & Tracking System',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
          ),

          const SizedBox(height: 36),

          // View / Search Records
          _homeButton(
            label: 'View / Search Records',
            icon: Icons.search_rounded,
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            onPressed: () => _open(context, '/search'),
          ),

          const SizedBox(height: 14),

          // Add Learner Record
          _homeButton(
            label: 'Add Learner Record',
            icon: Icons.person_add_alt_1_rounded,
            backgroundColor: colors.secondaryContainer,
            foregroundColor: colors.onSecondaryContainer,
            onPressed: () => _open(context, '/add-learner'),
          ),

          const SizedBox(height: 14),

          // Teachers / Sections
          _homeButton(
            label: 'Teachers / Sections',
            icon: Icons.groups_rounded,
            backgroundColor: colors.surfaceContainerHighest,
            foregroundColor: colors.onSurfaceVariant,
            hasBorder: true,
            onPressed: () => _open(context, '/admin'),
          ),

          const SizedBox(height: 14),

          // Admin
          _homeButton(
            label: 'Admin',
            icon: Icons.admin_panel_settings_rounded,
            backgroundColor: colors.tertiaryContainer,
            foregroundColor: colors.onTertiaryContainer,
            hasBorder: true,
            onPressed: () => _open(context, '/admin-tools'),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _homeButton({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    bool hasBorder = false,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          side: hasBorder
              ? BorderSide(
                  color: foregroundColor.withValues(alpha: 0.25),
                  width: 1.2,
                )
              : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: foregroundColor,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
