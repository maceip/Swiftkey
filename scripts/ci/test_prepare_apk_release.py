import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare-apk-release.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


def manifest(extra=""):
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application>
      <activity android:name="com.pureswift.swiftandroid.MainActivity" android:exported="true"/>
      <activity android:name="com.journeyapps.barcodescanner.CaptureActivity" android:exported="false"/>
      {extra}
    </application></manifest>'''


class ProductManifestTests(unittest.TestCase):
    def test_passkey_provider_requires_system_binding_permission(self):
        name = "com.pureswift.swiftandroid.passkeys.SwiftKeyCredentialProviderService"
        prepare.verify_product_manifest(manifest(f'<service android:name="{name}" android:exported="true" android:permission="android.permission.BIND_CREDENTIAL_PROVIDER_SERVICE"/>'))
        with self.assertRaises(ValueError):
            prepare.verify_product_manifest(manifest(f'<service android:name="{name}" android:exported="true"/>'))

    def test_product_and_private_scanner_are_allowed(self):
        prepare.verify_product_manifest(manifest())

    def test_preview_dependency_is_rejected_even_when_not_exported(self):
        for name in ("androidx.compose.ui.tooling.PreviewActivity", "androidx.activity.ComponentActivity"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                prepare.verify_product_manifest(manifest(f'<activity android:name="{name}" android:exported="false"/>'))

    def test_unexpected_exported_activity_and_alias_are_rejected(self):
        for tag in ("activity", "activity-alias"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                prepare.verify_product_manifest(manifest(f'<{tag} android:name="example.Gallery" android:exported="true"/>'))

    def test_implicit_export_through_intent_filter_is_rejected(self):
        with self.assertRaises(ValueError):
            prepare.verify_product_manifest(manifest('<activity android:name="example.Gallery"><intent-filter/></activity>'))


if __name__ == "__main__":
    unittest.main()
