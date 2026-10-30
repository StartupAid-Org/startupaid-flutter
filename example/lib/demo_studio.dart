import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A pretend StartupAid studio, so the example runs without a widget key. It
// answers the same routes as the real one, with sample pictures and a sample
// clip, and keeps the user's daily budget the way the server does. Swap it
// out by giving StudioClient a real publicKey and no httpClient.
class DemoStudio {
  int _budget = 400;
  final _assets = <Map<String, dynamic>>[];
  final _ready = <String, DateTime>{};
  int _n = 0;

  static const _videoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
  static const _talkUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
  static const _audioUrl =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

  int _talkPrice(Map<String, dynamic> body) {
    final words = (body['script'] as String? ?? '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return words == 0 ? 0 : 60 + 30 * (words ~/ 12);
  }

  late final http.Client client = MockClient((req) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final path = req.url.path.replaceFirst('/widget/v1', '');
    final body =
        req.body.isEmpty ||
            req.headers['content-type']?.startsWith('multipart') == true
        ? <String, dynamic>{}
        : jsonDecode(req.body) as Map<String, dynamic>;
    switch ((req.method, path)) {
      case ('POST', '/session'):
        return _ok({
          'token': 'demo',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 2))
              .toIso8601String(),
        });
      case ('GET', '/config'):
        return _ok(_config());
      case ('POST', '/images'):
        final count = (body['count'] as num?)?.toInt() ?? 1;
        final cost = 6 * count;
        if (cost > _budget) {
          return _no(
            402,
            'That needs $cost credits and you have $_budget left today.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        _budget -= cost;
        final made = [
          for (var i = 0; i < count; i++)
            _asset(
              'image',
              'ready',
              6,
              body['prompt'] as String,
              url: 'https://picsum.photos/seed/sa${++_n}/600/800',
            ),
        ];
        _assets.insertAll(0, made);
        return _ok({'images': made, 'budget': _budgetJson()});
      case ('POST', '/videos/quote'):
        return _ok({'credits': _price(body)});
      case ('POST', '/videos'):
        final cost = _price(body);
        if (cost > _budget) {
          return _no(
            402,
            'That needs $cost credits and you have $_budget left today.',
          );
        }
        _budget -= cost;
        final clip = _asset('video', 'pending', cost, body['prompt'] as String);
        _ready[clip['id'] as String] = DateTime.now().add(
          const Duration(seconds: 9),
        );
        _assets.insert(0, clip);
        return http.Response(
          jsonEncode({'asset': clip, 'budget': _budgetJson()}),
          202,
          headers: _json,
        );
      case ('POST', '/speech') || ('POST', '/music'):
        final speech = path == '/speech';
        final text = (body[speech ? 'text' : 'prompt'] as String? ?? '').trim();
        if (text.isEmpty) {
          return _no(
            400,
            speech
                ? 'Write what should be said.'
                : 'Describe the music you want.',
          );
        }
        final cost = speech ? 2 * ((text.length + 299) ~/ 300) : 8;
        if (cost > _budget) {
          return _no(
            402,
            'That needs $cost credits and you have $_budget left today.',
          );
        }
        _budget -= cost;
        final made = _asset(speech ? 'speech' : 'music', 'pending', cost, text);
        _ready[made['id'] as String] = DateTime.now().add(
          const Duration(seconds: 5),
        );
        _assets.insert(0, made);
        return http.Response(
          jsonEncode({'asset': made, 'budget': _budgetJson()}),
          202,
          headers: _json,
        );
      case ('POST', '/talking/quote'):
        return _ok({'credits': _talkPrice(body), 'seconds': 12});
      case ('POST', '/talking'):
        final cost = _talkPrice(body);
        if (cost > _budget) {
          return _no(
            402,
            'That needs $cost credits and you have $_budget left today.',
          );
        }
        _budget -= cost;
        final made = _asset(
          'talking',
          'pending',
          cost,
          body['script'] as String? ?? '',
        );
        _ready[made['id'] as String] = DateTime.now().add(
          const Duration(seconds: 9),
        );
        _assets.insert(0, made);
        return http.Response(
          jsonEncode({'asset': made, 'budget': _budgetJson()}),
          202,
          headers: _json,
        );
      case ('POST', '/uploads'):
        final up = _asset(
          'upload',
          'ready',
          0,
          '',
          url: 'https://picsum.photos/seed/upload${++_n}/600/800',
        );
        _assets.add(up);
        return _ok({'asset': up});
      case ('GET', '/assets'):
        final kind = req.url.queryParameters['kind'];
        return _ok({
          'assets': [
            for (final a in _assets)
              if (a['kind'] == kind) _settle(a),
          ],
        });
    }
    if (req.method == 'GET' && path.startsWith('/assets/')) {
      final id = path.substring('/assets/'.length);
      final a = _assets.where((x) => x['id'] == id).firstOrNull;
      return a == null
          ? _no(404, "That isn't one of yours.")
          : _ok({'asset': _settle(a)});
    }
    return _no(404, 'Not found');
  });

  Map<String, dynamic> _settle(Map<String, dynamic> a) {
    final at = _ready[a['id']];
    if (a['status'] == 'pending' && at != null && DateTime.now().isAfter(at)) {
      a['status'] = 'ready';
      switch (a['kind']) {
        case 'speech' || 'music':
          a['url'] = _audioUrl;
          a['seconds'] = a['kind'] == 'music' ? 20.0 : 4.0;
        case 'talking':
          a['url'] = _talkUrl;
          a['thumbnailUrl'] =
              'https://randomuser.me/api/portraits/women/44.jpg';
          a['seconds'] = 12.0;
        default:
          a['url'] = _videoUrl;
          a['thumbnailUrl'] =
              'https://picsum.photos/seed/clip${a['id']}/450/800';
      }
    }
    return a;
  }

  int _price(Map<String, dynamic> body) {
    final secs = (body['durationSecs'] as num?)?.toInt() ?? 5;
    final perSec = (body['model'] as String? ?? '').startsWith('standard')
        ? 30
        : 14;
    return perSec * secs;
  }

  Map<String, dynamic> _asset(
    String kind,
    String status,
    int credits,
    String prompt, {
    String url = '',
  }) => {
    'id': 'a${++_n}',
    'kind': kind,
    'status': status,
    'credits': credits,
    'prompt': prompt,
    'url': url,
    'createdAt': DateTime.now().toIso8601String(),
  };

  Map<String, dynamic> _budgetJson() => {
    'dailyCredits': 400,
    'usedToday': 400 - _budget,
    'remaining': _budget,
  };

  // The Look a key would carry from the dashboard: a light and a dark palette.
  // LOOK picks the mode when running the example (light, dark or system).
  static const _mode = String.fromEnvironment('LOOK', defaultValue: 'system');

  Map<String, dynamic> _config() => {
    'features': ['images', 'video', 'audio', 'talking'],
    'theme': {
      'mode': _mode,
      'corners': 'rounded',
      'light': {'accent': '#7c3aed', 'accentEnd': '#db2777'},
      'dark': {
        'accent': '#a78bfa',
        'accentEnd': '#f472b6',
        'background': '#0b0a12',
      },
    },
    'budget': _budgetJson(),
    'images': {
      'enabled': true,
      'maxCount': 4,
      'sizes': ['1:1', '3:4', '4:3', '9:16', '16:9'],
      'models': [
        {
          'id': 'quick',
          'label': 'Quick',
          'note': 'Fast and cheap',
          'credits': 6,
          'mode': 'text',
          'sizable': true,
          'maxImages': 4,
        },
        {
          'id': 'detailed',
          'label': 'Detailed',
          'note': 'Sharper faces and text',
          'credits': 12,
          'mode': 'text',
          'sizable': true,
          'maxImages': 4,
        },
      ],
    },
    'audio': {
      'speech': true,
      'music': true,
      'voices': [
        {'id': 'Rachel', 'note': 'Calm, clear narrator'},
        {'id': 'Aria', 'note': 'Expressive and warm'},
        {'id': 'Brian', 'note': 'Deep, steady narrator'},
        {'id': 'Liam', 'note': 'Friendly and energetic'},
      ],
      'languages': [
        {'code': 'en', 'name': 'English'},
        {'code': 'fr', 'name': 'French'},
        {'code': 'ha', 'name': 'Hausa'},
        {'code': 'ig', 'name': 'Igbo'},
        {'code': 'yo', 'name': 'Yoruba'},
      ],
      'maxChars': 2000,
      'charsPerUnit': 300,
      'speechCredits': 2,
      'musicCredits': 8,
      'musicLongCredits': 0,
      'musicLongOver': 0,
      'minSecs': 5,
      'maxSecs': 45,
      'defaultSecs': 20,
    },
    'talking': {
      'enabled': true,
      'maxChars': 3000,
      'aspectRatios': ['9:16', '16:9'],
      'categories': ['Office and business', 'Studio and creators'],
      'avatars': [
        for (final (i, a) in [
          ('amara', 'Amara', 'Founder', 'women/44', 'Office and business'),
          ('tunde', 'Tunde', 'Product lead', 'men/32', 'Office and business'),
          ('zoe', 'Zoe', 'Creator', 'women/68', 'Studio and creators'),
          ('kofi', 'Kofi', 'Host', 'men/75', 'Studio and creators'),
        ].indexed)
          {
            'id': a.$1,
            'name': a.$2,
            'role': a.$3,
            'description': '',
            'imageUrl': 'https://randomuser.me/api/portraits/${a.$4}.jpg',
            'category': a.$5,
            'order': i,
          },
      ],
    },
    'video': {
      'enabled': true,
      'aspectRatios': ['9:16', '16:9', '1:1'],
      'models': [
        {
          'id': 'fast',
          'label': 'Fast',
          'tag': 'Cheapest',
          'mode': 'text',
          'minSecs': 4,
          'maxSecs': 10,
          'credits': 56,
        },
        {
          'id': 'standard',
          'label': 'Standard',
          'tag': 'With sound',
          'mode': 'text',
          'durations': [4, 6, 8],
          'credits': 120,
        },
        {
          'id': 'fast-picture',
          'label': 'Fast',
          'tag': 'Cheapest',
          'mode': 'image',
          'minSecs': 4,
          'maxSecs': 10,
          'realPeople': false,
          'credits': 56,
        },
        {
          'id': 'standard-picture',
          'label': 'Standard',
          'tag': 'With sound',
          'mode': 'image',
          'durations': [4, 6, 8],
          'realPeople': true,
          'credits': 120,
        },
      ],
    },
  };

  static const _json = {'content-type': 'application/json'};
  http.Response _ok(Object body) =>
      http.Response(jsonEncode(body), 200, headers: _json);
  http.Response _no(int status, String error) =>
      http.Response(jsonEncode({'error': error}), status, headers: _json);
}
