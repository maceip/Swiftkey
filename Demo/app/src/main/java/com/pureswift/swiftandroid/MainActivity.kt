package com.pureswift.swiftandroid

import android.graphics.Color
import android.os.Bundle
import com.google.zxing.client.android.Intents
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.pureswift.swiftandroid.ui.theme.SwiftAndroidTheme

// A pure consumer: hosting, the JNI lifecycle and `setRootView` all live in
// `SwiftUIActivity` (`:androidbridge`). This app adds its composable registry
// and explicit native pairing effects; protocol decisions remain in Swift.
class MainActivity : SwiftUIActivity() {
    private val pairingScanner = registerForActivityResult(ScanContract()) { result ->
        PhoneProtocolHost.scannerResult(result.contents,
            result.originalIntent?.getBooleanExtra(Intents.Scan.MISSING_CAMERA_PERMISSION, false) == true)
    }
    fun launchPairingScanner() {
        try {
            pairingScanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setCaptureActivity(SecurePairingCaptureActivity::class.java).setBeepEnabled(false)
                .setBarcodeImageEnabled(false).setOrientationLocked(false)
                .setPrompt("Scan the other phone’s private pairing QR. Scanning does not approve ownership."))
        } catch (_: Exception) { PhoneProtocolHost.scannerResult(null, permissionDenied = true) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        PhoneProtocolHost.attach(this)
        super.onCreate(savedInstanceState)
        // System bars follow the same OS appearance as the shared adaptive colors.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT),
        )
    }

    override fun onStart() { super.onStart(); PhoneProtocolHost.foreground(this) }
    override fun onStop() { PhoneProtocolHost.background(this); super.onStop() }
    override fun onDestroy() { PhoneProtocolHost.detach(this); super.onDestroy() }

    override fun onRegisterComposables() {
        registerDemoComposables()
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello $name!",
        modifier = modifier
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    SwiftAndroidTheme {
        Greeting("Android")
    }
}
