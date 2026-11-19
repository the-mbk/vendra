// ══════════════════════════════════════════════════════════════
// Vendra App - Theme mode (System default | Light | Dark)
// ThemeCubit holds the user's choice and persists it with
// shared_preferences. ThemeScope (MaterialApp.builder) points the
// AppColors tokens at the resolved brightness and, when it flips,
// rebuilds every mounted widget so screens, dialogs and sheets switch
// together without losing their state.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  static const _prefsKey = 'vendra.theme_mode';

  ThemeCubit([super.initial = ThemeMode.system]);

  /// The saved choice, read before the first frame so the app starts in it
  static Future<ThemeMode> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    } catch (_) {
      return ThemeMode.system; // storage unavailable (e.g. private browsing)
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    emit(mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // The choice still applies for this session
    }
  }

  /// App-bar shortcut: flips to the opposite of what is on screen now
  Future<void> toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

/// Sits under MaterialApp (builder) and keeps the AppColors tokens in step with the theme
class ThemeScope extends StatefulWidget {
  final Widget child;
  const ThemeScope({super.key, required this.child});

  @override
  State<ThemeScope> createState() => _ThemeScopeState();
}

class _ThemeScopeState extends State<ThemeScope> {
  Brightness? _applied;

  static void _rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_rebuild);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness != _applied) {
      final firstBuild = _applied == null;
      _applied = brightness;
      applyThemeBrightness(brightness);
      // Widgets that read AppColors directly don't depend on Theme, so mark them
      // all dirty; they rebuild in this same frame (descendants of this build)
      if (!firstBuild) (context as Element).visitChildren(_rebuild);
    }
    return widget.child;
  }
}

/// App-bar sun / moon icon that flips between light and dark
class ThemeToggleButton extends StatelessWidget {
  final Color? color;
  const ThemeToggleButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      color: color,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => context.read<ThemeCubit>().toggle(Theme.of(context).brightness),
    );
  }
}

/// Profile / settings row: "Theme: System default | Light | Dark"
class ThemeModeTile extends StatelessWidget {
  final EdgeInsetsGeometry? contentPadding;
  const ThemeModeTile({super.key, this.contentPadding});

  static const _labels = {
    ThemeMode.system: 'System default',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeCubit>().state;
    return ListTile(
      contentPadding: contentPadding,
      leading: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          color: AppColors.textSecondary),
      title: const Text('Theme'),
      subtitle: Text(_labels[mode]!, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choose(context, mode),
    );
  }

  Future<void> _choose(BuildContext context, ThemeMode current) async {
    final cubit = context.read<ThemeCubit>();
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (m) => Navigator.pop(ctx, m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Theme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              for (final entry in _labels.entries)
                RadioListTile<ThemeMode>(value: entry.key, title: Text(entry.value)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await cubit.setMode(picked);
  }
}
