# Reglas ProGuard/R8 para Saber+ (Flutter)
# La ofuscación R8 está activada en release. Flutter y los plugins comunes
# ya traen sus reglas consumer-rules; aquí solo se añaden excepciones puntuales.

# --- Firebase / FCM ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# --- flutter_downloader (workmanager) ---
-keep class com.dexterous.** { *; }

# --- Wompi / webviews: conservar interfaces Javascript ---
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# --- Kotlin coroutines (usado por plugins) ---
-dontwarn kotlinx.coroutines.**

# --- Lectura de Códigos QR / biometría si se añaden luego ---
-keep class androidx.biometric.** { *; }
