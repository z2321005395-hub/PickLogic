final class DoiExtractor {
  const DoiExtractor();

  static final RegExp _pattern = RegExp(
    r'10\.\d{4,9}/[-._;()/:A-Z0-9]+',
    caseSensitive: false,
  );

  List<String> candidates(String text) {
    final seen = <String>{};
    for (final match in _pattern.allMatches(text)) {
      final value = _trimTrailingPunctuation(match.group(0)!).toLowerCase();
      if (value.length <= 255) seen.add(value);
    }
    return seen.toList(growable: false);
  }

  String _trimTrailingPunctuation(String value) {
    var result = value;
    while (result.isNotEmpty && '.,;:)]}'.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
