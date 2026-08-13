package com.saberplus.app

import io.flutter.embedding.android.FlutterFragmentActivity

// ✅ FIX #5: Cambiado de FlutterActivity a FlutterFragmentActivity
// Esto es REQUERIDO por el plugin local_auth para mostrar el diálogo
// biométrico nativo de Android (BiometricPrompt).
// Sin este cambio, el prompt de huella fallaría silenciosamente.
class MainActivity: FlutterFragmentActivity() {
}
