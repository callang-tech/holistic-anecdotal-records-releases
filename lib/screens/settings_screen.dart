import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
final AppThemeController themeController;

const SettingsScreen({
super.key,
required this.themeController,
});

@override
State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
late AppThemePreset _selectedPreset;

@override
void initState() {
super.initState();
_selectedPreset = widget.themeController.preset;
}

Future<void> _selectTheme(AppThemePreset preset) async {
await widget.themeController.setPreset(preset);


if (!mounted) return;

setState(() {
  _selectedPreset = preset;
});


}

@override
Widget build(BuildContext context) {
final theme = Theme.of(context);
final colorScheme = theme.colorScheme;


return Scaffold(
  appBar: AppBar(
    title: const Text('Settings'),
  ),
  body: ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Appearance',
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        'Choose the visual theme of the application. '
        'This changes the on-screen interface only.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: RadioGroup<AppThemePreset>(
            groupValue: _selectedPreset,
            onChanged: (value) {
              if (value != null) {
                _selectTheme(value);
              }
            },
            child: Column(
              children: AppThemePreset.values.map((preset) {
                final selected = _selectedPreset == preset;

                return RadioListTile<AppThemePreset>(
                  value: preset,
                  title: Text(
                    preset.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _themeDescription(preset),
                  ),
                  activeColor: colorScheme.primary,
                  selected: selected,
                );
              }).toList(),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          leading: Icon(
            Icons.print_outlined,
            color: colorScheme.primary,
          ),
          title: const Text(
            'Printed Anecdotal Records',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'The printed anecdotal record keeps its '
            'standard institutional colors regardless '
            'of the selected application theme.',
          ),
        ),
      ),
    ],
  ),
);

}

String _themeDescription(AppThemePreset preset) {
switch (preset) {
case AppThemePreset.natureOffice:
return 'Relaxing sage, cream, and natural office tones.';
case AppThemePreset.coffeeWood:
return 'Warm coffee, wood, and earthy tones.';
case AppThemePreset.calmBlue:
return 'Calm and professional blue tones.';
case AppThemePreset.forest:
return 'Deeper botanical green tones.';
case AppThemePreset.softBloom:
return 'Soft and gentle floral-inspired tones.';
case AppThemePreset.warmSunrise:
return 'Warm, bright, and welcoming tones.';
case AppThemePreset.gentleLavender:
return 'Soft lavender and calming tones.';
case AppThemePreset.cleanProfessional:
return 'Simple, clean, professional appearance.';
case AppThemePreset.jolly:
return 'Brighter and more cheerful interface tones.';
case AppThemePreset.darkNature:
return 'Dark interface with natural green accents.';
}
}
}
