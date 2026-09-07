import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_library_storage.dart';

export 'file_library_storage.dart';

LibraryStorage createLibraryStorage() => libraryStorageFactory();

@visibleForTesting
LibraryStorage Function() libraryStorageFactory = () => FileLibraryStorage(
  directory: () async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'library'),
  ),
);
