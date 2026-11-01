import 'dart:async';
import 'dart:math' show max;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'client.dart';
import 'models.dart';
import 'movie_maker.dart';
import 'theme.dart';

/// StartupAid's Creative studio, for one of your app's users.
///
/// Shows the features your widget key offers (pictures, video, or both) that
/// you also ask for in [features]. What the user makes is paid from your
/// StartupAid credits, within the daily budget you set on the key. When they
/// pick something, [onSelected] gets it; [show] opens the studio as a page and
/// returns the pick.
///
/// It looks the way the key's Look is set in StartupAid's dashboard (light and
/// dark palettes, which to use, corners). [theme] overrides any of that here.
class StartupAidStudio extends StatefulWidget {
  const StartupAidStudio({
    super.key,
    required this.client,
    this.features = StudioFeature.values,
    this.prompt,
    this.imageSize,
    this.aspectRatio = '9:16',
    this.startImage,
    this.title = 'Create with AI',
    this.theme,
    this.priceLabel,
    this.onBudget,
    this.onSelected,
  });

  final StudioClient client;
  final List<StudioFeature> features;

  /// A description to start from, which the user can change.
  final String? prompt;

  /// The picture shape to start on: 1:1, 3:4, 4:3, 9:16 or 16:9.
  final String? imageSize;

  /// The clip shape to start on: 9:16, 16:9 or 1:1.
  final String aspectRatio;

  /// A picture to animate (a cover, say). It's uploaded when the studio opens
  /// and offered as the clip's first frame.
  final Uint8List? startImage;

  final String title;

  /// Overrides the Look set on the key in StartupAid's dashboard.
  final StudioTheme? theme;
  final ValueChanged<StudioAsset>? onSelected;

  /// Shows prices in the app's own terms, for an app that charges its users
  /// its own way: given credits, the words to show (say, "12 coins"). Given,
  /// prices show even when the key hides credits.
  final String Function(int credits)? priceLabel;

  /// Told what the user has left whenever it changes, so the app can offer
  /// more (a top-up, an upgrade) in its own way.
  final ValueChanged<StudioBudget>? onBudget;

  /// Opens the studio as a full-screen page. Returns what the user picked, or
  /// null if they closed it.
  static Future<StudioAsset?> show(
    BuildContext context, {
    required StudioClient client,
    List<StudioFeature> features = StudioFeature.values,
    String? prompt,
    String? imageSize,
    String aspectRatio = '9:16',
    Uint8List? startImage,
    String title = 'Create with AI',
    StudioTheme? theme,
    String Function(int credits)? priceLabel,
    ValueChanged<StudioBudget>? onBudget,
  }) {
    // Films alone: straight into Film Maker, no tab to pass through.
    if (features.length == 1 && features.single == StudioFeature.movies) {
      return movieMaker(context,
          client: client,
          title: title == 'Create with AI' ? 'Film Maker' : title,
          theme: theme,
          priceLabel: priceLabel);
    }
    return Navigator.of(context).push<StudioAsset>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => StartupAidStudio(
        client: client,
        features: features,
        prompt: prompt,
        imageSize: imageSize,
        aspectRatio: aspectRatio,
        startImage: startImage,
        title: title,
        theme: theme,
        priceLabel: priceLabel,
        onBudget: onBudget,
        onSelected: (a) => Navigator.of(ctx).pop(a),
      ),
    ));
  }

  /// Opens Film Maker on its own: films of several scenes, a cast, voices
  /// and music, in StartupAid's own editor (a web view signed in as the
  /// client's user). Needs "Films" on the widget key. Returns the film the
  /// user picks (kind "film", with its url), or null. [theme] and
  /// [priceLabel] work as they do for [show].
  static Future<StudioAsset?> movieMaker(BuildContext context,
      {required StudioClient client,
      String title = 'Film Maker',
      StudioTheme? theme,
      String Function(int credits)? priceLabel}) {
    return Navigator.of(context).push<StudioAsset>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MovieMakerPage(
          client: client, title: title, theme: theme, priceLabel: priceLabel),
    ));
  }

  @override
  State<StartupAidStudio> createState() => _StartupAidStudioState();
}

/// The look, for every piece below the studio.
class _Look extends InheritedWidget {
  const _Look(
      {required this.look,
      this.prices = const _Prices(),
      required super.child});

  final StudioLook look;
  final _Prices prices;

  static StudioLook of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Look>()!.look;
  static _Prices pricesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Look>()!.prices;

  @override
  bool updateShouldNotify(_Look old) =>
      old.look != look ||
      old.prices.show != prices.show ||
      old.prices.label != prices.label;
}

/// How prices are shown: in credits, in the app's own words (its
/// priceLabel), or not at all.
class _Prices {
  const _Prices({this.show = true, this.label});

  final bool show;
  final String Function(int credits)? label;

  bool get custom => label != null;

  /// The figure for [credits], or null when prices are hidden.
  String? of(int credits) =>
      !show ? null : (label?.call(credits) ?? '$credits');

  /// The figure with its unit: "6 cr", or the app's own words.
  String withUnit(int credits, {String unit = 'cr'}) {
    final t = of(credits);
    return t == null ? '' : (custom ? t : '$t $unit');
  }
}

class _StartupAidStudioState extends State<StartupAidStudio> {
  StudioConfig? config;
  String? loadError;
  List<StudioFeature> tabs = const [];
  int tab = 0;

  // Pictures.
  late final TextEditingController imagePrompt =
      TextEditingController(text: widget.prompt ?? '');
  String? imageModel;
  String? imageSize;
  int imageCount = 1;
  bool makingImages = false;
  String? imageError;
  List<StudioAsset> images = [];

  // Video.
  late final TextEditingController videoPrompt =
      TextEditingController(text: widget.prompt ?? '');
  StudioAsset? startPicture;
  bool uploading = false;
  String? videoModel;
  int? secs;
  late String aspect = widget.aspectRatio;
  int? quote;
  Timer? quoteTimer;
  bool makingVideo = false;
  String? videoError;
  List<StudioAsset> clips = [];

  // Voice & music.
  bool musicMode = false;
  final TextEditingController speechText = TextEditingController();
  late final TextEditingController musicPrompt = TextEditingController();
  String? voice;
  String? language; // null = taken from the text
  int musicSecs = 20;
  bool makingSound = false;
  String? soundError;
  List<StudioAsset> sounds = [];

  // Presenters.
  final TextEditingController script = TextEditingController();
  String? avatar;
  List<StudioAvatar> minePresenters = const [];
  bool addingPresenter = false;
  String avatarCategory = '';
  String talkAspect = '9:16';
  int? talkQuote;
  Timer? talkQuoteTimer;
  bool makingTalk = false;
  String? talkError;
  List<StudioAsset> talks = [];

  Timer? poller;
  _Prices prices = const _Prices();

  @override
  void initState() {
    super.initState();
    script.addListener(requoteTalk);
    speechText.addListener(_rebuild);
    load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    quoteTimer?.cancel();
    talkQuoteTimer?.cancel();
    poller?.cancel();
    imagePrompt.dispose();
    videoPrompt.dispose();
    speechText.dispose();
    musicPrompt.dispose();
    script.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loadError = null);
    try {
      final c = await widget.client.config();
      if (!mounted) return;
      final offered = [
        for (final f in widget.features)
          if (c.offers(f)) f,
      ];
      widget.onBudget?.call(c.budget);
      setState(() {
        config = c;
        tabs = offered;
        tab = 0;
        if (c.imageModels.isNotEmpty) {
          imageModel = c.imageModels
              .firstWhere((m) => m.mode == 'text',
                  orElse: () => c.imageModels.first)
              .id;
          imageSize = c.imageSizes.contains(widget.imageSize)
              ? widget.imageSize
              : (c.imageSizes.isNotEmpty ? c.imageSizes.first : null);
        }
        if (!c.aspectRatios.contains(aspect) && c.aspectRatios.isNotEmpty) {
          aspect = c.aspectRatios.first;
        }
        final a = c.audio;
        if (a != null) {
          voice = a.voices.isNotEmpty ? a.voices.first.id : null;
          musicSecs = a.lengths.contains(a.defaultSecs)
              ? a.defaultSecs
              : (a.lengths.isNotEmpty ? a.lengths.first : 20);
          musicMode = !a.speech && a.music;
        }
        final t = c.talking;
        minePresenters = t?.mine ?? const [];
        if (t != null && t.avatars.isNotEmpty) avatar = t.avatars.first.id;
      });
      pickVideoModel();
      requoteTalk();
      // Earlier work, so coming back shows what was made.
      Future<void> history(
          String kind, void Function(List<StudioAsset>) put) async {
        try {
          final a = await widget.client.assets(kind: kind, limit: 12);
          if (mounted) setState(() => put(a));
          watch();
        } catch (_) {
          // the list fills as they make more
        }
      }

      if (offered.contains(StudioFeature.images)) {
        history('image', (a) => images = _merge(images, a));
      }
      if (offered.contains(StudioFeature.video)) {
        history('video', (a) => clips = _merge(clips, a));
        if (widget.startImage != null) {
          uploadStart(widget.startImage!, 'start.jpg');
        }
      }
      if (offered.contains(StudioFeature.audio)) {
        history('speech,music', (a) => sounds = _merge(sounds, a));
      }
      if (offered.contains(StudioFeature.talking)) {
        history('talking', (a) => talks = _merge(talks, a));
      }
    } on StudioException catch (e) {
      if (mounted) setState(() => loadError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => loadError =
            "The studio couldn't be reached. Check your connection and try again.");
      }
    }
  }

  static List<StudioAsset> _merge(
          List<StudioAsset> have, List<StudioAsset> more) =>
      [
        ...have,
        ...more.where((x) => !have.any((y) => y.id == x.id)),
      ];

  Future<void> refreshBudget() async {
    try {
      final c = await widget.client.config();
      widget.onBudget?.call(c.budget);
      if (mounted) setState(() => config = c);
    } catch (_) {
      // the figure can wait for the next try
    }
  }

  // ---- pictures ----

  StudioImageModel? get currentImageModel =>
      config?.imageModels.where((m) => m.id == imageModel).firstOrNull;

  Future<void> makeImages() async {
    final m = currentImageModel;
    if (m == null || imagePrompt.text.trim().isEmpty) {
      setState(() => imageError = 'Describe the picture you want.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      makingImages = true;
      imageError = null;
    });
    try {
      final made = await widget.client.createImages(
        prompt: imagePrompt.text.trim(),
        model: m.id,
        size: m.sizable ? imageSize : null,
        count: imageCount,
      );
      if (mounted) setState(() => images = [...made, ...images]);
      refreshBudget();
    } on StudioException catch (e) {
      if (mounted) setState(() => imageError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => imageError = "That didn't go through. Try again.");
      }
    } finally {
      if (mounted) setState(() => makingImages = false);
    }
  }

  // ---- video ----

  List<StudioVideoModel> get videoModels => [
        for (final m in config?.videoModels ?? const <StudioVideoModel>[])
          if (m.fromPicture == (startPicture != null)) m,
      ];

  StudioVideoModel? get currentVideoModel =>
      videoModels.where((m) => m.id == videoModel).firstOrNull;

  void pickVideoModel() {
    final models = videoModels;
    setState(() {
      if (!models.any((m) => m.id == videoModel)) {
        videoModel = models.isEmpty ? null : models.first.id;
      }
      final m = currentVideoModel;
      if (m != null && !m.lengths.contains(secs)) {
        secs = m.lengths.contains(5) ? 5 : m.lengths.first;
      }
    });
    requote();
  }

  void requote() {
    quoteTimer?.cancel();
    final m = currentVideoModel;
    setState(() => quote = null);
    if (m == null) return;
    quoteTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final q = await widget.client.quoteVideo(
            model: m.id,
            aspectRatio: aspect,
            durationSecs: secs,
            sourceImageUrl: startPicture?.url);
        if (mounted && m.id == videoModel) setState(() => quote = q);
      } on StudioException catch (e) {
        if (mounted) setState(() => videoError = e.message);
      } catch (_) {
        // the button still works; the price shows when it can
      }
    });
  }

  Future<void> uploadStart(Uint8List bytes, String name) async {
    setState(() {
      uploading = true;
      videoError = null;
    });
    try {
      final a = await widget.client.upload(bytes, filename: name);
      if (!mounted) return;
      setState(() => startPicture = a);
      pickVideoModel();
    } on StudioException catch (e) {
      if (mounted) setState(() => videoError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => videoError = "That picture didn't upload. Try again.");
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> pickFromGallery() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90);
    if (x == null) return;
    await uploadStart(await x.readAsBytes(), x.name);
  }

  void animate(StudioAsset picture) {
    setState(() {
      startPicture = picture;
      tab = tabs.indexOf(StudioFeature.video);
      // The picture's own description says what it is, not what happens in
      // it; leave the clip's to be written.
      if (videoPrompt.text.trim() == picture.prompt.trim()) videoPrompt.clear();
    });
    pickVideoModel();
  }

  Future<void> makeVideo() async {
    final m = currentVideoModel;
    if (m == null || videoPrompt.text.trim().isEmpty) {
      setState(() => videoError = startPicture == null
          ? 'Describe the clip you want.'
          : 'Say what happens in the picture.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      makingVideo = true;
      videoError = null;
    });
    try {
      final clip = await widget.client.createVideo(
        prompt: videoPrompt.text.trim(),
        model: m.id,
        aspectRatio: aspect,
        durationSecs: secs,
        sourceImageUrl: startPicture?.url,
        requestId: '${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() => clips = [clip, ...clips]);
      watch();
      refreshBudget();
    } on StudioException catch (e) {
      if (mounted) setState(() => videoError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => videoError = "That didn't go through. Try again.");
      }
    } finally {
      if (mounted) setState(() => makingVideo = false);
    }
  }

  // ---- voice & music ----

  int get soundPrice {
    final a = config?.audio;
    if (a == null) return 0;
    return musicMode ? a.musicPrice(musicSecs) : a.speechPrice(speechText.text);
  }

  Future<void> makeSound() async {
    final text = (musicMode ? musicPrompt : speechText).text.trim();
    if (text.isEmpty) {
      setState(() => soundError = musicMode
          ? 'Describe the music you want.'
          : 'Write what should be said.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      makingSound = true;
      soundError = null;
    });
    try {
      final made = musicMode
          ? await widget.client.createMusic(prompt: text, seconds: musicSecs)
          : await widget.client
              .createSpeech(text: text, voice: voice, language: language);
      if (!mounted) return;
      setState(() => sounds = [made, ...sounds]);
      watch();
      refreshBudget();
    } on StudioException catch (e) {
      if (mounted) setState(() => soundError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => soundError = "That didn't go through. Try again.");
      }
    } finally {
      if (mounted) setState(() => makingSound = false);
    }
  }

  Future<void> pickLanguage(StudioLook look) async {
    final a = config?.audio;
    if (a == null) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: look.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: ListView(
          children: [
            for (final l in [
              const StudioLanguage(code: '', name: 'Work it out from the text'),
              ...a.languages
            ])
              ListTile(
                title: Text(l.name,
                    style: look.style(16,
                        weight: (language ?? '') == l.code
                            ? FontWeight.w700
                            : FontWeight.w400)),
                trailing: (language ?? '') == l.code
                    ? Icon(Icons.check_rounded, color: look.accent)
                    : null,
                onTap: () => Navigator.of(ctx).pop(l.code),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => language = picked.isEmpty ? null : picked);
    }
  }

  // ---- presenters ----

  // Their own presenter. The photo leaves the phone only once they've said
  // they may use it.
  Future<void> addPresenter(StudioConfig c, StudioLook look) async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final saved = await showModalBottomSheet<({String name, String voice})>(
      context: context,
      backgroundColor: look.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _Look(
        look: look,
        child: Theme(
          data: look.material(),
          child: _NewPresenter(photo: bytes, voices: c.talking!.voices),
        ),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      addingPresenter = true;
      talkError = null;
    });
    try {
      final up = await widget.client.upload(bytes, filename: x.name);
      final made = await widget.client.createPresenter(
          uploadId: up.id,
          name: saved.name,
          voice: saved.voice,
          consent: true);
      if (!mounted) return;
      setState(() {
        minePresenters = [made, ...minePresenters];
        avatar = made.id;
        avatarCategory = '';
      });
      requoteTalk();
    } on StudioException catch (e) {
      if (mounted) setState(() => talkError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => talkError = "That presenter wasn't saved. Try again.");
      }
    } finally {
      if (mounted) setState(() => addingPresenter = false);
    }
  }

  Future<void> removePresenter(StudioAvatar who, StudioLook look) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: look.card,
        title: Text('Remove ${who.name}?',
            style: look.style(18, weight: FontWeight.w700)),
        content: Text(
            'Their photo is deleted too. Videos already made stay in your list.',
            style: look.style(15, color: look.muted, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Keep',
                  style: look.style(15, weight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Remove',
                  style: look.style(15,
                      weight: FontWeight.w700, color: look.danger))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await widget.client.deletePresenter(who.id);
      if (!mounted) return;
      final stock = config?.talking?.avatars ?? const <StudioAvatar>[];
      setState(() {
        minePresenters = [
          for (final m in minePresenters)
            if (m.id != who.id) m
        ];
        if (avatar == who.id) {
          avatar = minePresenters.isNotEmpty
              ? minePresenters.first.id
              : (stock.isNotEmpty ? stock.first.id : null);
        }
      });
      requoteTalk();
    } on StudioException catch (e) {
      if (mounted) setState(() => talkError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => talkError = "That didn't go through. Try again.");
      }
    }
  }

  void requoteTalk() {
    talkQuoteTimer?.cancel();
    final who = avatar;
    if (!mounted) return;
    setState(() => talkQuote = null);
    if (who == null || script.text.trim().isEmpty || config?.talking == null) {
      return;
    }
    talkQuoteTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final q = await widget.client.quoteTalking(
            avatarId: who, script: script.text.trim(), aspectRatio: talkAspect);
        if (mounted && who == avatar) setState(() => talkQuote = q);
      } catch (_) {
        // the price shows when it can
      }
    });
  }

  Future<void> makeTalk() async {
    final who = avatar;
    if (who == null || script.text.trim().isEmpty) {
      setState(() => talkError = 'Pick a presenter and write what they say.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      makingTalk = true;
      talkError = null;
    });
    try {
      final made = await widget.client.createTalking(
          avatarId: who, script: script.text.trim(), aspectRatio: talkAspect);
      if (!mounted) return;
      setState(() => talks = [made, ...talks]);
      watch();
      refreshBudget();
    } on StudioException catch (e) {
      if (mounted) setState(() => talkError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => talkError = "That didn't go through. Try again.");
      }
    } finally {
      if (mounted) setState(() => makingTalk = false);
    }
  }

  // ---- keeping up with what's being made ----

  List<StudioAsset> get _pending =>
      [...clips, ...sounds, ...talks].where((a) => a.isPending).toList();

  // Clips, sound and presenter videos take a while; check the ones still
  // being made.
  void watch() {
    if (poller != null || _pending.isEmpty) return;
    poller = Timer.periodic(const Duration(seconds: 4), (_) async {
      final pending = _pending;
      if (pending.isEmpty) {
        poller?.cancel();
        poller = null;
        return;
      }
      for (final p in pending) {
        try {
          final fresh = await widget.client.asset(p.id);
          if (!mounted) return;
          if (!fresh.isPending) {
            List<StudioAsset> swap(List<StudioAsset> list) =>
                [for (final c in list) c.id == fresh.id ? fresh : c];
            setState(() {
              clips = swap(clips);
              sounds = swap(sounds);
              talks = swap(talks);
            });
            if (fresh.isFailed) refreshBudget();
          }
        } catch (_) {
          // try again on the next tick
        }
      }
    });
  }

  // ---- picking ----

  Future<void> open(StudioAsset a, StudioLook look) async {
    final choice = await Navigator.of(context).push<String>(PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => _Preview(
        asset: a,
        look: look,
        prices: prices,
        canUse: widget.onSelected != null,
        canAnimate: !a.isVideo && tabs.contains(StudioFeature.video),
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child),
    ));
    if (!mounted) return;
    if (choice == 'use') widget.onSelected?.call(a);
    if (choice == 'animate') animate(a);
  }

  // ---- layout ----

  static const _tabLabel = {
    StudioFeature.images: 'Pictures',
    StudioFeature.video: 'Video',
    StudioFeature.audio: 'Voice',
    StudioFeature.talking: 'Presenter',
    StudioFeature.movies: 'Film Maker',
  };
  static const _tabIcon = {
    StudioFeature.images: Icons.image_rounded,
    StudioFeature.video: Icons.movie_rounded,
    StudioFeature.audio: Icons.graphic_eq_rounded,
    StudioFeature.talking: Icons.record_voice_over_rounded,
    StudioFeature.movies: Icons.movie_edit,
  };

  Widget? _button(StudioFeature f) => switch (f) {
        StudioFeature.images => _MakeButton(
            label: makingImages
                ? 'Making…'
                : 'Make $imageCount picture${imageCount == 1 ? '' : 's'}',
            price: makingImages
                ? null
                : (currentImageModel?.credits ?? 0) * imageCount,
            busy: makingImages,
            icon: Icons.auto_awesome_rounded,
            onPressed: makingImages ? null : makeImages,
          ),
        StudioFeature.video => _MakeButton(
            label: makingVideo ? 'Starting…' : 'Make the clip',
            price: makingVideo ? null : quote,
            busy: makingVideo,
            icon: Icons.movie_creation_rounded,
            onPressed: makingVideo || uploading || currentVideoModel == null
                ? null
                : makeVideo,
          ),
        StudioFeature.audio => _MakeButton(
            label: makingSound
                ? 'Starting…'
                : (musicMode ? 'Make the music' : 'Make the voice'),
            price: makingSound || soundPrice == 0 ? null : soundPrice,
            busy: makingSound,
            icon: musicMode
                ? Icons.music_note_rounded
                : Icons.record_voice_over_rounded,
            onPressed: makingSound ? null : makeSound,
          ),
        StudioFeature.talking => _MakeButton(
            label: makingTalk ? 'Starting…' : 'Make the video',
            price: makingTalk ? null : talkQuote,
            busy: makingTalk,
            icon: Icons.videocam_rounded,
            onPressed: makingTalk || avatar == null ? null : makeTalk,
          ),
        // Film Maker has its own buttons, inside the editor.
        StudioFeature.movies => null,
      };

  @override
  Widget build(BuildContext context) {
    final c = config;
    final look = StudioLook.resolve(
        context, (c?.theme ?? const StudioTheme()).merge(widget.theme));
    final current = tabs.isNotEmpty ? tabs[tab] : null;
    prices = _Prices(
        show: widget.priceLabel != null || (c?.display.showCredits ?? true),
        label: widget.priceLabel);
    final budget = c?.budget;
    // Close to the day's limit (a fifth or less left), or at it.
    final low = c != null &&
        c.display.warnLow &&
        budget != null &&
        budget.dailyCredits > 0 &&
        budget.remaining * 5 <= budget.dailyCredits;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: look.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Theme(
        data: look.material(),
        child: _Look(
          look: look,
          prices: prices,
          child: Scaffold(
            backgroundColor: look.background,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _Header(
                      title: widget.title,
                      remaining: c?.budget.remaining,
                      onClose: () => Navigator.of(context).maybePop()),
                  if (loadError != null)
                    Expanded(
                        child: _Message(
                            icon: Icons.wifi_off_rounded,
                            text: loadError!,
                            action: 'Try again',
                            onAction: load))
                  else if (c == null)
                    const Expanded(
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2.5)))
                  else if (current == null)
                    const Expanded(
                        child: _Message(
                            icon: Icons.auto_awesome_outlined,
                            text:
                                "This app's studio has nothing to offer right now."))
                  else ...[
                    if (tabs.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: _Tabs(
                          labels: [for (final f in tabs) _tabLabel[f]!],
                          icons: [for (final f in tabs) _tabIcon[f]!],
                          index: tab,
                          onChanged: (i) => setState(() => tab = i),
                        ),
                      ),
                    if (low) _LowBanner(remaining: budget.remaining),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(tab),
                          child: switch (current) {
                            StudioFeature.images => imagesTab(c, look),
                            StudioFeature.video => videoTab(c, look),
                            StudioFeature.audio => soundTab(c, look),
                            StudioFeature.talking => talkTab(c, look),
                            // Film Maker: StartupAid's editor, right in the
                            // tab, as this user.
                            StudioFeature.movies => MovieMakerView(
                                client: widget.client,
                                title: widget.title,
                                bare: true,
                                look: look,
                                priceLabel: widget.priceLabel,
                                onPicked: (a) => widget.onSelected?.call(a),
                              ),
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            bottomNavigationBar: c == null ||
                    current == null ||
                    loadError != null ||
                    _button(current) == null
                ? null
                : _BottomBar(child: _button(current)!),
          ),
        ),
      ),
    );
  }

  Widget imagesTab(StudioConfig c, StudioLook look) {
    final m = currentImageModel;
    final models = [
      for (final m in c.imageModels)
        if (m.mode == 'text') m,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _PromptField(
            controller: imagePrompt, hint: 'Describe the picture you want…'),
        if (models.length > 1) ...[
          const _Label('Style'),
          _ModelRow(
            items: [
              for (final m in models)
                (
                  id: m.id,
                  title: m.label,
                  detail: m.note,
                  price: prices.withUnit(m.credits)
                )
            ],
            selected: imageModel,
            onSelected: (id) => setState(() => imageModel = id),
          ),
        ],
        if (m != null && m.sizable && c.imageSizes.isNotEmpty) ...[
          const _Label('Shape'),
          _Pills<String>(
              values: c.imageSizes,
              selected: imageSize,
              shape: true,
              onSelected: (s) => setState(() => imageSize = s)),
        ],
        if (c.maxImageCount > 1) ...[
          const _Label('How many'),
          _Pills<int>(
            values: [
              for (var i = 1;
                  i <= c.maxImageCount && i <= (m?.maxImages ?? 1);
                  i++)
                i
            ],
            selected: imageCount,
            onSelected: (n) => setState(() => imageCount = n),
          ),
        ],
        if (imageError != null) _ErrorBanner(imageError!),
        _Gallery(
          title: 'Your pictures',
          items: images,
          onTap: (a) => open(a, look),
          emptyIcon: Icons.image_outlined,
          empty: 'What you make shows up here.',
        ),
      ],
    );
  }

  Widget videoTab(StudioConfig c, StudioLook look) {
    final m = currentVideoModel;
    final models = videoModels;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _StartPicture(
          picture: startPicture,
          uploading: uploading,
          onPick: pickFromGallery,
          onClear: () {
            setState(() => startPicture = null);
            pickVideoModel();
          },
        ),
        const SizedBox(height: 12),
        _PromptField(
          controller: videoPrompt,
          hint: startPicture == null
              ? 'Describe the clip: what we see, how the camera moves…'
              : 'What happens? Rain starts falling, the camera slowly pushes in…',
        ),
        if (models.isEmpty)
          _ErrorBanner(startPicture == null
              ? "Clips from a description aren't available here."
              : "Clips from a picture aren't available here.")
        else ...[
          if (models.length > 1) ...[
            const _Label('Model'),
            _ModelRow(
              items: [
                for (final m in models)
                  (
                    id: m.id,
                    title: m.label,
                    detail: m.tag.isEmpty ? m.engine : m.tag,
                    price: prices.of(m.credits) == null
                        ? ''
                        : 'from ${prices.withUnit(m.credits)}'
                  )
              ],
              selected: videoModel,
              onSelected: (id) {
                setState(() => videoModel = id);
                pickVideoModel();
              },
            ),
          ],
          if (m != null && !m.realPeople && startPicture != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: look.muted),
                const SizedBox(width: 6),
                Expanded(
                    child: Text("This one won't animate photos of real people.",
                        style: look.style(13, color: look.muted))),
              ]),
            ),
          if (m != null) ...[
            const _Label('Length'),
            _Pills<int>(
              values: m.lengths,
              selected: secs,
              name: (s) => '$s sec',
              onSelected: (s) {
                setState(() => secs = s);
                requote();
              },
            ),
          ],
          if (startPicture == null) ...[
            const _Label('Shape'),
            _Pills<String>(
              values: c.aspectRatios,
              selected: aspect,
              shape: true,
              onSelected: (a) {
                setState(() => aspect = a);
                requote();
              },
            ),
          ],
        ],
        if (videoError != null) _ErrorBanner(videoError!),
        _Gallery(
          title: 'Your clips',
          note: clips.any((c) => c.isPending)
              ? 'Clips take a minute or two. Keep going while they’re made.'
              : null,
          items: clips,
          onTap: (a) => open(a, look),
          emptyIcon: Icons.movie_outlined,
          empty: 'Clips take a minute or two. They show up here.',
        ),
      ],
    );
  }

  Widget soundTab(StudioConfig c, StudioLook look) {
    final a = c.audio!;
    final both = a.speech && a.music;
    final langName = language == null
        ? 'Work it out from the text'
        : a.languages.where((l) => l.code == language).firstOrNull?.name ??
            language!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (both)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _Pills<bool>(
              values: const [false, true],
              selected: musicMode,
              name: (m) => m ? 'Music' : 'Speech',
              onSelected: (m) => setState(() {
                musicMode = m;
                soundError = null;
              }),
            ),
          ),
        if (!musicMode) ...[
          _PromptField(
              controller: speechText, hint: 'Type what should be said…'),
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
                '${speechText.text.trim().runes.length} / ${a.maxChars}',
                textAlign: TextAlign.right,
                style: look.style(12.5, color: look.muted)),
          ),
          const _Label('Voice'),
          _ModelRow(
            items: [
              for (final v in a.voices)
                (id: v.id, title: v.id, detail: v.note, price: '')
            ],
            selected: voice,
            onSelected: (id) => setState(() => voice = id),
          ),
          if (a.languages.isNotEmpty) ...[
            const _Label('Language'),
            _RowButton(
                icon: Icons.translate_rounded,
                label: langName,
                onTap: () => pickLanguage(look)),
          ],
        ] else ...[
          _PromptField(
              controller: musicPrompt,
              hint:
                  'Describe the music: warm lo-fi beat, slow piano, upbeat Afrobeats…'),
          const _Label('Length'),
          _Pills<int>(
            values: a.lengths,
            selected: musicSecs,
            name: (s) => '$s sec',
            onSelected: (s) => setState(() => musicSecs = s),
          ),
        ],
        if (soundError != null) _ErrorBanner(soundError!),
        _AudioList(
          items: sounds,
          onUse: widget.onSelected,
        ),
      ],
    );
  }

  Widget talkTab(StudioConfig c, StudioLook look) {
    final t = c.talking!;
    final shown = [
      for (final av in t.avatars)
        if (avatarCategory.isEmpty || av.category == avatarCategory) av,
    ];
    final categories = [
      for (final cat in t.categories)
        if (t.avatars.any((av) => av.category == cat)) cat,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const _Label('Presenter'),
        if (categories.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final cat in ['', ...categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Pills<String>(
                        values: [cat],
                        selected: avatarCategory,
                        name: (v) => v.isEmpty ? 'All' : v,
                        onSelected: (v) => setState(() => avatarCategory = v),
                      ),
                    ),
                ],
              ),
            ),
          ),
        _AvatarRow(
          avatars: [...minePresenters, ...shown],
          selected: avatar,
          onSelected: (id) {
            setState(() => avatar = id);
            requoteTalk();
          },
          // Only a server that offers voices can make one of their own.
          adding: addingPresenter,
          onAdd: t.voices.isEmpty ? null : () => addPresenter(c, look),
          mine: {for (final m in minePresenters) m.id},
          onRemove: (id) => removePresenter(
              minePresenters.firstWhere((m) => m.id == id), look),
        ),
        const _Label('What they say'),
        _PromptField(
            controller: script,
            hint: 'Hi, I’m here to show you three things you’ll love about…'),
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 4),
          child: Text('${script.text.trim().runes.length} / ${t.maxChars}',
              textAlign: TextAlign.right,
              style: look.style(12.5, color: look.muted)),
        ),
        const _Label('Shape'),
        _Pills<String>(
          values: t.aspectRatios,
          selected: talkAspect,
          shape: true,
          onSelected: (a) {
            setState(() => talkAspect = a);
            requoteTalk();
          },
        ),
        if (talkError != null) _ErrorBanner(talkError!),
        _Gallery(
          title: 'Your presenter videos',
          note: talks.any((c) => c.isPending)
              ? 'Presenter videos take a few minutes. Keep going while they’re made.'
              : null,
          items: talks,
          onTap: (a) => open(a, look),
          emptyIcon: Icons.videocam_outlined,
          empty: 'Presenter videos take a few minutes. They show up here.',
        ),
      ],
    );
  }
}

// ---- pieces ----

/// How much room text takes in the font it will really be drawn in (the app's
/// own, unless the Look names one) at the phone's text size.
Size _measure(BuildContext context, String text, TextStyle style,
    {double maxWidth = double.infinity, int maxLines = 1}) {
  final painter = TextPainter(
    text: TextSpan(
        text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  final size = painter.size;
  painter.dispose();
  return size;
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.title, required this.remaining, required this.onClose});

  final String title;
  final int? remaining;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
      child: Row(
        children: [
          _RoundIcon(
              icon: Icons.close_rounded, onTap: onClose, tooltip: 'Close'),
          const SizedBox(width: 10),
          // The balance sits beside the title, or under it when an app's own
          // price words are too long for one line; the title is never cut.
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title,
                    style:
                        look.style(22, weight: FontWeight.w700, spacing: -0.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (remaining != null && _Look.pricesOf(context).show)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(remaining),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: look.accent
                              .withValues(alpha: look.dark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!_Look.pricesOf(context).custom) ...[
                          Icon(Icons.bolt_rounded,
                              size: 16, color: look.accentText),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                              '${_Look.pricesOf(context).of(remaining!)} left today',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: look.style(13,
                                  weight: FontWeight.w600,
                                  color: look.accentText)),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon,
      required this.onTap,
      this.tooltip,
      this.onDark = false});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: onDark ? Colors.white.withValues(alpha: 0.14) : look.field,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon,
                  size: 22, color: onDark ? Colors.white : look.text)),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs(
      {required this.labels,
      required this.icons,
      required this.index,
      required this.onChanged});

  final List<String> labels;
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final r = look.pill ? 999.0 : look.radius;
    // More than two: the icon over a small label, so four still fit a phone.
    final compact = labels.length > 2;
    return Container(
      height: compact ? 60 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: look.field, borderRadius: BorderRadius.circular(r)),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(
                labels.length == 1 ? 0 : -1 + 2 * index / (labels.length - 1),
                0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 1 / labels.length,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Lifted off the track: brighter than it in either mode.
                  color: look.dark
                      ? Color.lerp(look.field, Colors.white, 0.1)
                      : look.card,
                  borderRadius: BorderRadius.circular(
                      r == 999 ? 999 : (r - 4).clamp(2, 999)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black
                            .withValues(alpha: look.dark ? 0.35 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: compact
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icons[i],
                                      size: 20,
                                      color: i == index
                                          ? look.accent
                                          : look.muted),
                                  const SizedBox(height: 3),
                                  Text(labels[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: look.style(12.5,
                                          weight: FontWeight.w600,
                                          color: i == index
                                              ? look.text
                                              : look.muted)),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icons[i],
                                      size: 18,
                                      color: i == index
                                          ? look.accent
                                          : look.muted),
                                  const SizedBox(width: 6),
                                  Text(labels[i],
                                      style: look.style(15,
                                          weight: FontWeight.w600,
                                          color: i == index
                                              ? look.text
                                              : look.muted)),
                                ],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(text.toUpperCase(),
          style: look.style(12,
              weight: FontWeight.w700, color: look.muted, spacing: 1.1)),
    );
  }
}

class _PromptField extends StatelessWidget {
  const _PromptField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Container(
      decoration: BoxDecoration(
        color: look.card,
        borderRadius: look.corners,
        border: Border.all(color: look.line),
        boxShadow: look.dark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: look.style(16, height: 1.4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: look.style(16, color: look.muted, height: 1.4),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => controller.text.isEmpty
                ? const SizedBox(width: 8)
                : IconButton(
                    onPressed: controller.clear,
                    icon:
                        Icon(Icons.cancel_rounded, size: 20, color: look.muted),
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow(
      {required this.items, required this.selected, required this.onSelected});

  final List<({String id, String title, String detail, String price})> items;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final titleStyle = look.style(15, weight: FontWeight.w700);
    final detailStyle = look.style(12.5, color: look.muted);
    final priceStyle = look.style(12.5, weight: FontWeight.w700);
    // Sized to what's in them: an app's own price words, its font and the
    // phone's text size all vary. Cards widen to keep a price on one line, up
    // to a point; past that it takes two lines and the row grows.
    const inset = 2 * (12 + 1.6);
    final screen = MediaQuery.sizeOf(context).width;
    final widest = items.fold<double>(
        0, (w, it) => max(w, _measure(context, it.price, priceStyle).width));
    final double width =
        (widest + inset).clamp(158.0, max(158.0, screen * 0.7)).toDouble();
    double priceHeight = 0;
    for (final it in items) {
      if (it.price.isEmpty) continue;
      priceHeight = max(
          priceHeight,
          _measure(context, it.price, priceStyle,
                  maxWidth: width - inset, maxLines: 2)
              .height);
    }
    final height = inset +
        _measure(context, 'Hg', titleStyle).height +
        2 +
        _measure(context, 'Hg', detailStyle).height +
        (priceHeight > 0 ? 8 + priceHeight : 0);
    return SizedBox(
      height: max(92, height.ceilToDouble() + 1),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final it = items[i];
          final on = it.id == selected;
          return GestureDetector(
            onTap: () => onSelected(it.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: width,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: on
                    ? look.accent.withValues(alpha: look.dark ? 0.16 : 0.07)
                    : look.card,
                borderRadius:
                    BorderRadius.circular(look.pill ? 20 : look.radius),
                border: Border.all(
                    color: on ? look.accent : look.line, width: on ? 1.6 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(it.title,
                            style: titleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    AnimatedOpacity(
                      opacity: on ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.check_circle_rounded,
                          size: 18, color: look.accent),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(it.detail,
                      style: detailStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  if (it.price.isNotEmpty)
                    Text(it.price,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: priceStyle.copyWith(
                            color: on ? look.accentText : look.text)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Pills<T> extends StatelessWidget {
  const _Pills(
      {required this.values,
      required this.selected,
      required this.onSelected,
      this.name,
      this.shape = false});

  final List<T> values;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String Function(T)? name;

  /// Values are ratios ("3:4"); draw a little frame of that shape.
  final bool shape;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          Semantics(
            selected: v == selected,
            button: true,
            child: GestureDetector(
              onTap: () => onSelected(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                    horizontal: shape ? 12 : 16, vertical: 10),
                decoration: BoxDecoration(
                  color: v == selected ? look.accent : look.card,
                  borderRadius: BorderRadius.circular(look.chipRadius),
                  border: Border.all(
                      color: v == selected ? look.accent : look.line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (shape) ...[
                    _Frame(
                        ratio: '$v',
                        color: v == selected ? look.onAccent : look.muted),
                    const SizedBox(width: 8)
                  ],
                  Text(name?.call(v) ?? '$v',
                      style: look.style(14,
                          weight: FontWeight.w600,
                          color: v == selected ? look.onAccent : look.text)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small outline of an aspect ratio.
class _Frame extends StatelessWidget {
  const _Frame({required this.ratio, required this.color});

  final String ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final parts = ratio.split(':');
    final w = double.tryParse(parts.first) ?? 1;
    final h = double.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    const box = 16.0;
    final scale = box / (w > h ? w : h);
    return SizedBox(
      width: box,
      height: box,
      child: Center(
        child: Container(
          width: w * scale,
          height: h * scale,
          decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.6),
              borderRadius: BorderRadius.circular(2.5)),
        ),
      ),
    );
  }
}

class _StartPicture extends StatelessWidget {
  const _StartPicture(
      {required this.picture,
      required this.uploading,
      required this.onPick,
      required this.onClear});

  final StudioAsset? picture;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final p = picture;
    return Material(
      color: look.card,
      shape: RoundedRectangleBorder(
          borderRadius: look.corners, side: BorderSide(color: look.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: uploading || p != null ? null : onPick,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular((look.radius * 0.7).clamp(4, 14)),
                child: Container(
                  width: 64,
                  height: 64,
                  color: look.field,
                  child: uploading
                      ? const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4)))
                      : p == null
                          ? Icon(Icons.add_photo_alternate_rounded,
                              color: look.accent, size: 28)
                          : _NetImage(p.url),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uploading
                          ? 'Uploading…'
                          : p == null
                              ? 'Start from a picture'
                              : 'Starting from this picture',
                      style: look.style(15, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p == null
                          ? 'Optional. Animate a photo, or describe a clip from scratch.'
                          : 'The clip opens on it and brings it to life.',
                      style: look.style(13, color: look.muted, height: 1.3),
                    ),
                  ],
                ),
              ),
              if (p != null && !uploading)
                _RoundIcon(
                    icon: Icons.close_rounded,
                    onTap: onClear,
                    tooltip: 'Start from words instead'),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Container(
      decoration: BoxDecoration(
          color: look.background,
          border: Border(top: BorderSide(color: look.line))),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      child: child,
    );
  }
}

class _MakeButton extends StatelessWidget {
  const _MakeButton(
      {required this.label,
      required this.price,
      required this.busy,
      required this.icon,
      required this.onPressed});

  final String label;
  final int? price;
  final bool busy;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final enabled = onPressed != null;
    final prices = _Look.pricesOf(context);
    final figure = price == null ? null : prices.of(price!);
    final labelStyle =
        look.style(16.5, weight: FontWeight.w700, color: look.onAccent);
    final figureStyle =
        look.style(14, weight: FontWeight.w700, color: look.onAccent);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled || busy ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: look.gradient,
          borderRadius: BorderRadius.circular(look.buttonRadius),
          boxShadow: [
            BoxShadow(
                color: look.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6))
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(look.buttonRadius),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: LayoutBuilder(builder: (context, box) {
                  // The price sits in a chip beside the words when both fit,
                  // and under them when an app's own price words are long.
                  const iconAndGap = 22 + 10;
                  final chip = figure == null
                      ? 0.0
                      : 20 +
                          (prices.custom ? 0 : 15) +
                          _measure(context, figure, figureStyle).width;
                  final beside = figure == null ||
                      iconAndGap +
                              _measure(context, label, labelStyle).width +
                              8 +
                              chip <=
                          box.maxWidth;
                  return Row(
                    children: [
                      busy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: look.onAccent))
                          : Icon(icon, color: look.onAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: labelStyle),
                            if (!beside)
                              Text(figure,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: figureStyle.copyWith(fontSize: 12.5)),
                          ],
                        ),
                      ),
                      if (beside && figure != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: look.onAccent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (!prices.custom)
                              Icon(Icons.bolt_rounded,
                                  size: 15, color: look.onAccent),
                            Text(figure, style: figureStyle),
                          ]),
                        ),
                      ],
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: look.danger.withValues(alpha: 0.1),
            borderRadius:
                BorderRadius.circular((look.radius * 0.75).clamp(4, 14))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline_rounded, color: look.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: look.style(14, color: look.danger, height: 1.35))),
        ]),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery(
      {required this.title,
      required this.items,
      required this.onTap,
      required this.emptyIcon,
      required this.empty,
      this.note});

  final String title;
  final List<StudioAsset> items;
  final ValueChanged<StudioAsset> onTap;
  final IconData emptyIcon;
  final String empty;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 12),
          child: Row(children: [
            Text(title,
                style: look.style(18, weight: FontWeight.w700, spacing: -0.2)),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('${items.length}',
                  style: look.style(15,
                      weight: FontWeight.w600, color: look.muted)),
            ],
          ]),
        ),
        if (note != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(note!, style: look.style(13, color: look.muted))),
        if (items.isEmpty)
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
                borderRadius: look.corners,
                border: Border.all(color: look.line),
                color: look.card.withValues(alpha: 0.5)),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(emptyIcon,
                  size: 30, color: look.muted.withValues(alpha: 0.7)),
              const SizedBox(height: 8),
              Text(empty,
                  style: look.style(14, color: look.muted),
                  textAlign: TextAlign.center),
            ]),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
            children: [
              for (final a in items) _Tile(asset: a, onTap: () => onTap(a))
            ],
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.asset, required this.onTap});

  final StudioAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final a = asset;
    return ClipRRect(
      borderRadius: look.corners,
      child: Material(
        color: look.field,
        child: InkWell(
          onTap: a.isReady ? onTap : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (a.isPending)
                _Shimmer(label: a.isVideo ? 'Making your clip…' : 'Making…')
              else if (a.isFailed)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, color: look.danger),
                        const SizedBox(height: 8),
                        Text(a.error.isEmpty ? "Couldn't be made" : a.error,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style:
                                look.style(13, color: look.muted, height: 1.3)),
                      ]),
                )
              else if (a.previewUrl.isNotEmpty)
                _NetImage(a.previewUrl),
              if (a.isVideo && a.isReady) ...[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)]),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.play_arrow_rounded,
                          size: 18, color: look.accent),
                    ),
                    const SizedBox(width: 6),
                    Text('Clip',
                        style: look.style(13,
                            weight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage(this.url, {this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Image.network(
      url,
      fit: fit,
      frameBuilder: (_, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: child),
      errorBuilder: (_, __, ___) =>
          Center(child: Icon(Icons.broken_image_outlined, color: look.muted)),
    );
  }
}

/// A soft sweep of light while something is being made.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.label});

  final String label;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1.6 + 3.2 * c.value, -0.4),
            end: Alignment(-0.6 + 3.2 * c.value, 0.4),
            colors: [
              look.field,
              look.accent.withValues(alpha: look.dark ? 0.22 : 0.14),
              look.field
            ],
          ),
        ),
        child: child,
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_rounded, color: look.accent),
          const SizedBox(height: 8),
          Text(widget.label,
              style:
                  look.style(13, weight: FontWeight.w600, color: look.muted)),
        ]),
      ),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview(
      {required this.asset,
      required this.look,
      required this.prices,
      required this.canUse,
      required this.canAnimate});

  final StudioAsset asset;
  final StudioLook look;
  final _Prices prices;
  final bool canUse;
  final bool canAnimate;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  VideoPlayerController? player;

  @override
  void initState() {
    super.initState();
    if (widget.asset.isVideo) {
      player = VideoPlayerController.networkUrl(Uri.parse(widget.asset.url))
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            player?.play();
          }
        });
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final look = widget.look;
    final p = player;
    final backdrop = a.previewUrl;
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Theme(
          data: look.material(),
          child: _Look(
            look: look,
            prices: widget.prices,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  // The picture itself, blurred, fills the screen behind it.
                  if (backdrop.isNotEmpty)
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: Image.network(backdrop,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  Container(color: Colors.black.withValues(alpha: 0.55)),
                  SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: Row(children: [
                            _RoundIcon(
                                icon: Icons.close_rounded,
                                onTap: () => Navigator.of(context).pop(),
                                tooltip: 'Close',
                                onDark: true),
                            const SizedBox(width: 8),
                            Expanded(
                              child: a.credits > 0 && widget.prices.show
                                  ? Text(
                                      widget.prices
                                          .withUnit(a.credits, unit: 'credits'),
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: look.style(13,
                                          weight: FontWeight.w600,
                                          color: Colors.white70))
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 8),
                          ]),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: look.corners,
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0x80000000),
                                        blurRadius: 40,
                                        offset: Offset(0, 16))
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: look.corners,
                                  child: a.isVideo
                                      ? (p != null && p.value.isInitialized
                                          ? GestureDetector(
                                              onTap: () {
                                                p.value.isPlaying
                                                    ? p.pause()
                                                    : p.play();
                                                setState(() {});
                                              },
                                              child: AspectRatio(
                                                  aspectRatio:
                                                      p.value.aspectRatio,
                                                  child: VideoPlayer(p)),
                                            )
                                          : const SizedBox(
                                              width: 60,
                                              height: 60,
                                              child: Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                          color:
                                                              Colors.white))))
                                      : InteractiveViewer(
                                          child: _NetImage(a.url,
                                              fit: BoxFit.contain)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (a.prompt.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                            child: Text(a.prompt,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: look.style(14,
                                    color: Colors.white70, height: 1.4)),
                          ),
                        if (widget.canAnimate || widget.canUse)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: Row(children: [
                              if (widget.canAnimate)
                                Expanded(
                                  child: SizedBox(
                                    height: 56,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white38),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                look.buttonRadius)),
                                        textStyle: look.style(16,
                                            weight: FontWeight.w700),
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).pop('animate'),
                                      icon: const Icon(
                                          Icons.movie_creation_rounded),
                                      label: const Text('Animate it'),
                                    ),
                                  ),
                                ),
                              if (widget.canAnimate && widget.canUse)
                                const SizedBox(width: 12),
                              if (widget.canUse)
                                Expanded(
                                  child: _MakeButton(
                                    label: 'Use this',
                                    price: null,
                                    busy: false,
                                    icon: Icons.check_rounded,
                                    onPressed: () =>
                                        Navigator.of(context).pop('use'),
                                  ),
                                ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon, required this.text, this.action, this.onAction});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration:
                  BoxDecoration(color: look.field, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: look.muted),
            ),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: look.style(15, color: look.muted, height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 180,
                child: _MakeButton(
                    label: action!,
                    price: null,
                    busy: false,
                    icon: Icons.refresh_rounded,
                    onPressed: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable row that opens a choice, like the language list.
class _RowButton extends StatelessWidget {
  const _RowButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Material(
      color: look.card,
      shape: RoundedRectangleBorder(
          borderRadius: look.corners, side: BorderSide(color: look.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, color: look.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: look.style(15, weight: FontWeight.w600))),
            Icon(Icons.expand_more_rounded, color: look.muted),
          ]),
        ),
      ),
    );
  }
}

/// The presenters, as portrait cards in a row: a card to add their own, their
/// own, then the ready-made ones.
class _AvatarRow extends StatelessWidget {
  const _AvatarRow(
      {required this.avatars,
      required this.selected,
      required this.onSelected,
      this.adding = false,
      this.onAdd,
      this.mine = const {},
      this.onRemove});

  final List<StudioAvatar> avatars;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool adding;
  final VoidCallback? onAdd;
  final Set<String> mine;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: avatars.length + (onAdd == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          if (onAdd != null && index == 0) {
            return Semantics(
              button: true,
              label: 'Add your own presenter',
              child: GestureDetector(
                onTap: adding ? null : onAdd,
                child: SizedBox(
                  width: 104,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 130,
                        width: 104,
                        decoration: BoxDecoration(
                          color: look.card,
                          borderRadius: BorderRadius.circular(look.radius),
                          border: Border.all(color: look.line),
                        ),
                        child: Center(
                          child: adding
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4, color: look.accent))
                              : Icon(Icons.add_a_photo_rounded,
                                  color: look.accent, size: 28),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Add yours',
                          style: look.style(14, weight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('Your own photo',
                          style: look.style(12, color: look.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            );
          }
          final av = avatars[onAdd == null ? index : index - 1];
          final on = av.id == selected;
          return Semantics(
            selected: on,
            button: true,
            label: av.name,
            child: GestureDetector(
              onTap: () => onSelected(av.id),
              child: SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 130,
                      width: 104,
                      padding: EdgeInsets.all(on ? 3 : 0),
                      decoration: BoxDecoration(
                        gradient: on ? look.gradient : null,
                        borderRadius: BorderRadius.circular(look.radius),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            (look.radius - (on ? 3 : 0)).clamp(2, 999)),
                        child: Stack(fit: StackFit.expand, children: [
                          ColoredBox(color: look.field),
                          _NetImage(av.imageUrl),
                          if (mine.contains(av.id) && onRemove != null)
                            Positioned(
                              left: 2,
                              top: 2,
                              child: IconButton(
                                tooltip: 'Remove ${av.name}',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => onRemove!(av.id),
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(28, 28),
                                    padding: EdgeInsets.zero),
                                iconSize: 16,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          if (on)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle),
                                child: Icon(Icons.check_circle_rounded,
                                    color: look.accent, size: 20),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(av.name,
                        style: look.style(14, weight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(av.role,
                        style: look.style(12, color: look.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Their photo, what to call the presenter, the voice, and their word that
/// they may use this likeness. Nothing is sent until they save.
class _NewPresenter extends StatefulWidget {
  const _NewPresenter({required this.photo, required this.voices});

  final Uint8List photo;
  final List<StudioVoice> voices;

  @override
  State<_NewPresenter> createState() => _NewPresenterState();
}

class _NewPresenterState extends State<_NewPresenter> {
  final name = TextEditingController();
  late String voice = widget.voices.first.id;
  bool consent = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your presenter',
                  style: look.style(20, weight: FontWeight.w700)),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(look.radius),
                  child: Image.memory(widget.photo,
                      width: 84, height: 104, fit: BoxFit.cover),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: name,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    style: look.style(16),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'My presenter',
                      filled: true,
                      fillColor: look.field,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(look.radius),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ]),
              const _Label('Voice'),
              _Pills<String>(
                values: [for (final v in widget.voices) v.id],
                selected: voice,
                onSelected: (v) => setState(() => voice = v),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: consent,
                onChanged: (v) => setState(() => consent = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: look.accent,
                checkColor: look.onAccent,
                title: Text(
                    'This is me, or the person pictured has given me permission to use their likeness.',
                    style: look.style(14, height: 1.35)),
              ),
              const SizedBox(height: 8),
              _MakeButton(
                label: 'Save presenter',
                price: null,
                busy: false,
                icon: Icons.check_rounded,
                onPressed: consent
                    ? () => Navigator.of(context)
                        .pop((name: name.text.trim(), voice: voice))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speech and music made so far, each with a play button.
class _AudioList extends StatelessWidget {
  const _AudioList({required this.items, required this.onUse});

  final List<StudioAsset> items;
  final ValueChanged<StudioAsset>? onUse;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 12),
          child: Row(children: [
            Text('Your sounds',
                style: look.style(18, weight: FontWeight.w700, spacing: -0.2)),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('${items.length}',
                  style: look.style(15,
                      weight: FontWeight.w600, color: look.muted)),
            ],
          ]),
        ),
        if (items.isEmpty)
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
                borderRadius: look.corners,
                border: Border.all(color: look.line),
                color: look.card.withValues(alpha: 0.5)),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.graphic_eq_rounded,
                  size: 30, color: look.muted.withValues(alpha: 0.7)),
              const SizedBox(height: 8),
              Text('Voices and music show up here.',
                  style: look.style(14, color: look.muted)),
            ]),
          )
        else
          for (final a in items)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AudioRow(asset: a, onUse: onUse)),
      ],
    );
  }
}

class _AudioRow extends StatefulWidget {
  const _AudioRow({required this.asset, required this.onUse});

  final StudioAsset asset;
  final ValueChanged<StudioAsset>? onUse;

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  VideoPlayerController? player;
  bool playing = false;

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    var p = player;
    if (p == null) {
      p = VideoPlayerController.networkUrl(Uri.parse(widget.asset.url));
      player = p;
      p.addListener(() {
        final now = p!.value.isPlaying;
        if (mounted && now != playing) setState(() => playing = now);
      });
      await p.initialize();
    }
    if (p.value.isPlaying) {
      await p.pause();
    } else {
      if (p.value.position >= p.value.duration) await p.seekTo(Duration.zero);
      await p.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final a = widget.asset;
    final music = a.kind == 'music';
    final length = a.seconds > 0
        ? '${a.seconds ~/ 60}:${(a.seconds % 60).round().toString().padLeft(2, '0')}'
        : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: look.card,
          borderRadius: look.corners,
          border: Border.all(color: look.line)),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: a.isPending
                ? DecoratedBox(
                    decoration: BoxDecoration(
                        color: look.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: look.accent),
                    ),
                  )
                : Material(
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    color: a.isFailed ? look.field : look.accent,
                    child: InkWell(
                      onTap: a.isReady ? toggle : null,
                      child: Icon(
                        a.isFailed
                            ? Icons.error_outline_rounded
                            : (playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                        color: a.isFailed ? look.danger : look.onAccent,
                        size: 26,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.prompt.isEmpty ? (music ? 'Music' : 'Speech') : a.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: look.style(15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  a.isPending
                      ? (music ? 'Composing…' : 'Recording…')
                      : a.isFailed
                          ? (a.error.isEmpty ? "Couldn't be made" : a.error)
                          : [
                              music ? 'Music' : 'Speech',
                              if (length.isNotEmpty) length,
                              if (_Look.pricesOf(context).show)
                                _Look.pricesOf(context).withUnit(a.credits),
                            ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: look.style(13,
                      color: a.isFailed ? look.danger : look.muted),
                ),
              ],
            ),
          ),
          if (a.isReady && widget.onUse != null)
            TextButton(
              onPressed: () => widget.onUse!(a),
              child: Text('Use',
                  style: look.style(15,
                      weight: FontWeight.w700, color: look.accentText)),
            ),
        ],
      ),
    );
  }
}

/// A heads-up that the user is close to their daily limit, or at it. With
/// prices hidden it says so without figures.
class _LowBanner extends StatelessWidget {
  const _LowBanner({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(context);
    final prices = _Look.pricesOf(context);
    final figure = prices.of(remaining);
    final text = remaining <= 0
        ? "You've used today's allowance. It refills over the next 24 hours."
        : figure == null
            ? "You're close to today's limit. It refills over the next 24 hours."
            : "Running low: ${prices.custom ? figure : '$figure credits'} left today. It refills over the next 24 hours.";
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: look.accent.withValues(alpha: look.dark ? 0.16 : 0.08),
          borderRadius:
              BorderRadius.circular((look.radius * 0.75).clamp(4, 14)),
        ),
        child: Row(children: [
          Icon(
              remaining <= 0
                  ? Icons.hourglass_empty_rounded
                  : Icons.bolt_rounded,
              size: 18,
              color: look.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: look.style(13.5, height: 1.3))),
        ]),
      ),
    );
  }
}
