// Proxy de autocompletado Google Places
exports.placesAutocomplete = require('./placesAutocomplete').placesAutocomplete;
// Obtener detalles de un place (geometry) por place_id
exports.getPlaceDetails = require('./getPlaceDetails').getPlaceDetails;
// Crear usuario admin-side con unicidad de email/phone
exports.createUser = require('./createUser').createUser;
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
// NOTE: we avoid using the @google-cloud/tasks client to prevent version
// mismatches during local npm install. Instead we call the Cloud Tasks REST
// API directly using axios and a metadata-server access token (works from
// within Cloud Functions runtime).
const axios = require('axios');
const templates = require('./templates');
const crypto = require('crypto');


admin.initializeApp();

// Global helper: getAdminInboxForUid(uid)
// Returns { contact_messages, user_messages, incidencias } for an admin user
async function getAdminInboxForUid(uid) {
  const db = admin.firestore();
  const userDoc = await db.collection('users').doc(uid).get();
  const userData = userDoc.exists ? userDoc.data() || {} : {};
  const role = (userData.role || '').toString();
  const isAdmin = !!userData.isAdmin || role === 'admin';
  if (!isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
  }

  // Read contact_messages (admin-facing messages)
  const contactSnap = await db.collection('contact_messages').orderBy('timestamp', 'desc').limit(500).get();
  const contactMessages = contactSnap.docs
    .map(d => ({ ref: d.ref, id: d.id, data: d.data() || {} }))
    .filter(x => {
      const dd = x.data || {};
      if (dd.isIncidencia === true) return false;
      if (dd.pdiId) return false;
      if (dd.motivo) return false;
      return true;
    })
    .map(x => {
      const dd = x.data || {};
      return Object.assign({ id: x.id, sourceCollection: 'contact_messages' }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
    });

  // Read user_messages where 'to' is 'admins' OR messages explicitly addressed to admins.
  let userMessages = [];
  try {
    const userSnap = await db.collection('user_messages').where('to', 'in', ['admins','ADMIN','all']).orderBy('timestamp', 'desc').limit(500).get();
    userMessages = userSnap.docs.map(d => {
      const dd = d.data() || {};
      return Object.assign({ id: d.id, sourceCollection: 'user_messages' }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
    });
  } catch (e) {
    console.warn('getAdminInboxForUid: failed to query user_messages with in-clause', e && e.message);
    userMessages = [];
  }

  // Also include incidencias collection recent items
  const incidenciasSnap = await db.collection('incidencias').orderBy('timestamp', 'desc').limit(500).get();
  const incidencias = incidenciasSnap.docs.map(d => {
    const dd = d.data() || {};
    return Object.assign({ id: d.id, sourceCollection: 'incidencias' }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
  });

  return { contact_messages: contactMessages, user_messages: userMessages, incidencias: incidencias };
}

// Callable: invite an existing user (by email) to become an employee of a company
// Validations (performed server-side):
//  - caller must be authenticated and be company owner or company admin
//  - target email must exist in users collection
//  - target user must have an active subscription (subscription.active == true)
//  - if ok, add document companies/{companyId}/employees/{uid}
exports.companyInviteEmployee = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  }
  const callerUid = context.auth.uid;
  let companyId = (data && data.companyId) ? String(data.companyId) : null;
  const email = (data && data.email) ? String(data.email).toLowerCase().trim() : null;
  if (!email) {
    throw new functions.https.HttpsError('invalid-argument', 'Faltan parámetros companyId o email');
  }

  // Diagnostic log to help trace issues when clients report 'Empresa no encontrada'
  console.log('companyInviteEmployee called', { callerUid, companyId, email });

  const db = admin.firestore();

  // If client didn't provide a companyId, try to infer it from caller's user doc
  // when the caller itself is a 'company' account. This helps cases where the
  // client-side failed to resolve the company id but the authenticated user
  // represents the company.
  let isCallerCompany = false;
  if (!companyId) {
    try {
      const callerUserDoc = await db.collection('users').doc(callerUid).get();
      if (callerUserDoc.exists) {
        const cu = callerUserDoc.data() || {};
        if ((cu.role || '') === 'company') {
          companyId = callerUid;
          isCallerCompany = true;
          console.log('companyInviteEmployee: inferred companyId from caller role company', { inferredCompanyId: companyId });
        }
      }
    } catch (err) {
      console.warn('companyInviteEmployee: error reading caller user doc for fallback', err && err.message);
    }
  }

  // Verify company exists
  const compRef = db.doc(`companies/${companyId}`);
  const compSnap = await compRef.get();
  let comp = {};
  if (compSnap.exists) {
    comp = compSnap.data() || {};
  } else {
    // Support case where a 'company' account is represented by a users/{uid}
    // document instead of a companies/{id} doc. If the provided companyId
    // matches a user whose role is 'company', treat that as the company
    // (ownerUid will be the user uid). We won't create a companies doc here
    // automatically but we'll allow creating employees under
    // companies/{companyId}/employees (subcollections are permitted
    // even if parent doc doesn't exist). This makes the invite flow work
    // for 'company' user profiles.
    try {
      const possibleCompanyUser = await db.collection('users').doc(companyId).get();
      if (possibleCompanyUser.exists) {
        const pu = possibleCompanyUser.data() || {};
        if ((pu.role || '') === 'company') {
          comp = { ownerUid: companyId, name: pu.name || null };
        } else {
          throw new functions.https.HttpsError('not-found', 'Empresa no encontrada');
        }
      } else {
        throw new functions.https.HttpsError('not-found', 'Empresa no encontrada');
      }
    } catch (err) {
      if (err instanceof functions.https.HttpsError) throw err;
      throw new functions.https.HttpsError('not-found', 'Empresa no encontrada');
    }
  }

  // Check caller is owner or an admin employee of the company
  let callerIsAllowed = false;
  if (comp.ownerUid && comp.ownerUid === callerUid) callerIsAllowed = true;
  if (!callerIsAllowed) {
    try {
      const callerEmp = await db.doc(`companies/${companyId}/employees/${callerUid}`).get();
      if (callerEmp.exists) {
        const e = callerEmp.data() || {};
        if (e.role === 'admin' || e.role === 'manager') callerIsAllowed = true;
      }
    } catch (err) {
      console.warn('Error reading caller employee doc', err && err.message);
    }
  }
  if (!callerIsAllowed) {
    throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para invitar empleados');
  }

  // Lookup user by email
  const usersRef = db.collection('users');
  const q = await usersRef.where('email', '==', email).limit(1).get();
  // If caller is a company account, require they supplied a name for the invited worker
  const providedName = (data && data.name) ? String(data.name).trim() : null;
  if (isCallerCompany && !providedName) {
    throw new functions.https.HttpsError('invalid-argument', 'Se requiere el nombre del trabajador al invitar desde una cuenta empresa');
  }
  if (q.empty) {
    return { status: 'no_such_user' };
  }
  const userDoc = q.docs[0];
  const uid = userDoc.id;
  const userData = userDoc.data() || {};

  // Check subscription
  const subscription = userData.subscription || {};
  // Ensure target user has an active subscription.
  // Accept several schema variants that might exist in different user docs:
  // - user.subscription.active === true
  // - user.subscription.status === 'active'
  // - user.subscriptionActive === true
  // - user.subscription_active === true
  // - user.subscription.expiresAt in the future (Timestamp or ISO string)
  let hasActiveSubscription = false;
  try {
    if (userData.subscriptionActive === true || userData.subscription_active === true) hasActiveSubscription = true;
    if (subscription && subscription.active === true) hasActiveSubscription = true;
    if (subscription && typeof subscription.status === 'string' && subscription.status.toLowerCase() === 'active') hasActiveSubscription = true;
    if (subscription && subscription.expiresAt) {
      let exp = subscription.expiresAt;
      if (exp && typeof exp.toDate === 'function') {
        exp = exp.toDate();
      } else if (typeof exp === 'string' || typeof exp === 'number') {
        exp = new Date(exp);
      }
      if (exp instanceof Date && !isNaN(exp.getTime()) && exp > new Date()) {
        hasActiveSubscription = true;
      }
    }
  } catch (err) {
    console.warn('companyInviteEmployee: subscription detection error', err && err.message);
  }
  console.log('companyInviteEmployee: subscription check', { uid, hasActiveSubscription });
  if (!hasActiveSubscription) {
    return { status: 'no_subscription' };
  }

  // Add or update the employee document under the company
  try {
    const empRef = db.collection('companies').doc(companyId).collection('employees').doc(uid);
    // If an employee doc already exists and is active, report already_member
    try {
      const existing = await empRef.get();
      if (existing.exists) {
        const ed = existing.data() || {};
        if (ed.status === 'active' || ed.active === true) {
          return { status: 'already_member' };
        }
      }
    } catch (err) {
      console.warn('companyInviteEmployee: error checking existing employee doc', err && err.message);
    }

    // Resolve inviter/caller display names so we can store a human-readable
    // inviter name inside employee docs. This avoids clients needing to read
    // users/{inviterUid} which may be blocked by security rules.
    let callerDisplayName = callerUid;
    let inviterDisplayName = callerUid;
    try {
      const callerUserDoc2 = await db.collection('users').doc(callerUid).get();
      if (callerUserDoc2.exists) {
        const cud2 = callerUserDoc2.data() || {};
        callerDisplayName = cud2.companyName || cud2.displayName || cud2.name || callerUid;
        inviterDisplayName = cud2.displayName || cud2.name || callerUid;
      }
    } catch (e) {
      // ignore resolution errors and fall back to UID
    }

    // Prepare employee payload with helpful fields for client display
    const empPayload = {
      role: 'employee',
      invitedBy: callerUid,
      invitedByName: inviterDisplayName,
      invitedByCompanyName: callerDisplayName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'active',
      active: true,
      email: userData.email || email,
      // Prefer provided name when inviter is a company account, otherwise use existing user data
      displayName: providedName || userData.displayName || userData.name || null,
    };

    await empRef.set(empPayload, { merge: true });
    // Also write a copy into the nested invites structure so we keep invites
    // grouped by inviter. This helps UIs that want to list invites per inviter.
    try {
      const nestedRef = db.collection('companies').doc(companyId)
        .collection('employees_by_inviter').doc(callerUid)
        .collection('invited').doc(uid);
      // Use a lighter invite payload for the nested location (status may be 'invited')
  const nestedPayload = Object.assign({}, empPayload, { status: empPayload.status || 'invited', invitedAt: admin.firestore.FieldValue.serverTimestamp() });
      await nestedRef.set(nestedPayload, { merge: true });
    } catch (err) {
      console.warn('companyInviteEmployee: failed to write nested invite copy', err && err.message);
    }
  } catch (err) {
    console.error('companyInviteEmployee: failed to write employee doc', err && err.message);
    throw new functions.https.HttpsError('internal', 'Failed to add employee');
  }

  // Create an internal user message (in-app notification)
  try {
    // Resolve caller (inviter) info and prefer an explicit inviter name
    let callerName = callerUid; // used previously for company display fallback
    let inviterName = callerUid; // the human who performed the invite
    try {
      const callerUserDoc = await db.collection('users').doc(callerUid).get();
      if (callerUserDoc.exists) {
        const cud = callerUserDoc.data() || {};
        // callerName: if inviter is a company account prefer its companyName
        callerName = cud.companyName || cud.displayName || cud.name || callerUid;
        // inviterName: the actual person who initiated the invite (displayName/name)
        inviterName = cud.displayName || cud.name || callerUid;
      }
    } catch (e) {
      // ignore and fall back to uid
    }

    // Determine company display name (prefer companyName then companies.name)
    let companyDisplay = (comp && comp.name) ? comp.name : companyId;
    try {
      const companyUserDoc = await db.collection('users').doc(companyId).get();
      if (companyUserDoc.exists) {
        const cu = companyUserDoc.data() || {};
        if (cu.companyName) companyDisplay = cu.companyName;
      }
    } catch (e) {
      // ignore
    }

    const inviteMessage = `${inviterName} te ha añadido a la empresa ${companyDisplay}`;
    await db.collection('user_messages').add({
      to: uid,
      toUid: uid,
      // Backwards-compatible fields used by the client UI
      title: `Has sido invitado a la Cuenta Empresa ${companyDisplay}`,
      message: inviteMessage,
      body: inviteMessage,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      type: 'company_invite',
      companyId: companyId,
      fromUid: companyId, // sender is the company
      fromName: companyDisplay,
      fromEmail: null,
      // provide metadata about the inviter
      inviterUid: callerUid,
      inviterName: inviterName,
    });
  } catch (err) {
    console.warn('companyInviteEmployee: failed to create user message', err && err.message);
  }

  // Attempt to update custom claims to include companyId
  try {
    const userRecord = await admin.auth().getUser(uid);
    const currentClaims = userRecord.customClaims || {};
    const companyIds = Array.isArray(currentClaims.companyIds) ? currentClaims.companyIds.slice() : [];
    if (!companyIds.includes(companyId)) companyIds.push(companyId);
    const newClaims = Object.assign({}, currentClaims, { companyIds: companyIds });
    await admin.auth().setCustomUserClaims(uid, newClaims);
  } catch (err) {
    console.warn('companyInviteEmployee: failed to set custom claims', err && err.message);
  }
  // Also update the user's Firestore document to reflect company membership
  try {
    await db.collection('users').doc(uid).set({ companyIds: admin.firestore.FieldValue.arrayUnion(companyId) }, { merge: true });
  } catch (err) {
    console.warn('companyInviteEmployee: failed to update user doc companyIds', err && err.message);
  }

  return { status: 'added' };
});


// Callable: admin can change a user's role (user | company | employee | admin)
exports.adminSetUserRole = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const targetUid = (data && data.uid) ? String(data.uid) : null;
  const newRole = (data && data.role) ? String(data.role) : null;
  if (!targetUid || !newRole) throw new functions.https.HttpsError('invalid-argument', 'Faltan parámetros uid o role');

  const db = admin.firestore();
  // Verify caller is an admin (role in Firestore users or admin claim)
  let callerIsAdmin = false;
  try {
    const callerRec = await db.collection('users').doc(callerUid).get();
    if (callerRec.exists) {
      const r = callerRec.data() || {};
      if (r.role === 'admin') callerIsAdmin = true;
    }
    const callerAuth = await admin.auth().getUser(callerUid);
    if (callerAuth.customClaims && callerAuth.customClaims.admin === true) callerIsAdmin = true;
  } catch (err) {
    console.warn('adminSetUserRole: error checking caller admin status', err && err.message);
  }
  if (!callerIsAdmin) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para cambiar roles');

  // Update Firestore user doc
  try {
    await db.collection('users').doc(targetUid).update({ role: newRole });
  } catch (err) {
    throw new functions.https.HttpsError('internal', 'No se pudo actualizar el documento de usuario: ' + (err && err.message));
  }

  // Update Auth custom claims (merge existing)
  try {
    const userRecord = await admin.auth().getUser(targetUid);
    const currentClaims = userRecord.customClaims || {};
    const newClaims = Object.assign({}, currentClaims);
    // role claim mirrors Firestore role for faster rules checks
    newClaims.role = newRole;
    if (newRole === 'admin') {
      newClaims.admin = true;
    } else {
      if (newClaims.admin) delete newClaims.admin;
    }
    await admin.auth().setCustomUserClaims(targetUid, newClaims);
  } catch (err) {
    console.warn('adminSetUserRole: failed to set custom claims', err && err.message);
  }

  return { status: 'ok', role: newRole };
});

// Callable: create a route on behalf of a company member (team route)
// Validations:
//  - caller must be authenticated
//  - ownerCompanyId must be provided
//  - caller must be company owner or an active employee of the company
// If valid, the server writes to 'user_routes' using Admin SDK and returns the new id.
exports.createCompanyRoute = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const name = (data && data.name) ? String(data.name) : null;
  const description = (data && data.description) ? String(data.description) : '';
  const pdis = (data && data.pdis) ? data.pdis : [];
  const visibility = (data && data.visibility) ? String(data.visibility) : 'team';
  const ownerCompanyId = (data && data.ownerCompanyId) ? String(data.ownerCompanyId) : null;
  if (!ownerCompanyId) throw new functions.https.HttpsError('invalid-argument', 'ownerCompanyId requerido');

  const db = admin.firestore();

  // Resolve company doc or fallback to users/{companyId} if that user has role 'company'
  let comp = null;
  try {
    const compSnap = await db.collection('companies').doc(ownerCompanyId).get();
    if (compSnap.exists) comp = compSnap.data() || {};
    else {
      const userSnap = await db.collection('users').doc(ownerCompanyId).get();
      if (userSnap.exists) {
        const ud = userSnap.data() || {};
        if ((ud.role || '') === 'company') comp = { ownerUid: ownerCompanyId, name: ud.companyName || ud.name || null };
      }
    }
  } catch (err) {
    console.warn('createCompanyRoute: failed to resolve company', err && err.message);
  }
  if (!comp) throw new functions.https.HttpsError('not-found', 'Empresa no encontrada');

  // Check caller membership: ownerUid or companies/{companyId}/employees/{callerUid} exists and active
  let callerIsAllowed = false;
  try {
    if (comp.ownerUid && comp.ownerUid === callerUid) callerIsAllowed = true;
    if (!callerIsAllowed) {
      const empSnap = await db.collection('companies').doc(ownerCompanyId).collection('employees').doc(callerUid).get();
      if (empSnap.exists) {
        const ed = empSnap.data() || {};
        if (ed.status === 'active' || ed.active === true) callerIsAllowed = true;
      }
    }
  } catch (err) {
    console.warn('createCompanyRoute: membership check failed', err && err.message);
  }
  if (!callerIsAllowed) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para crear rutas para esta empresa');

  // Build route doc
  const route = {
    name: name || '(sin nombre)',
    description: description || '',
    createdBy: callerUid,
    pdis: Array.isArray(pdis) ? pdis : [],
    visibility: visibility,
    ownerCompanyId: ownerCompanyId,
    approved: true,
    isPublic: false,
    needsApproval: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    const ref = await db.collection('user_routes').add(route);
    return { status: 'ok', id: ref.id };
  } catch (err) {
    console.error('createCompanyRoute: failed to write route', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo crear la ruta');
  }
});

// Callable: create a company/team route on behalf of a user who is a member of the company.
// This allows invited employees (who may not have certain custom claims populated yet)
// to create routes for their company without relying on client-side write permissions.
exports.createCompanyRoute = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  }
  const callerUid = context.auth.uid;
  const db = admin.firestore();

  // Basic validation of inputs
  const name = data && data.name ? String(data.name).trim() : '';
  const description = data && data.description ? String(data.description).trim() : '';
  const pdis = Array.isArray(data && data.pdis) ? data.pdis : null;
  const visibility = data && data.visibility ? String(data.visibility) : 'team';
  const ownerCompanyId = data && data.ownerCompanyId ? String(data.ownerCompanyId) : null;

  if (!name || name.length === 0) throw new functions.https.HttpsError('invalid-argument', 'Nombre de ruta requerido');
  if (!pdis || !Array.isArray(pdis) || pdis.length < 2 || pdis.length > 20) throw new functions.https.HttpsError('invalid-argument', 'Pdis inválidos (deben ser entre 2 y 20)');
  if (!ownerCompanyId) throw new functions.https.HttpsError('invalid-argument', 'ownerCompanyId requerido');

  // Authorization: allow if caller is company owner, or has an active employee doc in companies/{companyId}/employees/{uid},
  // or if caller has companyOwners claim for the company, or is admin.
  let callerAllowed = false;
  try {
    // 1) company document owner check
    try {
      const compSnap = await db.collection('companies').doc(ownerCompanyId).get();
      if (compSnap.exists) {
        const comp = compSnap.data() || {};
        if (comp.ownerUid && comp.ownerUid === callerUid) callerAllowed = true;
      } else {
        // also support case where the company is represented by a users/{uid} doc
        const possibleUser = await db.collection('users').doc(ownerCompanyId).get();
        if (possibleUser.exists) {
          const pu = possibleUser.data() || {};
          if ((pu.role || '') === 'company' && ownerCompanyId === callerUid) callerAllowed = true;
        }
      }
    } catch (err) {
      console.warn('createCompanyRoute: error reading company doc', err && err.message);
    }

    // 2) employee document check
    if (!callerAllowed) {
      try {
        const empSnap = await db.collection('companies').doc(ownerCompanyId).collection('employees').doc(callerUid).get();
        if (empSnap.exists) {
          const emp = empSnap.data() || {};
          if (emp.status === 'active' || emp.active === true) callerAllowed = true;
        }
      } catch (err) {
        console.warn('createCompanyRoute: error reading employee doc', err && err.message);
      }
    }

    // 3) custom claims fallback (companyOwners/admin)
    if (!callerAllowed) {
      try {
        const callerAuth = await admin.auth().getUser(callerUid);
        const cc = callerAuth.customClaims || {};
        if (cc.admin === true) callerAllowed = true;
        if (Array.isArray(cc.companyOwners) && cc.companyOwners.includes(ownerCompanyId)) callerAllowed = true;
        if (Array.isArray(cc.companyIds) && cc.companyIds.includes(ownerCompanyId)) callerAllowed = true; // member via claim
      } catch (err) {
        console.warn('createCompanyRoute: error reading caller auth record', err && err.message);
      }
    }

    if (!callerAllowed) {
      throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para crear rutas para esta empresa');
    }
  } catch (err) {
    if (err instanceof functions.https.HttpsError) throw err;
    console.error('createCompanyRoute: authorization check failed unexpectedly', err && err.message);
    throw new functions.https.HttpsError('internal', 'Error de autorización');
  }

  // Construct route document server-side to ensure fields are valid and timestamps come from server
  const routeDoc = {
    name: name,
    description: description || '',
    createdBy: callerUid,
    pdis: pdis,
    visibility: visibility,
    ownerCompanyId: ownerCompanyId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    // Internal routes: mark as approved immediately and not public
    approved: true,
    isPublic: false,
    needsApproval: false,
  };

  try {
    const ref = await db.collection('user_routes').add(routeDoc);
    return { status: 'ok', id: ref.id };
  } catch (err) {
    console.error('createCompanyRoute: failed to write route', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo crear la ruta');
  }
});

// Callable: update a company route. Only company owner or active employee (admin/manager) may update.
exports.updateCompanyRoute = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const routeId = data && data.routeId ? String(data.routeId) : null;
  if (!routeId) throw new functions.https.HttpsError('invalid-argument', 'routeId requerido');

  const db = admin.firestore();
  // Read route
  let routeSnap;
  try {
    routeSnap = await db.collection('user_routes').doc(routeId).get();
  } catch (err) {
    console.error('updateCompanyRoute: failed to read route', err && err.message);
    throw new functions.https.HttpsError('internal', 'Error leyendo la ruta');
  }
  if (!routeSnap.exists) throw new functions.https.HttpsError('not-found', 'Ruta no encontrada');
  const route = routeSnap.data() || {};
  const ownerCompanyId = route.ownerCompanyId || null;
  if (!ownerCompanyId) throw new functions.https.HttpsError('invalid-argument', 'La ruta no pertenece a una empresa');

  // Authorization: only company owner or active employee (admin/manager) or platform admin
  let callerAllowed = false;
  try {
    const compSnap = await db.collection('companies').doc(ownerCompanyId).get();
    if (compSnap.exists) {
      const comp = compSnap.data() || {};
      if (comp.ownerUid && comp.ownerUid === callerUid) callerAllowed = true;
    } else {
      const possibleUser = await db.collection('users').doc(ownerCompanyId).get();
      if (possibleUser.exists) {
        const pu = possibleUser.data() || {};
        if ((pu.role || '') === 'company' && ownerCompanyId === callerUid) callerAllowed = true;
      }
    }
  } catch (err) {
    console.warn('updateCompanyRoute: error reading company doc', err && err.message);
  }
  if (!callerAllowed) {
    try {
      const empSnap = await db.collection('companies').doc(ownerCompanyId).collection('employees').doc(callerUid).get();
      if (empSnap.exists) {
        const ed = empSnap.data() || {};
        if (ed.status === 'active' || ed.active === true) {
          // allow active employees
          callerAllowed = true;
        }
      }
      // Also allow users who have the company referenced in their user document
      if (!callerAllowed) {
        try {
          const userSnap = await db.collection('users').doc(callerUid).get();
          if (userSnap.exists) {
            const ud = userSnap.data() || {};
            if (ud.companyId === ownerCompanyId) callerAllowed = true;
            if (!callerAllowed && Array.isArray(ud.companyIds) && ud.companyIds.includes(ownerCompanyId)) callerAllowed = true;
          }
        } catch (e) {
          console.warn('updateCompanyRoute: error reading caller user doc', e && e.message);
        }
      }
    } catch (err) {
      console.warn('updateCompanyRoute: error reading employee doc', err && err.message);
    }
  }
  if (!callerAllowed) {
    try {
      const callerAuth = await admin.auth().getUser(callerUid);
      const cc = callerAuth.customClaims || {};
      if (cc && cc.admin === true) callerAllowed = true;
    } catch (err) {
      console.warn('updateCompanyRoute: error reading caller auth', err && err.message);
    }
  }
  if (!callerAllowed) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para modificar rutas de esta empresa');

  // Build patch from allowed fields: name, description, pdis
  const patch = {};
  if (data && typeof data.name === 'string') patch.name = String(data.name);
  if (data && typeof data.description === 'string') patch.description = String(data.description);
  if (data && Array.isArray(data.pdis)) patch.pdis = data.pdis;
  if (Object.keys(patch).length === 0) throw new functions.https.HttpsError('invalid-argument', 'No hay campos para actualizar');
  patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();

  try {
    await db.collection('user_routes').doc(routeId).update(patch);
    return { status: 'ok' };
  } catch (err) {
    console.error('updateCompanyRoute: failed to update route', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo actualizar la ruta');
  }
});

// Callable: delete a company route. Only company owner or active employee (admin/manager) may delete.
exports.deleteCompanyRoute = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const routeId = data && data.routeId ? String(data.routeId) : null;
  if (!routeId) throw new functions.https.HttpsError('invalid-argument', 'routeId requerido');

  const db = admin.firestore();
  let routeSnap;
  try {
    routeSnap = await db.collection('user_routes').doc(routeId).get();
  } catch (err) {
    console.error('deleteCompanyRoute: failed to read route', err && err.message);
    throw new functions.https.HttpsError('internal', 'Error leyendo la ruta');
  }
  if (!routeSnap.exists) throw new functions.https.HttpsError('not-found', 'Ruta no encontrada');
  const route = routeSnap.data() || {};
  const ownerCompanyId = route.ownerCompanyId || null;
  if (!ownerCompanyId) throw new functions.https.HttpsError('invalid-argument', 'La ruta no pertenece a una empresa');

  // Authorization (same checks as update)
  let callerAllowed = false;
  try {
    const compSnap = await db.collection('companies').doc(ownerCompanyId).get();
    if (compSnap.exists) {
      const comp = compSnap.data() || {};
      if (comp.ownerUid && comp.ownerUid === callerUid) callerAllowed = true;
    } else {
      const possibleUser = await db.collection('users').doc(ownerCompanyId).get();
      if (possibleUser.exists) {
        const pu = possibleUser.data() || {};
        if ((pu.role || '') === 'company' && ownerCompanyId === callerUid) callerAllowed = true;
      }
    }
  } catch (err) {
    console.warn('deleteCompanyRoute: error reading company doc', err && err.message);
  }
  if (!callerAllowed) {
    try {
      const empSnap = await db.collection('companies').doc(ownerCompanyId).collection('employees').doc(callerUid).get();
      if (empSnap.exists) {
        const ed = empSnap.data() || {};
        if (ed.status === 'active' || ed.active === true) callerAllowed = true;
      }
      // Also allow users who have the company referenced in their user document
      if (!callerAllowed) {
        try {
          const userSnap = await db.collection('users').doc(callerUid).get();
          if (userSnap.exists) {
            const ud = userSnap.data() || {};
            if (ud.companyId === ownerCompanyId) callerAllowed = true;
            if (!callerAllowed && Array.isArray(ud.companyIds) && ud.companyIds.includes(ownerCompanyId)) callerAllowed = true;
          }
        } catch (e) {
          console.warn('deleteCompanyRoute: error reading caller user doc', e && e.message);
        }
      }
    } catch (err) {
      console.warn('deleteCompanyRoute: error reading employee doc', err && err.message);
    }
  }
  if (!callerAllowed) {
    try {
      const callerAuth = await admin.auth().getUser(callerUid);
      const cc = callerAuth.customClaims || {};
      if (cc && cc.admin === true) callerAllowed = true;
    } catch (err) {
      console.warn('deleteCompanyRoute: error reading caller auth', err && err.message);
    }
  }
  if (!callerAllowed) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para eliminar rutas de esta empresa');

  try {
    await db.collection('user_routes').doc(routeId).delete();
    return { status: 'ok' };
  } catch (err) {
    console.error('deleteCompanyRoute: failed to delete route', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo eliminar la ruta');
  }
});

// Callable: return the employees list for a company using admin privileges.
// This is useful when client-side security rules prevent direct reads from
// the `companies/{companyId}/employees` path. The function enforces the same
// permission model server-side: only admins, company owners or company admins/managers
// may retrieve the employees list.
exports.companyListEmployees = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const companyId = (data && data.companyId) ? String(data.companyId) : null;
  if (!companyId) throw new functions.https.HttpsError('invalid-argument', 'Falta companyId');

  const db = admin.firestore();

  // Resolve company doc or accept a 'company' user document as company owner
  let comp = null;
  try {
    const compRef = db.doc(`companies/${companyId}`);
    const compSnap = await compRef.get();
    if (compSnap.exists) {
      comp = compSnap.data() || {};
    } else {
      // accept users/{companyId} with role 'company' as canonical owner
      const possibleCompanyUser = await db.collection('users').doc(companyId).get();
      if (possibleCompanyUser.exists) {
        const pu = possibleCompanyUser.data() || {};
        if ((pu.role || '') === 'company') {
          comp = { ownerUid: companyId, name: pu.name || null };
        }
      }
    }
  } catch (err) {
    console.warn('companyListEmployees: error resolving company', err && err.message);
    throw new functions.https.HttpsError('internal', 'Error resolviendo la empresa');
  }
  if (!comp) throw new functions.https.HttpsError('not-found', 'Empresa no encontrada');

  // Check caller privileges: admin OR company owner OR company admin/manager employee
  let callerIsAdmin = false;
  try {
    if (context.auth.token && (context.auth.token.admin === true || context.auth.token.role === 'admin')) {
      callerIsAdmin = true;
    } else {
      // double-check Firestore user doc / custom claims as fallback
      const callerUserDoc = await db.collection('users').doc(callerUid).get();
      if (callerUserDoc.exists) {
        const ru = callerUserDoc.data() || {};
        if (ru.role === 'admin') callerIsAdmin = true;
      }
      try {
        const callerAuth = await admin.auth().getUser(callerUid);
        if (callerAuth.customClaims && callerAuth.customClaims.admin === true) callerIsAdmin = true;
      } catch (e) {
        // ignore
      }
    }
  } catch (err) {
    console.warn('companyListEmployees: error checking admin status', err && err.message);
  }

  let callerAllowed = false;
  if (callerIsAdmin) callerAllowed = true;
  if (!callerAllowed) {
    // owner
    if (comp.ownerUid && comp.ownerUid === callerUid) callerAllowed = true;
  }
  if (!callerAllowed) {
    // check employee role under company
    try {
      const empSnap = await db.doc(`companies/${companyId}/employees/${callerUid}`).get();
      if (empSnap.exists) {
        const ed = empSnap.data() || {};
        if (ed.role === 'admin' || ed.role === 'manager') callerAllowed = true;
      }
    } catch (err) {
      console.warn('companyListEmployees: error reading caller employee doc', err && err.message);
    }
  }
  if (!callerAllowed) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para ver los empleados');

  // Read employees with admin privileges
  try {
    const empSnap = await db.collection('companies').doc(companyId).collection('employees').get();
    const employees = empSnap.docs.map(d => ({ id: d.id, data: d.data() || {} }));
    return { status: 'ok', employees };
  } catch (err) {
    console.error('companyListEmployees: failed to read employees', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo leer la lista de empleados');
  }
});

// Callable: allow a user to leave a company they belong to.
// Removes the employee document under companies/{companyId}/employees/{uid}
// and removes the companyId from users/{uid}.companyIds. Also notifies
// the company owner (if present) with an in-app message.
exports.companyLeaveCompany = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const uid = context.auth.uid;
  const companyId = (data && data.companyId) ? String(data.companyId) : null;
  if (!companyId) throw new functions.https.HttpsError('invalid-argument', 'Falta companyId');

  const db = admin.firestore();
  try {
    const empRef = db.collection('companies').doc(companyId).collection('employees').doc(uid);
    const empSnap = await empRef.get();
    if (!empSnap.exists) {
      return { status: 'not_member' };
    }

    // Delete the employee doc (soft-delete could be used instead)
    await empRef.delete();

    // Remove companyId from user's companyIds array
    try {
      await db.collection('users').doc(uid).set({ companyIds: admin.firestore.FieldValue.arrayRemove(companyId) }, { merge: true });
    } catch (e) {
      console.warn('companyLeaveCompany: failed to update user doc', e && e.message);
    }

    // Notify company owner if available
    try {
      const compRef = db.collection('companies').doc(companyId);
      const compSnap = await compRef.get();
      let ownerUid = null;
      let companyName = companyId;
      if (compSnap.exists) {
        const comp = compSnap.data() || {};
        ownerUid = comp.ownerUid || null;
        companyName = comp.name || companyId;
      } else {
        // fallback: maybe the company is represented by a users/{companyId} doc
        const possibleUser = await db.collection('users').doc(companyId).get();
        if (possibleUser.exists) {
          const pu = possibleUser.data() || {};
          if ((pu.role || '') === 'company') {
            ownerUid = companyId;
            companyName = pu.companyName || pu.name || companyId;
          }
        }
      }

      // Compose notification to owner
      if (ownerUid) {
        const userRec = await db.collection('users').doc(uid).get();
        const userData = userRec.exists ? userRec.data() || {} : {};
        const userName = userData.displayName || userData.name || uid;
        const msg = `${userName} ha abandonado la empresa ${companyName}`;
        await db.collection('user_messages').add({
          to: ownerUid,
          toUid: ownerUid,
          title: 'Miembro abandonó la empresa',
          message: msg,
          body: msg,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          type: 'company_left',
          companyId: companyId,
          fromUid: uid,
          fromName: userName,
        });
      }
    } catch (e) {
      console.warn('companyLeaveCompany: notify owner failed', e && e.message);
    }

    return { status: 'ok' };
  } catch (err) {
    console.error('companyLeaveCompany: unexpected error', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo procesar la petición');
  }
});

// Callable: allow an owner/manager/admin to remove a specific employee from a company.
// Parameters: { companyId: string, uid: string }
exports.companyRemoveEmployee = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const companyId = (data && data.companyId) ? String(data.companyId) : null;
  const targetUid = (data && data.uid) ? String(data.uid) : null;
  if (!companyId || !targetUid) throw new functions.https.HttpsError('invalid-argument', 'Falta companyId o uid');

  const db = admin.firestore();
  try {
    // Basic permission checks: admin token, company owner, or employee with admin/manager role
    let callerIsAdmin = false;
    try {
      if (context.auth.token && (context.auth.token.admin === true || context.auth.token.role === 'admin')) {
        callerIsAdmin = true;
      }
    } catch (e) {}

    let callerAllowed = false;
    if (callerIsAdmin) callerAllowed = true;

    // Check owner
    try {
      const compSnap = await db.collection('companies').doc(companyId).get();
      if (compSnap.exists) {
        const comp = compSnap.data() || {};
        if (comp.ownerUid && comp.ownerUid === callerUid) callerAllowed = true;
      } else {
        // fallback: maybe company represented by users/{companyId}
        const possibleUser = await db.collection('users').doc(companyId).get();
        if (possibleUser.exists) {
          const pu = possibleUser.data() || {};
          if ((pu.role || '') === 'company' && companyId === callerUid) {
            // a company account removing members of its own account
            callerAllowed = true;
          }
        }
      }
    } catch (e) {
      console.warn('companyRemoveEmployee: error checking owner', e && e.message);
    }

    // Check if caller is an employee with manager/admin role
    if (!callerAllowed) {
      try {
        const empSnap = await db.collection('companies').doc(companyId).collection('employees').doc(callerUid).get();
        if (empSnap.exists) {
          const ed = empSnap.data() || {};
          if (ed.role === 'admin' || ed.role === 'manager') callerAllowed = true;
        }
      } catch (e) {
        console.warn('companyRemoveEmployee: error checking caller employee doc', e && e.message);
      }
    }

    if (!callerAllowed) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para eliminar empleados');

    // Check target membership
    const targetRef = db.collection('companies').doc(companyId).collection('employees').doc(targetUid);
    const targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      return { status: 'not_member' };
    }

    // Do delete
    await targetRef.delete();

    // Also remove any nested invite copies under employees_by_inviter/*/invited/{uid}
    try {
      const invitersCol = db.collection('companies').doc(companyId).collection('employees_by_inviter');
      const invitersSnap = await invitersCol.get();
      for (const invDoc of invitersSnap.docs) {
        try {
          const invitedRef = db.collection('companies').doc(companyId).collection('employees_by_inviter').doc(invDoc.id).collection('invited').doc(targetUid);
          const invitedSnap = await invitedRef.get();
          if (invitedSnap.exists) {
            await invitedRef.delete();
          }
        } catch (e) {
          console.warn('companyRemoveEmployee: failed to delete nested invited for inviter', invDoc.id, e && e.message);
        }
      }
    } catch (e) {
      console.warn('companyRemoveEmployee: error listing employees_by_inviter', e && e.message);
    }

    // Remove companyId from user's companyIds array
    try {
      await db.collection('users').doc(targetUid).set({ companyIds: admin.firestore.FieldValue.arrayRemove(companyId) }, { merge: true });
    } catch (e) {
      console.warn('companyRemoveEmployee: failed to update user doc', e && e.message);
    }

    // Notify target user
    try {
      const userRec = await db.collection('users').doc(targetUid).get();
      const userData = userRec.exists ? userRec.data() || {} : {};
      const targetName = userData.displayName || userData.name || targetUid;

      // Determine company display name
      let companyName = companyId;
      try {
        const compSnap2 = await db.collection('companies').doc(companyId).get();
        if (compSnap2.exists) {
          const cdata = compSnap2.data() || {};
          companyName = cdata.name || companyId;
        } else {
          const poss = await db.collection('users').doc(companyId).get();
          if (poss.exists) {
            const pd = poss.data() || {};
            companyName = pd.companyName || pd.name || companyId;
          }
        }
      } catch (e) {}

      const msg = `Has sido eliminado de la empresa ${companyName}`;
      await db.collection('user_messages').add({
        to: targetUid,
        toUid: targetUid,
        title: 'Eliminado de la empresa',
        message: msg,
        body: msg,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        type: 'company_removed',
        companyId: companyId,
        fromUid: callerUid,
        fromName: callerUid,
      });
    } catch (e) {
      console.warn('companyRemoveEmployee: notify target failed', e && e.message);
    }

    return { status: 'ok' };
  } catch (err) {
    console.error('companyRemoveEmployee: unexpected error', err && err.message);
    throw new functions.https.HttpsError('internal', 'No se pudo procesar la petición');
  }
});

// Callable: migrate existing employee/invite documents into the nested
// structure companies/{companyId}/employees_by_inviter/{inviterId}/invited/{uid}
// Options:
//  - deleteOld: boolean (default: false) -> delete the original employees/* docs after copying
// This callable is restricted to admin users (Firestore role 'admin' or custom claim admin=true)
exports.migrateInvitesToNested = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const callerUid = context.auth.uid;
  const companyId = (data && data.companyId) ? String(data.companyId) : null;
  const deleteOld = !!(data && data.deleteOld);
  if (!companyId) throw new functions.https.HttpsError('invalid-argument', 'Falta companyId');

  const db = admin.firestore();

  // Check caller is admin (fast path via token) or Firestore role
  let callerIsAdmin = false;
  try {
    if (context.auth.token && (context.auth.token.admin === true || context.auth.token.role === 'admin')) {
      callerIsAdmin = true;
    } else {
      const callerUserDoc = await db.collection('users').doc(callerUid).get();
      if (callerUserDoc.exists) {
        const ru = callerUserDoc.data() || {};
        if (ru.role === 'admin') callerIsAdmin = true;
      }
      try {
        const callerAuth = await admin.auth().getUser(callerUid);
        if (callerAuth.customClaims && callerAuth.customClaims.admin === true) callerIsAdmin = true;
      } catch (e) {
        // ignore
      }
    }
  } catch (err) {
    console.warn('migrateInvitesToNested: error checking admin status', err && err.message);
  }
  if (!callerIsAdmin) throw new functions.https.HttpsError('permission-denied', 'No tienes permiso para ejecutar esta migración');

  try {
    const empColRef = db.collection('companies').doc(companyId).collection('employees');
    const snapshot = await empColRef.get();
    if (snapshot.empty) {
      return { status: 'no_employees', migrated: 0 };
    }

    const results = { migrated: 0, errors: [] };
    // We'll perform writes in batches of up to 450 (reserve some room)
    let batch = db.batch();
    let opsInBatch = 0;

    for (const doc of snapshot.docs) {
      const uid = doc.id;
      const dataDoc = doc.data() || {};
      // Determine inviterId if available
      const inviterId = dataDoc.invitedBy ? String(dataDoc.invitedBy) : 'unknown_inviter';

      // Attempt to resolve a human-readable inviter name to store in the
      // migrated document so clients don't need cross-doc reads.
      let inviterNameResolved = inviterId;
      let inviterCompanyResolved = null;
      try {
        if (inviterId && inviterId !== 'unknown_inviter') {
          const invSnap = await db.collection('users').doc(inviterId).get();
          if (invSnap.exists) {
            const invData = invSnap.data() || {};
            inviterNameResolved = invData.displayName || invData.name || inviterId;
            inviterCompanyResolved = invData.companyName || null;
          }
        }
      } catch (e) {
        console.warn('migrateInvitesToNested: failed to resolve inviter name', e && e.message);
      }

      const targetRef = db.collection('companies').doc(companyId)
        .collection('employees_by_inviter').doc(inviterId)
        .collection('invited').doc(uid);

      const toWrite = Object.assign({}, dataDoc, {
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        invitedByName: inviterNameResolved,
        invitedByCompanyName: inviterCompanyResolved,
      });

      batch.set(targetRef, toWrite, { merge: true });
      opsInBatch++;

      if (deleteOld) {
        batch.delete(empColRef.doc(uid));
        opsInBatch++;
      }

      // commit if near limit
      if (opsInBatch >= 450) {
        await batch.commit();
        batch = db.batch();
        opsInBatch = 0;
      }

      results.migrated++;
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    return { status: 'ok', migrated: results.migrated };
  } catch (err) {
    console.error('migrateInvitesToNested: unexpected error', err && err.message);
    throw new functions.https.HttpsError('internal', 'Error durante la migración: ' + (err && err.message));
  }
});

// Callable: resolve a list of companyIds to human-readable display names.
// Runs with admin privileges so clients that cannot read `companies/{id}`
// or `users/{id}` due to rules can still display friendly names.
exports.getCompanyNames = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const companyIds = Array.isArray(data && data.companyIds) ? data.companyIds.map(String) : [];
  const db = admin.firestore();
  const result = {};
  for (const cid of companyIds) {
    let name = cid;
    try {
      const compRef = db.collection('companies').doc(cid);
      const compSnap = await compRef.get();
      if (compSnap.exists) {
        const cd = compSnap.data() || {};
        name = cd.name || cd.displayName || cd.companyName || name;
      } else {
        // fallback to users/{cid} if companies/{cid} not present
        try {
          const userSnap = await db.collection('users').doc(cid).get();
          if (userSnap.exists) {
            const ud = userSnap.data() || {};
            name = ud.companyName || ud.name || ud.displayName || name;
          }
        } catch (e) {
          // ignore
        }
      }
    } catch (e) {
      console.warn('getCompanyNames: error resolving', cid, e && e.message);
    }
    result[cid] = name || cid;
  }
  return { status: 'ok', names: result };
});

// Callable: resolve a list of companyIds to their ownerUid (if any).
// Runs with admin privileges so clients that cannot read `companies/{id}`
// due to rules can still determine the owner for permission checks in the UI.
exports.getCompanyOwners = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login requerido');
  const companyIds = Array.isArray(data && data.companyIds) ? data.companyIds.map(String) : [];
  const db = admin.firestore();
  const result = {};
  for (const cid of companyIds) {
    let owner = null;
    try {
      const compRef = db.collection('companies').doc(cid);
      const compSnap = await compRef.get();
      if (compSnap.exists) {
        const cd = compSnap.data() || {};
        owner = cd.ownerUid || null;
      } else {
        // fallback to users/{cid} if companies/{cid} not present
        try {
          const userSnap = await db.collection('users').doc(cid).get();
          if (userSnap.exists) {
            const ud = userSnap.data() || {};
            if ((ud.role || ud['role']) === 'company') {
              owner = cid;
            }
          }
        } catch (e) {
          // ignore
        }
      }
    } catch (e) {
      console.warn('getCompanyOwners: error resolving', cid, e && e.message);
    }
    result[cid] = owner;
  }
  return { status: 'ok', owners: result };
});


// Secret Manager client will be required dynamically inside accessSecretValue
// so the code still works if the dependency isn't installed yet.

// Notificación push a admins cuando se crea una review pendiente en cualquier PDI
exports.notifyAdminsOnPendingReview = functions.firestore
  .document('pdis_v2/{pdiId}/reviews/{reviewId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;
    // Guard: avoid sending notifications for mirrored copies or for docs
    // that are not in the canonical pdis_v2 path. There have been cases
    // where mirrored writes (users/{uid}/reviews) or other duplicate
    // writes caused admins to receive the same notification twice.
    // The canonical review documents we create include `isMirror: false`,
    // while mirrored per-user copies include `isMirror: true`. If present
    // and true, skip sending the admin notification.
    if (data.isMirror === true) {
      console.log('Skipping admin notification for mirrored review:', snap.id);
      return null;
    }
    // Extra defensive check: ensure the document path belongs to pdis_v2.
    // If not, skip (covers unexpected triggers).
    const docPath = snap.ref.path || '';
    if (!docPath.startsWith('pdis_v2/')) {
      console.log('Skipping admin notification for review not under pdis_v2:', docPath);
      return null;
    }
    if (data.status !== 'pending') return null;
    const comment = data.comment || '';
    const rating = data.rating || 0;
    const userId = data.userId || '';
    const pdiId = context.params.pdiId || '';
    const payload = {
      notification: {
        title: 'Nueva valoración/comentario pendiente',
        body: `PDI: ${pdiId}\nUsuario: ${userId}\nValoración: ${rating} estrellas\nComentario: ${comment.substring(0, 60)}${comment.length > 60 ? '...' : ''}`,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        pdiId: pdiId,
        userId: userId,
        type: 'review_pending',
      },
    };
    try {
      await admin.messaging().sendToTopic('admins', payload);
      console.log('Notificación push de review pendiente enviada a admins');
    } catch (err) {
      console.error('Error enviando notificación push de review pendiente:', err);
    }
    return null;
  });



exports.sendContactEmail = functions.firestore
  .document('contact_messages/{messageId}')
  .onCreate(async (snap, context) => {
    const smtpConfig = functions.config().smtp || {};
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;

    if (!smtpEmail || !smtpPassword) {
      console.error('SMTP config missing: email or password not set.');
      return null;
    }

    const transporter = nodemailer.createTransport({
      host: 'mail.buspoints.net',
      port: 465,
      secure: true,
      auth: {
        user: smtpEmail,
        pass: smtpPassword
      }
    });

    const data = snap.data();
    console.log('Datos recibidos del documento:', data);
    if (!data) {
      console.error('El documento no contiene datos.');
      return null;
    }
    const nombre = data.name || '';
    const email = data.email || '';
    const mensaje = data.message || '';

    // Enviar correo al administrador
    const mailOptionsAdmin = {
      from: smtpEmail,
      to: smtpEmail,
      subject: 'Nuevo mensaje de contacto',
      text: `Nombre: ${nombre}\nEmail: ${email}\nMensaje: ${mensaje}`
    };
    try {
      await transporter.sendMail(mailOptionsAdmin);
      console.log('Correo enviado correctamente al administrador');
    } catch (error) {
      console.error('Error enviando correo al administrador:', error);
    }

    // Verificar si el usuario está registrado
    let isRegistered = false;
    if (email) {
      try {
        const userDocs = await admin.firestore().collection('users').where('email', '==', email).get();
        isRegistered = !userDocs.empty;
      } catch (err) {
        console.error('Error buscando usuario registrado:', err);
      }
    }

    // Si está registrado, enviar copia al usuario
    if (isRegistered) {
      const mailOptionsUser = {
        from: smtpEmail,
        to: email,
        subject: 'Copia de tu mensaje enviado',
        text: `Hola ${nombre},\n\nHemos recibido tu mensaje:\n${mensaje}\n\nPuedes eliminarlo desde tu perfil si lo deseas.\n\nGracias por contactar.`
      };
      try {
        await transporter.sendMail(mailOptionsUser);
        console.log('Copia enviada al usuario registrado');
      } catch (error) {
        console.error('Error enviando copia al usuario:', error);
      }
    }
    return null;
  });

// Helper: schedule a one-time Cloud Task to call our pending reminder handler
// Helper to obtain an access token from the metadata server (works in GCP)
async function getAccessTokenFromMetadata() {
  try {
    const resp = await axios.get('http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token', {
      headers: { 'Metadata-Flavor': 'Google' },
      timeout: 5000,
    });
    return resp.data && resp.data.access_token;
  } catch (err) {
    console.error('Failed to get access token from metadata server:', err && err.message);
    return null;
  }
}

// Get tasks secret from config, env or Firestore (cached). This allows
// storing the key in Firestore at `app_config/tasks.key` as a fallback
// when runtime functions.config() is not available.
let _cachedTasksKey = null;
let _cachedTasksKeyAt = 0;
// small in-memory cache for secret manager values
const _secretCache = {};

// Access Secret Manager secret. `name` should be the full resource name
// like `projects/<project>/secrets/<name>/versions/latest` or a short
// secret id in which case we'll attempt to resolve using the current
// project. Returns string or null.
async function accessSecretValue(name) {
  if (!name) return null;
  try {
    // cache for 60s
    const now = Date.now();
    const cacheEntry = _secretCache[name];
    if (cacheEntry && (now - cacheEntry.at) < 60 * 1000) return cacheEntry.value;

    let resourceName = name;
    if (!/^projects\//.test(name)) {
      const project = process.env.GCLOUD_PROJECT || process.env.GCLOUD_PROJECT_ID || process.env.GCLOUD_PROJECT_NAME;
      resourceName = `projects/${project}/secrets/${name}/versions/latest`;
    }
    // require Secret Manager client dynamically so missing dependency won't
    // break module load (we fallback gracefully).
    let SecretManagerServiceClient;
    try {
      SecretManagerServiceClient = require('@google-cloud/secret-manager').SecretManagerServiceClient;
    } catch (er) {
      console.warn('Secret Manager client not available (dependency not installed)');
      return null;
    }
    const client = new SecretManagerServiceClient();
    const [version] = await client.accessSecretVersion({ name: resourceName });
    const payload = version && version.payload && version.payload.data ? Buffer.from(version.payload.data, 'base64').toString('utf8') : null;
    _secretCache[name] = { value: payload, at: now };
    return payload;
  } catch (e) {
    console.warn('accessSecretValue error', e && e.message);
    return null;
  }
}
async function getTasksKey() {
  const now = Date.now();
  try {
    // 1) Secret Manager: if a secret resource name is configured, try it first
    const secretFromCfg = (functions.config().secrets && functions.config().secrets.tasks_name) || null;
    const secretEnvName = process.env.TASKS_SECRET_NAME || null;
    const secretName = secretEnvName || secretFromCfg;
    if (secretName) {
      const secretVal = await accessSecretValue(secretName);
      if (secretVal) return secretVal;
    }

    const tasksCfg = functions.config().tasks || {};
    if (tasksCfg.key) return tasksCfg.key;
    if (process.env.TASKS_KEY) return process.env.TASKS_KEY;
    // cache for 60s to avoid a Firestore read on every invocation
    if (_cachedTasksKey && (now - _cachedTasksKeyAt) < 60 * 1000) return _cachedTasksKey;
    try {
      const doc = await admin.firestore().doc('app_config/tasks').get();
      if (doc.exists) {
        const d = doc.data() || {};
        if (d.key) {
          _cachedTasksKey = String(d.key);
          _cachedTasksKeyAt = now;
          return _cachedTasksKey;
        }
      }
    } catch (e) {
      console.warn('getTasksKey: error reading Firestore fallback', e && e.message);
    }
  } catch (e) {
    console.warn('getTasksKey: unexpected error', e && e.message);
  }
  return '';
}

// Get SMTP config from config, env or Firestore (cached)
let _cachedSmtp = null;
let _cachedSmtpAt = 0;
async function getSmtpConfig() {
  const now = Date.now();
  try {
    // 1) Secret Manager: allow a JSON secret containing smtp config
    const smtpSecretFromCfg = (functions.config().secrets && functions.config().secrets.smtp_name) || null;
    const smtpSecretEnv = process.env.SMTP_SECRET_NAME || null;
    const smtpSecretName = smtpSecretEnv || smtpSecretFromCfg;
    if (smtpSecretName) {
      const raw = await accessSecretValue(smtpSecretName);
      if (raw) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed.email && parsed.password) return parsed;
        } catch (e) {
          console.warn('getSmtpConfig: invalid JSON in secret manager smtp secret', e && e.message);
        }
      }
    }

    const cfg = functions.config().smtp || {};
    if (cfg && cfg.email && cfg.password) return cfg;
    // env fallback
    if (process.env.SMTP_EMAIL && process.env.SMTP_PASSWORD) {
      return { email: process.env.SMTP_EMAIL, password: process.env.SMTP_PASSWORD, host: process.env.SMTP_HOST || 'mail.buspoints.net', port: process.env.SMTP_PORT || '465', secure: process.env.SMTP_SECURE || 'true' };
    }
    if (_cachedSmtp && (now - _cachedSmtpAt) < 60 * 1000) return _cachedSmtp;
    try {
      const doc = await admin.firestore().doc('app_config/smtp').get();
      if (doc.exists) {
        const d = doc.data() || {};
        if (d.email && d.password) {
          _cachedSmtp = { email: String(d.email), password: String(d.password), host: d.host ? String(d.host) : 'mail.buspoints.net', port: d.port ? String(d.port) : '465', secure: d.secure ? String(d.secure) : 'true' };
          _cachedSmtpAt = now;
          return _cachedSmtp;
        }
      }
    } catch (e) {
      console.warn('getSmtpConfig: error reading Firestore fallback', e && e.message);
    }
  } catch (e) {
    console.warn('getSmtpConfig: unexpected error', e && e.message);
  }
  return {};
}

// Schedule a Cloud Tasks task via REST API
async function schedulePendingReminder(uid, runAtMs) {
  try {
    const project = process.env.GCLOUD_PROJECT || process.env.GCLOUD_PROJECT_ID || process.env.GCLOUD_PROJECT_NAME;
    const tasksCfg = functions.config().tasks || {};
    const location = tasksCfg.location || 'europe-west1';
    const queue = tasksCfg.queue || 'buspoints-reminders-queue';
    const handlerUrl = tasksCfg.handler_url || (tasksCfg.handlerUrl || `https://${location}-${project}.cloudfunctions.net/pendingReminderHandler`);

    const accessToken = await getAccessTokenFromMetadata();
    if (!accessToken) {
      console.error('No access token available to create Cloud Task');
      return null;
    }

    const url = `https://cloudtasks.googleapis.com/v2/projects/${project}/locations/${location}/queues/${queue}/tasks`;
    const payload = { uid };
    const bodyBase64 = Buffer.from(JSON.stringify(payload)).toString('base64');

  // Resolve tasks key (from config, env or Firestore)
  const tasksKeyForScheduling = await getTasksKey();

    const taskBody = {
      task: {
        httpRequest: {
          httpMethod: 'POST',
          url: handlerUrl,
          headers: {
            'Content-Type': 'application/json',
            'x-buspoints-task-secret': tasksKeyForScheduling
          },
          body: bodyBase64
        },
        scheduleTime: { seconds: Math.floor(runAtMs / 1000) }
      }
    };

    const resp = await axios.post(url, taskBody, { headers: { Authorization: `Bearer ${accessToken}` } });
    return resp.data && resp.data.name;
  } catch (err) {
    console.error('Error scheduling pending reminder task (REST):', err && err.response ? err.response.data || err.response.statusText : err.message || err);
    return null;
  }
}

// Delete a Cloud Tasks task by resource name via REST API
async function deletePendingTaskByName(taskName) {
  if (!taskName) return;
  try {
    const accessToken = await getAccessTokenFromMetadata();
    if (!accessToken) return;
    const url = `https://cloudtasks.googleapis.com/v2/${taskName}`;
    await axios.delete(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  } catch (err) {
    console.warn('Could not delete task', taskName, err && err.response ? err.response.data || err.response.statusText : err.message || err);
  }
}

// Notificación push a usuario cuando recibe mensaje nuevo
exports.toUserPush = functions.firestore
  .document('user_messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;
    const fromName = data.fromName || 'Nuevo mensaje';
    const messageText = data.message || '';

    // Target resolution: allow per-user topic `user_<uid>` or broadcast to topic 'users'
    const toUid = data.toUid || data.to || null;
    try {
  if (toUid === 'all' || toUid === 'ALL' || data.to === 'all') {
        // Broadcast to all users
        const payload = {
          notification: {
            title: `Mensaje de ${fromName}`,
            body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
          },
          data: {
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        };
        await admin.messaging().sendToTopic('users', payload);
        console.log('Broadcast push enviada a topic users');
        return null;
      }

      if (toUid) {
        // Send per-user message including badge count if possible
          try {
          const uid = toUid;
          const userDoc = await admin.firestore().collection('users').doc(uid).get();
          const userData = userDoc.exists ? userDoc.data() || {} : {};
          const tokens = Array.isArray(userData.fcmTokens) ? userData.fcmTokens : [];

          // compute badge: unread per-user notifications + unread user_messages
          const unreadNotifSnap = await admin.firestore().collection('users').doc(uid).collection('notifications').where('read', '==', false).get();
          const unreadMsgsSnap = await admin.firestore().collection('user_messages').where('to', '==', uid).where('read', '==', false).get();
          const badge = (unreadNotifSnap.size || 0) + (unreadMsgsSnap.size || 0);

            if (tokens && tokens.length > 0) {
            const message = {
              tokens: tokens,
              notification: {
                title: `Mensaje de ${fromName}`,
                body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
              },
              apns: { payload: { aps: { badge: badge, sound: 'default' } } },
              data: { click_action: 'FLUTTER_NOTIFICATION_CLICK', userId: uid, badge: String(badge) },
            };
            const response = await admin.messaging().sendMulticast(message);
            console.log(`Sent direct notification to user ${uid} tokens=${tokens.length} success=${response.successCount}`);
            } else {
            // Fallback to topic if no tokens: send to user topic (no per-user badge possible)
            const topic = `user_${uid}`;
            const payload = {
              notification: {
                title: `Mensaje de ${fromName}`,
                body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
              },
              data: {
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                userId: uid,
              },
            };
            await admin.messaging().sendToTopic(topic, payload);
            console.log(`Notificación push enviada al topic ${topic} (fallback)`);
          }
        } catch (err) {
          console.error('Error sending direct user push with badge:', err);
        }
        return null;
      }

      // Fallback: send to 'users' topic
      const payload = {
        notification: {
          title: `Mensaje de ${fromName}`,
          body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };
      await admin.messaging().sendToTopic('users', payload);
      console.log('Notificación push enviada a topic users (fallback)');
    } catch (err) {
      console.error('Error enviando notificación push:', err);
    }
    return null;
  });

// Notificación push a admins cuando hay usuarios o PDIs pendientes de aprobar
exports.notifyAdminsOnPending = functions.pubsub.schedule('every 10 minutes').onRun(async (context) => {
  // Usuarios pendientes
  const usersSnap = await admin.firestore().collection('users').where('status', '==', 'pending').get();
  // PDIs pendientes (ajusta la colección y campo según tu modelo)
  const pdisSnap = await admin.firestore().collection('pdis_v2').where('status', '==', 'pending').get();
  const pendingUsers = usersSnap.size;
  const pendingPdis = pdisSnap.size;
  if (pendingUsers === 0 && pendingPdis === 0) return null;

  let body = '';
  if (pendingUsers > 0) body += `${pendingUsers} usuario(s) pendiente(s) de aprobar.\n`;
  if (pendingPdis > 0) body += `${pendingPdis} PDI(s) pendiente(s) de aprobar.`;

  const payload = {
    notification: {
      title: 'Pendientes de aprobación',
      body: body,
    },
    data: {
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
  };
  try {
    await admin.messaging().sendToTopic('admins', payload);
    console.log('Notificación push enviada a admins');
  } catch (err) {
    console.error('Error enviando notificación push a admins:', err);
  }
  return null;
});

// HTTP handler invoked by Cloud Tasks to send the pending reminder for a specific user
exports.pendingReminderHandler = functions.https.onRequest(async (req, res) => {
  try {
    // Security: validate a shared secret to prevent abuse. Can be set via `functions.config().tasks.key`
  const tasksCfg = functions.config().tasks || {};
  // Resolve secret (from config, env or Firestore)
  const secret = await getTasksKey();
    const provided = req.get('x-buspoints-task-secret') || (req.body && req.body.key);

    // (debug logs removed)

    if (!secret || !provided || provided !== secret) {
      console.warn('Unauthorized pendingReminderHandler call');
      return res.status(403).send('unauthorized');
    }

    const uid = (req.body && req.body.uid) || (req.query && req.query.uid);
    if (!uid) return res.status(400).send('missing uid');

    const userRef = admin.firestore().collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) return res.status(404).send('user not found');
    const user = userSnap.data() || {};

    // If user is already approved or reminder already sent, do nothing
    const status = (user.status || '').toString();
    if (status === 'approved' || user.pendingReminderSent) {
      // Clean up stored task record if present
      if (user.pendingReminderTask) {
        try { await deletePendingTaskByName(user.pendingReminderTask); } catch (e) { /* ignore */ }
        try { await userRef.set({ pendingReminderTask: admin.firestore.FieldValue.delete() }, { merge: true }); } catch (e) { /* ignore */ }
      }
      return res.status(200).send('no action');
    }

    // Send reminder email - resolve SMTP config with fallback
    const smtpConfig = await getSmtpConfig();
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;
    if (!smtpEmail || !smtpPassword) {
      console.error('SMTP config missing for pending reminder.');
      return res.status(500).send('smtp not configured');
    }

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host || 'mail.buspoints.net',
      port: smtpConfig.port || 465,
      secure: smtpConfig.secure === undefined ? true : !!smtpConfig.secure,
      auth: { user: smtpEmail, pass: smtpPassword }
    });

    const userName = user.name || '';
    const to = (user.email || '').toString();
    if (!to) return res.status(400).send('user no email');

    // Render template
    const view = { name: userName, uid: uid, isTrial: !!user.trialExpiry, trialExpiry: user.trialExpiry ? (user.trialExpiry.toDate ? user.trialExpiry.toDate().toLocaleString('es-ES') : String(user.trialExpiry)) : '' };
    const rendered = templates.render('pending_reminder', view);
    const subject = 'Recordatorio: tu cuenta está pendiente de aprobación';

    try {
      await transporter.sendMail({ from: smtpEmail, to, subject, text: rendered.text || '', html: rendered.html || undefined });
      await userRef.set({ pendingReminderSent: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      // clear stored task name (task has run)
      if (user.pendingReminderTask) {
        try { await userRef.set({ pendingReminderTask: admin.firestore.FieldValue.delete() }, { merge: true }); } catch (e) { /* ignore */ }
      }
      console.log('Pending reminder sent to', to);
      return res.status(200).send('sent');
    } catch (err) {
      console.error('Error sending pending reminder:', err);
      return res.status(500).send('error sending');
    }
  } catch (err) {
    console.error('pendingReminderHandler error:', err);
    return res.status(500).send('internal');
  }
});

// Send welcome email when a user document is created
exports.sendWelcomeEmail = functions.firestore
  .document('users/{uid}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const email = (data.email || '').toString();
    if (!email) return null;

    const smtpConfig = await getSmtpConfig();
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;
    if (!smtpEmail || !smtpPassword) {
      console.error('SMTP config missing for welcome email.');
      return null;
    }

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host || 'mail.buspoints.net',
      port: Number(smtpConfig.port || 465),
      secure: (smtpConfig.secure === undefined ? true : (String(smtpConfig.secure) === 'true')),
      auth: { user: smtpEmail, pass: smtpPassword }
    });

    const isTrial = !!data.trialExpiry || (data.trialStatus === 'active');
    const userName = data.name || '';
    const subject = isTrial ? 'Bienvenido a BusPoints — Prueba activada' : 'Bienvenido a BusPoints';
    const body = isTrial
      ? `Hola ${userName},\n\nGracias por registrarte. Tu periodo de prueba ha sido activado y dura 48 horas. Disfruta y si tienes dudas contáctanos.\n\n— El equipo de BusPoints` 
      : `Hola ${userName},\n\nGracias por registrarte en BusPoints. Un administrador revisará tu cuenta pronto.\n\n— El equipo de BusPoints`;

    // Render welcome template
    const view = {
      name: userName,
      uid: context.params.uid,
      isTrial: isTrial,
      trialExpiry: data.trialExpiry && data.trialExpiry.toDate ? data.trialExpiry.toDate().toLocaleString('es-ES') : (data.trialExpiry || '')
    };
    const rendered = templates.render('welcome', view);
    const mailOptions = { from: smtpEmail, to: email, subject, text: rendered.text || body, html: rendered.html || undefined };
    try {
      await transporter.sendMail(mailOptions);
      console.log(`Welcome email sent to ${email}`);
    } catch (err) {
      console.error('Error sending welcome email:', err);
    }

    // Schedule per-user reminder task at createdAt + 7 days if user is pending
    try {
      const userData = data || {};
      const status = (userData.status || 'pending').toString();
      // Only schedule if user is pending
      if (status === 'pending') {
        // Determine runAt: prefer createdAt from doc, else now
        let createdAtMillis = Date.now();
        if (userData.createdAt && userData.createdAt.toMillis) createdAtMillis = userData.createdAt.toMillis();
        const runAtMs = createdAtMillis + 7 * 24 * 60 * 60 * 1000;
        const taskName = await schedulePendingReminder(context.params.uid, runAtMs);
        if (taskName) {
          // store task name on user doc to allow deletion if user activates earlier
          try { await snap.ref.set({ pendingReminderTask: taskName }, { merge: true }); } catch (e) { console.warn('Failed storing pendingReminderTask', e); }
        }
      }
    } catch (err) {
      console.error('Error scheduling per-user pending reminder:', err);
    }
    return null;
  });

// Send email when a user status changes to 'approved' (subscription confirmed / account activated)
exports.sendSubscriptionConfirmedOnUserUpdate = functions.firestore
  .document('users/{uid}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const email = (after.email || '').toString();
    if (!email) return null;

    // If status changed to 'approved' from something else, send confirmation
    const prevStatus = (before.status || '').toString();
    const newStatus = (after.status || '').toString();
  if (prevStatus === newStatus) return null;
  // Accept common active/approved status values
  const activatedStatuses = ['approved', 'active', 'activated'];
  if (!activatedStatuses.includes(newStatus)) return null;

    // Resolve SMTP config using fallback helper (Secret Manager, env, Firestore)
    const smtpConfig = await getSmtpConfig();
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;
    if (!smtpEmail || !smtpPassword) {
      console.error('SMTP config missing for subscription confirmation email.');
      return null;
    }

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host || 'mail.buspoints.net',
      port: Number(smtpConfig.port || 465),
      secure: smtpConfig.secure === undefined ? true : (String(smtpConfig.secure) === 'true'),
      auth: { user: smtpEmail, pass: smtpPassword }
    });

    const userName = after.name || '';
    const view = { name: userName, uid: context.params.uid };
    const rendered = templates.render('subscription_confirmed', view);
    const subject = 'Tu cuenta ha sido activada en BusPoints';

    try {
      await transporter.sendMail({ from: smtpEmail, to: email, subject, text: rendered.text || '', html: rendered.html || undefined });
      console.log(`Subscription confirmation email sent to ${email}`);
      // If there was a scheduled pending reminder task, delete it to avoid sending later
      try {
        const afterTask = (after.pendingReminderTask || '').toString();
        if (afterTask) {
          await deletePendingTaskByName(afterTask);
          // clear the task field
          try { await change.after.ref.set({ pendingReminderTask: admin.firestore.FieldValue.delete() }, { merge: true }); } catch (e) { /* ignore */ }
        }
      } catch (e) {
        console.warn('Error deleting pending reminder task after approval:', e);
      }
    } catch (err) {
      console.error('Error sending subscription confirmation email:', err);
    }
    return null;
  });

// Scheduled job: send reminder email for users in 'pending' for 7 days
// NOTE: per-user scheduled reminders are implemented using Cloud Tasks and
// a per-user task scheduled at createdAt + 7 days. The legacy batch job
// is left out in favor of per-user scheduling. If you still want a daily
// fallback, we can keep the scheduled job here.

// Scheduled job: send reminder email 30 days before subscription expiry
// This job runs daily and finds users with a `subscriptionExpiry` timestamp
// within the next 30 days and who have not yet been sent the 30-day reminder.
exports.sendSubscriptionExpiryReminders = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
  try {
    const nowMs = Date.now();
    const nowTs = admin.firestore.Timestamp.fromMillis(nowMs);
    const endMs = nowMs + 30 * 24 * 60 * 60 * 1000; // 30 days
    const endTs = admin.firestore.Timestamp.fromMillis(endMs);

    // Query users whose subscriptionExpiry is between now and 30 days from now
    const usersSnap = await admin.firestore().collection('users')
      .where('subscriptionExpiry', '>=', nowTs)
      .where('subscriptionExpiry', '<=', endTs)
      .get();

    if (!usersSnap || usersSnap.empty) {
      console.log('No users with subscriptions expiring in next 30 days');
      return null;
    }

    const smtpConfig = await getSmtpConfig();
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;
    if (!smtpEmail || !smtpPassword) {
      console.error('SMTP config missing for subscription expiry reminders. Skipping.');
      return null;
    }

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host || 'mail.buspoints.net',
      port: Number(smtpConfig.port || 465),
      secure: smtpConfig.secure === undefined ? true : !!smtpConfig.secure,
      auth: { user: smtpEmail, pass: smtpPassword }
    });

    const sendPromises = [];
    for (const doc of usersSnap.docs) {
      const user = doc.data() || {};
      const uid = doc.id;
      // Skip if already sent (defensive — some docs may have the field)
      if (user.subscriptionExpiryReminder30Sent) {
        continue;
      }
      const email = (user.email || '').toString();
      if (!email) continue;

      // Compute human-friendly expiry date
      let expiryDateStr = '';
      try {
        const expiryTs = user.subscriptionExpiry;
        if (expiryTs && expiryTs.toDate) expiryDateStr = expiryTs.toDate().toLocaleString('es-ES');
        else expiryDateStr = String(user.subscriptionExpiry || '');
      } catch (e) {
        expiryDateStr = String(user.subscriptionExpiry || '');
      }

      const view = { name: user.name || '', expiryDate: expiryDateStr };
      const rendered = templates.render('subscription_expiry_30', view);
      const subject = 'Tu suscripción expira en 30 días — BusPoints';

      const p = transporter.sendMail({ from: smtpEmail, to: email, subject, text: rendered.text || '', html: rendered.html || undefined })
        .then(async () => {
          try {
            await doc.ref.set({ subscriptionExpiryReminder30Sent: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
            console.log(`Sent 30-day expiry reminder to ${email} (uid=${uid})`);
          } catch (e) {
            console.warn('Failed to mark reminder sent for', uid, e && e.message);
          }
        }).catch(err => {
          console.error('Error sending subscription expiry reminder to', email, err && err.message);
        });
      sendPromises.push(p);
    }

    await Promise.all(sendPromises);
    console.log('Subscription expiry reminders run complete');
    return null;
  } catch (err) {
    console.error('sendSubscriptionExpiryReminders error:', err && err.message);
    return null;
  }
});

// HTTP handler to trigger sending the 30-day expiry reminder for a specific uid
// This is intended for testing: it uses the same SMTP/templates and will mark
// the user doc with `subscriptionExpiryReminder30Sent` unless `email` param is provided.
// Protect with the tasks key header `x-buspoints-task-secret`.
exports.sendSubscriptionExpiryReminderForUid = functions.https.onRequest(async (req, res) => {
  try {
    const secret = await getTasksKey();
    const provided = req.get('x-buspoints-task-secret') || (req.body && req.body.key);
    if (!secret || !provided || provided !== secret) {
      console.warn('Unauthorized sendSubscriptionExpiryReminderForUid call');
      return res.status(403).send('unauthorized');
    }

    const uid = (req.body && req.body.uid) || (req.query && req.query.uid);
    const force = (req.body && req.body.force) || (req.query && req.query.force) || false;
    const overrideEmail = (req.body && req.body.email) || (req.query && req.query.email) || null;
    const overrideName = (req.body && req.body.name) || (req.query && req.query.name) || '';

    if (!uid && !overrideEmail) return res.status(400).send('missing uid or email');

    const smtpConfig = await getSmtpConfig();
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;
    if (!smtpEmail || !smtpPassword) {
      console.error('SMTP config missing for sendSubscriptionExpiryReminderForUid.');
      return res.status(500).send('smtp not configured');
    }

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host || 'mail.buspoints.net',
      port: Number(smtpConfig.port || 465),
      secure: smtpConfig.secure === undefined ? true : !!smtpConfig.secure,
      auth: { user: smtpEmail, pass: smtpPassword }
    });

    // If overrideEmail provided, send directly and do not mark user doc
    if (overrideEmail) {
      const view = { name: overrideName || '', expiryDate: (new Date(Date.now() + 30*24*60*60*1000)).toLocaleString('es-ES') };
      const rendered = templates.render('subscription_expiry_30', view);
      const subject = 'PRUEBA: Tu suscripción expira en 30 días — BusPoints (TEST)';
      try {
        await transporter.sendMail({ from: smtpEmail, to: overrideEmail, subject, text: rendered.text || '', html: rendered.html || undefined });
        console.log('Sent test expiry email to', overrideEmail);
        return res.status(200).send('sent');
      } catch (err) {
        console.error('Error sending test expiry email to', overrideEmail, err && err.message);
        return res.status(500).send('error sending');
      }
    }

    // Otherwise operate on user doc
    const userRef = admin.firestore().collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) return res.status(404).send('user not found');
    const user = userSnap.data() || {};

    // If not forced, check subscriptionExpiry within next 30 days
    if (!force) {
      const nowMs = Date.now();
      const endMs = nowMs + 30 * 24 * 60 * 60 * 1000;
      const expiry = user.subscriptionExpiry;
      let expiryMillis = null;
      if (expiry && expiry.toMillis) expiryMillis = expiry.toMillis();
      else if (typeof expiry === 'number') expiryMillis = expiry;
      if (!expiryMillis || expiryMillis < nowMs || expiryMillis > endMs) {
        return res.status(400).send('user subscription not in 30-day window; use force=true to override');
      }
    }

    const email = (user.email || '').toString();
    if (!email) return res.status(400).send('user no email');

    const expiryDateStr = (user.subscriptionExpiry && user.subscriptionExpiry.toDate) ? user.subscriptionExpiry.toDate().toLocaleString('es-ES') : (user.subscriptionExpiry || '');
    const view = { name: user.name || '', expiryDate: expiryDateStr };
    const rendered = templates.render('subscription_expiry_30', view);
    const subject = 'Tu suscripción expira en 30 días — BusPoints';

    try {
      await transporter.sendMail({ from: smtpEmail, to: email, subject, text: rendered.text || '', html: rendered.html || undefined });
      try { await userRef.set({ subscriptionExpiryReminder30Sent: admin.firestore.FieldValue.serverTimestamp() }, { merge: true }); } catch (e) { console.warn('Failed to mark reminder sent for', uid, e && e.message); }
      console.log('Sent expiry reminder to user', uid, email);
      return res.status(200).send('sent');
    } catch (err) {
      console.error('Error sending expiry reminder to user', uid, err && err.message);
      return res.status(500).send('error sending');
    }
  } catch (err) {
    console.error('sendSubscriptionExpiryReminderForUid error:', err && err.message);
    return res.status(500).send('internal');
  }
});

// Callable: getAdminInbox
// Devuelve { contact_messages: [...], user_messages: [...] } para el admin autenticado
exports.getAdminInbox = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const uid = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const role = (userData.role || '').toString();
    const isAdmin = !!userData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    // Read contact_messages (admin-facing messages)
    // Exclude documents that look like incidencias (they belong to the
    // dedicated `incidencias` collection) to avoid duplicates in the
    // admin inbox. We treat a contact_message as an incidencia when it
    // contains a `pdiId`, `motivo` or an explicit `isIncidencia` flag.
    const contactSnap = await admin.firestore().collection('contact_messages').orderBy('timestamp', 'desc').limit(500).get();
    const contactMessages = contactSnap.docs
      .map(d => ({ ref: d.ref, id: d.id, data: d.data() || {} }))
      .filter(x => {
        const dd = x.data || {};
        if (dd.isIncidencia === true) return false;
        if (dd.pdiId) return false;
        if (dd.motivo) return false;
        // fallback: if comentario exists but no other fields, keep it
        return true;
      })
      .map(x => {
        const dd = x.data || {};
        return Object.assign({ id: x.id, sourceCollection: 'contact_messages' }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
      });

    // Read user_messages where admin is recipient OR messages not marked as contact (admins can read non-contact user messages)
    // We'll fetch messages where toUid equals one of admin UIDs. To support multiple admins, query where toUid == uid OR where isContact != true (admins can read all non-contact according to rules)
    const userMsgSnap = await admin.firestore().collection('user_messages').orderBy('timestamp', 'desc').limit(1000).get();
    const userMessages = userMsgSnap.docs.map(d => {
      const dd = d.data() || {};
      return Object.assign({ id: d.id, sourceCollection: 'user_messages' }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
    });

    // Read incidencias (POI reports sent by users) and mark with sourceCollection so client can act accordingly
    const incidenciasSnap = await admin.firestore().collection('incidencias').orderBy('timestamp', 'desc').limit(500).get();
    const incidencias = incidenciasSnap.docs.map(d => {
      const dd = d.data() || {};
      return Object.assign({ id: d.id, sourceCollection: 'incidencias' }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
    });

  return { contact_messages: contactMessages, user_messages: userMessages, incidencias: incidencias };
  } catch (err) {
    console.error('getAdminInbox error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: getAdminSummary
// Returns aggregated counts for admin UI badges. This runs with admin privileges
// and avoids client-side Firestore reads for admin-only collections.
exports.getAdminSummary = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const uid = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const role = (userData.role || '').toString();
    const isAdmin = !!userData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    // pending users
    const usersSnap = await admin.firestore().collection('users').where('status', '==', 'pending').get();
    const pendingUsers = usersSnap.size || 0;

    // pending pdis
    let pendingPdis = 0;
    try {
      const pdisSnap = await admin.firestore().collection('pdis_v2').where('status', '==', 'pending').get();
      pendingPdis = pdisSnap.size || 0;
    } catch (e) {
      console.warn('getAdminSummary: failed to read pdis_v2 pending count', e && e.message);
    }

    // pending user_pois
    let pendingUserPois = 0;
    try {
      const upSnap = await admin.firestore().collection('user_pois').where('status', '==', 'pending').get();
      pendingUserPois = upSnap.size || 0;
    } catch (e) {
      console.warn('getAdminSummary: failed to read user_pois pending count', e && e.message);
    }

    // pending reviews under pdis_v2 (collectionGroup filter + path check)
    let pendingReviews = 0;
    try {
      const reviewsSnap = await admin.firestore().collectionGroup('reviews').where('status', '==', 'pending').get();
      pendingReviews = reviewsSnap.docs.filter(d => d.ref.path.startsWith('pdis_v2/')).length;
    } catch (e) {
      console.warn('getAdminSummary: failed to read reviews pending count', e && e.message);
    }

    // system notifications unread
    let systemNotifications = 0;
    try {
      const sysSnap = await admin.firestore().collection('system_notifications').where('read', '==', false).get();
      systemNotifications = sysSnap.size || 0;
    } catch (e) {
      console.warn('getAdminSummary: failed to read system_notifications count', e && e.message);
    }

  // Also reuse existing inbox helper counts for messages/incidencias to keep parity
  const inbox = await getAdminInboxForUid(uid);
    const contactMessages = Array.isArray(inbox.contact_messages) ? inbox.contact_messages.length : 0;
    const userMessages = Array.isArray(inbox.user_messages) ? inbox.user_messages.length : 0;
    const incidencias = Array.isArray(inbox.incidencias) ? inbox.incidencias.length : 0;

    return {
      pendingUsers,
      pendingPdis,
      pendingUserPois,
      pendingReviews,
      systemNotifications,
      contactMessages,
      userMessages,
      incidencias
    };
  } catch (err) {
    console.error('getAdminSummary error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminUpdatePoi
// Performs an admin-only update across multiple POI collections (pdis_v2, Pdis_full, pois, user_pois)
// The client should call this with { oldId, newName, newCategory, description, position, iconPath, specialCategories }
exports.adminUpdatePoi = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const uid = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const role = (userData.role || '').toString().toLowerCase();
    const isAdmin = !!userData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const oldId = (data.oldId || '').toString();
    const newName = (data.newName || '').toString();
    const newCategory = (data.newCategory || '').toString();
    const description = (data.description || '').toString();
    const position = data.position || null; // expect { lat, lng } or string
    const iconPath = data.iconPath || null;
    const specialCategories = Array.isArray(data.specialCategories) ? data.specialCategories : null;
    const deleteOld = data.deleteOld === undefined ? true : !!data.deleteOld;

    if (!oldId || !newName || !newCategory) {
      throw new functions.https.HttpsError('invalid-argument', 'oldId, newName and newCategory are required');
    }

    const sanitizeId = (s) => {
      return s.replace(/[^A-Za-z0-9_\-]/g, '_').replace(/_+/g, '_').replace(/^_+|_+$/g, '');
    };

    const newId = sanitizeId(`${newName}_${newCategory}`);

    // Prepare canonical document data
    const docData = {
      name: newName,
      category: newCategory,
      description: description,
      position: typeof position === 'string' ? position : (position && position.lat && position.lng ? `${position.lat},${position.lng}` : null),
      iconPath: iconPath,
      specialCategories: specialCategories,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const collections = ['pdis_v2', 'Pdis_full', 'pois', 'user_pois'];
    const results = {};

    for (const coll of collections) {
      try {
        const collRef = admin.firestore().collection(coll);
        // If a document exists with oldId, move/merge into newId
        const oldDocRef = collRef.doc(oldId);
        const oldSnap = await oldDocRef.get();
        if (oldSnap.exists) {
          // write to newId (merge)
          await collRef.doc(newId).set(docData, { merge: true });
          if (deleteOld && oldId !== newId) {
            try { await oldDocRef.delete(); } catch (e) { /* ignore */ }
          }
          results[coll] = { action: 'moved_or_merged', docMoved: true };
        } else {
          // Update any documents that reference this pdi via a pdiId field
          const qSnap = await collRef.where('pdiId', '==', oldId).get();
          if (!qSnap.empty) {
            let updated = 0;
            for (const d of qSnap.docs) {
              const updateData = Object.assign({}, docData);
              // set pdiId to newId for references
              updateData.pdiId = newId;
              try {
                await d.ref.update(updateData);
                updated++;
              } catch (e) {
                console.error('Failed updating ref in', coll, d.id, e);
              }
            }
            results[coll] = { action: 'updated_references', updatedCount: updated };
          } else {
            results[coll] = { action: 'not_found' };
          }
        }
      } catch (e) {
        console.error('Error handling collection', coll, e);
        results[coll] = { action: 'error', message: e.message || String(e) };
      }
    }

    return { success: true, newId, results };
  } catch (err) {
    console.error('adminUpdatePoi error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminEndTrial
// Admin can end a user's trial early. Expects { userId }
exports.adminEndTrial = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const callerUid = context.auth.uid;
    const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
    const callerData = callerDoc.exists ? callerDoc.data() || {} : {};
    const role = (callerData.role || '').toString().toLowerCase();
    const isAdmin = !!callerData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const userId = (data.userId || '').toString();
    if (!userId) {
      throw new functions.https.HttpsError('invalid-argument', 'userId is required');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const updates = {
      trialStatus: 'expired',
      trialEndedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Optionally clear trial fields to avoid accidental reuse
    // Keep trialRequested and trialDeviceId for audit purposes
    await userRef.set(updates, { merge: true });

    // Notify user via FCM if tokens present
    try {
      const u = userSnap.data() || {};
      const tokens = Array.isArray(u.fcmTokens) ? u.fcmTokens : (u.fcmToken ? [u.fcmToken] : []);
      if (tokens && tokens.length > 0) {
        const payload = {
          notification: {
            title: 'Fin de periodo de prueba',
            body: 'Tu periodo de prueba ha sido terminado por un administrador. Accede para conocer opciones de pago.',
          },
          data: { type: 'trial_ended' },
        };
        await admin.messaging().sendToDevice(tokens, payload);
      }
    } catch (err) {
      console.error('Error notificando usuario sobre fin de trial:', err);
    }

    return { success: true };
  } catch (err) {
    console.error('adminEndTrial error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminApproveTrial
// Admin can approve a user's trial (or approve the user fully) when they review the request.
// Expects { userId, approveAsUser: boolean }.
// If approveAsUser is true the function will mark the user 'approved' and optionally create a 1-year subscription.
exports.adminApproveTrial = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const callerUid = context.auth.uid;
    const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
    const callerData = callerDoc.exists ? callerDoc.data() || {} : {};
    const role = (callerData.role || '').toString().toLowerCase();
    const isAdmin = !!callerData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const userId = (data.userId || '').toString();
    const approveAsUser = !!data.approveAsUser;
    if (!userId) {
      throw new functions.https.HttpsError('invalid-argument', 'userId is required');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const now = admin.firestore.Timestamp.now();
    const updates = {
      trialStatus: 'active',
      trialApprovedBy: callerUid,
      trialApprovedAt: now,
    };

    // If user did not request trial but admin chooses to approve as regular user,
    // create a 1-year subscription and mark status approved.
    if (approveAsUser) {
      const endDate = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 365 * 24 * 3600 * 1000));
      updates['status'] = 'approved';
      updates['approvedAt'] = now;
      updates['subscriptionStart'] = now;
      updates['subscriptionEnd'] = endDate;
      updates['subscriptionActive'] = true;
      updates['subscriptionHistory'] = admin.firestore.FieldValue.arrayUnion({ startDate: now, endDate: endDate });
      // If admin approves the user as a regular (paid) user, clear any
      // trial-related fields so the client no longer treats the user as in
      // trial mode (prevents trial popups/banners after upgrade).
      updates['trialStatus'] = admin.firestore.FieldValue.delete();
      updates['trialExpiry'] = admin.firestore.FieldValue.delete();
      updates['trialRequested'] = admin.firestore.FieldValue.delete();
      updates['trialRequestedAt'] = admin.firestore.FieldValue.delete();
      updates['trialDeviceId'] = admin.firestore.FieldValue.delete();
    }

    // If trialExpiry isn't present, set default 48h expiry
    const existing = userSnap.data() || {};
    if (!existing.trialExpiry) {
      const expiry = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 48 * 3600 * 1000));
      updates['trialExpiry'] = expiry;
    }

    await userRef.set(updates, { merge: true });

    // Register deviceTrials if trialDeviceId exists
    try {
      const deviceHash = (existing.trialDeviceId || '').toString();
      if (deviceHash) {
        await admin.firestore().collection('device_trials').doc(deviceHash).set({
          deviceIdHash: deviceHash,
          firstUsedAt: existing.trialRequestedAt || now,
          userId: userId,
          blocked: true,
        }, { merge: true });
      }
    } catch (err) {
      console.error('Error writing device_trials during adminApproveTrial:', err);
    }

    // Optionally notify the user by FCM
    try {
      const u = userSnap.data() || {};
      const tokens = Array.isArray(u.fcmTokens) ? u.fcmTokens : (u.fcmToken ? [u.fcmToken] : []);
      if (tokens && tokens.length > 0) {
        const payload = {
          notification: {
            title: 'Prueba gratuita aprobada',
            body: 'Tu período de prueba ha sido aprobado por el equipo. ¡Disfruta 48 horas de acceso gratuito!',
          },
          data: { type: 'trial_approved' },
        };
        await admin.messaging().sendToDevice(tokens, payload);
      }
    } catch (err) {
      console.error('Error notifying user about trial approval:', err);
    }

    return { success: true };
  } catch (err) {
    console.error('adminApproveTrial error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminSendMassEmail
// Admin-only: send a templated/explicit email to segments or manual list.
// Modes supported:
//  - mode: 'all' (default) => all users
//  - mode: 'segment' with segment: 'subscribers'|'admins'|'all' => predefined queries
//  - mode: 'manual' with manualEmails: [..] or manualUids: [..]
// Safety: requires functions.config().admin.mass_email_enabled === 'true' or MASS_EMAIL_ENABLED=1
exports.adminSendMassEmail = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const callerUid = context.auth.uid;
    const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
    const callerData = callerDoc.exists ? callerDoc.data() || {} : {};
    const role = (callerData.role || '').toString().toLowerCase();
    const isAdmin = !!callerData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const cfg = functions.config().admin || {};
    const enabled = (cfg.mass_email_enabled === 'true') || (process.env.MASS_EMAIL_ENABLED === '1');
    if (!enabled) {
      throw new functions.https.HttpsError('failed-precondition', 'Mass email sending is disabled in functions config. Enable functions.config().admin.mass_email_enabled or set MASS_EMAIL_ENABLED=1');
    }

    const subject = (data.subject || '').toString();
    const html = (data.html || '').toString();
    const text = (data.text || '').toString();
    const preview = !!data.preview;
    const limit = Number(data.limit || 0) || 0;

    if (!subject || (!html && !text)) {
      throw new functions.https.HttpsError('invalid-argument', 'subject and html/text body required');
    }

    const mode = (data.mode || 'all').toString();
    const segment = (data.segment || 'all').toString();
    const manualEmails = Array.isArray(data.manualEmails) ? data.manualEmails.map(String) : [];
    const manualUids = Array.isArray(data.manualUids) ? data.manualUids.map(String) : [];

    const recipients = [];

    if (mode === 'manual') {
      // Add manual emails directly
      for (const em of manualEmails) {
        const e = (em || '').toString().trim();
        if (e) recipients.push({ uid: null, email: e, name: '' });
        if (limit && recipients.length >= limit) break;
      }
      // Add manual UIDs by fetching their emails
      for (const uid of manualUids) {
        if (!uid) continue;
        try {
          const udoc = await admin.firestore().collection('users').doc(uid).get();
          if (!udoc.exists) continue;
          const u = udoc.data() || {};
          const em = (u.email || '').toString().trim();
          if (em) recipients.push({ uid: uid, email: em, name: u.name || '' });
        } catch (e) {
          // ignore individual failures
        }
        if (limit && recipients.length >= limit) break;
      }
    } else {
      // mode is 'all' or 'segment'
      if (mode === 'all' || (mode === 'segment' && segment === 'all')) {
        const usersSnap = await admin.firestore().collection('users').get();
        for (const d of usersSnap.docs) {
          const u = d.data() || {};
          const em = (u.email || '').toString().trim();
          if (!em) continue;
          recipients.push({ uid: d.id, email: em, name: u.name || '' });
          if (limit && recipients.length >= limit) break;
        }
      } else if (mode === 'segment') {
        if (segment === 'subscribers') {
          const qSnap = await admin.firestore().collection('users').where('subscriptionActive', '==', true).get();
          for (const d of qSnap.docs) {
            const u = d.data() || {};
            const em = (u.email || '').toString().trim();
            if (!em) continue;
            recipients.push({ uid: d.id, email: em, name: u.name || '' });
            if (limit && recipients.length >= limit) break;
          }
        } else if (segment === 'admins') {
          const qSnap = await admin.firestore().collection('users').where('isAdmin', '==', true).get();
          for (const d of qSnap.docs) {
            const u = d.data() || {};
            const em = (u.email || '').toString().trim();
            if (!em) continue;
            recipients.push({ uid: d.id, email: em, name: u.name || '' });
            if (limit && recipients.length >= limit) break;
          }
        } else {
          throw new functions.https.HttpsError('invalid-argument', 'Unknown segment');
        }
      } else {
        throw new functions.https.HttpsError('invalid-argument', 'Unknown mode');
      }
    }

    const count = recipients.length;
    const sample = recipients.slice(0, Math.min(10, recipients.length)).map(r => r.email);

    if (preview) {
      return { preview: true, count, sample };
    }

    if (count === 0) {
      return { success: true, sent: 0, failed: 0, message: 'No recipients found' };
    }

    const smtpConfig = await getSmtpConfig();
    const smtpEmail = smtpConfig.email;
    const smtpPassword = smtpConfig.password;
    if (!smtpEmail || !smtpPassword) {
      throw new functions.https.HttpsError('failed-precondition', 'SMTP not configured');
    }

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host || 'mail.buspoints.net',
      port: Number(smtpConfig.port || 465),
      secure: (smtpConfig.secure === undefined) ? true : (String(smtpConfig.secure) === 'true'),
      auth: { user: smtpEmail, pass: smtpPassword }
    });

    let sent = 0;
    let failed = 0;
    const errors = [];

    for (const r of recipients) {
      try {
        const mailOptions = { from: smtpEmail, to: r.email, subject, text: text || undefined, html: html || undefined };
        await transporter.sendMail(mailOptions);
        sent++;
      } catch (e) {
        failed++;
        if (errors.length < 10) errors.push({ to: r.email, error: (e && e.message) ? e.message : String(e) });
      }
    }

    return { success: true, sent, failed, errors: errors.slice(0, 10) };
  } catch (err) {
    console.error('adminSendMassEmail error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminApproveRoute
// Admin-only: approve a user-created route and optionally make it public.
// Expects { routeId: string, makePublic: boolean }
exports.adminApproveRoute = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const callerUid = context.auth.uid;
    const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
    const callerData = callerDoc.exists ? callerDoc.data() || {} : {};
    const role = (callerData.role || '').toString().toLowerCase();
    const isAdmin = !!callerData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const routeId = (data.routeId || '').toString();
    const makePublic = data.makePublic === undefined ? true : !!data.makePublic;
    if (!routeId) {
      throw new functions.https.HttpsError('invalid-argument', 'routeId is required');
    }

    const routeRef = admin.firestore().collection('user_routes').doc(routeId);
    const routeSnap = await routeRef.get();
    if (!routeSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Route not found');
    }

    const routeData = routeSnap.data() || {};

    await routeRef.update({ approved: true, isPublic: makePublic, approvedBy: callerUid, approvedAt: admin.firestore.Timestamp.now() });

    // Notify route owner if possible
    try {
      const ownerUid = routeData.createdBy;
      if (ownerUid) {
        const userRef = admin.firestore().collection('users').doc(ownerUid.toString());
        const userSnap = await userRef.get();
        const u = userSnap.exists ? userSnap.data() || {} : {};
        const tokens = Array.isArray(u.fcmTokens) ? u.fcmTokens : (u.fcmToken ? [u.fcmToken] : []);
        if (tokens && tokens.length > 0) {
          const payload = {
            notification: {
              title: 'Tu ruta ha sido aprobada',
              body: `La ruta "${routeData.name || 'tu ruta'}" ha sido aprobada por el equipo.`,
            },
            data: { type: 'route_approved', routeId: routeId },
          };
          await admin.messaging().sendToDevice(tokens, payload);
        }

        // Award points to the route owner for having a route approved.
        // Points value can be configured from Firestore at app_config/rewards.routeApprovalPoints
        try {
          const cfgSnap = await admin.firestore().doc('app_config/rewards').get().catch(() => null);
          let rewardPoints = 10; // default
          if (cfgSnap && cfgSnap.exists) {
            const cfg = cfgSnap.data() || {};
            if (cfg.routeApprovalPoints !== undefined) {
              const v = Number(cfg.routeApprovalPoints);
              if (!Number.isNaN(v)) rewardPoints = v;
            }
          }

          if (rewardPoints > 0) {
            await admin.firestore().runTransaction(async (tx) => {
              const userDoc = await tx.get(userRef);
              const cur = (userDoc.exists && userDoc.data() && Number(userDoc.data().points)) ? Number(userDoc.data().points) : 0;
              tx.update(userRef, { points: cur + rewardPoints });
              const notifRef = userRef.collection('notifications').doc();
              tx.set(notifRef, {
                title: 'Has recibido puntos',
                message: `Has recibido ${rewardPoints} puntos por la aprobación de tu ruta "${routeData.name || ''}".`,
                read: false,
                type: 'points',
                amount: rewardPoints,
                createdAt: admin.firestore.Timestamp.now(),
              });
            });
          }
        } catch (err) {
          console.error('Error awarding points to route owner:', err);
        }
      }
    } catch (err) {
      console.error('Error notifying route owner after approve:', err);
    }

    return { success: true };
  } catch (err) {
    console.error('adminApproveRoute error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminListPdis
// Returns merged list of PDIs from multiple collections for admins.
exports.adminListPdis = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    const uid = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const role = (userData.role || '').toString().toLowerCase();
    const isAdmin = !!userData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const collections = ['pdis_v2', 'Pdis_full', 'pois', 'user_pois'];
    const results = [];

    // load hidden markers so we can hide items reviewed by THIS admin
    const hiddenSnap = await admin.firestore().collection('admin_chaos_hidden').get().catch(() => null);
    const hiddenMap = {};
    if (hiddenSnap && hiddenSnap.docs) {
      for (const h of hiddenSnap.docs) {
        try {
          const hd = h.data() || {};
          hiddenMap[h.id] = hd.reviewedBy || '';
        } catch (e) { /* ignore */ }
      }
    }

    for (const coll of collections) {
      try {
        const snap = await admin.firestore().collection(coll).get();
        for (const d of snap.docs) {
          const key = `${coll}__${d.id}`;
          // skip if hidden by this admin
          if (hiddenMap[key] && hiddenMap[key] === uid) continue;
          const data = d.data() || {};
          results.push({ collection: coll, id: d.id, data });
        }
      } catch (e) {
        // ignore individual collection errors
      }
    }
    return { success: true, items: results };
  } catch (err) {
    console.error('adminListPdis error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Callable: adminUpdatePdi
// Admin-only: update category of a PDI and mark it hidden for admin list.
exports.adminUpdatePdi = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth || !context.auth.uid) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    const uid = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const role = (userData.role || '').toString().toLowerCase();
    const isAdmin = !!userData.isAdmin || role === 'admin';
    if (!isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'User is not an admin');
    }

    const collection = (data.collection || '').toString();
    const id = (data.id || '').toString();
    const newCategory = (data.newCategory || '').toString();
    if (!collection || !id) throw new functions.https.HttpsError('invalid-argument', 'collection and id are required');

    // Update document
    await admin.firestore().collection(collection).doc(id).set({ category: newCategory, updatedByAdminAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    const key = `${collection}__${id}`;
    await admin.firestore().collection('admin_chaos_hidden').doc(key).set({ reviewedBy: uid, reviewedAt: admin.firestore.FieldValue.serverTimestamp(), collection, docId: id });

    return { success: true };
  } catch (err) {
    console.error('adminUpdatePdi error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', String(err));
  }
});

// Monitor suspiciousAttempts and status changes on users and alert admins
exports.monitorSuspiciousAttempts = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.exists ? change.before.data() : {};
      const after = change.after.exists ? change.after.data() : {};
      const uid = context.params.userId;
      if (!uid) return null;

      const beforeAttempts = Number(before.suspiciousAttempts || 0);
      const afterAttempts = Number(after.suspiciousAttempts || 0);
      const beforeStatus = String(before.status || '').toLowerCase();
      const afterStatus = String(after.status || '').toLowerCase();

      // If attempts crossed threshold 2 (pre-alert)
      if (beforeAttempts < 2 && afterAttempts >= 2 && afterAttempts < 3) {
        const title = 'Alerta de seguridad: intentos sospechosos';
        const body = `El usuario ${after.name || after.email || uid} tiene ${afterAttempts} intento(s) de acceso concurrente.`;
        const payload = {
          notification: { title, body },
          data: { type: 'security_alert', userId: uid, attempts: String(afterAttempts) }
        };
        try {
          await admin.messaging().sendToTopic('admins', payload);
          console.log('Sent security pre-alert to admins for', uid);
        } catch (e) {
          console.error('Error sending admin pre-alert push:', e);
        }

        // send email if SMTP configured
        try {
          const smtpConfig = functions.config().smtp || {};
          if (smtpConfig.email && smtpConfig.password) {
            const transporter = nodemailer.createTransport({
              host: smtpConfig.host || 'mail.buspoints.net',
              port: smtpConfig.port ? Number(smtpConfig.port) : 465,
              secure: smtpConfig.secure !== 'false',
              auth: { user: smtpConfig.email, pass: smtpConfig.password }
            });
            const mailOptions = {
              from: smtpConfig.email,
              to: smtpConfig.email,
              subject: `[Seguridad] ${title}`,
              text: `${body}\n\nUsuarioId: ${uid}`
            };
            try {
              await transporter.sendMail(mailOptions);
              console.log('Security alert email sent to admins');
            } catch (errEmail) {
              console.error('Error sending security alert email:', errEmail);
            }
          }
        } catch (err) {
          console.error('Error preparing/ sending security alert email:', err);
        }
      }
    } catch (err) {
      console.error('Error in monitorSuspiciousAttempts:', err);
    }
    return null;
  });

// Notify admins immediately when a user-submitted POI is created with status 'pending'
exports.notifyAdminsOnUserPoiPending = functions.firestore
  .document('user_pois/{poiId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;
    if (data.status !== 'pending') return null;
    const title = 'Nuevo PDI pendiente';
    const body = `${data.title || 'Nuevo PDI'} enviado por ${data.submittedByName || data.submittedBy || 'usuario'}`;
    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        type: 'poi_pending',
        poiId: context.params.poiId,
      },
    };
    try {
      await admin.messaging().sendToTopic('admins', payload);
      console.log('Notificación push enviada a admins por nuevo user_poi pendiente:', context.params.poiId);
    } catch (err) {
      console.error('Error enviando notificación push para user_poi pending:', err);
    }
    return null;
  });

// Notify admins when a new user is created with status 'pending'
exports.notifyAdminsOnUserPending = functions.firestore
  .document('users/{userId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;
    if (data.status !== 'pending') return null;
    const title = 'Nuevo usuario pendiente';
    const body = `${data.name || data.email || 'Usuario nuevo'} requiere aprobación.`;
    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        type: 'user_pending',
        userId: context.params.userId,
      },
    };
    try {
      await admin.messaging().sendToTopic('admins', payload);
      console.log('Notificación push enviada a admins por nuevo usuario pendiente:', context.params.userId);
    } catch (err) {
      console.error('Error enviando notificación push para user pending:', err);
    }
    return null;
  });

  // Send push when a system notification is created (broadcast or per-user)
  exports.systemNotificationPush = functions.firestore
    .document('system_notifications/{notifId}')
    .onCreate(async (snap, context) => {
      const data = snap.data();
      if (!data) return null;
      const messageText = data.message || '';
      const fromName = data.fromName || 'BusPoints';
      const to = data.to || null; // 'all' or a uid

      try {
        if (to === 'all') {
          // For broadcasts we created per-user notification copies under
          // users/{uid}/notifications/{notifId}. To deliver badge counts on
          // iOS and allow per-device badge updates, send individual messages
          // to each user's registered FCM tokens with the unread count.
          const usersSnap = await admin.firestore().collection('users').get();
          for (const userDoc of usersSnap.docs) {
            try {
              const uid = userDoc.id;
              const userData = userDoc.data() || {};
              const tokens = Array.isArray(userData.fcmTokens) ? userData.fcmTokens : [];

              // compute unread count from per-user notifications collection
              const unreadSnap = await admin.firestore().collection('users').doc(uid).collection('notifications').where('read', '==', false).get();
              const badge = unreadSnap.size || 0;

              if (!tokens || tokens.length === 0) continue;

              // build message with APNs badge and data payload with badge for Android
              const notification = {
                title: fromName,
                body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
              };

              const message = {
                tokens: tokens,
                notification: notification,
                android: {
                  notification: {
                    // include badge count in data so the app can update the launcher badge
                    // many Android launchers rely on app-side badge libraries
                    // We also include the count in data below.
                  }
                },
                apns: {
                  payload: {
                    aps: {
                      badge: badge,
                      sound: 'default'
                    }
                  }
                },
                data: {
                  click_action: 'FLUTTER_NOTIFICATION_CLICK',
                  type: 'system_notification',
                  badge: String(badge),
                }
              };

              // sendMulticast supports up to 500 tokens per request
              const response = await admin.messaging().sendMulticast(message);
              console.log(`Sent system broadcast to user ${uid} tokens: ${tokens.length} success=${response.successCount} failure=${response.failureCount}`);
            } catch (err) {
              console.error('Error sending per-user system broadcast:', err);
            }
          }
          console.log('System broadcast sent to all users (per-device)');
          return null;
        }

        if (to) {
          // per-user system notification: send per-device with badge if tokens exist
          try {
            const uid = to;
            const userDoc = await admin.firestore().collection('users').doc(uid).get();
            const userData = userDoc.exists ? userDoc.data() || {} : {};
            const tokens = Array.isArray(userData.fcmTokens) ? userData.fcmTokens : [];

            const unreadSnap = await admin.firestore().collection('users').doc(uid).collection('notifications').where('read', '==', false).get();
            const badge = unreadSnap.size || 0;

            if (tokens && tokens.length > 0) {
              const message = {
                tokens: tokens,
                notification: {
                  title: fromName,
                  body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
                },
                apns: { payload: { aps: { badge: badge, sound: 'default' } } },
                data: { click_action: 'FLUTTER_NOTIFICATION_CLICK', type: 'system_notification', userId: uid, badge: String(badge) },
              };
              const response = await admin.messaging().sendMulticast(message);
              console.log(`Sent system notification to user ${uid} tokens=${tokens.length} success=${response.successCount}`);
            } else {
              // fallback: topic
              const topic = `user_${uid}`;
              const payload = {
                notification: {
                  title: fromName,
                  body: messageText.length > 60 ? messageText.substring(0, 60) + '...' : messageText,
                },
                data: {
                  click_action: 'FLUTTER_NOTIFICATION_CLICK',
                  type: 'system_notification',
                  userId: uid,
                },
              };
              await admin.messaging().sendToTopic(topic, payload);
              console.log(`System notification sent to user topic ${topic} (fallback)`);
            }
          } catch (err) {
            console.error('Error sending per-user system notification:', err);
          }
          return null;
        }
      } catch (err) {
        console.error('Error sending system notification push:', err);
      }
      return null;
    });

// Reviews are auto-approved and do not require admin approval or award days.

// Notify the submitting user when their user_poi is approved
exports.notifyUserOnUserPoiApproved = functions.firestore
  .document('user_pois/{poiId}')
  .onUpdate(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    if (!before || !after) return null;
    if (before.status === 'approved' || after.status !== 'approved') return null;
    const userId = after.submittedBy || after.userId || null;
    if (!userId) return null;
    const payload = {
      notification: {
        title: 'Tu PDI ha sido aprobado',
        body: `${after.title || 'Tu PDI'} ha sido aprobado por el equipo.`,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        type: 'poi_approved',
        poiId: context.params.poiId,
      },
    };
    try {
      const topic = `user_${userId}`;
      await admin.messaging().sendToTopic(topic, payload);
      console.log(`Notificación enviada al usuario ${userId} por user_poi aprobado`);
      // Award: 2 days of subscription for each approved PDI submission.
      try {
        // Use a transaction to atomically update subscriptionHistory and awardsHistory for PDI approvals
        await admin.firestore().runTransaction(async (tx) => {
          const userRef = admin.firestore().collection('users').doc(userId);
          const userSnap = await tx.get(userRef);
          if (!userSnap.exists) return;
          const udata = userSnap.data() || {};
          const history = Array.isArray(udata.subscriptionHistory) ? udata.subscriptionHistory.slice() : [];
          const awards = Array.isArray(udata.awardsHistory) ? udata.awardsHistory.slice() : [];
          const now = new Date();
          const nowTs = admin.firestore.Timestamp.fromDate(now);
          const addDaysMs = 2 * 24 * 60 * 60 * 1000; // 2 days

          const newAward = { type: 'pdi_approved', days: 2, date: nowTs, poiId: context.params.poiId };

          if (history.length === 0) {
            const newSub = { startDate: nowTs, endDate: admin.firestore.Timestamp.fromDate(new Date(now.getTime() + addDaysMs)) };
            history.push(newSub);
            tx.update(userRef, { subscriptionHistory: history, subscriptionStart: newSub.startDate, subscriptionEnd: newSub.endDate, awardsHistory: (awards.concat([newAward])) });
            console.log(`Awarded 2 days subscription to ${userId} for approved PDI (new history entry) [tx]`);
          } else {
            let latestIdx = 0;
            let latestEnd = new Date(0);
            for (let i = 0; i < history.length; i++) {
              try {
                const item = history[i];
                const endTs = (item.endDate && item.endDate.toDate) ? item.endDate.toDate() : new Date(item.endDate);
                if (endTs > latestEnd) { latestEnd = endTs; latestIdx = i; }
              } catch (e) { /* ignore malformed entries */ }
            }

            const latest = history[latestIdx];
            const latestEndDate = (latest.endDate && latest.endDate.toDate) ? latest.endDate.toDate() : new Date(latest.endDate);

            if (latestEndDate > now) {
              const newEnd = new Date(latestEndDate.getTime() + addDaysMs);
              history[latestIdx] = { startDate: latest.startDate || nowTs, endDate: admin.firestore.Timestamp.fromDate(newEnd) };
              tx.update(userRef, { subscriptionHistory: history, subscriptionEnd: admin.firestore.Timestamp.fromDate(newEnd), awardsHistory: (awards.concat([newAward])) });
              console.log(`Extended subscription for ${userId} by 2 days (merged into existing period) [tx]`);
            } else {
              const newSub = { startDate: nowTs, endDate: admin.firestore.Timestamp.fromDate(new Date(now.getTime() + addDaysMs)) };
              history.push(newSub);
              tx.update(userRef, { subscriptionHistory: history, subscriptionEnd: newSub.endDate, awardsHistory: (awards.concat([newAward])) });
              console.log(`Awarded 2 days subscription to ${userId} for approved PDI (appended new period) [tx]`);
            }
          }
        });
      } catch (err) {
        console.error('Error awarding subscription days for approved PDI (transaction):', err);
      }
    } catch (err) {
      console.error('Error enviando notificación de user_poi aprobada:', err);
    }
    return null;
  });

// Also handle the case where a user-submitted PDI is created already in 'approved' state
// (some admin workflows may create the document with status=approved). This ensures the
// same awarding logic runs on create if needed. We guard against double-awarding by
// checking awardsHistory for an existing entry with the same poiId inside the transaction.
const _enableAwardOnUserPoiCreate = process.env.DISABLE_AWARD_ON_CREATE !== 'true';
if (_enableAwardOnUserPoiCreate) {
  exports.awardOnUserPoiCreate = functions.firestore
    .document('user_pois/{poiId}')
    .onCreate(async (snap, context) => {
      const after = snap.data();
      if (!after) return null;
      if (after.status !== 'approved') return null; // only award when created as already approved
      const userId = after.submittedBy || after.userId || null;
      if (!userId) return null;

      try {
        await admin.firestore().runTransaction(async (tx) => {
          const userRef = admin.firestore().collection('users').doc(userId);
          const userSnap = await tx.get(userRef);
          if (!userSnap.exists) return;
          const udata = userSnap.data() || {};
          const history = Array.isArray(udata.subscriptionHistory) ? udata.subscriptionHistory.slice() : [];
          const awards = Array.isArray(udata.awardsHistory) ? udata.awardsHistory.slice() : [];

          // Prevent double-award: if awards already contain an entry for this poiId, skip
          const already = awards.some((a) => a && a.poiId === context.params.poiId);
          if (already) return;

          const now = new Date();
          const nowTs = admin.firestore.Timestamp.fromDate(now);
          const addDaysMs = 2 * 24 * 60 * 60 * 1000; // 2 days
          const newAward = { type: 'pdi_approved', days: 2, date: nowTs, poiId: context.params.poiId };

          if (history.length === 0) {
            const newSub = { startDate: nowTs, endDate: admin.firestore.Timestamp.fromDate(new Date(now.getTime() + addDaysMs)) };
            history.push(newSub);
            tx.update(userRef, { subscriptionHistory: history, subscriptionStart: newSub.startDate, subscriptionEnd: newSub.endDate, awardsHistory: (awards.concat([newAward])) });
            console.log(`Awarded 2 days subscription to ${userId} for approved PDI on create (new history entry) [tx]`);
          } else {
            let latestIdx = 0;
            let latestEnd = new Date(0);
            for (let i = 0; i < history.length; i++) {
              try {
                const item = history[i];
                const endTs = (item.endDate && item.endDate.toDate) ? item.endDate.toDate() : new Date(item.endDate);
                if (endTs > latestEnd) { latestEnd = endTs; latestIdx = i; }
              } catch (e) { /* ignore malformed entries */ }
            }

            const latest = history[latestIdx];
            const latestEndDate = (latest.endDate && latest.endDate.toDate) ? latest.endDate.toDate() : new Date(latest.endDate);

            if (latestEndDate > now) {
              const newEnd = new Date(latestEndDate.getTime() + addDaysMs);
              history[latestIdx] = { startDate: latest.startDate || nowTs, endDate: admin.firestore.Timestamp.fromDate(newEnd) };
              tx.update(userRef, { subscriptionHistory: history, subscriptionEnd: admin.firestore.Timestamp.fromDate(newEnd), awardsHistory: (awards.concat([newAward])) });
              console.log(`Extended subscription for ${userId} by 2 days on create (merged into existing period) [tx]`);
            } else {
              const newSub = { startDate: nowTs, endDate: admin.firestore.Timestamp.fromDate(new Date(now.getTime() + addDaysMs)) };
              history.push(newSub);
              tx.update(userRef, { subscriptionHistory: history, subscriptionEnd: newSub.endDate, awardsHistory: (awards.concat([newAward])) });
              console.log(`Awarded 2 days subscription to ${userId} for approved PDI on create (appended new period) [tx]`);
            }
          }
        });
      } catch (err) {
        console.error('Error awarding subscription days for approved PDI on create (transaction):', err);
      }

      // Send notification to user topic (best-effort)
      try {
        const payload = {
          notification: {
            title: 'Tu PDI ha sido aprobado',
            body: `${after.title || 'Tu PDI'} ha sido aprobado por el equipo.`,
          },
          data: {
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            type: 'poi_approved',
            poiId: context.params.poiId,
          },
        };
        await admin.messaging().sendToTopic(`user_${userId}`, payload);
        console.log(`Notificación enviada al usuario ${userId} por user_poi aprobado (create)`);
      } catch (err) {
        console.error('Error enviando notificación de user_poi aprobada (create):', err);
      }

      return null;
    });
} else {
  console.log('awardOnUserPoiCreate is disabled via DISABLE_AWARD_ON_CREATE env var - skipping export');
}

// Recordatorio automático: enviar mensaje y push 1 mes antes del fin de suscripción
exports.remindSubscriptionEnding = functions.pubsub
  .schedule('every 24 hours')
  .timeZone('Europe/Madrid')
  .onRun(async (context) => {
    const now = new Date();
    const target = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    try {
      const usersSnap = await admin.firestore().collection('users').where('subscriptionActive', '==', true).get();
      if (usersSnap.empty) return null;

      for (const doc of usersSnap.docs) {
        const data = doc.data();
        if (!data) continue;

        // Evitar enviar recordatorios duplicados
        if (data.reminder30Sent) continue;

        // Intentar resolver fecha de fin de suscripción desde varios campos/formats
        let endDate = null;
        try {
          if (data.subscriptionEnd instanceof admin.firestore.Timestamp) {
            endDate = data.subscriptionEnd.toDate();
          } else if (data.subscriptionEndDate instanceof admin.firestore.Timestamp) {
            endDate = data.subscriptionEndDate.toDate();
          } else if (typeof data.subscriptionEnd === 'string') {
            const parsed = Date.parse(data.subscriptionEnd);
            if (!Number.isNaN(parsed)) endDate = new Date(parsed);
          } else if (typeof data.subscriptionEndDate === 'string') {
            const parsed = Date.parse(data.subscriptionEndDate);
            if (!Number.isNaN(parsed)) endDate = new Date(parsed);
          }
        } catch (err) {
          console.warn('Error parsing subscription end for user', doc.id, err);
        }

        if (!endDate) continue;

        const diffMs = endDate.getTime() - now.getTime();
        const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));

        // Comprobar si queda aproximadamente 30 días (29-31 para margen)
        if (diffDays >= 29 && diffDays <= 31) {
          const uid = doc.id;

          // Mensaje completo (texto provisto por el admin) – se guardará como mensaje directo
          const fullMessage = `👋 ¡Ey! Pasamos por aquí para recordarte que en un mes termina tu suscripción a BusPoints ⏳\n\n` +
            `Nos encantaría que te quedaras con nosotros, porque seguimos a tope 💪:\n` +
            `🗺️ mejorando el mapa\n` +
            `📍 añadiendo paradas\n` +
            `⚙️ afinándolo todo para que siempre vayas sobre seguro\n\n` +
            `Gracias por confiar en BusPoints ❤️\n` +
            `Un abrazo, compi, y… ¡buena ruta! 🚌✨😄`;

          // Texto corto para la notificación push
          const pushBody = '👋 ¡Tu suscripción termina en 1 mes! Nos encantaría que te quedaras con nosotros. ❤️';

          // Crear documento user_messages (mensaje directo)
          try {
            await admin.firestore().collection('user_messages').add({
              fromUid: 'system',
              fromName: 'BusPoints',
              message: fullMessage,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              read: false,
              fromAdmin: true,
              system: true,
              to: uid,
            });

            // Enviar push al topic por-usuario
            const topic = `user_${uid}`;
            const payload = {
              notification: {
                title: 'Tu suscripción termina en 1 mes',
                body: pushBody,
              },
              data: {
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                type: 'subscription_reminder',
                userId: uid,
              },
            };

            await admin.messaging().sendToTopic(topic, payload);

            // Marcar que ya se envió el recordatorio para evitar duplicados
            await doc.ref.update({ reminder30Sent: admin.firestore.FieldValue.serverTimestamp() });

            console.log(`Recordatorio de suscripción enviado al usuario ${uid}`);
          } catch (err) {
            console.error('Error creando mensaje o enviando push para user', uid, err);
          }
        }
      }
    } catch (err) {
      console.error('Error en remindSubscriptionEnding:', err);
    }

    return null;
  });

  // Cloud Function: keep the 'lista_gold' special category updated for PDIs
  // Rule: when a PDI (pdis_v2/{pdiId}) has >= 3 approved reviews and average rating >= 4.0
  // then we add 'lista_gold' to a document array field `specialCategories` on the PDI.
  // If the condition no longer holds (reviews removed/rejected/changed), we remove it.
  exports.updateGoldOnReview = functions.firestore
    .document('pdis_v2/{pdiId}/reviews/{reviewId}')
    .onWrite(async (change, context) => {
      try {
        const after = change.after.exists ? change.after.data() : null;
        const before = change.before.exists ? change.before.data() : null;

        // We only care about transitions to 'approved' or any write that results
        // in an 'approved' state (covers approvals and edits that set approved).
        if (!after || after.status !== 'approved') {
          // If the review was changed from approved -> not approved, we still
          // need to recalc (fall through). If after is not approved, but before
          // was approved, we should continue to recalc; otherwise skip.
          if (!before || before.status !== 'approved') return null;
        }

        const pdiId = context.params.pdiId;
        if (!pdiId) return null;

        const reviewsRef = admin.firestore().collection('pdis_v2').doc(pdiId).collection('reviews');
        const approvedSnap = await reviewsRef.where('status', '==', 'approved').get();
        const approvedCount = approvedSnap.size;

        let avg = 0;
        if (approvedCount > 0) {
          let sum = 0;
          approvedSnap.docs.forEach((d) => {
            const r = d.data() || {};
            const rt = Number(r.rating) || 0;
            sum += rt;
          });
          avg = sum / approvedCount;
        }

        const pdiRef = admin.firestore().collection('pdis_v2').doc(pdiId);

        // Condition: at least 3 approved reviews and average >= 4.0
        const shouldBeGold = approvedCount >= 3 && avg >= 4.0;

        if (shouldBeGold) {
          await pdiRef.update({
            specialCategories: admin.firestore.FieldValue.arrayUnion('lista_gold'),
            goldComputedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`Marked pdi ${pdiId} as lista_gold (count=${approvedCount}, avg=${avg.toFixed(2)})`);
        } else {
          // Remove if present
          await pdiRef.update({
            specialCategories: admin.firestore.FieldValue.arrayRemove('lista_gold'),
            goldComputedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`Ensured pdi ${pdiId} is NOT lista_gold (count=${approvedCount}, avg=${avg.toFixed(2)})`);
        }
      } catch (err) {
        console.error('Error in updateGoldOnReview:', err);
      }
      return null;
    });

  // Callable function: return admin's sent pushes (system_notifications and user_messages)
  exports.getAdminPushes = functions.https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Debe iniciar sesión');
      }
      const uid = context.auth.uid;

      // Verify caller is admin (check users/{uid}.role == 'admin')
      const userDoc = await admin.firestore().collection('users').doc(uid).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError('permission-denied', 'Usuario no encontrado');
      }
      const udata = userDoc.data() || {};
      const role = (udata.role || '').toString().toLowerCase();
      if (role !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Acceso denegado: solo admin');
      }

      // Query system_notifications and user_messages sent by this admin
      const sysSnap = await admin.firestore().collection('system_notifications').where('fromUid', '==', uid).get();
      const userMsgSnap = await admin.firestore().collection('user_messages').where('fromUid', '==', uid).get();

      const toPlain = (docSnap) => {
        const d = docSnap.data() || {};
        let ts = null;
        if (d.timestamp && d.timestamp.toDate) {
          ts = d.timestamp.toDate().getTime();
        } else if (typeof d.timestamp === 'number') {
          ts = d.timestamp;
        }
        return Object.assign({ id: docSnap.id, timestamp: ts }, d);
      };

      const systemNotifications = sysSnap.docs.map(toPlain);
      const userMessages = userMsgSnap.docs.map(toPlain);

      return { systemNotifications, userMessages };
    } catch (err) {
      console.error('Error in getAdminPushes:', err);
      if (err instanceof functions.https.HttpsError) throw err;
      throw new functions.https.HttpsError('internal', 'Error interno al obtener envíos');
    }
  });
