import 'package:Canary/utils/canary_file_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanaryFileUri encode/decode roundtrip', () {
    test('handles spaces, #, %, and Unicode filenames', () {
      const cases = <String>[
        'hello world.png',
        'hash#tag.png',
        'percent%20done.png',
        '写真_😀.png',
        'nested/dir/file name (1).png',
      ];

      for (final name in cases) {
        final abs = '/data/app/upload/$name';
        final uri = CanaryFileUri.encodeFromAbsolute(abs, root: '/data/app');
        expect(uri, isNotNull, reason: name);
        expect(CanaryFileUri.isCanaryFileUri(uri!), isTrue);

        final segments = CanaryFileUri.decodeToSegments(uri);
        expect(segments, isNotNull, reason: name);
        expect(segments!.first, 'upload');
        expect(segments.skip(1).join('/'), name);

        final again = CanaryFileUri.encodeFromAbsolute(
          CanaryFileUri.resolveToAbsolute(uri, root: '/data/app')!,
          root: '/data/app',
        );
        expect(again, uri);
      }
    });
  });

  group('CanaryFileUri.decodeToSegments rejects invalid URIs', () {
    test(
      'rejects path traversal, unknown managed root, host, query/fragment',
      () {
        const invalid = <String>[
          'canary-file:///../secret',
          'canary-file:///unknown/a.png',
          'canary-file://host/upload/a.png',
          'canary-file:///upload/a.png?x=1',
          'canary-file:///upload/a.png#frag',
          'canary-file:///upload//a.png',
          'canary-file:///upload/',
          'canary-file:///upload',
          'canary-file:///',
          'canary-file:',
          'file:///upload/a.png',
        ];

        for (final uri in invalid) {
          expect(CanaryFileUri.decodeToSegments(uri), isNull, reason: uri);
        }
      },
    );

    test('rejects empty path segments and dot segments', () {
      expect(
        CanaryFileUri.decodeToSegments('canary-file:///images/a//b.png'),
        isNull,
      );
      expect(
        CanaryFileUri.decodeToSegments('canary-file:///images/./a.png'),
        isNull,
      );
      expect(
        CanaryFileUri.decodeToSegments('canary-file:///images/foo/../a.png'),
        isNull,
      );
    });

    test('returns null for malformed percent encoding', () {
      for (final uri in const [
        'canary-file:///upload/%ZZ.pdf',
        'canary-file:///upload/%.pdf',
        'canary-file:///upload/%FF.pdf',
      ]) {
        expect(CanaryFileUri.decodeToSegments(uri), isNull, reason: uri);
      }
    });
  });

  group('CanaryFileUri.resolveToAbsolute', () {
    test('joins under POSIX root without existence checks', () {
      final abs = CanaryFileUri.resolveToAbsolute(
        'canary-file:///upload/nested/a.png',
        root: '/var/mobile/Documents',
      );
      expect(abs, '/var/mobile/Documents/upload/nested/a.png');
    });

    test('joins under Windows-style root', () {
      final abs = CanaryFileUri.resolveToAbsolute(
        'canary-file:///images/photo.png',
        root: r'C:\Users\me\AppData\Local\Canary',
      );
      expect(abs, r'C:\Users\me\AppData\Local\Canary\images\photo.png');
    });

    test('returns null for invalid URI', () {
      expect(
        CanaryFileUri.resolveToAbsolute(
          'canary-file:///unknown/a.png',
          root: '/tmp/root',
        ),
        isNull,
      );
    });
  });

  group('CanaryFileUri.tryEncodeLegacyAbsolutePath', () {
    test('encodes iOS Documents style paths even when file is missing', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/upload/x.png',
        ),
        'canary-file:///upload/x.png',
      );
    });

    test('encodes Windows AppData canary style paths case-insensitively', () {
      for (final folder in ['canary', 'Canary', 'CANARY']) {
        expect(
          CanaryFileUri.tryEncodeLegacyAbsolutePath(
            'C:/Users/me/AppData/Local/$folder/images/Pic.PNG',
            allowGenericFallback: false,
          ),
          'canary-file:///images/Pic.PNG',
          reason: folder,
        );
      }
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/AppData/Roaming/canary/avatars/a.png',
          allowGenericFallback: false,
        ),
        'canary-file:///avatars/a.png',
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          r'C:\Users\old-user\AppData\Roaming\com.canary\canary\upload\legacy.pdf',
          allowGenericFallback: false,
        ),
        'canary-file:///upload/legacy.pdf',
      );
      // Bare .../Canary/images without AppData must not match.
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/Projects/Canary/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Suffix / prefix folder names must not match.
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/AppData/Local/CanaryNotes/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
    });

    test(
      'encodes Android package-private app_flutter and files style paths',
      () {
        expect(
          CanaryFileUri.tryEncodeLegacyAbsolutePath(
            '/data/user/0/app.canary.client/app_flutter/fonts/a.ttf',
            allowGenericFallback: false,
          ),
          'canary-file:///fonts/a.ttf',
        );
        expect(
          CanaryFileUri.tryEncodeLegacyAbsolutePath(
            '/data/user/0/app.canary.client/files/upload/doc.pdf',
            allowGenericFallback: false,
          ),
          'canary-file:///upload/doc.pdf',
        );
        // Non-canary package must not be claimed without generic fallback.
        expect(
          CanaryFileUri.tryEncodeLegacyAbsolutePath(
            '/data/user/0/com.example/app_flutter/fonts/a.ttf',
            allowGenericFallback: false,
          ),
          isNull,
        );
      },
    );

    test('rejects lookalike bundles, fake UUIDs, and nested archives', () {
      // Ordinary paths / substring Canary.
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Documents/images/report.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Projects/Canary/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Similar-but-not-whitelist bundles/packages.
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Containers/com.other.canary.notes/Data/Documents/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Application Support/com.other.canary.notes/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/data/user/0/com.other.canary.notes/app_flutter/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          'C:/Users/me/AppData/Local/CanaryNotes/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Fake / short UUID under real iOS root.
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Containers/Data/Application/ABC/Documents/upload/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      // Nested archives: prefixing a valid sandbox path must not claim it.
      for (final nested in const [
        '/tmp/archive/var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/x.png',
        '/tmp/archive/Users/alice/Library/Developer/CoreSimulator/Devices/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/data/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/sim.png',
        '/tmp/archive/Users/alice/Library/Application Support/app.canary.client/images/a.png',
        '/tmp/archive/Users/alice/Library/Containers/app.canary.client/Data/Documents/upload/x.png',
        '/tmp/archive/C:/Users/me/AppData/Local/Canary/images/Pic.PNG',
        '/tmp/archive/data/user/0/app.canary.client/app_flutter/fonts/a.ttf',
      ]) {
        expect(
          CanaryFileUri.tryEncodeLegacyAbsolutePath(
            nested,
            allowGenericFallback: false,
          ),
          isNull,
          reason: nested,
        );
      }
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/tmp/playground/app_flutter/images/x.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '//server/share/images/a.png',
          allowGenericFallback: false,
        ),
        isNull,
      );
    });

    test('encodes iOS Simulator CoreSimulator UUID Documents paths', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Developer/CoreSimulator/Devices/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/data/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/sim.png',
          allowGenericFallback: false,
        ),
        'canary-file:///images/sim.png',
      );
    });

    test('encodes iOS file: URI via portable slash path', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          'file:///var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/pic.png',
          allowGenericFallback: false,
        ),
        'canary-file:///images/pic.png',
      );
    });

    test('normalizes Windows managed root Images casing under AppData', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          r'C:\Users\me\AppData\Local\Canary\Images\x.png',
          allowGenericFallback: false,
        ),
        'canary-file:///images/x.png',
      );
    });

    test('encodes macOS Application Support canary bundle paths', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/Users/alice/Library/Application Support/app.canary.client/images/a.png',
          allowGenericFallback: false,
        ),
        'canary-file:///images/a.png',
      );
    });

    test('uses generic managed-subdir fallback', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/some/random/place/images/nested/file.png',
        ),
        'canary-file:///images/nested/file.png',
      );
    });

    test('rejects POSIX backslash filenames instead of splitting path', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          r'/var/mobile/Containers/Data/Application/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/Documents/images/a\b.png',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          r'/some/random/place/images/a\b.png',
        ),
        isNull,
      );
    });

    test('returns null when managed root/filename requirements fail', () {
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Documents/cache/x.png',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Documents/upload',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath(
          '/var/mobile/Documents/upload/',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.tryEncodeLegacyAbsolutePath('/tmp/only-file.png'),
        isNull,
      );
    });
  });

  group('CanaryFileUri.isCanaryFileUri', () {
    test('is a cheap prefix check', () {
      expect(
        CanaryFileUri.isCanaryFileUri('canary-file:///upload/a.png'),
        isTrue,
      );
      expect(CanaryFileUri.isCanaryFileUri('canary-file:anything'), isTrue);
      expect(CanaryFileUri.isCanaryFileUri('file:///upload/a.png'), isFalse);
      expect(
        CanaryFileUri.isCanaryFileUri('Canary-file:///upload/a.png'),
        isFalse,
      );
      expect(CanaryFileUri.isCanaryFileUri(''), isFalse);
    });
  });

  group('CanaryFileUri.encodeFromAbsolute', () {
    test('encodes only paths under root/<managed>/', () {
      expect(
        CanaryFileUri.encodeFromAbsolute(
          '/data/app/upload/a.png',
          root: '/data/app',
        ),
        'canary-file:///upload/a.png',
      );
      expect(
        CanaryFileUri.encodeFromAbsolute(
          '/data/app/images/nested/b.png',
          root: '/data/app',
        ),
        'canary-file:///images/nested/b.png',
      );
    });

    test('returns null for external or unmanaged paths', () {
      expect(
        CanaryFileUri.encodeFromAbsolute(
          '/other/place/upload/a.png',
          root: '/data/app',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.encodeFromAbsolute(
          '/data/app/cache/a.png',
          root: '/data/app',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.encodeFromAbsolute('/data/app/upload', root: '/data/app'),
        isNull,
      );
    });

    test('encodes Windows-style absolute paths under root', () {
      expect(
        CanaryFileUri.encodeFromAbsolute(
          r'C:\Users\me\AppData\Local\Canary\upload\a.png',
          root: r'C:\Users\me\AppData\Local\Canary',
        ),
        'canary-file:///upload/a.png',
      );
    });

    test('rejects backslash in filename segments', () {
      expect(
        CanaryFileUri.encodeFromAbsolute(
          r'/data/app/upload/a\b.png',
          root: '/data/app',
        ),
        isNull,
      );
      expect(
        CanaryFileUri.decodeToSegments('canary-file:///upload/a%5Cb.png'),
        isNull,
      );
    });
    test('percent-encodes special characters in filenames', () {
      expect(
        CanaryFileUri.encodeFromAbsolute(
          '/data/app/upload/report final.pdf',
          root: '/data/app',
        ),
        'canary-file:///upload/report%20final.pdf',
      );
      expect(
        CanaryFileUri.encodeFromAbsolute(
          '/data/app/upload/a#b.png',
          root: '/data/app',
        ),
        'canary-file:///upload/a%23b.png',
      );
    });
  });
}
