import 'verify_dependencies.dart';

void main() {
  const package = {
    'version': '1.0.0',
    'source': 'hosted',
    'description': {
      'name': 'fixture',
      'url': 'https://pub.dev',
      'sha256': 'hash',
    },
  };
  final client = {'fixture': package};
  if (verifyGraphs(client, client) != 1)
    throw StateError('Matching graph failed.');
  final rejected = [
    <String, Object?>{},
    {'unknown': package},
    {
      'fixture': {...package, 'version': '2.0.0'},
    },
    {
      'fixture': {...package, 'source': 'git'},
    },
    {
      'fixture': {...package, 'description': null},
    },
    for (final key in ['name', 'url', 'sha256'])
      {
        'fixture': {
          ...package,
          'description': {...package['description'] as Map, key: 'changed'},
        },
      },
  ];
  for (final graph in rejected) {
    try {
      verifyGraphs(client, graph);
    } on FormatException {
      continue;
    }
    throw StateError('Invalid dependency graph passed: $graph');
  }
  print(
    'Dependency policy accepted one valid and rejected eight invalid graphs.',
  );
}
