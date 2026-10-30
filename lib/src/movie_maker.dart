import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'client.dart';
import 'models.dart';
import 'theme.dart';

/// Film Maker: StartupAid's own film editor, in a web view signed in as the
/// client's user. The page asks for its sign-in over the StartupAidBridge
/// channel and is handed it the same way a website hands it, never in the
/// URL.
///
/// It's the studio's Film Maker tab, and the body of [MovieMakerPage].
/// [bare] hides the page's own title bar, for when it sits under the
/// studio's header.
class MovieMakerView extends StatefulWidget {
  const MovieMakerView({
    super.key,
    required this.client,
    this.title = 'Film Maker',
    this.bare = false,
    this.look,
    this.priceLabel,
    this.onPicked,
    this.onClose,
  });

  final StudioClient client;
  final String title;
  final bool bare;

  /// The studio's resolved Look, so the editor wears the native tabs'
  /// colours. Without one, the page uses the widget key's.
  final StudioLook? look;

  /// The app's own prices, as in the studio: the page asks for the figures it
  /// shows, and these words stand in for credits.
  final String Function(int credits)? priceLabel;

  /// The film the user picked ("Use this film"): kind "film", with its url.
  final ValueChanged<StudioAsset>? onPicked;

  /// The page's own close button.
  final VoidCallback? onClose;

  @override
  State<MovieMakerView> createState() => _MovieMakerViewState();
}

class _MovieMakerViewState extends State<MovieMakerView> {
  late final WebViewController web;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final page = Uri.parse(
        '${widget.client.webUrl.replaceAll(RegExp(r'/+$'), '')}/embed/movie');
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('StartupAidBridge',
          onMessageReceived: (m) => onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => loading = false);
        },
        // Only StartupAid's own page: a link elsewhere opens nothing here.
        onNavigationRequest: (r) => Uri.parse(r.url).host == page.host
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..loadRequest(page);
  }

  Future<void> post(Map<String, Object?> msg) =>
      web.runJavaScript('window.postMessage(${jsonEncode(msg)}, "*");');

  Future<void> onMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'startupaid:ready':
        final String signature;
        try {
          signature = await widget.client
              .signatureForUser()
              .timeout(widget.client.timeout);
        } catch (_) {
          // The page says so and offers to close, rather than waiting on.
          await post({'type': 'startupaid:init-failed'});
          return;
        }
        await post({
          'type': 'startupaid:init',
          'publicKey': widget.client.publicKey,
          'userId': widget.client.userId,
          'signature': signature,
          'options': {
            'features': ['movies'],
            'title': widget.title,
            'bare': widget.bare,
            if (widget.look != null) 'look': widget.look!.toJson(),
            if (widget.priceLabel != null) 'prices': 'host',
          },
        });
      case 'startupaid:price-labels':
        final label = widget.priceLabel;
        final credits = msg['credits'];
        if (label == null || credits is! List) return;
        await post({
          'type': 'startupaid:price-labels',
          'labels': {
            for (final n in credits.whereType<num>().take(200))
              '${n.toInt()}': label(n.toInt()),
          },
        });
      case 'startupaid:selected':
        final asset = msg['asset'];
        if (asset is Map<String, dynamic>) {
          widget.onPicked?.call(StudioAsset.fromJson(asset));
        }
      case 'startupaid:close':
        widget.onClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      WebViewWidget(controller: web),
      if (loading)
        Center(
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: widget.look?.accent)),
    ]);
  }
}

/// Film Maker on its own page. Pops with the film the user picks, or null.
///
/// It reads the widget key's Look first, with [theme] over it, so it looks
/// like the studio would.
class MovieMakerPage extends StatefulWidget {
  const MovieMakerPage({
    super.key,
    required this.client,
    this.title = 'Film Maker',
    this.theme,
    this.priceLabel,
  });

  final StudioClient client;
  final String title;
  final StudioTheme? theme;
  final String Function(int credits)? priceLabel;

  @override
  State<MovieMakerPage> createState() => _MovieMakerPageState();
}

class _MovieMakerPageState extends State<MovieMakerPage> {
  StudioTheme? keyTheme;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    // Without the key's Look the page still opens, in the Look it resolves.
    widget.client
        .config()
        .then((c) => keyTheme = c.theme, onError: (_) => null)
        .whenComplete(() {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = keyTheme == null && widget.theme == null
        ? null
        : StudioLook.resolve(
            context, (keyTheme ?? const StudioTheme()).merge(widget.theme));
    final dark = look?.dark ??
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The status bar reads on the page's own ground.
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: look?.background,
        body: SafeArea(
          child: !ready
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : MovieMakerView(
                  client: widget.client,
                  title: widget.title,
                  look: look,
                  priceLabel: widget.priceLabel,
                  onPicked: (a) => Navigator.of(context).pop(a),
                  onClose: () => Navigator.of(context).pop(),
                ),
        ),
      ),
    );
  }
}
