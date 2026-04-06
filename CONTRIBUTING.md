# Contributing

## Builds must succeed

Before pushing or opening a PR, ensure the project **builds cleanly** in Xcode (or via `xcodebuild`) for the targets you touched. Do not commit changes that leave the tree in a non-building state.

### SDK Playground

From `Examples/SDKPlayground`:

```bash
./generate_xcodeproj.sh
xcodebuild -scheme SDKPlayground -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Use `./generate_xcodeproj.sh` instead of raw `xcodegen generate` so local Swift package links are patched (see `Examples/SDKPlayground/README.md`).
