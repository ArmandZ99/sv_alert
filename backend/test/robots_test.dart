import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';
import 'package:test/test.dart';

void main() {
  const agent = 'SuceavaTravelAlerts/0.1 (+me@example.org)';

  test('empty or absent rules allow everything', () {
    expect(RobotsRules.allowAll().isAllowed('/anything'), isTrue);
    expect(
      RobotsRules.parse('', userAgent: agent).isAllowed('/anything'),
      isTrue,
    );
  });

  test('disallowAll blocks everything', () {
    expect(RobotsRules.disallowAll().isAllowed('/'), isFalse);
    expect(RobotsRules.disallowAll().isAllowed('/page'), isFalse);
  });

  test('wildcard group applies when no specific group matches', () {
    final rules = RobotsRules.parse('''
User-agent: *
Disallow: /administrator/
Disallow: /cache/
''', userAgent: agent);
    expect(rules.isAllowed('/administrator/login'), isFalse);
    expect(rules.isAllowed('/ro/zboruri'), isTrue);
  });

  test('an empty Disallow allows everything', () {
    final rules =
        RobotsRules.parse('User-agent: *\nDisallow:\n', userAgent: agent);
    expect(rules.isAllowed('/x'), isTrue);
  });

  test('a group naming this bot beats the wildcard group', () {
    final rules = RobotsRules.parse('''
User-agent: *
Disallow: /

User-agent: SuceavaTravelAlerts
Disallow: /private/
''', userAgent: agent);
    expect(rules.isAllowed('/public'), isTrue);
    expect(rules.isAllowed('/private/x'), isFalse);
  });

  test('longest matching rule wins and Allow beats Disallow on ties', () {
    final rules = RobotsRules.parse('''
User-agent: *
Disallow: /wp-admin/
Allow: /wp-admin/admin-ajax.php
Disallow: /a
Allow: /a
''', userAgent: agent);
    expect(rules.isAllowed('/wp-admin/options'), isFalse);
    expect(rules.isAllowed('/wp-admin/admin-ajax.php'), isTrue);
    expect(rules.isAllowed('/a'), isTrue);
  });

  test('wildcards and end anchors', () {
    final rules = RobotsRules.parse(r'''
User-agent: *
Disallow: /*.php$
Disallow: /dataset/*/history
''', userAgent: agent);
    expect(rules.isAllowed('/ajax.php'), isFalse);
    expect(rules.isAllowed('/ajax.php?x=1'), isTrue);
    expect(rules.isAllowed('/dataset/abc/history'), isFalse);
    expect(rules.isAllowed('/dataset/abc'), isTrue);
  });

  test('comments, blank lines and CRLF are tolerated; crawl-delay is read', () {
    final rules = RobotsRules.parse(
      '# hi\r\nUser-agent: *  # all\r\n\r\nCrawl-Delay: 10\r\nDisallow: /api/\r\n',
      userAgent: agent,
    );
    expect(rules.crawlDelay, const Duration(seconds: 10));
    expect(rules.isAllowed('/api/x'), isFalse);
    expect(rules.isAllowed('/dataset/x'), isTrue);
  });

  test('consecutive User-agent lines share one group', () {
    final rules = RobotsRules.parse('''
User-agent: otherbot
User-agent: suceavatravelalerts
Disallow: /x
''', userAgent: agent);
    expect(rules.isAllowed('/x'), isFalse);
  });
}
