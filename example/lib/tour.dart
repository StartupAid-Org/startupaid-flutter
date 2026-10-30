import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:startupaid_studio/startupaid_studio.dart';

// A hands-off walk through the studio for screenshots: run with
// --dart-define=TOUR=true and it taps through by itself, printing
// "TOUR:<screen>" as each screen settles. Not needed to use the widget.

final tourNavigator = GlobalKey<NavigatorState>();

void startTourIfAsked(StudioClient client) {
  if (!const bool.fromEnvironment('TOUR')) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => _tour());
}

Future<void> _wait(double s) =>
    Future<void>.delayed(Duration(milliseconds: (s * 1000).round()));

// Each screen holds still a moment, so the screenshot catches it settled.
Future<void> _mark(String name) async {
  debugPrint('TOUR:$name');
  await _wait(1.5);
}

Iterable<Element> _all() sync* {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  final stack = <Element>[root];
  while (stack.isNotEmpty) {
    final e = stack.removeLast();
    yield e;
    final kids = <Element>[];
    e.visitChildren(kids.add);
    stack.addAll(kids.reversed);
  }
}

// The last match in the tree is on the page in front.
Element? _last(bool Function(Element) test) {
  Element? found;
  for (final e in _all()) {
    final box = e.renderObject;
    if (test(e) && box is RenderBox && box.attached && box.hasSize) found = e;
  }
  return found;
}

Element? _text(bool Function(String) test) =>
    _last((e) => e.widget is Text && test((e.widget as Text).data ?? ''));

int _pointer = 1;
Future<void> _tap(Element? e) async {
  if (e == null) {
    debugPrint('TOUR:missing');
    return;
  }
  final box = e.renderObject! as RenderBox;
  final at = box.localToGlobal(box.size.center(Offset.zero));
  final id = _pointer++;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: id, position: at),
  );
  await _wait(0.08);
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: id, position: at),
  );
}

Future<void> _scrollDown() async {
  ScrollableState? best;
  for (final e in _all()) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final s = e.state as ScrollableState;
      if (s.position.axis == Axis.vertical &&
          s.position.hasContentDimensions &&
          s.position.maxScrollExtent > 0) {
        best = s;
      }
    }
  }
  await best?.position.animateTo(
    best.position.maxScrollExtent,
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeOut,
  );
}

Element? _galleryImage() => _last((e) {
  final w = e.widget;
  return w is Image &&
      w.image is NetworkImage &&
      (w.image as NetworkImage).url.contains('picsum') &&
      w.fit == BoxFit.cover;
});

Future<void> _tour() async {
  await _wait(2);
  // TOUR_PART=movie: the Film Maker tab, and Film Maker on its own,
  // against a real key.
  if (const String.fromEnvironment('TOUR_PART') == 'movie') {
    await _tap(_text((t) => t == 'Make with AI'));
    await _wait(10);
    await _mark('studio-tabs');
    await _tap(_text((t) => t == 'Film Maker'));
    await _wait(20);
    await _mark('film-maker-tab');
    await _tap(
      _last(
        (e) =>
            e.widget is Icon && (e.widget as Icon).icon == Icons.close_rounded,
      ),
    );
    await _wait(2);
    await _tap(_text((t) => t == 'Make a film'));
    await _wait(15);
    await _mark('film-maker-page');
    await _mark('done');
    return;
  }
  await _mark('home');
  await _tap(_text((t) => t == 'Make with AI'));
  await _wait(3);
  await _mark('pictures');

  await _tap(_text((t) => t.startsWith('Make ') && t.endsWith('picture')));
  await _wait(3.5);
  await _scrollDown();
  await _wait(2.5);
  await _mark('pictures-made');

  await _tap(_galleryImage());
  await _wait(3);
  await _mark('preview');

  await _tap(_text((t) => t == 'Animate it'));
  await _wait(3);
  await _mark('video');

  final field = _last((e) => e.widget is TextField)?.widget as TextField?;
  field?.controller?.text =
      'Rain starts to fall and the camera slowly pushes in on the door.';
  await _wait(1);
  await _tap(_text((t) => t.startsWith('Make the clip')));
  await _wait(2.5);
  await _scrollDown();
  await _wait(1.5);
  await _mark('clip-making');

  await _wait(12);
  await _mark('clip-ready');

  // Voice & music.
  await _tap(_text((t) => t == 'Voice'));
  await _wait(2.5);
  (_last((e) => e.widget is TextField)?.widget as TextField?)
          ?.controller
          ?.text =
      'Lagos After Dark. New episodes every Friday, only on StatusNet.';
  await _wait(1);
  await _mark('voice');
  await _tap(_text((t) => t == 'Make the voice'));
  await _wait(7);
  await _mark('voice-made');

  // Presenters.
  await _tap(_text((t) => t == 'Presenter'));
  await _wait(3);
  (_last((e) => e.widget is TextField)?.widget as TextField?)
          ?.controller
          ?.text =
      'Hi, I’m Amara. Tonight on Lagos After Dark: a missing driver, a stolen car, and one long night across the city.';
  await _wait(2);
  await _mark('presenter');
  await _tap(_text((t) => t.startsWith('Make the video')));
  await _wait(2.5);
  await _scrollDown();
  await _wait(1);
  await _mark('presenter-making');
  await _wait(10);
  await _scrollDown();
  await _wait(1.5);
  await _mark('presenter-ready');

  await _tap(_text((t) => t == 'Video'));
  await _wait(2);
  await _scrollDown();
  await _wait(1);

  await _tap(_galleryImage());
  await _wait(5);
  await _mark('clip-preview');

  await _tap(_text((t) => t == 'Use this'));
  await _wait(3);
  await _mark('picked');
  await _mark('done');
}
