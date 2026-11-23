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

/// Genera variantes singulares básicas para un token normalizado en español
/// (ej: "machimbres" → "machimbre", "perfiles" → "perfil", "luces" → "luz"),
/// conservando siempre el token original.
List<String> expandSpanishSearchTokenVariants(String normalizedToken) {
  final token = normalizedToken.trim();
  if (token.isEmpty) return const [];
  final variants = <String>[token];
  final len = token.length;
  if (len < 4) return variants;

  if (token.endsWith('s')) {
    final minus1 = token.substring(0, len - 1);
    if (minus1.isNotEmpty && !variants.contains(minus1)) {
      variants.add(minus1);
    }
  }

  if (len >= 5 && token.endsWith('es')) {
    final beforeEs = token[len - 3];
    if (beforeEs == 'd' ||
        beforeEs == 'l' ||
        beforeEs == 'n' ||
        beforeEs == 'r' ||
        beforeEs == 's') {
      final minus2 = token.substring(0, len - 2);
      if (minus2.length >= 3 && !variants.contains(minus2)) {
        variants.add(minus2);
      }
    }
  }

  if (len >= 5 && token.endsWith('ces')) {
    final minus3Z = '${token.substring(0, len - 3)}z';
    if (!variants.contains(minus3Z)) {
      variants.add(minus3Z);
    }
  }

  return variants;
}

/// Evalúa si [searchableFields] coincide con todas las palabras de [query],
/// tolerando tildes, orden distinto de palabras y plurales comunes en español.
bool matchesSpanishSearchQuery(
  String query,
  Iterable<String?> searchableFields,
) {
  final normQuery = normalizeSearchText(query);
  if (normQuery.isEmpty) return false;
  final tokens = normQuery
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .take(6)
      .toList();
  if (tokens.isEmpty) return false;

  final normFields = searchableFields
      .whereType<String>()
      .map(normalizeSearchText)
      .where((f) => f.isNotEmpty)
      .toList();
  if (normFields.isEmpty) return false;

  for (final token in tokens) {
    final variants = expandSpanishSearchTokenVariants(token);
    final matched = normFields.any(
      (field) => variants.any((v) => field.contains(v)),
    );
    if (!matched) return false;
  }
  return true;
}
