/// StartupAid's Creative studio for your app's users.
///
/// Make a widget key in StartupAid → Developers → Studio widget, have your
/// server sign each user's id with the key's signing secret, then:
///
/// ```dart
/// final client = StudioClient(publicKey: 'pk_live_…', userId: me.id, signer: (_) => api.studioSignature());
/// final picked = await StartupAidStudio.show(context, client: client);
/// ```
library;

export 'src/client.dart' show StudioClient, StudioSigner;
export 'src/models.dart';
export 'src/movie_maker.dart' show MovieMakerPage;
export 'src/studio_widget.dart' show StartupAidStudio;
export 'src/theme.dart'
    show StudioTheme, StudioPalette, StudioThemeMode, StudioCorners;
