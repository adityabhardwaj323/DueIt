importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// To receive background messages in Web, you must manually populate your 
// firebaseConfig here. This cannot easily be dynamically pulled from 
// dart environment variables in the service worker context without a build step.
// DO NOT commit private secrets. This config is safe to be public (it's the client config).

const firebaseConfig = {
  apiKey: "REPLACE_WITH_API_KEY",
  authDomain: "REPLACE_WITH_AUTH_DOMAIN",
  projectId: "dueit-323",
  storageBucket: "REPLACE_WITH_STORAGE_BUCKET",
  messagingSenderId: "REPLACE_WITH_SENDER_ID",
  appId: "REPLACE_WITH_APP_ID"
};

// Initialize Firebase
if (!firebase.apps.length) {
    firebase.initializeApp(firebaseConfig);
}

// Retrieve firebase messaging
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  
  const notificationTitle = payload.notification?.title || 'DueIt';
  const notificationOptions = {
    body: payload.notification?.body,
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
