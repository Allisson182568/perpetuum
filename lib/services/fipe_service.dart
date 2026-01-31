import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FipeService {
  // Usaremos a Parallelum para tudo, pois ela mantém a estrutura hierárquica correta
  static const String _baseUrl = 'https://parallelum.com.br/fipe/api/v1';

  // 1. Listar Marcas
  // Retorna: [{"nome": "Acura", "codigo": "1"}, ...]
  Future<List<Map<String, String>>> getBrands(String type) async {
    try {
      final url = Uri.parse('$_baseUrl/$type/marcas');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => {
          'nome': e['nome'].toString(),
          'codigo': e['codigo'].toString() // Parallelum usa 'codigo'
        }).toList();
      }
    } catch (e) {
      debugPrint("Erro Fipe (Marcas): $e");
    }
    return [];
  }

  // 2. Listar Modelos
  // Retorna: { "modelos": [{"nome": "Integra...", "codigo": "1"}], "anos": [] }
  Future<List<Map<String, dynamic>>> getModels(String type, String brandId) async {
    try {
      final url = Uri.parse('$_baseUrl/$type/marcas/$brandId/modelos');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> modelos = data['modelos'];

        return modelos.map((e) => {
          'nome': e['nome'].toString(),
          'codigo': e['codigo'].toString()
        }).toList();
      }
    } catch (e) {
      debugPrint("Erro Fipe (Modelos): $e");
    }
    return [];
  }

  // 3. Listar Anos
  Future<List<Map<String, String>>> getYears(String type, String brandId, String modelId) async {
    try {
      final url = Uri.parse('$_baseUrl/$type/marcas/$brandId/modelos/$modelId/anos');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => {
          'nome': e['nome'].toString(),
          'codigo': e['codigo'].toString()
        }).toList();
      }
    } catch (e) {
      debugPrint("Erro Fipe (Anos): $e");
    }
    return [];
  }

  // 4. Detalhes Finais (Preço)
  Future<Map<String, dynamic>> getFipeDetails(String type, String brandId, String modelId, String yearId) async {
    try {
      final url = Uri.parse('$_baseUrl/$type/marcas/$brandId/modelos/$modelId/anos/$yearId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Erro Fipe (Detalhes): $e");
    }
    throw Exception('Falha ao buscar valor da tabela FIPE');
  }
}