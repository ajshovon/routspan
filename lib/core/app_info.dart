/// App identity + legal strings shown in the About screen and the bundled
/// open-source licenses page. Keep [version] in sync with pubspec.yaml.
class AppInfo {
  const AppInfo._();

  static const name = 'Routspan';
  static const version = '0.1.0';

  /// Shown on the licenses page footer.
  static const legalese = '© 2026 Shovon\nMIT License';

  /// Nominative-fair-use / non-affiliation notice. OLAX and ZTE are trademarks
  /// of their respective owners; Routspan is an independent interoperability
  /// tool and names them only to say what it works with.
  static const trademarkNotice =
      'Routspan is an independent, unofficial application and is not affiliated '
      'with, endorsed by, or sponsored by OLAX, ZTE, or any of their '
      'affiliates. All product names, logos, and trademarks are the property of '
      'their respective owners and are used only for identification and '
      'interoperability purposes.';

  static const licenseSummary =
      'Routspan is free and open-source software released under the MIT License. '
      'It bundles third-party packages under permissive licenses (MIT / BSD) — '
      'see "Open-source licenses" for full texts.';
}
