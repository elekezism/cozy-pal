class BrowserSpeech {
  static bool get supported => false;
  bool get listening => false;
  void start({
    String lang = 'en-US',
    bool continuous = false,
    required void Function(String text) onText,
    void Function()? onEnd,
    void Function(String error)? onError,
  }) =>
      onError?.call('Speech recognition is only used in the browser.');
  void stop() {}
}
