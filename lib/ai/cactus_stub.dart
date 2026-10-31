/// Browser stand-in for the Cactus engine (cactus_bindings.dart uses dart:ffi,
/// which doesn't exist on the web). [instance] is always null, so the app
/// falls back to keyword routing and keyword search, and speech goes through
/// the browser.
class CactusEngine {
  CactusEngine._();

  static CactusEngine? get instance => null;
  static String? loadError = 'On-device AI runs in the phone app, not in the browser.';

  int loadModel(String dir) => 0;
  void destroyModel(int address) {}
  String runComplete(int modelAddress, String messagesJson, {String? toolsJson, String? optionsJson}) =>
      throw UnsupportedError('Cactus is not available on the web');
  String runTranscribe(int modelAddress, String wavPath, {String? optionsJson}) =>
      throw UnsupportedError('Cactus is not available on the web');
  List<double> runEmbed(int modelAddress, String text, {int maxDim = 4096}) =>
      throw UnsupportedError('Cactus is not available on the web');
}
