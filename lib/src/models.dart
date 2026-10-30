// What the studio sends back, as plain Dart.

import 'theme.dart';

/// The features a widget key can offer.
enum StudioFeature {
  images,
  video,

  /// Voice & music: speech in the stock voices, and music.
  audio,

  /// Talking videos with the ready-made presenters.
  talking,

  /// Film Maker: films of several scenes, a cast and voices. It's
  /// StartupAid's own editor, opened in a web view.
  movies,
}

StudioFeature? _feature(String name) => switch (name) {
      'images' => StudioFeature.images,
      'video' => StudioFeature.video,
      'audio' => StudioFeature.audio,
      'talking' => StudioFeature.talking,
      'movies' => StudioFeature.movies,
      _ => null,
    };

double _num(Object? v) => v is num ? v.toDouble() : 0;

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';

/// Something the user made (a picture or a clip) or uploaded.
class StudioAsset {
  const StudioAsset({
    required this.id,
    required this.kind,
    required this.status,
    required this.credits,
    this.prompt = '',
    this.url = '',
    this.thumbnailUrl = '',
    this.error = '',
    this.createdAt,
    this.seconds = 0,
  });

  factory StudioAsset.fromJson(Map<String, dynamic> j) => StudioAsset(
        id: _str(j['id']),
        kind: _str(j['kind']),
        status: _str(j['status']),
        credits: _int(j['credits']),
        prompt: _str(j['prompt']),
        url: _str(j['url']),
        thumbnailUrl: _str(j['thumbnailUrl']),
        error: _str(j['error']),
        createdAt: DateTime.tryParse(_str(j['createdAt'])),
        seconds: _num(j['seconds']),
      );

  final String id;

  /// "image", "video" or "upload".
  final String kind;

  /// "pending" (a clip being made), "ready" or "failed".
  final String status;
  final int credits;
  final String prompt;

  /// Where the picture or clip is. Empty until it's ready.
  final String url;

  /// A still from a clip, when there is one.
  final String thumbnailUrl;
  final String error;

  /// How long a clip or piece of audio runs, once it's made.
  final double seconds;
  final DateTime? createdAt;

  /// A clip or a presenter video.
  bool get isVideo => kind == 'video' || kind == 'talking' || kind == 'film';

  /// Speech or music.
  bool get isAudio => kind == 'speech' || kind == 'music';
  bool get isPending => status == 'pending';
  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';

  /// The picture to show for it: the image itself, or a clip's still.
  String get previewUrl => isVideo ? thumbnailUrl : url;
}

/// What the user has left to spend today.
class StudioBudget {
  const StudioBudget(
      {required this.dailyCredits,
      required this.usedToday,
      required this.remaining});

  factory StudioBudget.fromJson(Map<String, dynamic>? j) => StudioBudget(
        dailyCredits: _int(j?['dailyCredits']),
        usedToday: _int(j?['usedToday']),
        remaining: _int(j?['remaining']),
      );

  final int dailyCredits;
  final int usedToday;
  final int remaining;
}

/// A picture model on offer.
class StudioImageModel {
  const StudioImageModel({
    required this.id,
    required this.label,
    required this.note,
    required this.credits,
    required this.mode,
    required this.sizable,
    required this.maxImages,
  });

  factory StudioImageModel.fromJson(Map<String, dynamic> j) => StudioImageModel(
        id: _str(j['id']),
        label: _str(j['label']),
        note: _str(j['note']),
        credits: _int(j['credits']),
        mode: _str(j['mode']),
        sizable: j['sizable'] == true,
        maxImages: _int(j['maxImages']).clamp(1, 4),
      );

  final String id;
  final String label;
  final String note;

  /// Credits for each picture.
  final int credits;

  /// "text" for a description alone, "edit" to change pictures given.
  final String mode;
  final bool sizable;
  final int maxImages;
}

/// A video model on offer.
class StudioVideoModel {
  const StudioVideoModel({
    required this.id,
    required this.label,
    required this.engine,
    required this.tag,
    required this.note,
    required this.mode,
    required this.credits,
    required this.minSecs,
    required this.maxSecs,
    required this.durations,
    required this.resolutions,
    required this.realPeople,
  });

  factory StudioVideoModel.fromJson(Map<String, dynamic> j) => StudioVideoModel(
        id: _str(j['id']),
        label: _str(j['label']),
        engine: _str(j['engine']),
        tag: _str(j['tag']),
        note: _str(j['note']),
        mode: _str(j['mode']),
        credits: _int(j['credits']),
        minSecs: _int(j['minSecs']),
        maxSecs: _int(j['maxSecs']),
        durations: [
          for (final d in (j['durations'] as List? ?? const [])) _int(d)
        ],
        resolutions: [
          for (final r in (j['resolutions'] as List? ?? const [])) _str(r)
        ],
        realPeople: j['realPeople'] == true,
      );

  final String id;
  final String label;
  final String engine;
  final String tag;
  final String note;

  /// "text" makes a clip from words; "image" animates a picture.
  final String mode;

  /// The "from" price: the shortest clip at the usual resolution.
  final int credits;
  final int minSecs;
  final int maxSecs;

  /// When set, the only lengths the model makes.
  final List<int> durations;
  final List<String> resolutions;

  /// Whether it will animate a photo of a real person.
  final bool realPeople;

  bool get fromPicture => mode == 'image';

  /// The lengths worth offering, shortest first.
  List<int> get lengths {
    if (durations.isNotEmpty) return durations;
    final lo = minSecs > 0 ? minSecs : 4;
    final hi = maxSecs > 0 ? maxSecs : 8;
    return {
      for (final s in [4, 5, 6, 8, 10, 15])
        if (s >= lo && s <= hi) s,
      lo
    }.toList()
      ..sort();
  }
}

/// A stock voice.
class StudioVoice {
  const StudioVoice({required this.id, required this.note});
  factory StudioVoice.fromJson(Map<String, dynamic> j) =>
      StudioVoice(id: _str(j['id']), note: _str(j['note']));
  final String id;
  final String note;
}

/// A language speech can be made in.
class StudioLanguage {
  const StudioLanguage({required this.code, required this.name});
  factory StudioLanguage.fromJson(Map<String, dynamic> j) =>
      StudioLanguage(code: _str(j['code']), name: _str(j['name']));
  final String code;
  final String name;
}

/// What Voice & music offers, and its prices.
class StudioAudioOptions {
  const StudioAudioOptions({
    required this.speech,
    required this.music,
    required this.voices,
    required this.languages,
    required this.maxChars,
    required this.charsPerUnit,
    required this.speechCredits,
    required this.musicCredits,
    required this.musicLongCredits,
    required this.musicLongOver,
    required this.minSecs,
    required this.maxSecs,
    required this.defaultSecs,
  });

  factory StudioAudioOptions.fromJson(Map<String, dynamic> j) =>
      StudioAudioOptions(
        speech: j['speech'] == true,
        music: j['music'] == true,
        voices: [
          for (final v in (j['voices'] as List? ?? const []))
            StudioVoice.fromJson(v as Map<String, dynamic>)
        ],
        languages: [
          for (final l in (j['languages'] as List? ?? const []))
            StudioLanguage.fromJson(l as Map<String, dynamic>)
        ],
        maxChars: _int(j['maxChars']),
        charsPerUnit: _int(j['charsPerUnit']),
        speechCredits: _int(j['speechCredits']),
        musicCredits: _int(j['musicCredits']),
        musicLongCredits: _int(j['musicLongCredits']),
        musicLongOver: _int(j['musicLongOver']),
        minSecs: _int(j['minSecs']),
        maxSecs: _int(j['maxSecs']),
        defaultSecs: _int(j['defaultSecs']),
      );

  final bool speech;
  final bool music;
  final List<StudioVoice> voices;
  final List<StudioLanguage> languages;
  final int maxChars;
  final int charsPerUnit;
  final int speechCredits;
  final int musicCredits;
  final int musicLongCredits;
  final int musicLongOver;
  final int minSecs;
  final int maxSecs;
  final int defaultSecs;

  /// What speaking [text] costs: a price per started block of characters.
  int speechPrice(String text) {
    final n = text.trim().runes.length;
    if (n == 0 || charsPerUnit <= 0) return 0;
    return speechCredits * ((n + charsPerUnit - 1) ~/ charsPerUnit);
  }

  /// What a piece of music this long costs.
  int musicPrice(int secs) =>
      musicLongOver > 0 && secs > musicLongOver && musicLongCredits > 0
          ? musicLongCredits
          : musicCredits;

  /// The lengths worth offering, shortest first.
  List<int> get lengths {
    final lo = minSecs > 0 ? minSecs : 5;
    final hi = maxSecs > 0 ? maxSecs : 45;
    return {
      for (final s in [10, 20, 30, 45, 60, 90, 120])
        if (s >= lo && s <= hi) s,
      if (defaultSecs >= lo && defaultSecs <= hi) defaultSecs,
    }.toList()
      ..sort();
  }
}

/// A ready-made presenter.
class StudioAvatar {
  const StudioAvatar({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
    required this.imageUrl,
    required this.category,
  });
  factory StudioAvatar.fromJson(Map<String, dynamic> j) => StudioAvatar(
        id: _str(j['id']),
        name: _str(j['name']),
        role: _str(j['role']),
        description: _str(j['description']),
        imageUrl: _str(j['imageUrl']),
        category: _str(j['category']),
      );
  final String id;
  final String name;
  final String role;
  final String description;
  final String imageUrl;
  final String category;
}

/// What presenter videos offer.
class StudioTalkingOptions {
  const StudioTalkingOptions(
      {required this.avatars,
      required this.categories,
      required this.maxChars,
      required this.aspectRatios});
  factory StudioTalkingOptions.fromJson(Map<String, dynamic> j) =>
      StudioTalkingOptions(
        avatars: j['enabled'] != true
            ? const []
            : [
                for (final a in (j['avatars'] as List? ?? const []))
                  StudioAvatar.fromJson(a as Map<String, dynamic>)
              ],
        categories: [
          for (final c in (j['categories'] as List? ?? const [])) _str(c)
        ],
        maxChars: _int(j['maxChars']),
        aspectRatios: [
          for (final a
              in (j['aspectRatios'] as List? ?? const ['9:16', '16:9']))
            _str(a)
        ],
      );
  final List<StudioAvatar> avatars;
  final List<String> categories;
  final int maxChars;
  final List<String> aspectRatios;
}

/// What the app's users are shown of credits, as set on the widget key.
class StudioDisplay {
  const StudioDisplay({this.showCredits = true, this.warnLow = true});
  factory StudioDisplay.fromJson(Map<String, dynamic>? j) => StudioDisplay(
      showCredits: j?['credits'] != 'hide',
      warnLow: j == null || j['warnLow'] != false);

  /// Prices and what's left are shown in credits. Off, no credit figures
  /// appear, unless the app gives the widget its own priceLabel.
  final bool showCredits;

  /// Users are told when they're close to their daily limit.
  final bool warnLow;
}

/// What the widget can offer this user.
class StudioConfig {
  const StudioConfig({
    required this.features,
    required this.budget,
    required this.imageModels,
    required this.imageSizes,
    required this.maxImageCount,
    required this.videoModels,
    required this.aspectRatios,
    this.theme = const StudioTheme(),
    this.audio,
    this.talking,
    this.display = const StudioDisplay(),
  });

  factory StudioConfig.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    final video = j['video'] as Map<String, dynamic>?;
    return StudioConfig(
      features: [
        for (final f in (j['features'] as List? ?? const []))
          if (_feature(_str(f)) case final feature?) feature,
      ],
      budget: StudioBudget.fromJson(j['budget'] as Map<String, dynamic>?),
      imageModels: images == null || images['enabled'] != true
          ? const []
          : [
              for (final m in (images['models'] as List? ?? const []))
                StudioImageModel.fromJson(m as Map<String, dynamic>)
            ],
      imageSizes: [
        for (final s in (images?['sizes'] as List? ?? const [])) _str(s)
      ],
      maxImageCount: _int(images?['maxCount']).clamp(1, 4),
      videoModels: video == null || video['enabled'] != true
          ? const []
          : [
              for (final m in (video['models'] as List? ?? const []))
                StudioVideoModel.fromJson(m as Map<String, dynamic>)
            ],
      aspectRatios: [
        for (final a in (video?['aspectRatios'] as List? ??
            const ['9:16', '16:9', '1:1']))
          _str(a)
      ],
      theme: StudioTheme.fromJson(j['theme'] as Map<String, dynamic>?),
      audio: j['audio'] is Map<String, dynamic>
          ? StudioAudioOptions.fromJson(j['audio'] as Map<String, dynamic>)
          : null,
      talking: j['talking'] is Map<String, dynamic>
          ? StudioTalkingOptions.fromJson(j['talking'] as Map<String, dynamic>)
          : null,
      display: StudioDisplay.fromJson(j['display'] as Map<String, dynamic>?),
    );
  }

  final List<StudioFeature> features;
  final StudioBudget budget;
  final List<StudioImageModel> imageModels;
  final List<String> imageSizes;
  final int maxImageCount;
  final List<StudioVideoModel> videoModels;
  final List<String> aspectRatios;

  /// The look set on the widget key in StartupAid's dashboard.
  final StudioTheme theme;

  /// Voice & music, when the key offers it.
  final StudioAudioOptions? audio;

  /// Presenter videos, when the key offers them.
  final StudioTalkingOptions? talking;

  /// What the app's users are shown of credits.
  final StudioDisplay display;

  bool offers(StudioFeature f) =>
      features.contains(f) &&
      switch (f) {
        StudioFeature.images => imageModels.isNotEmpty,
        StudioFeature.video => videoModels.isNotEmpty,
        StudioFeature.audio => audio != null && (audio!.speech || audio!.music),
        StudioFeature.talking => talking != null && talking!.avatars.isNotEmpty,
        StudioFeature.movies => true,
      };
}

/// A refusal from the studio, in words fit to show the user.
class StudioException implements Exception {
  const StudioException(this.status, this.message);

  final int status;
  final String message;

  /// The user has spent today's credits (or the app has).
  bool get outOfCredits => status == 402;

  @override
  String toString() => message;
}
