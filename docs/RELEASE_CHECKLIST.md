# TestFlight and App Store release checklist

- [ ] Assign the Apple Developer team and verify `com.cwc.beadpattern` is available.
- [ ] Complete an AGPL/App Store compatibility review before uploading a release build.
- [ ] Tag the exact public source revision corresponding to the binary.
- [ ] Put the source, license, privacy policy, and warranty notice links in App Store metadata.
- [ ] Verify camera denial, limited Photos access, Files import, and document recovery on hardware.
- [ ] Run unit and UI tests on a supported CoreSimulator installation.
- [ ] Test 300×300 editing, undo, focus persistence, PNG export, and CSV round-trip on iPhone and iPad.
- [ ] Capture current iPhone and iPad screenshots from the release candidate.
- [ ] Complete App Privacy answers as "Data Not Collected" after inspecting the final binary.
- [ ] Upload to an internal TestFlight group before external testing or App Review.
