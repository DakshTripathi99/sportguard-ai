importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js");

firebase.initializeApp({
    apiKey: "AIzaSyCLdNOeHn0ezRzlxa_VeL9XpnGsQ7mWqKY",
    authDomain: "sportguard-ai-7a73a.firebaseapp.com",
    projectId: "sportguard-ai-7a73a",
    storageBucket: "sportguard-ai-7a73a.firebasestorage.app",
    messagingSenderId: "1010188362147",
    appId: "1:1010188362147:web:a59f62bfb40f24ad753a16",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    self.registration.showNotification(payload.notification.title, {
        body: payload.notification.body,
    });
});