// Proxy de autocompletado Google Places
exports.placesAutocomplete = require('./placesAutocomplete').placesAutocomplete;
// Obtener detalles de un place (geometry) por place_id
exports.getPlaceDetails = require('./getPlaceDetails').getPlaceDetails;
// Crear usuario admin-side con unicidad de email/phone
exports.createUser = require('./createUser').createUser;
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();

// Notificación push a admins cuando se crea una review pendiente en cualquier PDI
exports.notifyAdminsOnPendingReview = functions.firestore
  .document('pdis_v2/{pdiId}/reviews/{reviewId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;
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
    const contactSnap = await admin.firestore().collection('contact_messages').orderBy('timestamp', 'desc').limit(500).get();
    const contactMessages = contactSnap.docs.map(d => {
      const dd = d.data() || {};
      return Object.assign({ id: d.id }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
    });

    // Read user_messages where admin is recipient OR messages not marked as contact (admins can read non-contact user messages)
    // We'll fetch messages where toUid equals one of admin UIDs. To support multiple admins, query where toUid == uid OR where isContact != true (admins can read all non-contact according to rules)
    const userMsgSnap = await admin.firestore().collection('user_messages').orderBy('timestamp', 'desc').limit(1000).get();
    const userMessages = userMsgSnap.docs.map(d => {
      const dd = d.data() || {};
      return Object.assign({ id: d.id }, dd, { timestamp: dd.timestamp ? (dd.timestamp.toMillis ? dd.timestamp.toMillis() : dd.timestamp) : null });
    });

    return { contact_messages: contactMessages, user_messages: userMessages };
  } catch (err) {
    console.error('getAdminInbox error:', err);
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
