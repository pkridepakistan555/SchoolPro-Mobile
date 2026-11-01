const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');

initializeApp();
const db = getFirestore();

function requireAdmin(request) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Only an authorized SchoolPro admin can approve accounts.');
  }
}

// Admin-only issuance. This callable never grants an Admin claim and never
// trusts an ID supplied by the client. It allocates sequential IDs in a
// Firestore transaction and updates the pending user's canonical profile.
exports.approveAndIssueSchoolId = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const uid = String(request.data && request.data.uid || '').trim();
  const role = String(request.data && request.data.role || '').trim();
  if (!uid || !['student', 'teacher', 'parent'].includes(role)) {
    throw new HttpsError('invalid-argument', 'A valid uid and role (student, teacher, parent) are required.');
  }
  const authUser = await getAuth().getUser(uid);
  if (!authUser.emailVerified) throw new HttpsError('failed-precondition', 'User must verify the email address before approval.');
  const userRef = db.collection('users').doc(uid);
  const counterName = role === 'student' ? 'student' : role;
  const counterRef = db.collection('systemCounters').doc(counterName);
  const canonicalCollection = role === 'student' ? 'students' : role === 'teacher' ? 'teachers' : 'parents';
  const canonicalRef = db.collection(canonicalCollection).doc(uid);
  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const counterSnap = await tx.get(counterRef);
    const existingCanonical = await tx.get(canonicalRef);
    let linkedStudentSnap = null;
    if (role === 'parent' && userSnap.exists) {
      const admissionNo = String(userSnap.data().childAdmissionNo || '').trim();
      if (!admissionNo) throw new HttpsError('failed-precondition', 'Parent registration must include the child Admission Number.');
      const matches = await tx.get(db.collection('students').where('admissionNo', '==', admissionNo).limit(2));
      if (matches.docs.length !== 1) throw new HttpsError('failed-precondition', 'Child Admission Number is missing or duplicated.');
      linkedStudentSnap = await tx.get(matches.docs[0].ref);
    }
    if (!userSnap.exists) throw new HttpsError('not-found', 'Registration request not found.');
    const user = userSnap.data();
    if (String(user.name || '').trim().length < 2 || String(user.address || '').trim().length < 5 ||
        !['male','female','other','prefer_not_to_say'].includes(String(user.gender || ''))) {
      throw new HttpsError('failed-precondition', 'The registration profile is incomplete. Edit the name, address and gender before approval.');
    }
    if (role === 'student' && String(user.existingAdmissionNo || '').trim()) {
      throw new HttpsError('failed-precondition', 'This student already has an Admission Number. Use the Admin attach-student-account workflow to avoid creating a duplicate student record.');
    }
    if (role === 'student' && (String(user.currentClass || '').trim().length === 0 || String(user.guardianName || '').trim().length < 2 || !String(user.guardianPhone || '').trim())) {
      throw new HttpsError('failed-precondition', 'Student registration requires class and guardian name/phone.');
    }
    if (role === 'teacher' && (!String(user.qualification || '').trim() || !String(user.subjects || '').trim() || !Number.isInteger(Number(user.experienceYears)) || Number(user.experienceYears) < 0 || Number(user.experienceYears) > 60)) {
      throw new HttpsError('failed-precondition', 'Teacher registration requires qualification, subjects and valid experience years.');
    }
    if (role === 'parent' && (!String(user.childAdmissionNo || '').trim() || !String(user.relationshipToStudent || '').trim())) {
      throw new HttpsError('failed-precondition', 'Parent registration requires child Admission Number and relationship.');
    }
    const dobMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(user.dateOfBirth || ''));
    const dob = dobMatch ? new Date(Date.UTC(Number(dobMatch[1]), Number(dobMatch[2]) - 1, Number(dobMatch[3]))) : null;
    if (!dob || dob.toISOString().slice(0, 10) !== user.dateOfBirth || dob.getTime() > Date.now()) {
      throw new HttpsError('failed-precondition', 'A valid date of birth is required before approval.');
    }
    if (String(user.email || '').toLowerCase() !== String(authUser.email || '').toLowerCase()) throw new HttpsError('failed-precondition', 'Auth email does not match the registration profile.');
    if (user.role !== 'pending' || user.approvalStatus === 'approved' || user.approvalStatus === 'rejected') {
      throw new HttpsError('failed-precondition', 'Only a pending registration can be approved.');
    }
    if (user.requestedRole !== role) throw new HttpsError('failed-precondition', 'Selected role does not match the requested role.');
    if (existingCanonical.exists) throw new HttpsError('already-exists', 'A canonical role profile already exists for this account.');
    if (linkedStudentSnap && (!linkedStudentSnap.exists || linkedStudentSnap.data().admissionNo !== user.childAdmissionNo || ['inactive', 'deleted'].includes(linkedStudentSnap.data().status))) {
      throw new HttpsError('failed-precondition', 'The linked student record changed during approval.');
    }
    let next = Number(counterSnap.exists ? counterSnap.data().value : 0) + 1;
    if (!Number.isSafeInteger(next) || next < 1) throw new HttpsError('resource-exhausted', 'ID counter is invalid.');
    const year = new Date().getUTCFullYear();
    const idField = role === 'student' ? 'admissionNo' : role === 'teacher' ? 'teacherId' : 'parentId';
    let issued = null;
    let uniqueIdFound = false;
    // Counters may be absent or behind existing school data after an upgrade.
    // Check the canonical collection inside this transaction before issuing.
    for (let attempt = 0; attempt < 1000; attempt++, next++) {
      if (next > 99999) break;
      const serial = String(next).padStart(5, '0');
      const candidate = role === 'student' ? `SP-${year}-${serial}`
        : role === 'teacher' ? `TCH-${year}-${serial}` : `PAR-${year}-${serial}`;
      const collision = await tx.get(db.collection(canonicalCollection).where(idField, '==', candidate).limit(1));
      if (collision.empty) {
        issued = role === 'student' ? { admissionNo: candidate, rollNo: serial }
          : role === 'teacher' ? { teacherId: candidate } : { parentId: candidate };
        uniqueIdFound = true;
        break;
      }
    }
    if (!uniqueIdFound || !issued) throw new HttpsError('resource-exhausted', 'Could not allocate a unique school ID. Contact the administrator.');
    const linkedStudentId = linkedStudentSnap ? linkedStudentSnap.id : null;
    const linkedClass = linkedStudentSnap ? String(linkedStudentSnap.data().className || '') : '';
    const common = {
      uid, name: String(user.name || ''), phone: String(user.phone || ''), email: String(user.email || ''),
      dateOfBirth: String(user.dateOfBirth || ''), gender: String(user.gender || ''), address: String(user.address || ''),
      emergencyContactName: String(user.emergencyContactName || ''), emergencyContactPhone: String(user.emergencyContactPhone || ''),
      createdBy: request.auth.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    };
    tx.set(counterRef, { value: next, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(userRef, {
      role, approvalStatus: 'approved', approvedAt: FieldValue.serverTimestamp(), approvedBy: request.auth.uid,
      ...issued, ...(role === 'student' ? { linkedStudentId: uid } : {}), ...(linkedStudentId ? { linkedStudentId, linkedStudentIds: [linkedStudentId], linkedStudentClasses: linkedClass ? [linkedClass] : [], currentClass: linkedClass } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const canonical = role === 'student'
      ? { ...common, ...issued, className: String(user.currentClass || ''), teacherId: '', guardianName: String(user.guardianName || ''), guardianPhone: String(user.guardianPhone || user.phone || ''), previousSchool: String(user.previousSchool || ''), status: 'active' }
      : role === 'teacher'
        ? { ...common, ...issued, qualification: String(user.qualification || ''), subjects: String(user.subjects || ''), experienceYears: Number(user.experienceYears || 0), status: 'active' }
        : { ...common, ...issued, childAdmissionNo: String(user.childAdmissionNo || ''), relationshipToStudent: String(user.relationshipToStudent || ''), occupation: String(user.occupation || ''), linkedStudentId, linkedStudentIds: linkedStudentId ? [linkedStudentId] : [], linkedStudentClasses: linkedClass ? [linkedClass] : [], currentClass: linkedClass, status: 'active' };
    tx.set(canonicalRef, canonical);
    const auditRef = db.collection('adminAuditLogs').doc();
    tx.set(auditRef, { action: 'approve_and_issue_id', uid, role, issued, actorUid: request.auth.uid, createdAt: FieldValue.serverTimestamp() });
    return { uid, role, ...issued, approvalStatus: 'approved' };
  });
});



// Admin may add an enrolment record without creating login credentials. The
// Admission Number is still server-issued and collision-checked transactionally.
exports.createStudentRecord = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const input = request.data || {};
  const name = String(input.name || '').trim();
  const className = String(input.className || '').trim();
  const guardianName = String(input.guardianName || '').trim();
  const guardianPhone = String(input.guardianPhone || '').trim();
  const dateOfBirth = String(input.dateOfBirth || '').trim();
  const gender = String(input.gender || 'prefer_not_to_say').trim();
  const address = String(input.address || '').trim();
  const previousSchool = String(input.previousSchool || '').trim();
  const teacherId = String(input.teacherId || '').trim();
  const emergencyContactName = String(input.emergencyContactName || '').trim();
  const emergencyContactPhone = String(input.emergencyContactPhone || '').trim();
  const dobMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateOfBirth);
  const dob = dobMatch ? new Date(Date.UTC(Number(dobMatch[1]), Number(dobMatch[2]) - 1, Number(dobMatch[3]))) : null;
  if (name.length < 2 || name.length > 100 || !className || className.length > 80 ||
      guardianName.length < 2 || guardianName.length > 100 || guardianPhone.length > 30 ||
      !dob || dob.toISOString().slice(0, 10) !== dateOfBirth || dob.getTime() > Date.now() ||
      !['male','female','other','prefer_not_to_say'].includes(gender) || address.length < 5 || address.length > 300 ||
      previousSchool.length > 150 || emergencyContactName.length > 100 || emergencyContactPhone.length > 30) {
    throw new HttpsError('invalid-argument', 'Student name, class, guardian, valid DOB, gender and address are required; check field lengths.');
  }
  const counterRef = db.collection('systemCounters').doc('student');
  const studentRef = db.collection('students').doc();
  const teacherQuery = teacherId ? db.collection('teachers').where('teacherId', '==', teacherId).limit(2) : null;
  return db.runTransaction(async (tx) => {
    const counterSnap = await tx.get(counterRef);
    let teacherSnap = null;
    if (teacherQuery) {
      teacherSnap = await tx.get(teacherQuery);
      if (teacherSnap.docs.length !== 1 || teacherSnap.docs[0].data().status === 'inactive') {
        throw new HttpsError('failed-precondition', 'Assigned Teacher ID does not identify one active teacher.');
      }
    }
    let next = Number(counterSnap.exists ? counterSnap.data().value : 0) + 1;
    if (!Number.isSafeInteger(next) || next < 1) throw new HttpsError('resource-exhausted', 'Student ID counter is invalid.');
    const year = new Date().getUTCFullYear();
    let admissionNo = '';
    let rollNo = '';
    for (let attempt = 0; attempt < 1000; attempt++, next++) {
      if (next > 99999) break;
      const serial = String(next).padStart(5, '0');
      const candidate = `SP-${year}-${serial}`;
      const collision = await tx.get(db.collection('students').where('admissionNo', '==', candidate).limit(1));
      if (collision.empty) { admissionNo = candidate; rollNo = serial; break; }
    }
    if (!admissionNo) throw new HttpsError('resource-exhausted', 'Could not allocate a unique Admission Number.');
    const now = FieldValue.serverTimestamp();
    tx.set(counterRef, { value: next, updatedAt: now }, { merge: true });
    tx.set(studentRef, {
      name, admissionNo, rollNo, className, guardianName, guardianPhone,
      dateOfBirth, gender, address, previousSchool, teacherId,
      emergencyContactName, emergencyContactPhone, status: 'active',
      linkedUserUid: null, createdBy: request.auth.uid, createdAt: now, updatedAt: now,
    });
    const audit = db.collection('adminAuditLogs').doc();
    tx.set(audit, { action: 'create_student_record', studentId: studentRef.id, admissionNo, actorUid: request.auth.uid, createdAt: now });
    return { studentId: studentRef.id, admissionNo, rollNo };
  });
});

// Validate Teacher ID against exactly one active canonical teacher before
// assigning it to a student. Empty ID explicitly clears the assignment.
exports.assignTeacherToStudent = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const studentId = String(request.data && request.data.studentId || '').trim();
  const teacherId = String(request.data && request.data.teacherId || '').trim();
  if (!studentId || teacherId.length > 80) throw new HttpsError('invalid-argument', 'A student document ID and valid Teacher ID are required.');
  const studentRef = db.collection('students').doc(studentId);
  const teacherQuery = teacherId ? db.collection('teachers').where('teacherId', '==', teacherId).limit(2) : null;
  await db.runTransaction(async (tx) => {
    const studentSnap = await tx.get(studentRef);
    if (!studentSnap.exists || ['inactive','deleted'].includes(studentSnap.data().status)) throw new HttpsError('not-found', 'Active student record was not found.');
    if (teacherQuery) {
      const teachers = await tx.get(teacherQuery);
      if (teachers.docs.length !== 1 || teachers.docs[0].data().status === 'inactive') {
        throw new HttpsError('failed-precondition', 'Teacher ID must match exactly one active teacher.');
      }
    }
    tx.update(studentRef, { teacherId, updatedAt: FieldValue.serverTimestamp() });
    const audit = db.collection('adminAuditLogs').doc();
    tx.set(audit, { action: 'assign_teacher_to_student', studentId, teacherId, actorUid: request.auth.uid, createdAt: FieldValue.serverTimestamp() });
  });
  return { studentId, teacherId };
});

// Attach a pending, email-verified student login to an existing Admin-created
// enrolment record. This reuses the existing Admission Number and document ID.
exports.attachStudentAccount = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const uid = String(request.data && request.data.uid || '').trim();
  const admissionNo = String(request.data && request.data.admissionNo || '').trim();
  if (!uid || !admissionNo) throw new HttpsError('invalid-argument', 'Student UID and Admission Number are required.');
  const authUser = await getAuth().getUser(uid);
  if (!authUser.emailVerified) throw new HttpsError('failed-precondition', 'Student must verify their email before account linking.');
  const userRef = db.collection('users').doc(uid);
  const studentQuery = db.collection('students').where('admissionNo', '==', admissionNo).limit(2);
  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const matches = await tx.get(studentQuery);
    if (!userSnap.exists) throw new HttpsError('not-found', 'Student registration request was not found.');
    const user = userSnap.data();
    const dobMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(user.dateOfBirth || ''));
    const dob = dobMatch ? new Date(Date.UTC(Number(dobMatch[1]), Number(dobMatch[2]) - 1, Number(dobMatch[3]))) : null;
    if (!dob || dob.toISOString().slice(0,10) !== user.dateOfBirth || dob.getTime() > Date.now() ||
        String(user.name || '').trim().length < 2 || String(user.address || '').trim().length < 5 ||
        String(user.guardianName || '').trim().length < 2 || !String(user.guardianPhone || '').trim()) {
      throw new HttpsError('failed-precondition', 'Student registration profile is incomplete or contains invalid details.');
    }
    if (user.role !== 'pending' || user.requestedRole !== 'student' || user.approvalStatus !== 'pending') {
      throw new HttpsError('failed-precondition', 'Only a pending student registration can be linked.');
    }
    if (String(user.email || '').toLowerCase() !== String(authUser.email || '').toLowerCase()) {
      throw new HttpsError('failed-precondition', 'Auth email does not match the registration profile.');
    }
    if (matches.docs.length !== 1) throw new HttpsError('failed-precondition', 'Admission Number is missing or duplicated.');
    const studentRef = matches.docs[0].ref;
    const studentSnap = await tx.get(studentRef);
    const student = studentSnap.data() || {};
    if (!studentSnap.exists || ['inactive','deleted'].includes(student.status) ||
        (student.linkedUserUid && student.linkedUserUid !== uid)) {
      throw new HttpsError('failed-precondition', 'Student record is inactive or already linked to another login.');
    }
    const canonicalUidRef = db.collection('students').doc(uid);
    if (studentRef.id !== uid) {
      const duplicateUidRecord = await tx.get(canonicalUidRef);
      if (duplicateUidRecord.exists) throw new HttpsError('already-exists', 'A student profile already exists for this login.');
    }
    tx.update(userRef, {
      role: 'student', approvalStatus: 'approved', admissionNo,
      rollNo: String(student.rollNo || ''), linkedStudentId: studentRef.id,
      currentClass: String(student.className || ''),
      approvedAt: FieldValue.serverTimestamp(), approvedBy: request.auth.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(studentRef, { linkedUserUid: uid, linkedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    const audit = db.collection('adminAuditLogs').doc();
    tx.set(audit, { action: 'attach_student_account', uid, studentId: studentRef.id, admissionNo, actorUid: request.auth.uid, createdAt: FieldValue.serverTimestamp() });
  });
  return { uid, admissionNo, linked: true };
});

// Admin-only rejection with a mandatory reason and immutable audit entry.
exports.rejectSchoolRegistration = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const uid = String(request.data && request.data.uid || '').trim();
  const reason = String(request.data && request.data.reason || '').trim();
  if (!uid || !reason || reason.length > 1000) {
    throw new HttpsError('invalid-argument', 'A uid and a rejection reason (1-1000 characters) are required.');
  }
  const authUser = await getAuth().getUser(uid);
  const userRef = db.collection('users').doc(uid);
  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) throw new HttpsError('not-found', 'Registration request not found.');
    const user = userSnap.data();
    if (!authUser.email || String(user.email || '').toLowerCase() !== String(authUser.email).toLowerCase()) throw new HttpsError('failed-precondition', 'Auth email does not match the registration profile.');
    if (user.role !== 'pending' || user.approvalStatus === 'approved' || user.approvalStatus === 'rejected') {
      throw new HttpsError('failed-precondition', 'Only a pending registration can be rejected.');
    }
    tx.update(userRef, {
      role: 'rejected', approvalStatus: 'rejected', rejectionReason: reason,
      rejectedAt: FieldValue.serverTimestamp(), rejectedBy: request.auth.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const auditRef = db.collection('adminAuditLogs').doc();
    tx.set(auditRef, {
      action: 'reject_registration', uid, reason, actorUid: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { uid, approvalStatus: 'rejected' };
  });
});



// A user may update only their own non-privileged profile fields. Approved
// canonical role records are synchronized in the same transaction; issued IDs,
// class/teacher assignments, approval state and parent-child links are immutable
// to the client through this endpoint.
exports.updateOwnSchoolProfile = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to update your profile.');
  const uid = request.auth.uid;
  const input = request.data && request.data.profile;
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new HttpsError('invalid-argument', 'A profile object is required.');
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw new HttpsError('not-found', 'User profile was not found.');
  const role = String(userSnap.data().role || '');
  const common = ['name','phone','dateOfBirth','gender','address','emergencyContactName','emergencyContactPhone'];
  const roleFields = {
    student: ['guardianName','guardianPhone','previousSchool'],
    teacher: ['qualification','subjects','experienceYears'],
    parent: ['relationshipToStudent','occupation'],
  };
  const allowed = new Set([...common, ...(roleFields[role] || [])]);
  const keys = Object.keys(input);
  if (!['pending','student','teacher','parent','admin'].includes(role) || keys.length === 0 || keys.some((key) => !allowed.has(key))) {
    throw new HttpsError('permission-denied', 'One or more profile fields cannot be changed by this account.');
  }
  const update = {};
  for (const key of keys) {
    const value = input[key];
    if (key === 'experienceYears') {
      const n = Number(value);
      if (!Number.isInteger(n) || n < 0 || n > 60) throw new HttpsError('invalid-argument', 'Experience must be a whole number from 0 to 60.');
      update[key] = n;
      continue;
    }
    if (typeof value !== 'string') throw new HttpsError('invalid-argument', `${key} must be text.`);
    const limits = { name:100, phone:30, dateOfBirth:10, gender:24, address:300, emergencyContactName:100, emergencyContactPhone:30, guardianName:100, guardianPhone:30, previousSchool:150, qualification:150, subjects:300, relationshipToStudent:50, occupation:100 };
    const trimmed = value.trim();
    if (trimmed.length > limits[key] || (['name','dateOfBirth','gender','address'].includes(key) && trimmed.length === 0)) {
      throw new HttpsError('invalid-argument', `${key} is empty or exceeds its allowed length.`);
    }
    if (key === 'dateOfBirth') {
      const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(trimmed);
      const parsed = match ? new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))) : null;
      if (!parsed || parsed.toISOString().slice(0, 10) !== trimmed || parsed.getTime() > Date.now()) {
        throw new HttpsError('invalid-argument', 'Date of birth must be a valid past date in YYYY-MM-DD format.');
      }
    }
    if (key === 'gender' && !['male','female','other','prefer_not_to_say'].includes(trimmed)) {
      throw new HttpsError('invalid-argument', 'Choose a valid gender option.');
    }
    update[key] = trimmed;
  }
  const mergedProfile = { ...userSnap.data(), ...update };
  if (role === 'student' && (String(mergedProfile.guardianName || '').trim().length < 2 || !String(mergedProfile.guardianPhone || '').trim())) {
    throw new HttpsError('failed-precondition', 'Student profile must retain a guardian name and phone number.');
  }
  if (role === 'teacher' && (!String(mergedProfile.qualification || '').trim() || !String(mergedProfile.subjects || '').trim())) {
    throw new HttpsError('failed-precondition', 'Teacher profile must include qualification and subjects.');
  }
  if (role === 'parent' && !String(mergedProfile.relationshipToStudent || '').trim()) {
    throw new HttpsError('failed-precondition', 'Parent profile must include the relationship to the student.');
  }
  update.updatedAt = FieldValue.serverTimestamp();
  const canonicalCollection = role === 'student' ? 'students' : role === 'teacher' ? 'teachers' : role === 'parent' ? 'parents' : null;
  const canonicalId = role === 'student' ? String(userSnap.data().linkedStudentId || uid) : uid;
  const canonicalRef = canonicalCollection ? db.collection(canonicalCollection).doc(canonicalId) : null;
  await db.runTransaction(async (tx) => {
    const current = await tx.get(userRef);
    if (!current.exists || current.data().role !== role || (role === 'student' && String(current.data().linkedStudentId || uid) !== canonicalId)) throw new HttpsError('failed-precondition', 'Account role or linked student record changed; reload and try again.');
    let canonical = null;
    if (canonicalRef && current.data().approvalStatus === 'approved') {
      canonical = await tx.get(canonicalRef);
      if (!canonical.exists) throw new HttpsError('failed-precondition', 'Canonical school profile is missing; contact the administrator.');
    }
    tx.update(userRef, update);
    if (canonical && canonical.exists) tx.update(canonicalRef, update);
  });
  return { uid, updatedFields: keys };
});

// Admin-controlled parent-child relationship maintenance. All admission numbers
// must resolve to exactly one active student; no client can self-link a child.
exports.setParentStudentLinks = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const uid = String(request.data && request.data.uid || '').trim();
  const admissionNumbers = Array.isArray(request.data && request.data.admissionNumbers)
    ? [...new Set(request.data.admissionNumbers.map((v) => String(v).trim()).filter(Boolean))]
    : [];
  if (!uid || admissionNumbers.length < 1 || admissionNumbers.length > 10) {
    throw new HttpsError('invalid-argument', 'Provide a parent uid and 1–10 unique admission numbers.');
  }
  const parentRef = db.collection('users').doc(uid);
  const parentRecordRef = db.collection('parents').doc(uid);
  const studentQueries = admissionNumbers.map((n) => db.collection('students').where('admissionNo', '==', n).limit(2));
  let linkedStudentIds = [];
  await db.runTransaction(async (tx) => {
    const parent = await tx.get(parentRef);
    const matchSnapshots = await Promise.all(studentQueries.map((query) => tx.get(query)));
    const matchedStudentRefs = [];
    for (let i = 0; i < matchSnapshots.length; i++) {
      if (matchSnapshots[i].docs.length !== 1) throw new HttpsError('failed-precondition', `Admission number ${admissionNumbers[i]} is missing or duplicated.`);
      matchedStudentRefs.push(matchSnapshots[i].docs[0].ref);
    }
    const studentSnapshots = await Promise.all(matchedStudentRefs.map((ref) => tx.get(ref)));
    if (!parent.exists || parent.data().role !== 'parent' || parent.data().approvalStatus !== 'approved') {
      throw new HttpsError('failed-precondition', 'Only an approved parent account can be updated.');
    }
    const studentIds = [];
    const classNames = [];
    for (let i = 0; i < studentSnapshots.length; i++) {
      const student = studentSnapshots[i];
      const data = student.data() || {};
      if (!student.exists || data.admissionNo !== admissionNumbers[i] || ['inactive', 'deleted'].includes(data.status)) {
        throw new HttpsError('failed-precondition', `Admission number ${admissionNumbers[i]} is no longer eligible for linking.`);
      }
      studentIds.push(student.id);
      classNames.push(String(data.className || ''));
    }
    linkedStudentIds = studentIds;
    const links = studentIds.map((id, i) => ({ studentId: id, admissionNo: admissionNumbers[i], className: classNames[i] }));
    const parentRecord = await tx.get(parentRecordRef);
    if (!parentRecord.exists) throw new HttpsError('failed-precondition', 'Canonical parent profile is missing; contact the administrator.');
    tx.update(parentRef, { linkedStudentIds: studentIds, linkedStudents: links, linkedStudentClasses: [...new Set(classNames)], linkedStudentId: studentIds[0], currentClass: classNames[0] || '', updatedAt: FieldValue.serverTimestamp() });
    tx.update(parentRecordRef, { linkedStudentIds: studentIds, linkedStudents: links, linkedStudentClasses: [...new Set(classNames)], linkedStudentId: studentIds[0], updatedAt: FieldValue.serverTimestamp() });
    const audit = db.collection('adminAuditLogs').doc();
    tx.set(audit, { action: 'update_parent_student_links', uid, studentIds, actorUid: request.auth.uid, createdAt: FieldValue.serverTimestamp() });
  });
  return { uid, linkedStudentIds };
});

// Staff leave requests are submitted by the authenticated teacher and reviewed
// only by an Admin. Approval/rejection writes an immutable audit event.
exports.reviewTeacherLeaveRequest = onCall({ region: 'asia-south1', enforceAppCheck: false }, async (request) => {
  requireAdmin(request);
  const requestId = String(request.data && request.data.requestId || '').trim();
  const decision = String(request.data && request.data.decision || '').trim();
  const note = String(request.data && request.data.note || '').trim();
  if (!requestId || !['approved', 'rejected'].includes(decision) || note.length > 1000) {
    throw new HttpsError('invalid-argument', 'Invalid leave request review.');
  }
  const ref = db.collection('leaveRequests').doc(requestId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== 'pending') throw new HttpsError('failed-precondition', 'Leave request is not pending.');
    tx.update(ref, { status: decision, adminNote: note, reviewedBy: request.auth.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    const notification = db.collection('notifications').doc();
    tx.set(notification, { recipientUid: snap.data().teacherUid, type: 'leave', title: `Leave request ${decision}`, body: note || `Your leave request was ${decision}.`, relatedId: requestId, isRead: false, createdAt: FieldValue.serverTimestamp() });
    const audit = db.collection('adminAuditLogs').doc();
    tx.set(audit, { action: 'review_teacher_leave', requestId, decision, actorUid: request.auth.uid, createdAt: FieldValue.serverTimestamp() });
  });
  return { requestId, status: decision };
});


async function notifyParentsForStudent(studentId, payload) {
  if (!studentId) return;
  const [modern, legacy] = await Promise.all([
    db.collection('parents').where('linkedStudentIds', 'array-contains', studentId).get(),
    db.collection('parents').where('linkedStudentId', '==', studentId).get(),
  ]);
  const parents = new Map();
  for (const snap of [...modern.docs, ...legacy.docs]) parents.set(snap.id, snap);
  const batch = db.batch();
  for (const parent of parents.values()) {
    if (parent.data().status !== 'active') continue;
    const notificationId = `${payload.type}_${payload.relatedId || 'event'}_${parent.id}`.replace(/[^A-Za-z0-9_-]/g, '_');
    const notificationRef = db.collection('notifications').doc(notificationId);
    batch.set(notificationRef, {
      recipientUid: parent.id,
      studentId,
      type: payload.type,
      title: payload.title,
      body: payload.body,
      relatedId: payload.relatedId || null,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  if (parents.size) await batch.commit();
}

exports.notifyParentsOnAttendance = onDocumentCreated({ document: 'attendance/{id}', region: 'asia-south1' }, async (event) => {
  const data = event.data && event.data.data();
  if (!data || !['Absent', 'Leave'].includes(String(data.status))) return;
  await notifyParentsForStudent(String(data.studentId || ''), {
    type: 'attendance', title: 'Attendance update',
    body: `Attendance marked ${data.status} for ${data.studentName || data.admissionNo || 'your child'}.`, relatedId: event.params.id,
  });
});

exports.notifyParentsOnAttendanceUpdated = onDocumentUpdated({ document: 'attendance/{id}', region: 'asia-south1' }, async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!after || !['Absent', 'Leave'].includes(String(after.status)) || (before && before.status === after.status)) return;
  await notifyParentsForStudent(String(after.studentId || ''), {
    type: 'attendance', title: 'Attendance update',
    body: `Attendance updated to ${after.status} for ${after.studentName || after.admissionNo || 'your child'}.`, relatedId: event.params.id,
  });
});

exports.notifyParentsOnResult = onDocumentCreated({ document: 'results/{id}', region: 'asia-south1' }, async (event) => {
  const data = event.data && event.data.data();
  if (!data || !data.studentId) return;
  await notifyParentsForStudent(String(data.studentId), {
    type: 'result', title: 'New result published',
    body: `A new academic result is available for ${data.studentName || 'your child'}.`, relatedId: event.params.id,
  });
});

exports.notifyTeacherOnPayrollPaid = onDocumentUpdated({ document: 'teacherPayroll/{id}', region: 'asia-south1' }, async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!after || after.paymentStatus !== 'paid' || (before && before.paymentStatus === 'paid')) return;
  const uid = String(after.teacherUid || '');
  if (!uid) return;
  await db.collection('notifications').doc(`payroll_${event.params.id}_${uid}`).set({
    recipientUid: uid, type: 'payroll', title: 'Salary payment recorded',
    body: `Your salary for ${after.month || 'the selected month'} has been marked as paid.`,
    relatedId: event.params.id, isRead: false, createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
});

exports.notifyParentsOnFeePayment = onDocumentCreated({ document: 'feePayments/{id}', region: 'asia-south1' }, async (event) => {
  const data = event.data && event.data.data();
  if (!data || !data.studentId) return;
  await notifyParentsForStudent(String(data.studentId), {
    type: 'fee', title: 'Fee payment recorded',
    body: `A fee payment of ${data.amount || ''} has been recorded. Receipt: ${data.receiptNo || 'issued'}.`, relatedId: event.params.id,
  });
});

exports.notifyParentsOnPublishedNotice = onDocumentUpdated({ document: 'notices/{id}', region: 'asia-south1' }, async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!after || after.status !== 'published' || (before && before.status === 'published')) return;
  const parents = await db.collection('parents').get();
  for (let i = 0; i < parents.docs.length; i += 450) {
    const batch = db.batch();
    for (const parent of parents.docs.slice(i, i + 450)) {
      if (parent.data().status !== 'active') continue;
      const notificationRef = db.collection('notifications').doc(`notice_${event.params.id}_${parent.id}`);
      batch.set(notificationRef, {
        recipientUid: parent.id, type: 'notice', title: String(after.title || 'School announcement'),
        body: String(after.body || after.message || 'A new school notice has been published.'),
        relatedId: event.params.id, isRead: false, createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
});


exports.notifyParentsOnNewPublishedNotice = onDocumentCreated({ document: 'notices/{id}', region: 'asia-south1' }, async (event) => {
  const data = event.data && event.data.data();
  if (!data || data.status !== 'published') return;
  const parents = await db.collection('parents').get();
  const docs = parents.docs;
  for (let i = 0; i < docs.length; i += 450) {
    const batch = db.batch();
    for (const parent of docs.slice(i, i + 450)) {
      if (parent.data().status !== 'active') continue;
      const ref = db.collection('notifications').doc(`notice_${event.params.id}_${parent.id}`);
      batch.set(ref, { recipientUid: parent.id, type: 'notice', title: String(data.title || 'School announcement'), body: String(data.body || data.message || 'A new school notice has been published.'), relatedId: event.params.id, isRead: false, createdAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }
});
