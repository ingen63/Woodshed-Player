// #131: the answer of the sign-in by redirect is taken from the page address at start, before Flutter
// replaces the address; the browser side is in test/web/oauth_return_web_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/sync/oauth_return.dart';

void main() {
  test(
    '#131/AK2 an answer is returned without «#» and removed from the address',
    () {
      var removed = 0;
      expect(
        takeOAuthAnswer(
          '#state=s1&access_token=t&expires_in=3599',
          () => removed++,
        ),
        'state=s1&access_token=t&expires_in=3599',
      );
      expect(removed, 1);
      expect(
        takeOAuthAnswer('error=access_denied&state=s1', () => removed++),
        'error=access_denied&state=s1',
      );
      expect(removed, 2);
    },
  );

  test('#131 no answer: empty, the address stays', () {
    for (final hash in [
      '',
      '#',
      '#/',
      '#/library',
      '#mystate=x',
      '#xaccess_token=y',
    ]) {
      expect(
        takeOAuthAnswer(hash, () => fail('address changed: $hash')),
        '',
        reason: hash,
      );
    }
    expect(isOAuthAnswer('a=1&access_token=t'), isTrue);
    expect(isOAuthAnswer('a=1&error=x'), isTrue);
  });
}
