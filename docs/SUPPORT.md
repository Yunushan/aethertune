# Support

## Getting help

Open a GitHub issue with:

- device model
- Android/iOS version
- app version
- exact steps to reproduce
- logs or screenshots when useful

## Common issues

### Flutter is not found

Install Flutter and make sure `flutter` is on your PATH.

### Android/iOS folders are missing

Run:

```bash
./scripts/bootstrap_mobile.sh
```

### Audio file does not play

Try another local file first. Some codecs may not be supported equally across Android and iOS.

### Provider does not stream

Provider adapters must resolve a legal playable URI. Metadata-only tracks cannot play until a provider returns a stream URL.
