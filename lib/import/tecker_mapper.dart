class TickerMapper {
  // Dicionário: Chave é o CNPJ (só números), Valor é o Ticker real
  static const Map<String, String> cnpjToTicker = {
    "07628528000159": "AGRO3", // Brasilagro
    "00000000000191": "BBAS3", // Banco do Brasil
    "22543331000100": "CXSE3", // Caixa Seguridade
    "09346601000125": "B3SA3", // B3
    "89850341000160": "GRND3", // Grendene
    "00001180000126": "ELET3", // Eletrobras
    "61532644000115": "ITSA4", // Itaúsa
    "17155730000164": "CMIG4", // Cemig
    "89637490000145": "KLBN11", // Klabin
    "28737771000185": "ALZR11", // Alianza Trust
    "11839593000109": "BTLG11", // BTG Logística
    "28757546000100": "XPML11", // XP Malls
    "11728688000147": "HGLG11", // Pátria Logística
  };

  static String? getTicker(String cnpj) {
    // Remove qualquer caractere que não seja número antes de buscar
    final cleanCnpj = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
    return cnpjToTicker[cleanCnpj];
  }
}