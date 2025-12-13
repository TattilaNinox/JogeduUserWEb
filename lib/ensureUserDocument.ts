import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';
import { type User } from 'firebase/auth';
import { getFirebase } from './firebase';
import { getWebDeviceFingerprint } from './deviceFingerprint';

type NullableDate = Date | null | undefined;

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

export async function ensureUserDocument(user: User, opts?: { firstName?: string; lastName?: string }): Promise<void> {
  const { db } = getFirebase();
  const ref = doc(db, 'users', user.uid);
  const snap = await getDoc(ref);
  const now = new Date();
  const fingerprint = getWebDeviceFingerprint();

  const baseFields = {
    email: user.email ?? '',
    userType: 'normal',
    science: 'Jogász',
    subscriptionStatus: 'free',
    isSubscriptionActive: false,
    subscriptionEndDate: null as NullableDate,
    lastPaymentDate: null as NullableDate,
    freeTrialStartDate: now,
    freeTrialEndDate: addDays(now, 5),
    deviceRegistrationDate: now,
    authorizedDeviceFingerprint: fingerprint,
    isActive: true,
    firstName: opts?.firstName ?? null,
    lastName: opts?.lastName ?? null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  } as const;

  if (!snap.exists()) {
    await setDoc(ref, baseFields, { merge: true });
    // Helyi tárolás (web): próbaidőszak dátumok
    if (typeof window !== 'undefined') {
      try {
        window.localStorage.setItem('trial_start_date', now.toISOString());
        window.localStorage.setItem('trial_end_date', addDays(now, 5).toISOString());
      } catch (_) {}
    }
  } else {
    const data = snap.data() as any;
    const toSet: Record<string, any> = { updatedAt: serverTimestamp() };

    const ensure = (key: string, value: any) => {
      if (data[key] === undefined || data[key] === null) toSet[key] = value;
    };

    ensure('email', baseFields.email);
    ensure('userType', baseFields.userType);
    ensure('science', baseFields.science);
    ensure('subscriptionStatus', baseFields.subscriptionStatus);
    ensure('isSubscriptionActive', baseFields.isSubscriptionActive);
    ensure('subscriptionEndDate', baseFields.subscriptionEndDate);
    ensure('lastPaymentDate', baseFields.lastPaymentDate);
    ensure('freeTrialStartDate', baseFields.freeTrialStartDate);
    ensure('freeTrialEndDate', baseFields.freeTrialEndDate);
    ensure('deviceRegistrationDate', baseFields.deviceRegistrationDate);
    ensure('isActive', baseFields.isActive);
    if (opts?.firstName && !data.firstName) toSet.firstName = opts.firstName;
    if (opts?.lastName && !data.lastName) toSet.lastName = opts.lastName;
    // authorizedDeviceFingerprint csak akkor, ha hiányzik
    if (!data.authorizedDeviceFingerprint) toSet.authorizedDeviceFingerprint = fingerprint;

    if (Object.keys(toSet).length > 1) {
      await updateDoc(ref, toSet);
      // Ha pótlás történt, frissítsük a lokális próbaidőszakot is
      if (typeof window !== 'undefined') {
        try {
          if (toSet.freeTrialStartDate instanceof Date) {
            window.localStorage.setItem('trial_start_date', toSet.freeTrialStartDate.toISOString());
          }
          if (toSet.freeTrialEndDate instanceof Date) {
            window.localStorage.setItem('trial_end_date', toSet.freeTrialEndDate.toISOString());
          }
        } catch (_) {}
      }
    }
  }

  // Admin e-mail override
  if (user.email === 'tattila.ninox@gmail.com') {
    await updateDoc(ref, { userType: 'admin', updatedAt: serverTimestamp() });
  }
}


