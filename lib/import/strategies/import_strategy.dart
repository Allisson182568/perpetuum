import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Modelo de dados unificado
class ImportResult {
  final String ticker;
  final double qty;
  final double price; // Preço Unitário (já considerando taxas se for compra)
  final String type; // 'C', 'V', 'DIV'
  final String assetType; // ACAO, FII, ETC
  final String date;
  final String broker;
  final String cnpj;
  final bool isEarning;

  // NOVOS CAMPOS CRUCIAIS
  final double fees; // Taxas totais da operação
  final String transactionId; // ID para evitar duplicatas (Coluna "Número")

  final Map<String, dynamic> enrichment;

  ImportResult({
    required this.ticker,
    required this.qty,
    required this.price,
    this.type = 'C',
    this.assetType = 'OUTROS',
    required this.date,
    required this.broker,
    this.cnpj = '',
    this.isEarning = false,
    this.fees = 0.0, // Default 0
    this.transactionId = '', // Default vazio
    this.enrichment = const {},
  });
}

/// Contrato para Estratégias
abstract class ImportStrategy {
  String get title;
  String get description;
  List<String> get allowedExtensions;
  IconData get icon;

  Future<List<ImportResult>> parse(PlatformFile file, Uint8List bytes);
}