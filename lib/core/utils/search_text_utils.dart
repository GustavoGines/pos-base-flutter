/// Normaliza texto para comparaciones alfabéticas y búsqueda flexible en español
/// (insensible a mayúsculas, tildes y espacios sobrantes).
String normalizeSearchText(String input) {
  final lower = input.trim().toLowerCase();
  if (lower.isEmpty) return '';

  final buffer = StringBuffer();
  for (int i = 0; i < lower.length; i++) {
    final ch = lower[i];
    switch (ch) {
      case 'á':
      case 'à':
      case 'ä':
      case 'â':
      case 'ã':
        buffer.write('a');
        break;
      case 'é':
      case 'è':
      case 'ë':
      case 'ê':
        buffer.write('e');
        break;
      case 'í':
      case 'ì':
      case 'ï':
      case 'î':
        buffer.write('i');
        break;
      case 'ó':
      case 'ò':
      case 'ö':
      case 'ô':
      case 'õ':
        buffer.write('o');
        break;
      case 'ú':
      case 'ù':
      case 'ü':
      case 'û':
        buffer.write('u');
        break;
      case 'ñ':
        buffer.write('n');
        break;
      case 'ç':
        buffer.write('c');
        break;
      default:
        buffer.write(ch);
    }
  }
  return buffer.toString();
}

/// Compara dos cadenas en orden alfabético español A->Z ignorando tildes y mayúsculas.
int compareSpanishAlphabetical(String a, String b) {
  final normA = normalizeSearchText(a);
  final normB = normalizeSearchText(b);
  final primary = normA.compareTo(normB);
  if (primary != 0) return primary;

  final secondary = a.toLowerCase().compareTo(b.toLowerCase());
  if (secondary != 0) return secondary;
  return a.compareTo(b);
}

/// Devuelve una nueva lista ordenada alfabéticamente (A->Z) según [nameOf].
List<T> sortByAlphabeticalName<T>(
  Iterable<T> items,
  String Function(T item) nameOf,
) {
  final copy = List<T>.from(items);
  copy.sort((a, b) => compareSpanishAlphabetical(nameOf(a), nameOf(b)));
  return copy;
}
