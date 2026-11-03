# SchoolPro RC7 — Account & Permission Fixes

اس پیکیج میں درج ذیل تبدیلیاں شامل کی گئی ہیں:

- Admin dashboard میں Create School Account اسکرین: Student، Teacher اور Parent کے لیے۔
- `adminCreateSchoolUser` callable صرف `admin == true` custom claim والے صارف کو اجازت دیتی ہے؛ Firebase Auth اکاؤنٹ سرور پر بنتا ہے، password Firestore یا audit log میں محفوظ نہیں ہوتا، اور منفرد School ID سرور جاری کرتا ہے۔
- Admin-created account کو transaction کے اندر `users` اور canonical role collection میں approved/active بنایا جاتا ہے؛ Parent کے لیے موجودہ فعال طالب علم کا Admission Number validate/link ہوتا ہے۔
- User Approvals query اب `role == pending` اور `approvalStatus == pending` دونوں دیکھتی ہے اور صرف student/teacher/parent درخواستیں دکھاتی ہے۔
- Attendance collection میں ٹیچر کو اپنے `markedBy == auth.uid` ریکارڈ پڑھنے کی اجازت شامل ہے؛ دوسرے صارفین کی رسائی موجودہ محدود شرائط کے مطابق ہے۔
- Root اور Admin Web Firestore Rules دونوں میں یکساں متعلقہ تبدیلی کی گئی ہے۔

## لازمی operational نوٹ

1. اس ZIP میں source changes ہیں؛ Firebase پر کوئی deployment نہیں کی گئی۔
2. `teacherAttendance` اور `teacherPayroll` کی موجودہ access شرط برقرار ہے: approved teacher profile اور record کا `teacherUid == Firebase Auth UID` ہونا ضروری ہے۔ اگر live documents میں `teacherUid` مختلف یا غائب ہے تو اسے محفوظ data migration کے ذریعے درست کرنا ہوگا؛ Rules کو کھول کر دوسرے اساتذہ کی payroll ظاہر نہیں کی گئی۔
3. Homework Submissions کی read شرط teacher profile کے `teacherId` اور submission کے `teacherId` کی مطابقت برقرار رکھتی ہے۔ غلط یا خالی پرانے records کو الگ review/migration درکار ہوگی۔
4. عام self-registration کے لیے email verification لازمی برقرار ہے۔ Admin کے ذریعے براہِ راست بنائے گئے اکاؤنٹ کو Admin SDK `emailVerified: true` کے ساتھ بناتا ہے؛ Admin کو temporary password محفوظ طریقے سے متعلقہ صارف تک پہنچانا ہوگا۔
5. موجودہ Firebase users، students، teachers، parents یا دوسرے live collections کو delete/reset نہیں کیا جاتا۔
