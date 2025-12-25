import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: "AIzaSyCWkH2x7ujj3xc8M1fhJAMphWo7pLBhV_k",
  authDomain: "orlomed-f8f9f.firebaseapp.com",
  projectId: "orlomed-f8f9f",
  storageBucket: "orlomed-f8f9f.firebasestorage.app",
  messagingSenderId: "673799768268",
  appId: "1:673799768268:web:2313db56d5226e17c6da69",
};

// Firebase inicializálás
const app = initializeApp(firebaseConfig);

// Szolgáltatások exportálása
export const db = getFirestore(app);
export const auth = getAuth(app);
export default app;