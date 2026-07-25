package com.pureswift.swiftandroid

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.pureswift.swiftandroid.ui.theme.SwiftAndroidTheme

// A pure consumer: hosting, the JNI lifecycle and `setRootView` all live in
// `SwiftUIActivity` (`:androidbridge`). All this app adds is its own
// composable registry.
class MainActivity : SwiftUIActivity() {

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
