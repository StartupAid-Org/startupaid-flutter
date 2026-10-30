import 'package:flutter/material.dart';
import 'package:startupaid_studio/startupaid_studio.dart';

import 'demo_studio.dart';
import 'tour.dart';

// The studio widget in a bare app. It runs against a pretend studio
// (demo_studio.dart); for the real thing, pass your widget key's public key
// and a signer, and leave out httpClient.
void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studio widget',
      navigatorKey: tourNavigator,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE11D48),
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final client = StudioClient(
    publicKey: 'pk_live_demo',
    userId: 'demo-user',
    signature: 'demo',
    httpClient: DemoStudio().client,
  );
  StudioAsset? picked;

  // Film Maker is StartupAid's own editor, so it needs a real widget key
  // (with Films on) and your server's signature for the user. With one, the
  // studio below is the real one too, with its Film Maker tab:
  //   flutter run --dart-define=STUDIO_KEY=pk_live_… \
  //     --dart-define=STUDIO_USER=… --dart-define=STUDIO_SIG=…
  // STUDIO_WEB and STUDIO_API point at a StartupAid site and API other than
  // startupaid.org's.
  static const _key = String.fromEnvironment('STUDIO_KEY');
  final films = _key.isEmpty
      ? null
      : StudioClient(
          publicKey: _key,
          userId: const String.fromEnvironment(
            'STUDIO_USER',
            defaultValue: 'demo-user',
          ),
          signature: const String.fromEnvironment('STUDIO_SIG'),
          webUrl: const String.fromEnvironment(
            'STUDIO_WEB',
            defaultValue: 'https://startupaid.org',
          ),
          baseUrl: const String.fromEnvironment(
            'STUDIO_API',
            defaultValue: 'https://api.startupaid.org',
          ),
        );

  Future<void> makeFilm() async {
    final f = films;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Film Maker needs a real widget key: run with --dart-define=STUDIO_KEY=…',
          ),
        ),
      );
      return;
    }
    final a = await StartupAidStudio.movieMaker(context, client: f);
    if (a != null) setState(() => picked = a);
  }

  @override
  void initState() {
    super.initState();
    startTourIfAsked(client);
  }

  Future<void> open() async {
    final a = await StartupAidStudio.show(
      context,
      client: films ?? client,
      // --dart-define=COINS=true: the app's own prices, as "coins".
      priceLabel: const bool.fromEnvironment('COINS')
          ? (credits) => '${credits * 2} coins'
          : null,
      prompt:
          'A striking portrait poster for a series called “Lagos After Dark”, a thriller. No text on the image.',
      imageSize: '3:4',
    );
    if (a != null) setState(() => picked = a);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My app')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (picked != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(picked!.previewUrl, height: 260),
              ),
              const SizedBox(height: 8),
              Text(
                'You picked a ${picked!.kind == 'film'
                    ? 'film'
                    : picked!.isVideo
                    ? 'clip'
                    : 'picture'}',
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: open,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Make with AI'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: makeFilm,
              icon: const Icon(Icons.movie_edit),
              label: const Text('Make a film'),
            ),
          ],
        ),
      ),
    );
  }
}
