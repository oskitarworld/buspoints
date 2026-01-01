# Firestore rules snippet for trial enforcement

Add the following rules (or merge the logic) to your `firestore.rules` to allow access to premium resources when a user is in an active trial or has an active subscription.

Example rule to guard a `premiumContent` collection:

```rules
match /databases/{database}/documents {
  // helper to check admin
  function isAdmin() {
    return request.auth != null && (request.auth.token.admin == true ||
      exists(/databases/$(database)/documents/users/$(request.auth.uid)) &&
      (get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin' ||
       get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true)
    );
  }

  match /premiumContent/{docId} {
    allow read: if request.auth != null && (
      // user has active subscription
      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.subscriptionActive == true
      // OR user is inside trial period
      || (
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.trialStatus == 'active'
        && request.time < get(/databases/$(database)/documents/users/$(request.auth.uid)).data.trialExpiry
      )
      // OR admin
      || isAdmin()
    );

    // Only admins can write premiumContent
    allow write: if isAdmin();
  }
}
```

Notes & guidance
- `request.time` is compared to the stored `trialExpiry` (a Firestore timestamp). This makes enforcement server-side and robust against client tampering.
- Keep trial state updates restricted to trusted server-side code (Cloud Functions) or to admin writes. For example, only callable functions or admins should set `trialStatus: 'active'` or `trialExpiry`.
- Optionally create a scheduled Cloud Function that marks users whose `trialExpiry` < now as `trialStatus: 'expired'` to keep the state explicit and easy to query in admin UIs.
- To reduce abuse, combine device binding (`device_trials` collection) with App Check / Play Integrity and optionally phone verification.

Security reminder
- Never rely on client-side checks for premium gating. Always enforce access in Firestore security rules and/or Cloud Functions.
- Keep `device_trials` write access limited to server-side code (Cloud Functions) so it's not possible to mark a device as already used from the client.
