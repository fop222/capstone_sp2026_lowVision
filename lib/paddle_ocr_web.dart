import 'dart:js_interop';
import 'dart:typed_data';

extension type _PaddleModule._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> warmUp();
  external JSPromise<JSString> readText(JSUint8Array bytes);
}

Future<_PaddleModule>? _module;

/// The module (about 11 MB) and models (about 21 MB) load only when the
/// Paddle scan is first used, then stay cached.
Future<_PaddleModule> _load() {
  return _module ??=
      importModule(
        Uri.base.resolve('/paddleocr/lumio_paddle.js').toString().toJS,
      ).toDart.then((module) => module as _PaddleModule).catchError((
        Object error,
      ) {
        _module = null;
        throw error;
      });
}

/// Loads the Paddle models ahead of the first photo.
Future<void> paddleWarmUp() async {
  await (await _load()).warmUp().toDart;
}

/// JSON from Paddle OCR: `{"width","height","lines":[{"text","score","box"}]}`.
Future<String> paddleReadText(Uint8List bytes) async {
  final module = await _load();
  return (await module.readText(bytes.toJS).toDart).toDart;
}
