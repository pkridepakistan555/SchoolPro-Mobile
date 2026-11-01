# SchoolPro — RC7 Expanded Release Candidate

یہ پیکج SchoolPro Android ایپ، الگ Admin Web، Firebase Functions، Firestore/Storage Rules، indexes، emulator tests اور CI workflow پر مشتمل ہے۔ Firebase project `school-e8d44` configured ہے۔ پیکج بناتے وقت کوئی live Firebase deployment یا live-data migration نہیں کی گئی۔

## RC7 میں شامل فیچرز

- Student، Teacher اور Parent کی registration درخواست؛ DOB، جنس، پتہ، emergency contact اور role-specific پروفائل؛ Firebase email verification link؛ Admin edit/approval/rejection اور server-issued منفرد IDs۔
- Admin-only Cloud Functions: approval، rejection، manual enrolment کے لیے unique Admission No، pending student login کو existing enrolment سے attach کرنا، Parent کے 1–10 بچوں کی linking، Teacher leave review اور محفوظ profile update۔ Existing Admission No درج کرنے پر Admin approval کے دوران duplicate Student record نہیں بنتا۔
- Student/Teacher/Parent role dashboards، scoped Firestore reads اور Admin-only school-wide writes۔
- `updateOwnSchoolProfile` callable کے ذریعے authenticated صارف اپنے غیر privileged profile fields اپ ڈیٹ کر سکتا ہے اور canonical role profile کے ساتھ sync ہوتا ہے۔
- Pending screen سے بھی profile photo اور شناختی/تعلیمی دستاویزات Firebase Storage میں upload؛ Admin approval screen سے review/open links۔
- Teacher leave request، Admin review، teacher notification؛ Admin-managed teacher attendance اور monthly payroll، salary formula validation اور paid ہونے پر teacher notification۔
- Parent dashboard میں متعدد بچوں کا ریکارڈ، attendance، fee payments، results، timetable، homework، notices اور in-app notifications۔
- Attendance absent/leave، نئے results، fee payment اور published notices پر Parent کے لیے in-app notifications۔
- Fee payment کے ساتھ sequential receipt number، counter اور audit entry ایک transaction میں؛ fee payment records immutable۔ Fee payment کو matching fee structure، student class اور `YYYY-MM` month کے ساتھ validate کیا جاتا ہے۔
- Student homework submission کے لیے deterministic document ID؛ duplicate submissions روکی جاتی ہیں؛ teacher marks/feedback دے سکتا ہے۔
- Admin Web میں report-card generation/save، Student/Parent mobile dashboard پر متعلقہ report card، finance reconciliation، configured monthly dues estimate، attendance report، CSV export، Print/Save-as-PDF اور 80mm receipt print layout۔
- GitHub Actions میں Flutter analyze/tests/build اور Firebase Emulator Rules tests کی workflow۔

## Firebase اور سکیورٹی

- Admin اکاؤنٹ کے Firebase Auth ID token میں `admin: true` custom claim پہلے سے موجود ہونا ضروری ہے۔ Client خود کو Admin نہیں بنا سکتا۔
- Cloud Functions `asia-south1` میں configured ہیں۔
- Firestore Rules اور Admin copy byte-identical ہونی چاہیے؛ release script یہ check کرتی ہے۔
- کوئی service-account private key یا Android signing key اس پیکج میں شامل نہیں۔

## Verification

اس ماحول میں کامیاب checks: `node --check functions/index.js`، `node --check tests/rules.test.js`، JSON/YAML parsing، اور Firestore Rules copies کی یکسانیت۔ Flutter/Dart، Firebase CLI اور مکمل npm test dependencies دستیاب نہ ہونے کی وجہ سے Flutter analyze/build اور Emulator tests یہاں نہیں چل سکے۔ اس لیے RC7 کو ابھی 100% verified یا Production Final نہیں کہا جا سکتا۔

Termux میں مکمل جانچ کے لیے:

```bash
cd ~/SchoolPro-RC7
bash scripts/schoolpro_release.sh --check
```

تمام checks کامیاب ہونے کے بعد، اور Firebase project کی authenticated CLI session کے ساتھ، آپ کی دی ہوئی اجازت کے مطابق deploy کے لیے:

```bash
bash scripts/schoolpro_release.sh --deploy
```

`--deploy` صرف Functions، Firestore Rules/indexes، Storage Rules اور Admin Hosting deploy کرتا ہے؛ Firestore documents delete/reset یا migrate نہیں کرتا۔ پھر بھی live deployment کے بعد Admin/Teacher/Student/Parent اکاؤنٹس سے عملی smoke tests لازمی ہیں۔

## ابھی کی واضح حدود

- Registration میں numeric email OTP نہیں؛ Firebase email verification link استعمال ہوتا ہے۔ Numeric OTP کے لیے email delivery provider اور اس کی secret credentials درکار ہیں۔
- Parent notifications in-app ہیں؛ FCM push، SMS یا بیرونی email notifications configured نہیں۔
- Monthly dues صرف ان fee structures پر بنتے ہیں جن کی `frequency` واضح طور پر `monthly` ہو اور payment میں matching `feeStructureId` اور `YYYY-MM` ہو۔ پرانے/non-monthly records کے لیے Admin configuration درکار ہے۔
- Finance report کی حد 2,000 payments، 2,000 expenses، 3,000 students اور 500 fee structures فی run ہے؛ bank balance reconciliation شامل نہیں۔
- Report card فی طالب علم generate ہوتا ہے؛ bulk class-wide report publishing شامل نہیں۔
- PDF براؤزر کے Print/Save as PDF سے بنتا ہے؛ 80mm thermal layout میں Admin اپنی printer منتخب کرتا ہے۔
- APK verification debug signing کے ساتھ ہے؛ Play Store release کے لیے مالک کی private upload key درکار ہے، جو اس پیکج میں شامل نہیں۔

مکمل عملی verification اور live smoke tests کے بعد ہی Production Final کا فیصلہ کیا جائے۔

## GitHub پر محفوظ Push

RC7 کو پہلے verification branch پر بھیجنے کے لیے Git، rsync اور GitHub write authentication درکار ہے:

```bash
bash scripts/push_github.sh
```

یہ موجودہ `main` clone کرتا ہے، اسے delete یا force-push نہیں کرتا، RC7 فائلیں merge کرتا ہے اور `schoolpro-rc7` branch پر push کرتا ہے۔ GitHub Actions کامیاب ہونے کے بعد PR کے ذریعے `main` میں merge کریں۔ اگر آپ نے CI پہلے ہی کامیابی سے چلا لی ہو تو براہِ راست main کے لیے:

```bash
bash scripts/push_github.sh --main
```

GitHub authentication Termux میں پہلے configure کریں؛ Personal Access Token کو ChatGPT یا کسی فائل میں نہ بھیجیں۔

**Billing نوٹ:** Firebase Cloud Functions (خصوصاً Gen 2) deploy کرنے کے لیے Firebase/Google Cloud project پر عموماً Blaze billing plan درکار ہوتا ہے۔ Deploy سے پہلے Billing/Usage limits دیکھیں؛ کوئی billing upgrade یا paid resource خودکار طور پر فعال نہیں کیا گیا۔
