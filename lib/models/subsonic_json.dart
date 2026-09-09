/// Subsonic collapses a single-element list into a bare object: a directory
/// with two songs sends `"child": [{...},{...}]`, and one with a single song
/// sends `"child": {...}`. Every list in a response therefore has to be read
/// through this, or the one-element case parses as nothing (or throws on the
/// cast) while the many-element case works — which is why the bug survives
/// casual testing against a real library.
///
/// A missing key yields the empty list, so callers can pass `json['child']`
/// straight in without a null check.
List<dynamic> subsonicList(dynamic value) {
  if (value == null) return const [];
  return value is List ? value : [value];
}
