# Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter plugins
-keep class co.quis.flutter_contacts.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.llfbandit.app_links.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# Play Core & Deferred Components
-dontwarn com.google.android.play.core.**

# Kotlin & AndroidX
-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
