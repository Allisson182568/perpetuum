import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html; // Para Web segura

class ExcelGeneratorService {

  /// Gera e baixa o modelo oficial de importação do Perpetuum
  Future<void> generateAndDownloadTemplate() async {
    var excel = Excel.createExcel();

    // Remove a aba padrão "Sheet1" se existir
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Cria aba com nome limpo
    String sheetName = 'Importacao';
    Sheet sheet = excel[sheetName];

    // --- ESTILOS ---
    CellStyle titleStyle = CellStyle(
        bold: true,
        fontSize: 18,
        horizontalAlign: HorizontalAlign.Center,
        fontColorHex: ExcelColor.fromHexString("#00E5FF"),
        backgroundColorHex: ExcelColor.fromHexString("#1E1E1E")
    );

    CellStyle headerStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString("#E0E0E0"),
        fontColorHex: ExcelColor.black,
        fontFamily: getFontFamily(FontFamily.Arial)
    );

    // --- 1. CABEÇALHO (LINHA 0) ---
    var titleCell = sheet.cell(CellIndex.indexByString("A1"));
    titleCell.value = TextCellValue("PERPETUUM - Modelo de Importação");
    titleCell.cellStyle = titleStyle;

    sheet.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("H1"), customValue: TextCellValue("PERPETUUM - Modelo de Importação"));

    // --- 2. INSTRUÇÕES (LINHA 1) ---
    var instrCell = sheet.cell(CellIndex.indexByString("A2"));
    instrCell.value = TextCellValue("Instruções: Preencha abaixo. 'Taxas' abatem IR. 'ID' evita duplicatas.");
    // Sem merge aqui para evitar bugs visuais em alguns leitores, texto vai estourar a célula o que é ok.

    // --- 3. COLUNAS (LINHA 2) ---
    List<String> headers = [
      "Data (DD/MM/AAAA)", // A
      "Ativo (Ticker)",    // B
      "Operação (C/V)",    // C
      "Quantidade",        // D
      "Preço Unitário",    // E
      "Taxas (Total)",     // F
      "Corretora",         // G
      "ID (Opcional)"      // H
    ];

    for (int i = 0; i < headers.length; i++) {
      var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // --- 4. DADOS DE EXEMPLO (LINHAS 3-5) ---
    _addSampleRow(sheet, 3, "15/05/2023", "PETR4", "C", 100, 25.50, 5.30, "Inter", "ID_001");
    _addSampleRow(sheet, 4, "20/06/2023", "VALE3", "C", 50, 60.00, 2.50, "XP", "ID_002");
    _addSampleRow(sheet, 5, "10/08/2023", "PETR4", "V", 50, 28.00, 1.20, "Inter", "ID_003");

    // --- AJUSTE DE LARGURA (IMPORTANTE PARA VISUALIZAÇÃO) ---
    sheet.setColumnWidth(0, 20.0); // Data
    sheet.setColumnWidth(1, 15.0); // Ticker
    sheet.setColumnWidth(2, 15.0); // Op
    sheet.setColumnWidth(3, 15.0); // Qtd
    sheet.setColumnWidth(4, 15.0); // Preço
    sheet.setColumnWidth(5, 15.0); // Taxas
    sheet.setColumnWidth(6, 20.0); // Corretora
    sheet.setColumnWidth(7, 20.0); // ID

    // --- 5. SALVAR E BAIXAR ---
    List<int>? fileBytes = excel.save();

    if (fileBytes != null) {
      String fileName = "Perpetuum_Modelo_Importacao.xlsx";

      if (kIsWeb) {
        // --- LÓGICA WEB (CORRIGIDA) ---
        final blob = html.Blob([fileBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // --- LÓGICA MOBILE (ANDROID/IOS) ---
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/$fileName';
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);

        // Abre o menu de compartilhamento com o nome certo
        await Share.shareXFiles([XFile(path)], text: 'Modelo de Importação Perpetuum');
      }
    }
  }

  void _addSampleRow(Sheet sheet, int rowIndex, String date, String ticker, String op, int qty, double price, double fees, String broker, String id) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = TextCellValue(date);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = TextCellValue(ticker);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = TextCellValue(op);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = DoubleCellValue(qty.toDouble());
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = DoubleCellValue(price);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = DoubleCellValue(fees);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = TextCellValue(broker);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = TextCellValue(id);
  }
}