# SchoolPro RC7 — QA / Audit Report (Urdu)

## RC7 میں شامل اور اس ریویژن میں تبدیل شدہ سورس

### Registration / identity / approval
- Student، Teacher اور Parent درخواستیں `pending` رہتی ہیں؛ Firebase Auth email verification link بھیجا جاتا ہے۔
- Approval/rejection Admin custom claim `admin: true` سے محفوظ Cloud Callable Functions کے ذریعے ہوتی ہے۔ Approval Auth `emailVerified`، Auth email/profile email match، requested role، duplicate canonical profile اور parent child Admission No کی جانچ کرتی ہے۔
- Approval کے بعد server-generated sequential Student Admission No / Teacher ID / Parent ID اور canonical profile record transaction میں بنتے ہیں؛ stale/missing counters کی صورت میں موجودہ IDs سے collision query کر کے اگلا unique ID منتخب ہوتا ہے۔
- Admin manual student enrolment بھی server callable سے unique Admission No جاری کرتا ہے؛ بعد میں email-verified pending Student login کو موجودہ enrolment document سے attach کیا جا سکتا ہے، نیا duplicate record نہیں بنتا۔ Student registration میں موجودہ Admission No optional درج کرنے پر Admin approval flow خود existing record attach کرتا ہے۔
- Rejection Function میں Auth user email lookup کی خرابی درست کی گئی؛ اب Auth email/profile email match چیک ہوتا ہے۔

### Profiles / uploads
- Registration اور My Profile میں date of birth، gender، address، emergency contact اور role-specific معلومات (Student guardian/previous school، Teacher qualification/subjects/experience، Parent relationship/occupation) شامل ہیں۔
- `assignTeacherToStudent` callable Teacher ID کو active teacher record سے validate کرکے student assignment اور audit log بناتا ہے۔
- `updateOwnSchoolProfile` callable صرف authenticated user کے اپنے غیر privileged fields کو update کرتا ہے اور canonical role profile کے ساتھ transaction میں sync کرتا ہے۔
- Admin pending registration کو edit کر سکتا ہے؛ approval function تمام role-specific required fields دوبارہ validate کرتا ہے۔
- Student/Teacher/Parent اور financial/history records کے لیے generic permanent delete UI بند ہے؛ student/teacher/parent accounts کو deactivate/suspend کر کے history محفوظ رکھی جاتی ہے۔
- Pending registration screen سے بھی profile photo اور ID/education documents upload کیے جا سکتے ہیں تاکہ Admin approval سے پہلے review کر سکے۔ Mobile اور Admin Web میں profile image/document workflows شامل ہیں۔
- Storage path owner/Admin rules، image/PDF MIME restrictions اور size limits لاگو ہیں۔ User profile metadata میں 20-document cap بھی UI/Rules میں ہے۔

### Parent / teacher workflows
- Parent کے لیے Admin-controlled multi-child linking (1–10 Admission Numbers)؛ transaction کے اندر student records دوبارہ validate ہوتے ہیں۔
- Parent dashboard میں linked children کے لیے attendance، fee payments، results، exams، timetable، homework، notices، notifications اور report cards کے queries ہیں۔
- Teacher leave submission، Admin approval/rejection، audit record اور teacher in-app notification۔ تاریخ کی شکل اور start/end ترتیب validate ہوتی ہے۔
- Teacher HR میں Admin-managed staff attendance، monthly payroll records (base + allowances - deductions = net salary validation)، teacher-only record reads، اور salary paid ہونے پر teacher in-app notification شامل ہیں۔
- Teacher attendance read scope assigned student ID کے مطابق ہے؛ teacher اپنے assigned students کی attendance reports پڑھ سکتا ہے۔
- Parent in-app notifications absent/leave attendance (create/update)، new results، fee payments اور published notices پر بنتی ہیں؛ deterministic IDs duplicate event retry notifications سے بچاتے ہیں۔

### Fees / homework / reporting
- Fee payment immutable ہے؛ sequential receipt، counter اور audit entry ایک transaction میں۔ Payment میں student، matching class fee structure، `YYYY-MM` period، positive amount اور issued receipt number لازم ہیں۔
- Fee structure form میں billing frequency (monthly/term/annual/one-time) شامل ہے۔
- Student homework submission کا deterministic document ID ہے؛ ایک student ایک assignment کے لیے duplicate submission نہیں کر سکتا۔ Teacher review/marks/feedback الگ scoped update ہے۔
- Admin Web میں individual student report card generation/save، student/parent report-card read access، finance reconciliation، configured monthly dues estimate، attendance report، CSV exports، browser Print/Save-as-PDF اور 80mm receipt print layout شامل ہیں۔
- Monthly dues صرف explicit `frequency=monthly` structures اور matching `feeStructureId` + `YYYY-MM` payments پر calculate ہوتے ہیں۔ غیر مربوط/legacy payments الگ unallocated دکھائے جاتے ہیں۔

## اس ریویژن میں درست کیے گئے واضح مسائل
- Published notice کے Create اور Update کے الگ الگ triggers کو ایک `onDocumentWritten` trigger میں یکجا کیا؛ اب صرف نئی published notice یا draft-to-published transition پر اطلاع بنتی ہے۔
- Notice notification deterministic ID کے ساتھ transaction میں صرف عدم موجودگی پر create ہوتی ہے؛ event retry یا دوبارہ execution پہلے سے پڑھی گئی notification کا `isRead` واپس `false` نہیں کرتا اور `createdAt` بھی تبدیل نہیں ہوتا۔
- Firestore Rules میں `teacherAttendance` کی duplicate match declaration ختم کی؛ approved teacher کی اپنی attendance read اور Admin-only writes والی اصل اجازت برقرار ہے۔ Root اور Admin Web rules دونوں synchronized ہیں۔
- Notice eligibility اور notification idempotency کے regression tests شامل کیے؛ release preflight اور GitHub CI میں نئے source/test syntax checks شامل ہیں۔
- `rejectSchoolRegistration` میں missing Auth user lookup درست کیا گیا۔
- Parent-child linking transaction میں student records کی fresh revalidation شامل کی گئی؛ inactive/deleted students link نہیں ہو سکتے۔
- Teacher leave Rules میں allowed keys، date format/order اور server timestamps validate ہوتے ہیں۔
- Fee payment Rules اب matching student/fee structure class اور valid billing month چیک کرتے ہیں۔
- Homework Rules duplicate IDs، client-added marks/review fields اور invalid submit timestamps روکتے ہیں۔
- Parent report cards کے لیے محدود read rule اور required Firestore composite index شامل کیا گیا۔
- GitHub CI artifact path درست کیا، widget tests کو Firebase initialization سے آزاد کیا، اور APK CI build کو debug-verification label دیا (Play Store release signing موجود نہیں)۔

## اس ماحول میں حقیقتاً چلائے گئے checks
- `node --check functions/index.js` — PASS
- `node --check functions/notice_notifications.js` — PASS
- `node --check tests/rules.test.js` — PASS
- `node --check tests/functions.test.js` — PASS
- Published-notice helper regression checks (local Node assertions) — PASS
- `firebase.json`، `firestore.indexes.json`، functions/tests package JSON — PASS parse
- Mobile/Admin pubspec YAML اور GitHub Actions YAML — PASS parse
- Root اور Admin Web Firestore Rules copies byte-identical — PASS

## ابھی نہیں چل سکے / باقی لازمی verification
- Flutter/Dart SDK اس runtime میں دستیاب نہیں: `flutter analyze`، mobile/admin widget tests، Android APK build اور Admin Web build نہیں چل سکے۔
- npm test dependencies install timeout کی وجہ سے Firebase Emulator Rules tests نہیں چل سکے۔
- Firebase CLI اور authenticated project session دستیاب نہیں: Functions/Rules/Storage/Hosting deployment اور live role-based end-to-end smoke tests نہیں کیے گئے۔
- GitHub CI ابھی run نہیں ہوئی؛ اس کے کامیاب ہونے کا دعویٰ نہیں کیا جا رہا۔

## اہم functional حدود (انہیں مکمل قرار نہ دیں)
- Email numeric OTP نہیں؛ Firebase email verification link استعمال ہوتا ہے۔ Numeric OTP کے لیے email delivery provider اور secret credentials درکار ہیں۔
- Parent notifications Firestore in-app notifications ہیں؛ FCM push، SMS اور external email configured نہیں۔
- Finance report per-run caps: 2,000 payments، 2,000 expenses، 3,000 students، 500 fee structures۔ Bank reconciliation/bank statement import نہیں۔
- Teacher payroll records Admin manually enters and reconciles; bank transfer integration, tax/statutory payroll automation and payslip emailing are not configured.
- Monthly dues estimate صرف configured monthly structures کے لیے؛ term/annual/one-time dues کے لیے الگ billing-cycle engine اور legacy data normalization باقی ہے۔
- Report card ایک student فی run generate ہوتا ہے؛ bulk class-wide generation/publishing workflow ابھی نہیں۔
- PDF browser Print/Save-as-PDF سے بنتی ہے؛ thermal output 80mm print layout ہے، printer integration browser/OS پر منحصر ہے۔
- Android CI APK debug-signed ہے؛ Play Store upload signing کے لیے مالک کی private upload key درکار ہے۔

## Release فیصلہ
**RC7 = Expanded Release Candidate، 100% verified / Production Final نہیں۔**
کوئی live Firebase deployment، Firestore document migration، deletion یا reset اس پیکج کی تیاری کے دوران نہیں ہوا۔ Deployment script `--check` اور `--deploy` کو الگ رکھتی ہے؛ `--deploy` صرف Functions، Firestore rules/indexes، Storage rules اور Admin Hosting deploy کرتا ہے، اور پہلے مقامی checks کامیاب ہونا ضروری ہے۔
