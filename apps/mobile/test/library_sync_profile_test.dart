import 'package:aethertune/src/domain/library_sync_profile.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const device = <String, Object?>{
    'id': '0123456789abcdef01234567',
    'deviceName': 'Phone',
    'createdAt': '2026-07-20T12:00:00.000Z',
  };

  test('detects the public-profile capability from a current server', () {
    final profile = LibrarySyncProfile.fromServerJson(<String, Object?>{
      'account': <String, Object?>{
        'id': 'primary',
        'displayName': 'Primary listener',
        'avatarTone': 'emerald',
        'publicProfileEnabled': true,
        'managed': true,
        'editable': true,
      },
      'device': device,
    });

    expect(profile.publicProfileSupported, isTrue);
    expect(profile.publicProfileEnabled, isTrue);
    expect(profile.publicProfileFieldAudienceSupported, isFalse);
    expect(profile.publicDisplayNameEnabled, isTrue);
    expect(profile.publicAvatarToneEnabled, isTrue);
  });

  test('parses independent public profile audiences from a current server', () {
    final profile = LibrarySyncProfile.fromServerJson(<String, Object?>{
      'account': <String, Object?>{
        'id': 'primary',
        'displayName': 'Primary listener',
        'avatarTone': 'emerald',
        'publicProfileEnabled': true,
        'publicProfileFieldAudienceSupported': true,
        'publicDisplayNameEnabled': true,
        'publicAvatarToneEnabled': false,
        'managed': true,
        'editable': true,
      },
      'device': device,
    });

    expect(profile.publicProfileFieldAudienceSupported, isTrue);
    expect(profile.publicDisplayNameEnabled, isTrue);
    expect(profile.publicAvatarToneEnabled, isFalse);
  });

  test('keeps public profiles disabled for older compatible servers', () {
    final profile = LibrarySyncProfile.fromServerJson(<String, Object?>{
      'account': <String, Object?>{
        'id': 'primary',
        'managed': true,
        'editable': true,
      },
      'device': device,
    });

    expect(profile.publicProfileSupported, isFalse);
    expect(profile.publicProfileEnabled, isFalse);
  });

  test('builds a token-free public profile endpoint under a server path', () {
    final account = createLibrarySyncAccount(
      baseUrl: 'https://sync.example.test/aethertune',
      deviceId: 'Phone',
      allowInsecureHttp: false,
    );

    expect(
      account.publicProfileEndpointUri('primary').toString(),
      'https://sync.example.test/aethertune/api/v1/public-profiles/primary',
    );
    expect(
      account.publicProfilePageUri('primary').toString(),
      'https://sync.example.test/aethertune/api/v1/public-profiles/primary?format=html',
    );
  });
}
