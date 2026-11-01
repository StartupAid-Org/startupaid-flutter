import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:startupaid_studio/startupaid_studio.dart';
import 'package:startupaid_studio/src/theme.dart' show StudioLook;

// A pretend studio: sessions, config, pictures. It counts sessions and can
// make the next request look like a lapsed one.
class FakeStudio {
  int sessions = 0;
  bool expireNext = false;
  final signatures = <String>[];
  final images = <Map<String, dynamic>>[];
  Map<String, dynamic>? display;
  List<Map<String, dynamic>> extraImageModels = [];
  Map<String, dynamic>? talking;
  final calls = <String>[];

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (path == '/widget/v1/session') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      signatures.add(body['signature'] as String);
      sessions++;
      return http.Response(
          jsonEncode({
            'token': 't$sessions',
            'expiresAt':
                DateTime.now().add(const Duration(hours: 2)).toIso8601String()
          }),
          200);
    }
    if (req.headers['Authorization'] != 'Bearer t$sessions' || expireNext) {
      expireNext = false;
      return http.Response(
          jsonEncode({'error': 'Your studio session has ended.'}), 401);
    }
    switch (path) {
      case '/widget/v1/uploads':
        calls.add('upload');
        return http.Response(
            jsonEncode({
              'asset': {
                'id': 'up1',
                'kind': 'upload',
                'status': 'ready',
                'url': 'https://cdn.test/me.png'
              }
            }),
            200);
      case '/widget/v1/talking/presenters':
        calls.add('presenter:${req.body}');
        return http.Response(
            jsonEncode({
              'presenter': {
                'id': 'own-9',
                'name': 'Ada',
                'role': 'Yours',
                'imageUrl': ''
              }
            }),
            201);
      case '/widget/v1/config':
        return http.Response(
            jsonEncode({
              'features': ['images', if (talking != null) 'talking'],
              if (display != null) 'display': display,
              if (talking != null) 'talking': talking,
              'budget': {
                'dailyCredits': 150,
                'usedToday': images.length * 30,
                'remaining': 150 - images.length * 30
              },
              'images': {
                'enabled': true,
                'models': [
                  {
                    'id': 'still',
                    'label': 'Standard',
                    'credits': 30,
                    'mode': 'text',
                    'sizable': true,
                    'maxImages': 4
                  },
                  ...extraImageModels,
                ],
                'sizes': ['1:1', '3:4'],
                'maxCount': 4,
              },
            }),
            200);
      case '/widget/v1/images':
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if ((body['prompt'] as String).contains('too much')) {
          return http.Response(
              jsonEncode({
                'error': 'That needs 120 credits and you have 30 left today.'
              }),
              402);
        }
        final made = {
          'id': 'img${images.length + 1}',
          'kind': 'image',
          'status': 'ready',
          'credits': 30,
          'prompt': body['prompt'],
          'url': 'https://cdn.test/a.png'
        };
        images.insert(0, made);
        return http.Response(
            jsonEncode({
              'images': [made]
            }),
            200);
      case '/widget/v1/assets':
        return http.Response(jsonEncode({'assets': images}), 200);
    }
    return http.Response(jsonEncode({'error': 'not found'}), 404);
  });

  StudioClient studio() => StudioClient(
        publicKey: 'pk_live_test',
        userId: 'ada',
        signer: (id) async => 'sig-for-$id',
        httpClient: client,
      );
}

void main() {
  test(
      'starts one session, signs with the signer, and renews a lapsed one once',
      () async {
    final fake = FakeStudio();
    final c = fake.studio();
    await Future.wait([c.config(), c.config()]);
    expect(fake.sessions, 1);
    expect(fake.signatures, ['sig-for-ada']);

    fake.expireNext = true;
    final cfg = await c.config();
    expect(fake.sessions, 2);
    expect(cfg.offers(StudioFeature.images), isTrue);
    expect(cfg.offers(StudioFeature.video), isFalse);
  });

  test('refusals come back as StudioException in the server\'s words',
      () async {
    final c = FakeStudio().studio();
    await expectLater(
      c.createImages(prompt: 'too much'),
      throwsA(isA<StudioException>()
          .having((e) => e.outOfCredits, 'outOfCredits', isTrue)
          .having((e) => e.message, 'message', contains('30 left'))),
    );
  });

  testWidgets('make a picture, open it and use it', (tester) async {
    final fake = FakeStudio();
    StudioAsset? picked;
    await tester.pumpWidget(MaterialApp(
      home: StartupAidStudio(
          client: fake.studio(),
          prompt: 'A lighthouse at dusk',
          imageSize: '3:4',
          onSelected: (a) => picked = a),
    ));
    await tester.pumpAndSettle();

    // Only pictures are offered, so there's no switch between tabs.
    expect(find.text('Video'), findsNothing);
    expect(find.text('150 left today'), findsOneWidget);
    expect(find.text('Make 1 picture'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('Make 2 pictures'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    await tester.tap(find.text('1'));
    await tester.pump();

    await tester.tap(find.text('Make 1 picture'));
    await tester.pumpAndSettle();
    expect(find.text('120 left today'), findsOneWidget);

    final tile = find
        .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('A lighthouse at dusk'), findsWidgets);
    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'img1');
  });

  testWidgets("the key's look applies, and the app's theme overrides it",
      (tester) async {
    final fake = FakeStudio();
    await tester.pumpWidget(MaterialApp(
      home: StartupAidStudio(
        client: fake.studio(),
        theme: const StudioTheme(
            mode: StudioThemeMode.dark,
            dark: StudioPalette(
                background: Color(0xFF101820), accent: Color(0xFF22C55E))),
      ),
    ));
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF101820));
  });

  test('a theme from the dashboard reads both palettes', () {
    final t = StudioTheme.fromJson({
      'mode': 'system',
      'corners': 'round',
      'light': {'accent': '#E11D48', 'background': '#FFFFFF'},
      'dark': {'accent': '#FB7185', 'accentEnd': '#F97316'},
    });
    expect(t.mode, StudioThemeMode.system);
    expect(t.corners, StudioCorners.round);
    expect(t.light?.accent, const Color(0xFFE11D48));
    expect(t.dark?.accentEnd, const Color(0xFFF97316));
    final merged = t.merge(
        const StudioTheme(dark: StudioPalette(accent: Color(0xFF000000))));
    expect(merged.dark?.accent, const Color(0xFF000000));
    expect(merged.dark?.accentEnd, const Color(0xFFF97316));
    expect(merged.light?.accent, const Color(0xFFE11D48));
  });

  testWidgets(
      'a key that hides credits shows no figures, and warns without them',
      (tester) async {
    final fake = FakeStudio()..display = {'credits': 'hide', 'warnLow': true};
    for (var i = 0; i < 4; i++) {
      fake.images.add({
        'id': 'old$i',
        'kind': 'image',
        'status': 'ready',
        'credits': 30,
        'url': 'https://cdn.test/$i.png'
      });
    }
    StudioBudget? told;
    await tester.pumpWidget(MaterialApp(
        home: StartupAidStudio(
            client: fake.studio(), onBudget: (b) => told = b)));
    await tester.pumpAndSettle();
    expect(find.textContaining('left today'), findsNothing);
    expect(find.text('30'), findsNothing);
    expect(find.text('Make 1 picture'), findsOneWidget);
    expect(find.textContaining("close to today's limit"), findsOneWidget);
    expect(told?.remaining, 30);
  });

  testWidgets("long price words fit on a small phone, at a large text size",
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeStudio()
      ..extraImageModels = [
        {
          'id': 'fine',
          'label': 'High quality',
          'note': 'Best quality',
          'credits': 90,
          'mode': 'text',
          'sizable': true,
          'maxImages': 4
        }
      ];
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
        home: StartupAidStudio(
            client: fake.studio(),
            title: 'Make with AI',
            priceLabel: (c) => '${c * 53} tokens (≈ ₦${c * 133})')));
    await tester.pumpAndSettle();
    // An overflow fails the test by itself; the title and price are whole.
    expect(tester.takeException(), isNull);
    expect(find.text('Make with AI'), findsOneWidget);
    final title = tester.getSize(find.text('Make with AI'));
    expect(title.width, greaterThan(100));
  });

  testWidgets('their own presenters come first, after a card to add one',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeStudio()
      ..talking = {
        'enabled': true,
        'maxChars': 3000,
        'aspectRatios': ['9:16'],
        'categories': [],
        'avatars': [
          {'id': 'amara', 'name': 'Amara', 'role': 'Host', 'imageUrl': ''}
        ],
        'mine': [
          {'id': 'own-1', 'name': 'Ada', 'role': 'Yours', 'imageUrl': ''}
        ],
        'voices': [
          {'id': 'Rachel', 'note': 'Calm'}
        ],
      };
    await tester.pumpWidget(MaterialApp(
        home: StartupAidStudio(client: fake.studio(), features: const [
      StudioFeature.talking
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Add yours'), findsOneWidget);
    expect(find.byTooltip('Remove Ada'), findsOneWidget);
    expect(find.byTooltip('Remove Amara'), findsNothing);
    expect(tester.getTopLeft(find.text('Ada')).dx,
        lessThan(tester.getTopLeft(find.text('Amara')).dx));
    expect(tester.getTopLeft(find.text('Add yours')).dx,
        lessThan(tester.getTopLeft(find.text('Ada')).dx));
  });

  testWidgets('their own presenter needs their word before the photo is sent',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    final dir = Directory.systemTemp.createTempSync('presenter');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/me.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (call) async => file.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final fake = FakeStudio()
      ..talking = {
        'enabled': true,
        'maxChars': 3000,
        'aspectRatios': ['9:16'],
        'categories': [],
        'avatars': [
          {'id': 'amara', 'name': 'Amara', 'role': 'Host', 'imageUrl': ''}
        ],
        'voices': [
          {'id': 'Rachel', 'note': 'Calm'},
          {'id': 'Brian', 'note': 'Deep'}
        ],
      };
    await tester.pumpWidget(MaterialApp(
        home: StartupAidStudio(
            client: fake.studio(), features: const [StudioFeature.talking])));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Add yours'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Saving does nothing until they tick the box.
    await tester.tap(find.text('Save presenter'));
    await tester.pump();
    expect(find.text('Save presenter'), findsOneWidget);
    expect(fake.calls, isEmpty);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Brian'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save presenter'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(fake.calls.first, 'upload');
    final sent = jsonDecode(fake.calls[1].substring('presenter:'.length));
    expect(sent['uploadId'], 'up1');
    expect(sent['voice'], 'Brian');
    expect(sent['consent'], isTrue);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byTooltip('Remove Ada'), findsOneWidget);
  });

  testWidgets('accent words stay readable on a pale card', (tester) async {
    late StudioLook look;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      look = StudioLook.resolve(
          context,
          const StudioTheme(
              mode: StudioThemeMode.light,
              light: StudioPalette(accent: Color(0xFFFFE600))));
      return const SizedBox();
    })));
    final x = look.accentText.computeLuminance();
    final y = look.card.computeLuminance();
    expect((y + 0.05) / (x + 0.05), greaterThanOrEqualTo(4.5));
  });


  testWidgets("an app's own price label shows even with credits hidden",
      (tester) async {
    final fake = FakeStudio()..display = {'credits': 'hide', 'warnLow': false};
    await tester.pumpWidget(MaterialApp(
        home: StartupAidStudio(
            client: fake.studio(), priceLabel: (c) => '${c * 2} coins')));
    await tester.pumpAndSettle();
    expect(find.text('60 coins'), findsOneWidget);
    expect(find.text('300 coins left today'), findsOneWidget);
  });

  testWidgets('the Look Film Maker is sent is whole and only colours',
      (tester) async {
    late Map<String, Object> sent;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        sent = StudioLook.resolve(
                context,
                const StudioTheme(
                    mode: StudioThemeMode.dark,
                    corners: StudioCorners.round,
                    dark: StudioPalette(accent: Color(0xFF7C3AED))))
            .toJson();
        return const SizedBox();
      }),
    ));
    // What the web page accepts (MovieEmbed's lookFromHost); anything else
    // and it falls back to the key's Look.
    final colour = RegExp(
        r'^(#[0-9a-f]{3,8}|rgba?\(\s*[\d.]+%?\s*,\s*[\d.]+%?\s*,\s*[\d.]+%?\s*(,\s*[\d.]+%?\s*)?\))$',
        caseSensitive: false);
    for (final k in [
      'accent',
      'accentEnd',
      'onAccent',
      'background',
      'card',
      'field',
      'line',
      'text',
      'muted'
    ]) {
      expect(colour.hasMatch(sent[k] as String), isTrue,
          reason: '$k: ${sent[k]}');
    }
    expect(sent['accent'], 'rgba(124,58,237,1.000)');
    expect(sent['dark'], isTrue);
    expect(sent['pill'], isTrue);
  });

  test(
      'no answer, no connection or no signature is a StudioException, not a hang',
      () async {
    StudioClient over(MockClient c, {StudioSigner? signer}) => StudioClient(
          publicKey: 'pk_live_test',
          userId: 'ada',
          signer: signer ?? (id) async => 'sig',
          httpClient: c,
          timeout: const Duration(milliseconds: 50),
        );
    final silent = over(MockClient((_) => Completer<http.Response>().future));
    await expectLater(
        silent.config(),
        throwsA(isA<StudioException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', contains("didn't answer"))));
    final offline =
        over(MockClient((_) async => throw http.ClientException('no route')));
    await expectLater(
        offline.config(),
        throwsA(isA<StudioException>()
            .having((e) => e.message, 'message', contains("Couldn't reach"))));
    final unsigned = over(MockClient((_) async => http.Response('{}', 200)),
        signer: (_) async => throw StateError('the app server is down'));
    await expectLater(
        unsigned.config(),
        throwsA(isA<StudioException>()
            .having((e) => e.message, 'message', contains('sign you in'))));
  });
}
