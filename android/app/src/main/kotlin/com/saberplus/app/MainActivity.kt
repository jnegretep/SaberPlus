package com.saberplus.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity

// ✅ FIX #5: Cambiado de FlutterActivity a FlutterFragmentActivity
// Esto es REQUERIDO por el plugin local_auth para mostrar el diálogo
// biométrico nativo de Android (BiometricPrompt).
// Sin este cambio, el prompt de huella fallaría silenciosamente.
//
// ✅ v2.0 (FCM): se crea el canal de notificaciones 'saberplus_notificaciones'.
// En Android 8+ (API 26+), una notificación cuyo canal no existe se descarta
// silenciosamente con la app en background/terminada — este era uno de los
// motivos por los que las push "no llegaban". El backend envía exactamente
// este channel_id (send_notification.php / send_notification_all.php /
// admin/send_bulk.php).
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Notificaciones Saber+",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Retos, recordatorios de simulacros y novedades"
                    enableVibration(true)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    companion object {
        private const val CHANNEL_ID = "saberplus_notificaciones"
    }
}
