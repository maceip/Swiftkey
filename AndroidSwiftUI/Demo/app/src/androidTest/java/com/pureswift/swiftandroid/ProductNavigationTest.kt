package com.pureswift.swiftandroid

import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith

/** Exercises the shipped debug host and its real Swift-rendered navigation. */
@RunWith(AndroidJUnit4::class)
class ProductNavigationTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Suppress("DEPRECATION")
    @Test fun installedDebugPackageExportsOnlyTheProductLauncher() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val installed = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_ACTIVITIES)
        assertEquals(
            setOf(MainActivity::class.java.name),
            installed.activities.orEmpty().filter { it.exported }.map { it.name }.toSet(),
        )
    }

    @Test fun launcherAndPairingReturnOnlyExposeProductScreens() {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        assertProductNavigation(intent)
    }

    @Test fun websitePasskeysAreReachableFromTheProductLauncher() {
        ActivityScenario.launch<MainActivity>(Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)).use {
            awaitControl("swiftkey.open-passkeys")
            compose.onNodeWithTag("swiftkey.open-passkeys").performClick()
            awaitControl("swiftkey.passkeys.enable")
            compose.onNodeWithText("Website passkeys").assertIsDisplayed()
            assertNoDeveloperGallery()
            compose.onNodeWithText("Back").performClick()
            awaitControl("swiftkey.open-passkeys")
        }
    }

    @Test fun incomingGalleryDataAndExtrasCannotSelectADeveloperScreen() {
        // MainActivity is exported for the launcher. Explicit external intents
        // must not acquire a developer route, even in the distributed debug APK.
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("swiftkey://cupertino/catalog"))
            .putExtra("screen", "cupertino")
            .putExtra("route", "catalog")
            .putExtra("showcase", true)
        assertProductNavigation(intent)
    }

    private fun assertProductNavigation(intent: Intent) {
        ActivityScenario.launch<MainActivity>(intent).use {
            awaitControl("swiftkey.open-phone-protocol")
            assertNoDeveloperGallery()
            compose.onNodeWithTag("swiftkey.open-phone-protocol").performClick()
            awaitControl("swiftkey.close-phone-protocol")
            assertNoDeveloperGallery()
            compose.onNodeWithTag("swiftkey.close-phone-protocol").performClick()
            awaitControl("swiftkey.open-phone-protocol")
            assertNoDeveloperGallery()
        }
    }

    private fun awaitControl(tag: String) {
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag(tag).assertIsDisplayed()
    }

    private fun assertNoDeveloperGallery() {
        compose.onAllNodes(
            hasText("Cupertino", substring = true, ignoreCase = true) or
                hasText("catalog", substring = true, ignoreCase = true) or
                hasText("showcase", substring = true, ignoreCase = true),
            useUnmergedTree = true,
        ).assertCountEquals(0)
        compose.onAllNodesWithTag("swiftkey.open-cupertino-catalog").assertCountEquals(0)
        compose.onAllNodesWithTag("swiftkey.close-cupertino-catalog").assertCountEquals(0)
    }
}
