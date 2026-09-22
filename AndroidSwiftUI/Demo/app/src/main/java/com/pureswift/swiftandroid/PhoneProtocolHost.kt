package com.pureswift.swiftandroid

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.Keep
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.journeyapps.barcodescanner.CaptureActivity
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/** Camera captures are private, have no deep-link entry and save no barcode image. */
class SecurePairingCaptureActivity : CaptureActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
}

/** Native effects only. Swift verifies links, protocols, bindings and approvals. */
@Keep
object PhoneProtocolHost {
    private val main = Handler(Looper.getMainLooper())
    private var applicationContext: Context? = null
    private var activity = WeakReference<MainActivity>(null)
    private var dialog: AlertDialog? = null
    private var expiryTask: Runnable? = null
    private val presentationContext = AtomicReference("")
    private val foreground = AtomicBoolean(false)
    private data class Event(val payload: String, val deadline: Long)
    private val pendingEvent = AtomicReference<Event?>(null)

    fun initialize(context: Context) { applicationContext = context.applicationContext }
    fun attach(host: MainActivity) { activity = WeakReference(host) }
    fun detach(host: MainActivity) {
        if (activity.get() === host) { foreground.set(false); dismiss(); pendingEvent.set(null); activity.clear() }
    }
    fun foreground(host: MainActivity) { if (activity.get() === host) foreground.set(true) }
    fun background(host: MainActivity) {
        if (activity.get() === host) { foreground.set(false); dismiss(); pendingEvent.set(null) }
    }
    @JvmStatic fun isForeground(): Boolean = foreground.get()
    @JvmStatic fun openPasskeys() {
        main.post {
            activity.get()?.let { host ->
                host.startActivity(Intent(host, com.pureswift.swiftandroid.passkeys.PasskeyActivity::class.java)
                    .setAction(com.pureswift.swiftandroid.passkeys.PasskeyActivity.MANAGE))
            }
        }
    }
    @JvmStatic fun readConfiguration(): String = applicationContext?.let(PhoneProtocolIO::readConfiguration) ?: failure("hostUnavailable")
    @JvmStatic fun readState(): String = applicationContext?.let(PhoneProtocolIO::readState) ?: failure("hostUnavailable")
    @JvmStatic fun writeState(json: String): String = applicationContext?.let { PhoneProtocolIO.writeState(it, json) } ?: failure("hostUnavailable")
    @JvmStatic fun postJSON(url: String, body: String, bearer: String): String = applicationContext?.let { PhoneProtocolIO.post(it, url, body, bearer) } ?: failure("hostUnavailable")
    @JvmStatic fun consumeEvent(): String {
        val event = pendingEvent.getAndSet(null) ?: return "{}"
        return if (event.deadline > now()) event.payload else "{}"
    }
    @JvmStatic fun updatePresentationContext(binding: String) {
        val previous = presentationContext.getAndSet(binding)
        if (previous != binding) dismiss()
    }
    @JvmStatic fun dismiss() { main.post { expiryTask?.let(main::removeCallbacks); expiryTask = null; dialog?.dismiss(); dialog = null } }

    @JvmStatic fun requestImport(camera: Boolean) {
        main.post {
            val host = activity.get() ?: return@post emitFailure("hostUnavailable")
            dismissCurrent()
            if (camera) host.launchPairingScanner() else manualImport(host)
        }
    }
    fun scannerResult(link: String?, permissionDenied: Boolean) {
        val host = activity.get() ?: return
        if (link != null) {
            try { PhoneHostPolicy.validateLinkSize(link); emit(JSONObject().put("kind", "invitation").put("link", link)) }
            catch (_: Exception) { emitFailure("invalidInvitation") }
        } else if (permissionDenied) {
            AlertDialog.Builder(host).setTitle("Camera access is unavailable")
                .setMessage("You can paste the pairing link from the other phone instead. No pairing or approval has been sent.")
                .setPositiveButton("Enter pairing link") { _, _ -> manualImport(host) }
                .setNegativeButton("Cancel") { _, _ -> emitCancelled() }.show()
        } else { emitCancelled() }
    }
    @JvmStatic fun presentInvitation(link: String, binding: String, expiry: String) {
        val deadline = expiry.toLongOrNull() ?: return emitFailure("invalidInvitation")
        try { PhoneHostPolicy.validateLinkSize(link) } catch (_: Exception) { return emitFailure("invalidInvitation") }
        if (!PhoneHostPolicy.mayPresent(presentationContext.get(), binding, deadline, now())) return emitFailure("invitationExpired")
        main.post {
            val host = activity.get() ?: return@post emitFailure("hostUnavailable")
            if (!PhoneHostPolicy.mayPresent(presentationContext.get(), binding, deadline, now())) return@post emitFailure("invitationExpired")
            dismissCurrent()
            val content = column(host)
            content.addView(text(host, "Scan this private QR on the other phone. The invitation grants no ownership and never replaces its trusted authority configuration."))
            val matrix = try {
                MultiFormatWriter().encode(link, BarcodeFormat.QR_CODE, 640, 640,
                    mapOf(EncodeHintType.MARGIN to 4, EncodeHintType.CHARACTER_SET to "UTF-8"))
            } catch (_: Exception) { return@post emitFailure("qrUnavailable") }
            val bitmap = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(matrix.width * matrix.height) { index -> if (matrix[index % matrix.width, index / matrix.width]) Color.BLACK else Color.WHITE }
            bitmap.setPixels(pixels, 0, matrix.width, 0, 0, matrix.width, matrix.height)
            val qr = ImageView(host).apply {
                setImageBitmap(bitmap); adjustViewBounds = true
                contentDescription = "Private one-use pairing QR. You can share the pairing link with the button below."
                isSaveEnabled = false
            }
            content.addView(qr, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(host, 280)))
            val countdown = text(host, "Expires in ${deadline - now()} seconds")
            content.addView(countdown)
            val sheet = AlertDialog.Builder(host).setTitle("Pair another phone").setView(ScrollView(host).apply { addView(content) })
                .setPositiveButton("Share pairing link", null).setNeutralButton("Copy link", null)
                .setNegativeButton("Hide") { _, _ -> }.create()
            sheet.setOnDismissListener {
                expiryTask?.let(main::removeCallbacks); expiryTask = null
                qr.setImageDrawable(null); bitmap.eraseColor(Color.TRANSPARENT); bitmap.recycle()
                if (dialog === sheet) dialog = null
            }
            dialog = sheet; sheet.show(); secure(sheet)
            fun stillCurrent(): Boolean = PhoneHostPolicy.mayPresent(presentationContext.get(), binding, deadline, now())
            sheet.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (!stillCurrent()) { sheet.dismiss(); return@setOnClickListener }
                val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
                host.startActivity(Intent.createChooser(intent, "Share this short-lived pairing link"))
            }
            sheet.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                if (!stillCurrent()) { sheet.dismiss(); return@setOnClickListener }
                val clip = ClipData.newPlainText("Private pairing invitation", link)
                if (android.os.Build.VERSION.SDK_INT >= 33) clip.description.extras = android.os.PersistableBundle().apply {
                    putBoolean(android.content.ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
                val clipboard = host.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(clip)
                main.postDelayed({
                    // Clear only this exact clipboard value; never overwrite a later user copy.
                    if (clipboard.primaryClip?.getItemAt(0)?.text?.toString() == link) clipboard.clearPrimaryClip()
                }, ((deadline - now()).coerceAtLeast(1) * 1000).coerceAtMost(Int.MAX_VALUE.toLong()))
                Toast.makeText(host, "Pairing link copied", Toast.LENGTH_SHORT).show()
            }
            expiryTask = object : Runnable {
                override fun run() {
                    if (!stillCurrent()) { sheet.dismiss(); return }
                    countdown.text = "Expires in ${deadline - now()} seconds"
                    main.postDelayed(this, 1000)
                }
            }.also { main.post(it) }
        }
    }
    @JvmStatic fun requestConfiguration() {
        main.post {
            val host = activity.get() ?: return@post emitFailure("hostUnavailable")
            dismissCurrent()
            val content = column(host)
            content.addView(text(host, "Obtain the authority configuration through a trusted channel. A pairing QR must never set this pin. Existing v2 identity state locks its authority configuration."))
            val field = input(host).apply {
                hint = "{\"serverURL\":\"https://authority.example\",\"serverPublicKey\":\"BASE64_P256_KEY\",\"audience\":\"swiftkey-authority-v2\",\"workloadAudience\":\"swiftkey.local\"}"
                minLines = 6
            }
            val existing = readConfiguration()
            if (existing != "{}" && !existing.contains("\"error\"")) field.setText(existing)
            content.addView(field)
            val error = text(host, "HTTPS is required. Debug builds also support explicit 127.0.0.1 ports for adb reverse.")
            content.addView(error)
            val sheet = AlertDialog.Builder(host).setTitle("Trusted authority configuration").setView(ScrollView(host).apply { addView(content) })
                .setPositiveButton("Save trusted configuration", null).setNegativeButton("Cancel") { _, _ -> }.create()
            sheet.setOnDismissListener { field.text.clear(); if (dialog === sheet) dialog = null }
            dialog = sheet; sheet.show(); secure(sheet)
            sheet.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val result = applicationContext?.let { PhoneProtocolIO.saveConfiguration(it, field.text.toString()) }
                if (result != null && JSONObject(result).optBoolean("ok")) {
                    sheet.dismiss(); emit(JSONObject().put("kind", "configurationChanged"))
                } else { error.text = "Configuration is invalid, cannot be stored, or is locked by an existing v2 identity. No key or state was replaced." }
            }
        }
    }
    private fun manualImport(host: MainActivity) {
        dismissCurrent()
        val content = column(host)
        content.addView(text(host, "Paste the full private link from the other phone. Import only inspects the invitation; you must review the authority and peers before any confirmation."))
        val field = input(host).apply { hint = "Pairing link"; minLines = 3 }
        content.addView(field)
        val error = text(host, "The link is held only in this private session and is never used as authority configuration.")
        content.addView(error)
        val sheet = AlertDialog.Builder(host).setTitle("Enter pairing link").setView(ScrollView(host).apply { addView(content) })
            .setPositiveButton("Inspect invitation", null).setNegativeButton("Cancel") { _, _ -> emitCancelled() }.create()
        sheet.setOnDismissListener { field.text.clear(); if (dialog === sheet) dialog = null }
        dialog = sheet; sheet.show(); secure(sheet)
        sheet.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val link = field.text.toString().trim()
            try {
                PhoneHostPolicy.validateLinkSize(link)
                sheet.dismiss(); emit(JSONObject().put("kind", "invitation").put("link", link))
            } catch (_: Exception) { error.text = "Enter a complete pairing link of at most 8192 characters." }
        }
    }
    private fun dismissCurrent() { expiryTask?.let(main::removeCallbacks); expiryTask = null; dialog?.dismiss(); dialog = null }
    private fun secure(sheet: AlertDialog) { sheet.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    private fun column(context: Context) = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; setPadding(dp(context, 20), dp(context, 12), dp(context, 20), dp(context, 16))
        setBackgroundColor(if (isDark(context)) Color.rgb(30, 30, 30) else Color.WHITE); isSaveEnabled = false
    }
    private fun text(context: Context, value: String) = TextView(context).apply {
        text = value; textSize = 16f; typeface = androidx.core.content.res.ResourcesCompat.getFont(context, com.pureswift.swiftandroid.R.font.host_grotesk_400); setTextColor(if (isDark(context)) Color.rgb(252, 252, 252) else Color.rgb(30, 30, 30)); setPadding(0, dp(context, 8), 0, dp(context, 8)); isSaveEnabled = false
    }
    private fun input(context: Context) = EditText(context).apply {
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        typeface = androidx.core.content.res.ResourcesCompat.getFont(context, com.pureswift.swiftandroid.R.font.jetbrains_mono_400); isSaveEnabled = false; setTextColor(if (isDark(context)) Color.rgb(252, 252, 252) else Color.rgb(30, 30, 30)); setTextSize(15f)
    }
    private fun emit(event: JSONObject) { pendingEvent.set(Event(event.toString(), now() + 120)) }
    private fun emitFailure(code: String) { emit(JSONObject().put("kind", "failure").put("code", code)) }
    private fun emitCancelled() { emit(JSONObject().put("kind", "cancelled")) }
    private fun failure(code: String) = JSONObject().put("error", code).toString()
    private fun now() = System.currentTimeMillis() / 1000
    private fun isDark(context: Context) = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES
    private fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density).toInt()
}
