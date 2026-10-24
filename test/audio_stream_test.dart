import 'package:blisten/models/audio_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTPS candidates preserve base and backup priority', () {
    final track = AudioTrack(
      id: 30280,
      baseUrl: 'https://primary.example/audio.m4s',
      backupUrls: [
        'https://backup-one.example/audio.m4s',
        'https://backup-two.example/audio.m4s',
      ],
    );

    expect(track.httpsCandidates, [
      'https://primary.example/audio.m4s',
      'https://backup-one.example/audio.m4s',
      'https://backup-two.example/audio.m4s',
    ]);
  });

  test('HTTP candidates are upgraded to HTTPS without changing their order', () {
    final track = AudioTrack(
      id: 30280,
      baseUrl: 'http://primary.example/audio.m4s',
      backupUrls: ['HTTP://backup.example/audio.m4s'],
    );

    expect(track.httpsCandidates, [
      'https://primary.example/audio.m4s',
      'https://backup.example/audio.m4s',
    ]);
  });

  test('scheme normalization preserves signed paths and query bytes', () {
    const suffix = '//cdn.example/a%2fb.m4s?token=a%2Fb%2bC+Z&key=%26%3d'
        '&repeat=1&repeat=2&empty=';
    final track = AudioTrack(
      id: 30280,
      baseUrl: 'http:$suffix',
      backupUrls: ['HTTPS:$suffix'],
    );

    expect(track.httpsCandidates, ['https:$suffix', 'https:$suffix']);
  });

  test('invalid base URL does not hide a valid HTTPS backup', () {
    final track = AudioTrack(
      id: 30280,
      baseUrl: 'content://blisten.invalid/media',
      backupUrls: ['file:///invalid/audio', 'https://backup.example/audio.m4s'],
    );

    expect(track.httpsCandidates, ['https://backup.example/audio.m4s']);
  });

  test('valid HTTPS IPv6 host is accepted', () {
    final track = AudioTrack(id: 30280, baseUrl: 'https://[::1]:8443/audio.m4s');

    expect(track.httpsCandidates, ['https://[::1]:8443/audio.m4s']);
  });

  for (final url in [
    '',
    ' ',
    'https://',
    'https:///audio.m4s',
    'https://?token=abc',
    'https://#fragment',
    'https://[::1',
    'https://cdn.example:invalid/audio.m4s',
    'https://cdn.example/%ZZ',
    'https://cdn.example/audio file.m4s',
    'https://cdn.example/audio\nfile.m4s',
    r'https://cdn.example/audio\file.m4s',
    'https://user:password@cdn.example/audio.m4s',
    'https://user@cdn.example/audio.m4s',
    'https://@cdn.example/audio.m4s',
    'content://blisten.invalid/audio',
    'file:///invalid/audio.m4s',
    'ftp://cdn.example/audio.m4s',
    '/audio.m4s',
    'audio.m4s',
    '//cdn.example/audio.m4s',
  ]) {
    test('invalid or non-HTTP(S) candidate is rejected: ${Uri.encodeComponent(url)}', () {
      final track = AudioTrack(id: 30280, baseUrl: url, backupUrls: [url]);

      expect(track.httpsCandidates, isEmpty);
    });
  }
}
