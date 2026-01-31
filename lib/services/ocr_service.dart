import 'ocr/ocr_service_impl.dart';
import 'ocr/ocr_stub.dart';
// Importação Condicional Mágica
// Se tiver dart.library.io (Mobile), usa o mobile.dart
// Se não (Web), usa o web.dart
import 'ocr/ocr_web.dart' if (dart.library.io) 'ocr/ocr_mobile.dart';

class OcrService {
  final OcrServiceImpl _impl = OcrServiceImpl();

  Future<List<Map<String, dynamic>>> extractData(String path) {
    return _impl.extractData(path);
  }
}