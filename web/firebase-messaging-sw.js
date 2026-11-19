/**
 * web/firebase-messaging-sw.js — Service Worker de FCM para la web de Saber+.
 * ✅ v2.0 (FCM): imprescindible para que las notificaciones push lleguen con
 * la pestaña cerrada o en background. firebase_messaging lo registra solo.
 *
 * La configuración corresponde al proyecto Firebase real (saberplus-1ec41),
 * leída de lib/firebase_options.dart (web). Son valores públicos de cliente.
 *
 * ⚠️ IMPORTANTE: además de este archivo, el push web requiere generar una
 * "VAPID key" (llave de par web) en Firebase Console → Project settings →
 * Cloud Messaging → Web Push certificates, y definirla en el `.env` de
 * Flutter como FIREBASE_VAPID_KEY (ver GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md).
 */

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBK9xvXbP9pLXyzkvlLj0QpEaD8mi2kMG4',
  appId: '1:341784491066:web:26ca4e954d757889447103',
  messagingSenderId: '341784491066',
  projectId: 'saberplus-1ec41',
  authDomain: 'saberplus-1ec41.firebaseapp.com',
  storageBucket: 'saberplus-1ec41.firebasestorage.app',
  measurementId: 'G-CLQPZCG2F6',
});

try {
  const messaging = firebase.messaging();

  // Mensajes en background (pestaña cerrada o app en segundo plano):
  // se muestra la notificación del sistema con el título/cuerpo del backend.
  messaging.onBackgroundMessage((payload) => {
    const title = (payload.notification && payload.notification.title) || 'Saber+';
    const body = (payload.notification && payload.notification.body) || '';
    const action =
      (payload.data && payload.data.action) || 'go_dashboard';

    self.registration.showNotification(title, {
      body: body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: 'saberplus-' + Date.now(),
      data: { action: action, ...payload.data },
    });
  });

  // Click en la notificación: abre/enfoca la app y navega según la acción.
  self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    const action = (event.notification.data && event.notification.data.action) || 'go_dashboard';

    event.waitUntil(
      self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
        // Si ya hay una pestaña abierta, enfocarla y enviarle la acción.
        for (const client of clientList) {
          if ('focus' in client) {
            client.focus();
            if (client.postMessage) {
              client.postMessage({ type: 'saberplus_notification_click', action: action });
            }
            return;
          }
        }
        // Si no, abrir la app en la raíz (la SPA enruta al dashboard).
        return self.clients.openWindow('/');
      })
    );
  });
} catch (e) {
  // Sin permisos o sin VAPID configurada, el SW queda inerte (no rompe la app).
  console.warn('[saberplus-sw] FCM no disponible:', e);
}
