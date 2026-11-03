import 'library_profile_test.dart' as library_profile;
import 'share_profile_test.dart' as sharing;

// One profile installation measures the actual compact model before testing
// sharing. The normal release is installed separately after a full uninstall.
void main() {
  library_profile.main();
  sharing.main();
}
