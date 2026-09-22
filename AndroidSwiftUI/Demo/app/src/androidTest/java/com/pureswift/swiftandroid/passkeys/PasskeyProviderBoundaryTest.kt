package com.pureswift.swiftandroid.passkeys

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.credentials.provider.CallingAppInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PasskeyProviderBoundaryTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    @Suppress("DEPRECATION")
    @Test fun providerCanOnlyBeBoundByTheOperatingSystemAndApprovalActivityIsPrivate() {
        val info = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SERVICES or PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS)
        val provider = info.services.orEmpty().single { it.name == SwiftKeyCredentialProviderService::class.java.name }
        assertTrue(provider.exported)
        assertEquals("android.permission.BIND_CREDENTIAL_PROVIDER_SERVICE", provider.permission)
        assertFalse(info.activities.orEmpty().single { it.name == PasskeyActivity::class.java.name }.exported)
    }
    @Suppress("DEPRECATION")
    @Test fun anAppCannotClaimABrowserOriginWithItsOwnCertificate() {
        assumeTrue(Build.VERSION.SDK_INT >= 34)
        val info = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        val caller = CallingAppInfo("com.android.chrome", info.signingInfo!!, "https://example.com")
        assertThrows(Exception::class.java) { TrustedPasskeyCaller.verify(context, caller, ByteArray(32)) }
    }
    @Test fun forgedAndProcessDeathSelectionsNeverReturnAPasskey() {
        assumeTrue(Build.VERSION.SDK_INT >= 34)
        for (action in listOf(PasskeyActivity.CREATE, PasskeyActivity.GET)) {
            ActivityScenario.launchActivityForResult<PasskeyActivity>(Intent(context, PasskeyActivity::class.java)
                .setAction(action).setData(Uri.parse("swiftkey-passkey://selection/unrecognized"))).use { scenario ->
                val result = scenario.result
                // Error results are RESULT_OK to deliver a typed Credential Manager exception.
                assertEquals(Activity.RESULT_OK, result.resultCode)
                assertNotNull(result.resultData)
                if (action == PasskeyActivity.CREATE) {
                    assertNotNull(androidx.credentials.provider.PendingIntentHandler.retrieveCreateCredentialException(result.resultData!!))
                } else {
                    assertNotNull(androidx.credentials.provider.PendingIntentHandler.retrieveGetCredentialException(result.resultData!!))
                }
            }
        }
    }
}
