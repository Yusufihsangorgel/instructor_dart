Issue: #<number>

Checklist, matching CI. Run in the repository root:

- [ ] `dart pub get`
- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `dart analyze --fatal-infos`
- [ ] `dart test --exclude-tags e2e`
- [ ] `CHANGELOG.md` entry added
