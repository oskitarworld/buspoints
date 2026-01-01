Testing admin callables locally (emulator)

This document describes a simple way to test `adminApproveTrial` and `adminEndTrial` callables using the Firebase Emulator Suite.

1) Start the emulators (from project root):

```bash
# Install firebase-tools if you don't have it
# npm install -g firebase-tools

cd functions
npm install
cd ..

# Start emulators (functions + firestore + auth)
firebase emulators:start --only functions,firestore,auth
```

2) Create test users in the Auth emulator and a test user doc in Firestore

Use the Emulator UI (http://localhost:4000) or CLI to create an admin account and a regular user account.

3) Obtain an ID token for the admin user (example using firebase auth REST against emulator):

```bash
# Create an account via REST (emulator)
ADMIN_EMAIL="admin@example.com"
ADMIN_PASS="secret123"

# Sign up
curl -s -X POST "http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake" \
  -H "Content-Type: application/json" \
  -d '{"email":"'$ADMIN_EMAIL'","password":"'$ADMIN_PASS'","returnSecureToken":true}' | jq .

# Sign in to get idToken
ID_TOKEN=$(curl -s -X POST "http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake" \
  -H "Content-Type: application/json" \
  -d '{"email":"'$ADMIN_EMAIL'","password":"'$ADMIN_PASS'","returnSecureToken":true}' | jq -r .idToken)

# Now you can call the callable via emulator endpoint:
USER_ID_TO_APPROVE="someUid"

curl -s -X POST "http://localhost:5001/YOUR_FIREBASE_PROJECT/us-central1/adminApproveTrial" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"data": {"userId": "'$USER_ID_TO_APPROVE'", "approveAsUser": false}}' | jq .
```

Notes
- Replace `YOUR_FIREBASE_PROJECT` with the project id you use in `firebase.json` (emulator uses that). The functions host and port are shown in the emulator console.
- When calling callables directly via HTTP (emulator), the payload must be `{ "data": { ... } }` and include an Authorization bearer idToken for an authenticated user.
- Alternatively, use the Firebase JS client SDK pointed at the emulator to call the callables from a small test page.

If you prefer, I can also provide a small Node script that signs in with the Auth emulator and calls the callable programmatically.