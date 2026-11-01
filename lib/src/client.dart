import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Signs a user id for the studio. Call your own server, which returns
/// `v2.<expiry>.<hex HMAC-SHA256 of "userId.expiry">` under the widget key's
/// signing secret (expiry in Unix seconds, up to a day ahead). It's asked
/// again for every new session. The secret must never be in the app.
typedef StudioSigner = Future<String> Function(String userId);

/// Talks to StartupAid's studio for one of your app's users.
///
/// It starts a session with your public key, the user's id and its signature,
/// keeps it fresh, and starts a new one if it lapses.
class StudioClient {
  StudioClient({
    required this.publicKey,
    required this.userId,
    this.signer,
    this.signature,
    this.baseUrl = 'https://api.startupaid.org',
    this.webUrl = 'https://startupaid.org',
    this.timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  })  : assert(publicKey.startsWith('pk_'),
            'publicKey is the widget key from StartupAid → Developers → Studio widget'),
        _ownsHttp = httpClient == null,
        _http = httpClient ?? http.Client();

  /// The widget key from StartupAid's dashboard (pk_live_…).
  final String publicKey;

  /// Your app's id for the signed-in user.
  final String userId;

  /// Fetches the user's signature from your server. Preferred over
  /// [signature]: it is asked again whenever a new session starts.
  final StudioSigner? signer;

  /// A signature fetched beforehand, when [signer] isn't given.
  final String? signature;

  final String baseUrl;

  /// Where StartupAid's own pages are, for Film Maker's web view.
  final String webUrl;

  /// How long a request may take before it gives up with a
  /// [StudioException] (status 0). Uploads get four times as long.
  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttp;

  String? _token;
  DateTime? _expiresAt;
  Future<void>? _starting;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/widget/v1$path');

  Future<void> _session({bool fresh = false}) {
    final valid = _token != null &&
        _expiresAt != null &&
        _expiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 1)));
    if (valid && !fresh) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  /// The user's signature, from [signer] or [signature]: what Film Maker's
  /// web view is handed to sign in.
  Future<String> signatureForUser() async =>
      signer != null ? await signer!(userId) : (signature ?? '');

  Future<void> _start() async {
    final String sig;
    try {
      sig = await signatureForUser().timeout(timeout);
    } catch (_) {
      // The app's own server didn't sign: nothing the user can fix but retry.
      throw const StudioException(
          0, "The studio couldn't sign you in. Try again.");
    }
    final req = http.Request('POST', _uri('/session'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(
          {'publicKey': publicKey, 'userId': userId, 'signature': sig});
    final res = await _go(req);
    final body = _decode(res);
    _token = body['token'] as String?;
    _expiresAt = DateTime.tryParse(body['expiresAt'] as String? ?? '');
  }

  // Sends a request within the timeout. A dropped connection or no answer
  // comes back as a StudioException the widget shows, never a spinner that
  // turns forever.
  Future<http.Response> _go(http.BaseRequest req, {Duration? limit}) async {
    Future<http.Response> send() async =>
        http.Response.fromStream(await _http.send(req));
    try {
      // The whole exchange, the wait for an answer as well as the reading.
      return await send().timeout(limit ?? timeout);
    } on TimeoutException {
      throw const StudioException(
          0, "The studio didn't answer. Check your connection and try again.");
    } on http.ClientException {
      throw const StudioException(
          0, "Couldn't reach the studio. Check your connection and try again.");
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body = const {};
    try {
      final v = jsonDecode(res.body);
      if (v is Map<String, dynamic>) body = v;
    } catch (_) {
      // not JSON; the status says enough
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StudioException(
          res.statusCode,
          body['error'] as String? ??
              'The studio didn\'t answer (${res.statusCode}). Try again.');
    }
    return body;
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body, Map<String, String>? headers}) async {
    for (var attempt = 0;; attempt++) {
      await _session(fresh: attempt > 0);
      final req = http.Request(method, _uri(path))
        ..headers.addAll({
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          ...?headers
        });
      if (body != null) req.body = jsonEncode(body);
      final res = await _go(req);
      // A lapsed session gets one fresh start before giving up.
      if (res.statusCode == 401 && attempt == 0) continue;
      return _decode(res);
    }
  }

  /// What this user can make, and what they have left today.
  Future<StudioConfig> config() async =>
      StudioConfig.fromJson(await _send('GET', '/config'));

  /// Makes pictures from a description. Comes back when they're ready.
  Future<List<StudioAsset>> createImages({
    required String prompt,
    String? model,
    String? size,
    int count = 1,
    List<String> fromImageUrls = const [],
  }) async {
    final out = await _send('POST', '/images', body: {
      'prompt': prompt,
      if (model != null) 'model': model,
      if (size != null) 'size': size,
      'count': count,
      if (fromImageUrls.isNotEmpty) 'imageUrls': fromImageUrls,
    });
    return [
      for (final a in (out['images'] as List? ?? const []))
        StudioAsset.fromJson(a as Map<String, dynamic>)
    ];
  }

  /// What a clip would cost, in credits.
  Future<int> quoteVideo(
      {required String model,
      String? aspectRatio,
      int? durationSecs,
      String? resolution,
      String? sourceImageUrl}) async {
    final out = await _send('POST', '/videos/quote', body: {
      'model': model,
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
      if (durationSecs != null) 'durationSecs': durationSecs,
      if (resolution != null) 'resolution': resolution,
      if (sourceImageUrl != null) 'sourceImageUrl': sourceImageUrl,
    });
    return (out['credits'] as num?)?.toInt() ?? 0;
  }

  /// Starts a clip. It comes back pending; [waitFor] sees it finish. Pass the
  /// same [requestId] when retrying the same tap, so it isn't made twice.
  Future<StudioAsset> createVideo({
    required String prompt,
    required String model,
    String? aspectRatio,
    int? durationSecs,
    String? resolution,
    String? sourceImageUrl,
    String? requestId,
  }) async {
    final out = await _send('POST', '/videos', body: {
      'prompt': prompt,
      'model': model,
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
      if (durationSecs != null) 'durationSecs': durationSecs,
      if (resolution != null) 'resolution': resolution,
      if (sourceImageUrl != null) 'sourceImageUrl': sourceImageUrl,
      if (requestId != null) 'idempotencyKey': requestId,
    });
    return StudioAsset.fromJson(out['asset'] as Map<String, dynamic>);
  }

  /// Speaks [text] in one of the stock voices. Comes back pending; [waitFor]
  /// sees it finish. [language] is an ISO 639-1 code, or null to take it from
  /// the text.
  Future<StudioAsset> createSpeech(
      {required String text, String? voice, String? language}) async {
    final out = await _send('POST', '/speech', body: {
      'text': text,
      if (voice != null) 'voice': voice,
      if (language != null) 'language': language,
    });
    return StudioAsset.fromJson(out['asset'] as Map<String, dynamic>);
  }

  /// Composes music from a description. Comes back pending.
  Future<StudioAsset> createMusic(
      {required String prompt, int? seconds}) async {
    final out = await _send('POST', '/music',
        body: {'prompt': prompt, if (seconds != null) 'seconds': seconds});
    return StudioAsset.fromJson(out['asset'] as Map<String, dynamic>);
  }

  /// What a presenter video would cost, in credits.
  Future<int> quoteTalking(
      {required String avatarId,
      required String script,
      String? aspectRatio}) async {
    final out = await _send('POST', '/talking/quote', body: {
      'avatarId': avatarId,
      'script': script,
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
    });
    return (out['credits'] as num?)?.toInt() ?? 0;
  }

  /// A presenter says [script] on camera: a ready-made one or the user's own.
  /// Comes back pending; presenter videos take a few minutes.
  Future<StudioAsset> createTalking(
      {required String avatarId,
      required String script,
      String? aspectRatio}) async {
    final out = await _send('POST', '/talking', body: {
      'avatarId': avatarId,
      'script': script,
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
    });
    return StudioAsset.fromJson(out['asset'] as Map<String, dynamic>);
  }

  /// Makes the user's own presenter from a picture they [upload]ed, speaking
  /// in one of the stock voices. A real person's likeness: [consent] says the
  /// user confirmed it's them, or that they have the person's permission.
  Future<StudioAvatar> createPresenter(
      {required String uploadId,
      required String name,
      required String voice,
      required bool consent}) async {
    final out = await _send('POST', '/talking/presenters', body: {
      'uploadId': uploadId,
      'name': name,
      'voice': voice,
      'consent': consent,
    });
    return StudioAvatar.fromJson(out['presenter'] as Map<String, dynamic>);
  }

  /// Removes one of the user's own presenters and its photo. Videos already
  /// made with it stay.
  Future<void> deletePresenter(String id) async {
    await _send('DELETE', '/talking/presenters/${Uri.encodeComponent(id)}');
  }

  /// Uploads a picture (JPEG, PNG or WebP, up to 10 MB) to animate.
  Future<StudioAsset> upload(Uint8List bytes,
      {String filename = 'picture.jpg'}) async {
    for (var attempt = 0;; attempt++) {
      await _session(fresh: attempt > 0);
      final req = http.MultipartRequest('POST', _uri('/uploads'))
        ..headers['Authorization'] = 'Bearer $_token'
        ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final res = await _go(req, limit: timeout * 4);
      if (res.statusCode == 401 && attempt == 0) continue;
      return StudioAsset.fromJson(
          _decode(res)['asset'] as Map<String, dynamic>);
    }
  }

  /// One of the user's own, up to date.
  Future<StudioAsset> asset(String id) async => StudioAsset.fromJson(
      (await _send('GET', '/assets/${Uri.encodeComponent(id)}'))['asset']
          as Map<String, dynamic>);

  /// What the user has made, newest first. [kind] is "image" or "video".
  Future<List<StudioAsset>> assets({String? kind, int limit = 30}) async {
    final q = '?limit=$limit${kind != null ? '&kind=$kind' : ''}';
    final out = await _send('GET', '/assets$q');
    return [
      for (final a in (out['assets'] as List? ?? const []))
        StudioAsset.fromJson(a as Map<String, dynamic>)
    ];
  }

  /// Checks a pending clip until it's ready or has failed.
  Future<StudioAsset> waitFor(String id,
      {Duration every = const Duration(seconds: 4),
      Duration timeout = const Duration(minutes: 10)}) async {
    final until = DateTime.now().add(timeout);
    while (true) {
      final a = await asset(id);
      if (!a.isPending || DateTime.now().isAfter(until)) return a;
      await Future<void>.delayed(every);
    }
  }

  /// Closes the HTTP client, if this client made it.
  void close() {
    if (_ownsHttp) _http.close();
  }
}
