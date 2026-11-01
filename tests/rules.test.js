const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, serverTimestamp, collection, query, where, getDocs } = require('firebase/firestore');
const { ref, uploadBytes, getBytes } = require('firebase/storage');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'schoolpro-rules-test',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
    storage: { rules: fs.readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8') },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

describe('SchoolPro Firestore security baseline', () => {
  it('allows a user to create only their own pending profile', async () => {
    const db = env.authenticatedContext('u1', { email: 'u1@example.com' }).firestore();
    await assertSucceeds(setDoc(doc(db, 'users/u1'), { email: 'u1@example.com', name: 'Test User', phone: '', qualification: '', subjects: '', currentClass: '5', childAdmissionNo: '', existingAdmissionNo: '', dateOfBirth: '2010-01-01', gender: 'prefer_not_to_say', address: 'School road, Lahore', emergencyContactName: '', emergencyContactPhone: '', guardianName: 'Guardian', guardianPhone: '03001234567', previousSchool: '', experienceYears: 0, relationshipToStudent: '', occupation: '', requestedRole: 'student', role: 'pending', approvalStatus: 'pending', profileCompleted: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

  it('requires the role-specific registration profile fields', async () => {
    const db = env.authenticatedContext('u-profile', { email: 'u-profile@example.com' }).firestore();
    const profile = {
      email: 'u-profile@example.com', name: 'Test Student', phone: '', qualification: '', subjects: '',
      currentClass: '5', childAdmissionNo: '', existingAdmissionNo: '', dateOfBirth: '2010-01-01', gender: 'prefer_not_to_say',
      address: 'School road, Lahore', emergencyContactName: '', emergencyContactPhone: '',
      guardianName: '', guardianPhone: '', previousSchool: '', experienceYears: 0,
      relationshipToStudent: '', occupation: '', requestedRole: 'student', role: 'pending',
      approvalStatus: 'pending', profileCompleted: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    };
    await assertFails(setDoc(doc(db, 'users/u-profile'), profile));
    await assertFails(setDoc(doc(db, 'users/u-profile'), {...profile, guardianName: 'Guardian', guardianPhone: '03001234567', dateOfBirth: '01-01-2010'}));
  });
  it('denies self-assigned privileged roles', async () => {
    const db = env.authenticatedContext('u2', { email: 'u2@example.com' }).firestore();
    await assertFails(setDoc(doc(db, 'users/u2'), { email: 'u2@example.com', name: 'Test User', phone: '', qualification: '', subjects: '', currentClass: '', childAdmissionNo: '', existingAdmissionNo: '', dateOfBirth: '2010-01-01', gender: 'prefer_not_to_say', address: 'School road, Lahore', emergencyContactName: '', emergencyContactPhone: '', guardianName: 'Guardian', guardianPhone: '03001234567', previousSchool: '', experienceYears: 0, relationshipToStudent: '', occupation: '', requestedRole: 'student', role: 'admin', approvalStatus: 'approved', profileCompleted: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
  it('denies unsupported requested roles even when the account is pending', async () => {
    const db = env.authenticatedContext('u-role', { email: 'u-role@example.com' }).firestore();
    await assertFails(setDoc(doc(db, 'users/u-role'), { email: 'u-role@example.com', name: 'Test User', phone: '', qualification: '', subjects: '', currentClass: '', childAdmissionNo: '', existingAdmissionNo: '', dateOfBirth: '2010-01-01', gender: 'prefer_not_to_say', address: 'School road, Lahore', emergencyContactName: '', emergencyContactPhone: '', guardianName: 'Guardian', guardianPhone: '03001234567', previousSchool: '', experienceYears: 0, relationshipToStudent: '', occupation: '', requestedRole: 'admin', role: 'pending', approvalStatus: 'pending', profileCompleted: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
  it('denies non-admin access to school records', async () => {
    const db = env.authenticatedContext('u3').firestore();
    await assertFails(getDoc(doc(db, 'students/s1')));
    await assertFails(setDoc(doc(db, 'students/s1'), { name: 'Student' }));
  });
  it('allows an admin custom claim to access school records', async () => {
    const db = env.authenticatedContext('a1', { admin: true }).firestore();
    await assertSucceeds(setDoc(doc(db, 'students/s1'), { name: 'Student' }));
    await assertSucceeds(getDoc(doc(db, 'students/s1')));
  });
  it('allows only Admin-claim clients to maintain issuance counters and audit logs', async () => {
    const adminDb = env.authenticatedContext('a2', { admin: true }).firestore();
    await assertSucceeds(setDoc(doc(adminDb, 'adminAuditLogs/log1'), { action: 'approve_and_issue_id' }));
    await assertSucceeds(setDoc(doc(adminDb, 'systemCounters/student'), { value: 1 }));
    const userDb = env.authenticatedContext('u-counter').firestore();
    await assertFails(setDoc(doc(userDb, 'adminAuditLogs/fake'), { action: 'fake' }));
    await assertFails(setDoc(doc(userDb, 'systemCounters/student'), { value: 900 }));
  });

  it('allows an approved student to read only the matching student profile and attendance', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/student-auth'), { role: 'student', approvalStatus: 'approved', admissionNo: 'SP-2026-00001' });
      await setDoc(doc(db, 'students/student-auth'), { admissionNo: 'SP-2026-00001', name: 'A Student' });
      await setDoc(doc(db, 'students/other-student'), { admissionNo: 'SP-2026-00002', name: 'Other Student' });
      await setDoc(doc(db, 'attendance/a1'), { studentId: 'student-auth', date: '2026-10-31', status: 'Present' });
      await setDoc(doc(db, 'attendance/a2'), { studentId: 'other-student', date: '2026-10-31', status: 'Absent' });
    });
    const db = env.authenticatedContext('student-auth').firestore();
    await assertSucceeds(getDoc(doc(db, 'students/student-auth')));
    await assertFails(getDoc(doc(db, 'students/other-student')));
    await assertSucceeds(getDoc(doc(db, 'attendance/a1')));
    await assertFails(getDoc(doc(db, 'attendance/a2')));
  });

  it('allows an approved parent to read the child linked by the issued admission number only', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/parent-auth'), { role: 'parent', approvalStatus: 'approved', childAdmissionNo: 'SP-2026-00011', linkedStudentId: 'child-doc' });
      await setDoc(doc(db, 'students/child-doc'), { admissionNo: 'SP-2026-00011', name: 'Child' });
      await setDoc(doc(db, 'students/unrelated-doc'), { admissionNo: 'SP-2026-00012', name: 'Unrelated' });
      await setDoc(doc(db, 'feePayments/payment-child'), { studentId: 'child-doc', amount: 5000 });
      await setDoc(doc(db, 'feePayments/payment-other'), { studentId: 'unrelated-doc', amount: 9000 });
    });
    const db = env.authenticatedContext('parent-auth').firestore();
    await assertSucceeds(getDoc(doc(db, 'students/child-doc')));
    await assertFails(getDoc(doc(db, 'students/unrelated-doc')));
    await assertSucceeds(getDoc(doc(db, 'feePayments/payment-child')));
    await assertFails(getDoc(doc(db, 'feePayments/payment-other')));
  });


  it('prevents a parent from changing the Admin-issued child link', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/parent-link'), {
        role: 'parent', approvalStatus: 'approved', parentId: 'PAR-2026-00001', linkedStudentId: 'child-one',
      });
    });
    const db = env.authenticatedContext('parent-link').firestore();
    await assertFails(updateDoc(doc(db, 'users/parent-link'), { linkedStudentId: 'child-two' }));
  });

  it('allows an admin to create a fee payment record with a valid receipt number and matching fee structure', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'students/student-1'), { name: 'Student One', className: '5' });
      await setDoc(doc(db, 'feeStructures/tuition-5'), { name: 'Tuition', className: '5', amount: 2500, frequency: 'monthly' });
    });
    const db = env.authenticatedContext('admin-fee', { admin: true }).firestore();
    await assertSucceeds(setDoc(doc(db, 'feePayments/receipt-1'), {
      studentId: 'student-1', studentName: 'Student One', feeStructureId: 'tuition-5',
      amount: 2500, month: '2026-11', receiptNo: 'FEE-2026-000001', createdBy: 'admin-fee',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  it('rejects malformed receipt numbers and non-admin fee collection', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'students/student-1'), { className: '5' });
      await setDoc(doc(db, 'feeStructures/tuition-5'), { className: '5' });
    });
    const adminDb = env.authenticatedContext('admin-fee-invalid', { admin: true }).firestore();
    const base = { studentId: 'student-1', feeStructureId: 'tuition-5', amount: 2500, month: '2026-11', createdBy: 'admin-fee-invalid', createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
    await assertFails(setDoc(doc(adminDb, 'feePayments/bad-receipt'), {...base, receiptNo: 'MANUAL-001'}));
    const userDb = env.authenticatedContext('regular-fee-user').firestore();
    await assertFails(setDoc(doc(userDb, 'feePayments/forbidden'), {...base, receiptNo: 'FEE-2026-000002'}));
  });

  it('allows a teacher to read only records assigned to the issued teacher ID', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/teacher-auth'), { role: 'teacher', approvalStatus: 'approved', teacherId: 'TCH-2026-00001' });
      await setDoc(doc(db, 'students/teacher-student'), { admissionNo: 'SP-2026-00041', teacherId: 'TCH-2026-00001', name: 'Assigned' });
      await setDoc(doc(db, 'students/other-teacher-student'), { admissionNo: 'SP-2026-00042', teacherId: 'TCH-2026-00002', name: 'Not Assigned' });
      await setDoc(doc(db, 'timetables/own'), { teacherId: 'TCH-2026-00001', className: '5', subject: 'Math' });
      await setDoc(doc(db, 'timetables/other'), { teacherId: 'TCH-2026-00002', className: '6', subject: 'Science' });
    });
    const db = env.authenticatedContext('teacher-auth').firestore();
    await assertSucceeds(getDoc(doc(db, 'timetables/own')));
    await assertFails(getDoc(doc(db, 'timetables/other')));
    await assertSucceeds(getDoc(doc(db, 'students/teacher-student')));
    await assertFails(getDoc(doc(db, 'students/other-teacher-student')));
  });



  it('allows a teacher to mark attendance only for students assigned to that teacher', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/teacher-attend'), { role: 'teacher', approvalStatus: 'approved', teacherId: 'TCH-2026-00031' });
      await setDoc(doc(db, 'students/assigned'), { name: 'Assigned Student', admissionNo: 'SP-2026-00031', className: '7', teacherId: 'TCH-2026-00031' });
      await setDoc(doc(db, 'students/not-assigned'), { admissionNo: 'SP-2026-00032', teacherId: 'TCH-2026-00032' });
    });
    const db = env.authenticatedContext('teacher-attend').firestore();
    await assertSucceeds(setDoc(doc(db, 'attendance/assigned-day'), {
      studentId: 'assigned', studentName: 'Assigned Student', admissionNo: 'SP-2026-00031',
      className: '7', date: '2026-10-31', status: 'Present', markedBy: 'teacher-attend',
    }));
    await assertFails(setDoc(doc(db, 'attendance/not-assigned-day'), {
      studentId: 'not-assigned', studentName: 'Other', admissionNo: 'SP-2026-00032',
      className: '8', date: '2026-10-31', status: 'Present', markedBy: 'teacher-attend',
    }));
  });

  it('allows a student to submit homework only for their own student record', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/student-submit'), { role: 'student', approvalStatus: 'approved', admissionNo: 'SP-2026-00021' });
      await setDoc(doc(db, 'students/student-submit'), { admissionNo: 'SP-2026-00021', name: 'Submitting Student', className: '5' });
      await setDoc(doc(db, 'assignments/assignment-1'), { className: '5', teacherId: 'TCH-2026-00021' });
    });
    const db = env.authenticatedContext('student-submit').firestore();
    await assertSucceeds(setDoc(doc(db, 'homeworkSubmissions/student-submit__assignment-1'), {
      studentId: 'student-submit', assignmentId: 'assignment-1', createdBy: 'student-submit',
      answer: 'My completed answer', status: 'submitted', teacherId: 'TCH-2026-00021', submittedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db, 'homeworkSubmissions/student-submit__assignment-1'), {
      studentId: 'student-submit', assignmentId: 'assignment-1', createdBy: 'student-submit',
      answer: 'Duplicate submission', status: 'submitted', teacherId: 'TCH-2026-00021', submittedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db, 'homeworkSubmissions/another-student__assignment-1'), {
      studentId: 'another-student', assignmentId: 'assignment-1', createdBy: 'student-submit',
      answer: 'Trying to submit for someone else', status: 'submitted', teacherId: 'TCH-2026-00021', submittedAt: serverTimestamp(),
    }));
  });




  it('allows an approved student login to use an Admin-issued existing enrolment document ID', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/linked-student-user'), {
        role: 'student', approvalStatus: 'approved', requestedRole: 'student',
        admissionNo: 'SP-2026-00041', linkedStudentId: 'student-record-41',
      });
      await setDoc(doc(db, 'students/student-record-41'), { admissionNo: 'SP-2026-00041', className: '6', status: 'active' });
    });
    const db = env.authenticatedContext('linked-student-user').firestore();
    await assertSucceeds(getDoc(doc(db, 'students/student-record-41')));
    await assertFails(getDoc(doc(db, 'students/someone-elses-record')));
  });

  it('allows students and linked parents to read only their own generated report cards', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/report-student'), { role: 'student', approvalStatus: 'approved' });
      await setDoc(doc(db, 'users/report-parent'), { role: 'parent', approvalStatus: 'approved', linkedStudentIds: ['report-student'] });
      await setDoc(doc(db, 'students/report-student'), { name: 'Report Student' });
      await setDoc(doc(db, 'reports/card-own'), { reportType: 'report_card', studentId: 'report-student', percentage: 88 });
      await setDoc(doc(db, 'reports/card-other'), { reportType: 'report_card', studentId: 'someone-else', percentage: 55 });
      await setDoc(doc(db, 'reports/finance'), { reportType: 'finance_reconciliation', studentId: 'report-student' });
    });
    const student = env.authenticatedContext('report-student').firestore();
    const parent = env.authenticatedContext('report-parent').firestore();
    await assertSucceeds(getDoc(doc(student, 'reports/card-own')));
    await assertFails(getDoc(doc(student, 'reports/card-other')));
    await assertFails(getDoc(doc(student, 'reports/finance')));
    await assertSucceeds(getDoc(doc(parent, 'reports/card-own')));
    await assertFails(getDoc(doc(parent, 'reports/card-other')));
  });

  it('denies fee payments with an invalid month or a mismatched fee structure class', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'students/fee-student'), { className: '6' });
      await setDoc(doc(db, 'feeStructures/fee-class-5'), { className: '5', amount: 1000, frequency: 'monthly' });
    });
    const db = env.authenticatedContext('admin-fee-month', { admin: true }).firestore();
    const base = { studentId: 'fee-student', studentName: 'Student', feeStructureId: 'fee-class-5', amount: 1000, createdBy: 'admin-fee-month', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), receiptNo: 'FEE-2026-000009' };
    await assertFails(setDoc(doc(db, 'feePayments/invalid-month'), {...base, month: 'November 2026'}));
    await assertFails(setDoc(doc(db, 'feePayments/wrong-class'), {...base, month: '2026-11'}));
  });
  it('allows an approved parent to read all Admin-linked children and their fee records', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/multi-parent'), { role: 'parent', approvalStatus: 'approved', linkedStudentId: 'child-a', linkedStudentIds: ['child-a', 'child-b'], linkedStudentClasses: ['4', '7'] });
      await setDoc(doc(db, 'students/child-a'), { admissionNo: 'SP-2026-00051', className: '4' });
      await setDoc(doc(db, 'students/child-b'), { admissionNo: 'SP-2026-00052', className: '7' });
      await setDoc(doc(db, 'students/child-c'), { admissionNo: 'SP-2026-00053', className: '8' });
      await setDoc(doc(db, 'feePayments/payment-b'), { studentId: 'child-b', amount: 1000 });
    });
    const db = env.authenticatedContext('multi-parent').firestore();
    await assertSucceeds(getDoc(doc(db, 'students/child-a')));
    await assertSucceeds(getDoc(doc(db, 'students/child-b')));
    await assertFails(getDoc(doc(db, 'students/child-c')));
    await assertSucceeds(getDoc(doc(db, 'feePayments/payment-b')));
  });


  it('allows teachers to read only their own attendance and payroll records', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users/hr-teacher'), { role: 'teacher', approvalStatus: 'approved', teacherId: 'TCH-2026-00101' });
      await setDoc(doc(db, 'teacherAttendance/own-day'), { teacherUid: 'hr-teacher', teacherId: 'TCH-2026-00101', date: '2026-11-01', status: 'Present' });
      await setDoc(doc(db, 'teacherAttendance/other-day'), { teacherUid: 'other-teacher', teacherId: 'TCH-2026-00102', date: '2026-11-01', status: 'Absent' });
      await setDoc(doc(db, 'teacherPayroll/own-month'), { teacherUid: 'hr-teacher', month: '2026-11', netSalary: 50000 });
      await setDoc(doc(db, 'teacherPayroll/other-month'), { teacherUid: 'other-teacher', month: '2026-11', netSalary: 60000 });
    });
    const db = env.authenticatedContext('hr-teacher').firestore();
    await assertSucceeds(getDoc(doc(db, 'teacherAttendance/own-day')));
    await assertFails(getDoc(doc(db, 'teacherAttendance/other-day')));
    await assertSucceeds(getDoc(doc(db, 'teacherPayroll/own-month')));
    await assertFails(getDoc(doc(db, 'teacherPayroll/other-month')));
    await assertFails(setDoc(doc(db, 'teacherPayroll/forged'), { teacherUid: 'hr-teacher', month: '2026-11', netSalary: 999999 }));
  });

  it('allows approved teachers to submit their own leave requests but not approve them', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/leave-teacher'), { role: 'teacher', approvalStatus: 'approved', teacherId: 'TCH-2026-00070' });
    });
    const db = env.authenticatedContext('leave-teacher').firestore();
    await assertSucceeds(setDoc(doc(db, 'leaveRequests/own'), { teacherUid: 'leave-teacher', teacherId: 'TCH-2026-00070', teacherName: 'Teacher Name', reason: 'Medical appointment', startDate: '2026-11-10', endDate: '2026-11-11', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, 'leaveRequests/own'), { status: 'approved' }));
    await assertFails(setDoc(doc(db, 'leaveRequests/forged'), { teacherUid: 'someone-else', teacherId: 'TCH-2026-00070', teacherName: 'Teacher Name', reason: 'Forged request', startDate: '2026-11-10', endDate: '2026-11-11', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

  it('rejects invalid teacher leave dates and extra approval fields', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/leave-guard'), { role: 'teacher', approvalStatus: 'approved', teacherId: 'TCH-2026-00091' });
    });
    const db = env.authenticatedContext('leave-guard').firestore();
    await assertFails(setDoc(doc(db, 'leaveRequests/bad-date'), {
      teacherUid: 'leave-guard', teacherId: 'TCH-2026-00091', reason: 'Annual leave',
      startDate: '2026-11-15', endDate: '2026-11-10', status: 'pending',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db, 'leaveRequests/forged-review'), {
      teacherUid: 'leave-guard', teacherId: 'TCH-2026-00091', reason: 'Annual leave',
      startDate: '2026-11-10', endDate: '2026-11-15', status: 'approved',
      reviewedBy: 'leave-guard', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  it('allows users to update their own profile upload metadata but not their role', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/profile-owner'), { role: 'pending', approvalStatus: 'pending', displayName: 'Original', phone: '' });
    });
    const db = env.authenticatedContext('profile-owner').firestore();
    await assertSucceeds(updateDoc(doc(db, 'users/profile-owner'), { photoUrl: 'https://example.invalid/photo.jpg' }));
    await assertSucceeds(updateDoc(doc(db, 'users/profile-owner'), { uploadedDocuments: [{ name: 'id.pdf', url: 'https://example.invalid/id.pdf', storagePath: 'userDocuments/profile-owner/id.pdf', contentType: 'application/pdf' }] }));
    await assertFails(updateDoc(doc(db, 'users/profile-owner'), { role: 'admin' }));
  });


  it('restricts profile document storage to the owning user or an Admin', async () => {
    const owner = env.authenticatedContext('storage-owner').storage();
    const stranger = env.authenticatedContext('storage-stranger').storage();
    const metadata = { contentType: 'image/jpeg' };
    await assertSucceeds(uploadBytes(ref(owner, 'userProfiles/storage-owner/avatar.jpg'), new Uint8Array([1, 2, 3]), metadata));
    await assertFails(uploadBytes(ref(stranger, 'userProfiles/storage-owner/other.jpg'), new Uint8Array([1, 2, 3]), metadata));
    await assertFails(uploadBytes(ref(owner, 'userDocuments/storage-owner/not.exe'), new Uint8Array([1, 2, 3]), { contentType: 'application/octet-stream' }));
  });


  it('restricts notification inbox access to the intended recipient', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'notifications/n1'), { recipientUid: 'notify-user', isRead: false, title: 'Test' });
    });
    const owner = env.authenticatedContext('notify-user').firestore();
    const stranger = env.authenticatedContext('notify-stranger').firestore();
    await assertSucceeds(getDoc(doc(owner, 'notifications/n1')));
    await assertSucceeds(updateDoc(doc(owner, 'notifications/n1'), { isRead: true }));
    await assertFails(getDoc(doc(stranger, 'notifications/n1')));
    await assertFails(updateDoc(doc(owner, 'notifications/n1'), { title: 'Tampered' }));
  });

  it('denies fee payment update and delete even for Admin', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'feePayments/f1'), { amount: 10 });
    });
    const db = env.authenticatedContext('a3', { admin: true }).firestore();
    await assertFails(updateDoc(doc(db, 'feePayments/f1'), { amount: 20 }));
    const { deleteDoc } = require('firebase/firestore');
    await assertFails(deleteDoc(doc(db, 'feePayments/f1')));
  });
});
