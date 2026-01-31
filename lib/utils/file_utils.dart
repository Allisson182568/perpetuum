import 'dart:io';
import 'package:crypto/crypto.dart'; // Certifique-se de ter: flutter pub add crypto

class FileUtils {
  /// Gera o Hash (Digital Única) do arquivo
  static Future<String> getFileHash(File file) async {
    final bytes = await file.readAsBytes();
    var digest = sha256.convert(bytes);
    return digest.toString();
  }
}