import 'package:flutter/material.dart';

/// Light, dark, or whatever the phone is set to.
enum StudioThemeMode { light, dark, system }

/// How round the studio's cards and buttons are.
enum StudioCorners { sharp, rounded, round }

/// The colours for one of the two modes. Anything left unset is worked out
/// from [accent] and the mode.
class StudioPalette {
  const StudioPalette(
      {this.accent, this.accentEnd, this.background, this.card});

  factory StudioPalette.fromJson(Map<String, dynamic>? j) => StudioPalette(
        accent: _hex(j?['accent']),
        accentEnd: _hex(j?['accentEnd']),
        background: _hex(j?['background']),
        card: _hex(j?['card']),
      );

  /// The brand colour: the main button, the selected tab, highlights.
  final Color? accent;

  /// What the main button fades into. Unset, a deeper shade of [accent].
  final Color? accentEnd;

  /// Behind everything.
  final Color? background;

  /// Cards, fields and options.
  final Color? card;

  StudioPalette merge(StudioPalette? over) => over == null
      ? this
      : StudioPalette(
          accent: over.accent ?? accent,
          accentEnd: over.accentEnd ?? accentEnd,
          background: over.background ?? background,
          card: over.card ?? card,
        );
}

/// How the studio looks: a light palette, a dark palette, which of them to
/// use, and the shape of things. Set on the widget key in StartupAid's
/// dashboard, so it can change without an app release; anything given in code
/// wins. Left unset, a field follows the dashboard, then the app's own theme.
class StudioTheme {
  const StudioTheme(
      {this.mode, this.corners, this.fontFamily, this.light, this.dark});

  factory StudioTheme.fromJson(Map<String, dynamic>? j) => StudioTheme(
        mode: switch (j?['mode']) {
          'light' => StudioThemeMode.light,
          'dark' => StudioThemeMode.dark,
          'system' => StudioThemeMode.system,
          _ => null,
        },
        corners: switch (j?['corners']) {
          'sharp' => StudioCorners.sharp,
          'rounded' => StudioCorners.rounded,
          'round' => StudioCorners.round,
          _ => null,
        },
        light: j?['light'] is Map<String, dynamic>
            ? StudioPalette.fromJson(j!['light'] as Map<String, dynamic>)
            : null,
        dark: j?['dark'] is Map<String, dynamic>
            ? StudioPalette.fromJson(j!['dark'] as Map<String, dynamic>)
            : null,
      );

  final StudioThemeMode? mode;
  final StudioCorners? corners;

  /// A font your app already bundles. Unset, the app's own.
  final String? fontFamily;

  /// Colours when the studio is light.
  final StudioPalette? light;

  /// Colours when the studio is dark.
  final StudioPalette? dark;

  /// This theme with [over]'s settings taking precedence.
  StudioTheme merge(StudioTheme? over) => over == null
      ? this
      : StudioTheme(
          mode: over.mode ?? mode,
          corners: over.corners ?? corners,
          fontFamily: over.fontFamily ?? fontFamily,
          light: (light ?? const StudioPalette()).merge(over.light),
          dark: (dark ?? const StudioPalette()).merge(over.dark),
        );
}

Color? _hex(Object? v) {
  if (v is! String) return null;
  final s = v.replaceFirst('#', '');
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

/// The resolved look the studio draws with.
class StudioLook {
  StudioLook._({
    required this.dark,
    required this.accent,
    required this.accentEnd,
    required this.onAccent,
    required this.background,
    required this.card,
    required this.field,
    required this.line,
    required this.text,
    required this.muted,
    required this.danger,
    required this.radius,
    required this.pill,
    required this.fontFamily,
  });

  factory StudioLook.resolve(BuildContext context, StudioTheme theme) {
    final host = Theme.of(context);
    final dark = switch (theme.mode) {
      StudioThemeMode.light => false,
      StudioThemeMode.dark => true,
      StudioThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      null => host.brightness == Brightness.dark,
    };
    final palette = (dark ? theme.dark : theme.light) ?? const StudioPalette();
    final accent = palette.accent ?? host.colorScheme.primary;
    final hsl = HSLColor.fromColor(accent);
    final accentEnd = palette.accentEnd ??
        hsl
            .withHue((hsl.hue + 18) % 360)
            .withLightness(
                (hsl.lightness * (dark ? 1.08 : 0.82)).clamp(0.0, 1.0))
            .toColor();
    // Text on the button: white or near-black, whichever reads better on the
    // middle of its gradient.
    final onAccent = _onColor(Color.lerp(accent, accentEnd, 0.5)!);

    // Neutrals with a breath of the accent in them, so the studio feels like
    // the brand's rather than a grey box dropped into it. A background or card
    // the account chose is used as given; the text then follows it.
    Color tint(Color base, double amount) => Color.lerp(base, accent, amount)!;
    final background = palette.background ??
        (dark
            ? tint(const Color(0xFF0B0C10), 0.04)
            : tint(const Color(0xFFF6F6F8), 0.03));
    final darkGround =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final card = palette.card ??
        (darkGround
            ? Color.lerp(background, Colors.white, 0.05)!
            : Color.lerp(background, Colors.white, 0.85)!);
    final text = darkGround ? const Color(0xFFF3F4F6) : const Color(0xFF111318);
    final radius = switch (theme.corners ?? StudioCorners.rounded) {
      StudioCorners.sharp => 6.0,
      StudioCorners.rounded => 16.0,
      StudioCorners.round => 26.0,
    };
    return StudioLook._(
      dark: darkGround,
      accent: accent,
      accentEnd: accentEnd,
      onAccent: onAccent,
      background: background,
      card: card,
      field: Color.lerp(card, darkGround ? Colors.white : Colors.black,
          darkGround ? 0.05 : 0.035)!,
      line: darkGround
          ? Colors.white.withValues(alpha: 0.09)
          : Colors.black.withValues(alpha: 0.08),
      text: text,
      muted: Color.lerp(text, background, 0.42)!,
      danger: darkGround ? const Color(0xFFFF8A8A) : const Color(0xFFD93636),
      radius: radius,
      pill: theme.corners == StudioCorners.round,
      fontFamily: theme.fontFamily ?? host.textTheme.bodyMedium?.fontFamily,
    );
  }

  static Color _onColor(Color c) {
    const ink = Color(0xFF111111);
    final l = c.computeLuminance();
    final onWhite = 1.05 / (l + 0.05);
    final onInk = (l + 0.05) / (ink.computeLuminance() + 0.05);
    return onWhite >= onInk ? Colors.white : ink;
  }

  final bool dark;
  final Color accent;
  final Color accentEnd;
  final Color onAccent;
  final Color background;
  final Color card;
  final Color field;
  final Color line;
  final Color text;
  final Color muted;
  final Color danger;
  final double radius;

  /// Buttons and options are fully round.
  final bool pill;
  final String? fontFamily;

  /// The Look as Film Maker's web page takes it ("look" in its options), so
  /// the web editor wears exactly the colours of the native tabs.
  Map<String, Object> toJson() {
    String css(Color c) => 'rgba(${(c.r * 255).round()},${(c.g * 255).round()},'
        '${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';
    return {
      'dark': dark,
      'accent': css(accent),
      'accentEnd': css(accentEnd),
      'onAccent': css(onAccent),
      'background': css(background),
      'card': css(card),
      'field': css(field),
      'line': css(line),
      'text': css(text),
      'muted': css(muted),
      'radius': radius,
      'pill': pill,
    };
  }

  double get buttonRadius => pill ? 999 : radius;
  double get chipRadius => pill ? 999 : (radius * 0.75).clamp(4, 14);
  BorderRadius get corners => BorderRadius.circular(radius);

  Gradient get gradient => LinearGradient(
      colors: [accent, accentEnd],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight);

  /// A ThemeData for the bits the studio borrows from Material (text fields,
  /// selection handles, progress indicators), in the studio's own colours.
  ThemeData material() {
    final scheme = ColorScheme.fromSeed(
            seedColor: accent,
            brightness: dark ? Brightness.dark : Brightness.light)
        .copyWith(
            primary: accent,
            onPrimary: onAccent,
            surface: card,
            onSurface: text,
            error: danger);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: fontFamily,
      textSelectionTheme: TextSelectionThemeData(
          cursorColor: accent,
          selectionHandleColor: accent,
          selectionColor: accent.withValues(alpha: 0.25)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    );
  }

  TextStyle style(double size,
          {FontWeight weight = FontWeight.w400,
          Color? color,
          double? height,
          double? spacing}) =>
      TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color ?? text,
          height: height,
          letterSpacing: spacing,
          fontFamily: fontFamily);
}
