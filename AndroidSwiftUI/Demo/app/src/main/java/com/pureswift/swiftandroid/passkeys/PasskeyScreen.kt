package com.pureswift.swiftandroid.passkeys

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import com.pureswift.swiftandroid.R

/** Product controls use the same source design tokens as the shared Swift views. */
@Composable internal fun PasskeyScreen(managing: Boolean, request: WebAuthnRequest?, selected: PasskeyRecord?,
    records: List<PasskeyRecord>, availability: PasskeyAvailability, busy: Boolean, message: String?,
    onBack: () -> Unit, onEnable: () -> Unit, onApprove: () -> Unit, onDelete: (PasskeyRecord) -> Unit) {
    val dark = isSystemInDarkTheme()
    val font = FontFamily(Font(R.font.host_grotesk_400), Font(R.font.host_grotesk_500, FontWeight.Medium),
        Font(R.font.host_grotesk_600, FontWeight.SemiBold))
    val colors = if (dark) darkColorScheme(primary = Color(0xFFD28FE2), onPrimary = Color(0xFF1E1E1E),
        background = Color(0xFF1E1E1E), surface = Color(0xFF252326), onSurface = Color(0xFFFCFCFC),
        onBackground = Color(0xFFFCFCFC), onSurfaceVariant = Color(0xFFABBAB9), outlineVariant = Color(0xFF2F2D30), error = Color(0xFFF9786A))
    else lightColorScheme(primary = Color(0xFFA02AB8), onPrimary = Color.White,
        background = Color.White, surface = Color.White, onSurface = Color(0xFF1E1E1E),
        onBackground = Color(0xFF1E1E1E), onSurfaceVariant = Color(0xFF6B6B6B), outlineVariant = Color(0xFFE5E5E5), error = Color(0xFFD33C33))
    val typography = Typography(
        bodyLarge = androidx.compose.ui.text.TextStyle(fontFamily = font, fontSize = 16.sp, lineHeight = 28.sp),
        bodyMedium = androidx.compose.ui.text.TextStyle(fontFamily = font, fontSize = 14.sp, lineHeight = 21.sp),
        titleLarge = androidx.compose.ui.text.TextStyle(fontFamily = font, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 32.sp),
        headlineLarge = androidx.compose.ui.text.TextStyle(fontFamily = font, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 40.sp),
        labelLarge = androidx.compose.ui.text.TextStyle(fontFamily = font, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 21.sp))
    var deleting by remember { mutableStateOf<PasskeyRecord?>(null) }
    MaterialTheme(colorScheme = colors, typography = typography,
        shapes = Shapes(small = RoundedCornerShape(8.dp), medium = RoundedCornerShape(12.dp))) {
        Surface(color = colors.background, modifier = Modifier.fillMaxSize().testTag("swiftkey.passkeys")) {
            Column(Modifier.safeDrawingPadding().fillMaxSize().verticalScroll(rememberScrollState())
                .padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 760.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text("SwiftKey", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                        TextButton(onClick = onBack) { Text(if (managing) "Back" else "Cancel") }
                    }
                    Text(if (managing) "Website passkeys" else if (request is WebAuthnCreateRequest) "Create a passkey" else "Approve sign-in",
                        style = MaterialTheme.typography.headlineLarge)
                    Text(if (managing) "Use SwiftKey in your browser’s normal passkey flow. Each website gets its own key, protected by this phone."
                        else "Check the website and account, then verify with your fingerprint or screen lock.",
                        style = MaterialTheme.typography.bodyLarge)
                    if (managing) {
                        PasskeyCard {
                            Text(if (availability.canCreate) "Ready on this phone" else "Device requirements", style = MaterialTheme.typography.titleLarge)
                            Text(availability.message)
                            Button(onClick = onEnable, modifier = Modifier.fillMaxWidth().testTag("swiftkey.passkeys.enable"),
                                shape = RoundedCornerShape(8.dp)) { Text("Enable SwiftKey in Android Settings") }
                        }
                        Text("Saved on this phone · ${records.size}", style = MaterialTheme.typography.titleLarge)
                        if (records.isEmpty()) PasskeyCard {
                            Text("Your first passkey starts on a website", style = MaterialTheme.typography.titleLarge)
                            Text("Open a website’s account security settings, choose Add a passkey, and select SwiftKey. Return here to manage saved passkeys.")
                        }
                        records.forEach { record ->
                            PasskeyCard {
                                Text(record.rpId, style = MaterialTheme.typography.titleLarge)
                                Text(record.userName, style = MaterialTheme.typography.bodyLarge)
                                if (record.displayName != record.userName) Text(record.displayName)
                                Text("Device-bound · verification required", color = colors.onSurfaceVariant)
                                TextButton(onClick = { deleting = record }, enabled = !busy) { Text("Remove from this phone", color = colors.error) }
                            }
                        }
                        Text("Passkeys stay on this phone and do not rotate. Pairing another phone does not copy them. Add that phone separately on each website, and keep another sign-in or recovery method.",
                            color = colors.onSurfaceVariant)
                    } else {
                        PasskeyCard {
                            Text("Website", color = colors.onSurfaceVariant)
                            Text(request?.rpId ?: "Unavailable", style = MaterialTheme.typography.titleLarge)
                            Text("Account", color = colors.onSurfaceVariant)
                            Text((request as? WebAuthnCreateRequest)?.userName ?: selected?.userName.orEmpty(), style = MaterialTheme.typography.bodyLarge)
                            Text("Private key stays in this phone’s StrongBox. The website receives a public key and verified signatures.")
                        }
                        Button(onClick = onApprove, enabled = !busy,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("swiftkey.passkeys.approve"),
                            shape = RoundedCornerShape(8.dp)) {
                            Text(if (busy) "Waiting for device verification…" else if (request is WebAuthnCreateRequest) "Create passkey" else "Verify and sign in")
                        }
                    }
                    if (busy) LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    message?.let { Text(it, color = colors.error, modifier = Modifier.testTag("swiftkey.passkeys.message")) }
                }
            }
        }
        deleting?.let { record ->
            AlertDialog(onDismissRequest = { deleting = null }, title = { Text("Remove this passkey?") },
                text = { Text("${record.userName} at ${record.rpId}\n\nThis cannot be undone. Make sure you have another way to sign in. The website’s account is not deleted.") },
                confirmButton = { TextButton(onClick = { deleting = null; onDelete(record) }) { Text("Remove", color = colors.error) } },
                dismissButton = { TextButton(onClick = { deleting = null }) { Text("Keep passkey") } })
        }
    }
}

@Composable private fun PasskeyCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(12.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}
