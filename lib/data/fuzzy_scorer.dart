import 'dart:math' as math;

/// Computes Optimal String Alignment (restricted Damerau-Levenshtein) distance.
int damerauLevenshtein(String a, String b) {
  final m = a.length;
  final n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;

  var prevPrev = List<int>.filled(n + 1, 0);
  var prev = List<int>.generate(n + 1, (j) => j);
  var curr = List<int>.filled(n + 1, 0);

  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= n; j++) {
      final cb = b.codeUnitAt(j - 1);
      final cost = ca == cb ? 0 : 1;
      var best = math.min(
        math.min(prev[j] + 1, curr[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          ca == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == cb) {
        best = math.min(best, prevPrev[j - 2] + 1);
      }
      curr[j] = best;
    }
    final tmp = prevPrev;
    prevPrev = prev;
    prev = curr;
    curr = tmp;
  }

  return prev[n];
}

double _nameClassBoost(String nameClass) {
  return switch (nameClass) {
    'scientific name' => 0.12,
    'genbank common name' => 0.09,
    'common name' => 0.07,
    'blast name' => 0.05,
    'synonym' => 0.02,
    _ => 0.0,
  };
}

/// Scores a candidate [candidateName] against [query] in [0.0, 1.3+].
/// Higher is better.
double scoreFuzzyMatch({
  required String query,
  required String candidateName,
  required String nameClass,
}) {
  final q = query.trim().toLowerCase();
  final c = candidateName.trim().toLowerCase();
  if (q.isEmpty || c.isEmpty) return 0.0;

  if (q == c) {
    return 1.2 + _nameClassBoost(nameClass);
  }

  final maxLen = math.max(q.length, c.length);
  final dist = damerauLevenshtein(q, c);
  var score = 1.0 - (dist / maxLen);

  if (c.startsWith(q)) {
    score += 0.25;
  } else if (c.contains(q)) {
    score += 0.15;
  } else {
    // Compare against individual words in multi-word names (e.g. "sapiens" in "Homo sapiens").
    final words = c.split(RegExp(r'\s+'));
    var bestWordSim = 0.0;
    for (final w in words) {
      if (w.isEmpty) continue;
      final wDist = damerauLevenshtein(q, w);
      final wSim = 1.0 - (wDist / math.max(q.length, w.length));
      if (wSim > bestWordSim) bestWordSim = wSim;
    }
    score = math.max(score, bestWordSim * 0.92);
  }

  return score + _nameClassBoost(nameClass);
}
