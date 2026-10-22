/// Minimal robots.txt interpreter (RFC 9309 subset): groups by user-agent,
/// `Allow` / `Disallow` with the longest matching rule winning, `*` and `$`
/// wildcards, and `Crawl-delay`.
class RobotsRules {
  RobotsRules._(this._rules, this.crawlDelay);

  /// Everything allowed (used when a site publishes no robots.txt).
  RobotsRules.allowAll() : this._(const [], null);

  /// Everything refused (used when robots.txt cannot be read reliably).
  RobotsRules.disallowAll() : this._(const [_Rule(false, '/')], null);

  final List<_Rule> _rules;
  final Duration? crawlDelay;

  /// Reads the group that best matches [userAgent]; falls back to `*`.
  factory RobotsRules.parse(String text, {required String userAgent}) {
    final product = userAgent.split('/').first.toLowerCase();
    final groups = <_Group>[];
    _Group? current;
    var lastWasAgent = false;

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.split('#').first.trim();
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final field = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();

      if (field == 'user-agent') {
        if (!lastWasAgent || current == null) {
          current = _Group();
          groups.add(current);
        }
        current.agents.add(value.toLowerCase());
        lastWasAgent = true;
        continue;
      }
      lastWasAgent = false;
      if (current == null) continue;
      switch (field) {
        case 'allow':
          if (value.isNotEmpty) current.rules.add(_Rule(true, value));
        case 'disallow':
          // An empty Disallow means "allow everything" and adds no rule.
          if (value.isNotEmpty) current.rules.add(_Rule(false, value));
        case 'crawl-delay':
          final seconds = double.tryParse(value);
          if (seconds != null && seconds >= 0) {
            current.crawlDelay =
                Duration(milliseconds: (seconds * 1000).round());
          }
      }
    }

    _Group? specific;
    _Group? wildcard;
    for (final group in groups) {
      if (group.agents.any((a) => a != '*' && product.contains(a))) {
        specific ??= group;
      }
      if (group.agents.contains('*')) wildcard ??= group;
    }
    final chosen = specific ?? wildcard;
    return RobotsRules._(chosen?.rules ?? const [], chosen?.crawlDelay);
  }

  /// Whether [path] (with optional query) may be fetched.
  bool isAllowed(String path) {
    _Rule? best;
    for (final rule in _rules) {
      if (!rule.matches(path)) continue;
      if (best == null ||
          rule.pattern.length > best.pattern.length ||
          (rule.pattern.length == best.pattern.length && rule.allow)) {
        best = rule;
      }
    }
    return best?.allow ?? true;
  }
}

class _Group {
  final List<String> agents = [];
  final List<_Rule> rules = [];
  Duration? crawlDelay;
}

class _Rule {
  const _Rule(this.allow, this.pattern);

  final bool allow;
  final String pattern;

  bool matches(String path) {
    final anchored = pattern.endsWith(r'$');
    final body = anchored ? pattern.substring(0, pattern.length - 1) : pattern;
    final regex = RegExp(
      '^${body.split('*').map(RegExp.escape).join('.*')}${anchored ? r'$' : ''}',
    );
    return regex.hasMatch(path);
  }
}
