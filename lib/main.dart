import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin_modules.dart';
import 'firebase_options.dart';
import 'profile_documents_screen.dart';
import 'teacher_leave_screen.dart';
import 'admin_workflows_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SchoolProApp());
}

class SchoolProApp extends StatefulWidget {
  const SchoolProApp({super.key});

  @override
  State<SchoolProApp> createState() => _SchoolProAppState();
}

class _SchoolProAppState extends State<SchoolProApp> {
  bool urdu = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchoolPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          if (snapshot.hasError) {
            return ErrorScreen(message: snapshot.error.toString());
          }
          if (snapshot.data == null) {
            return AuthScreen(
              urdu: urdu,
              onLanguageChanged: (value) {
                setState(() => urdu = value);
              },
            );
          }
          return UserGate(user: snapshot.data!, urdu: urdu);
        },
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(message),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.urdu,
    required this.onLanguageChanged,
  });

  final bool urdu;
  final ValueChanged<bool> onLanguageChanged;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final qualificationController = TextEditingController();
  final subjectController = TextEditingController();
  final classController = TextEditingController();
  final childAdmissionController = TextEditingController();
  final existingAdmissionController = TextEditingController();
  final dobController = TextEditingController();
  final addressController = TextEditingController();
  final emergencyNameController = TextEditingController();
  final emergencyPhoneController = TextEditingController();
  final guardianNameController = TextEditingController();
  final guardianPhoneController = TextEditingController();
  final previousSchoolController = TextEditingController();
  final experienceController = TextEditingController(text: '0');
  final relationshipController = TextEditingController();
  final occupationController = TextEditingController();
  String gender = 'prefer_not_to_say';
  String requestedRole = 'student';
  bool registering = false;
  bool busy = false;
  bool hidePassword = true;
  String message = '';

  String t(String english, String urdu) => widget.urdu ? urdu : english;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    phoneController.dispose();
    qualificationController.dispose();
    subjectController.dispose();
    classController.dispose();
    childAdmissionController.dispose(); existingAdmissionController.dispose();
    dobController.dispose(); addressController.dispose();
    emergencyNameController.dispose(); emergencyPhoneController.dispose();
    guardianNameController.dispose(); guardianPhoneController.dispose();
    previousSchoolController.dispose(); experienceController.dispose();
    relationshipController.dispose(); occupationController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    if (registering) {
      final dob = DateTime.tryParse(dobController.text.trim());
      if (dob == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dobController.text.trim()) || dob.isAfter(DateTime.now()) || addressController.text.trim().length < 5) {
        setState(() => message = t('Enter a valid past date of birth and a complete address.', 'درست تاریخِ پیدائش اور مکمل پتہ درج کریں۔'));
        return;
      }
      if (requestedRole == 'student' && (guardianNameController.text.trim().length < 2 || guardianPhoneController.text.trim().isEmpty || classController.text.trim().isEmpty)) {
        setState(() => message = t('Student registration requires class and guardian name/phone.', 'طالب علم کی درخواست کے لیے جماعت اور سرپرست کا نام/فون ضروری ہے۔'));
        return;
      }
      if (requestedRole == 'teacher' && (qualificationController.text.trim().isEmpty || subjectController.text.trim().isEmpty || int.tryParse(experienceController.text.trim()) == null || int.parse(experienceController.text.trim()) < 0 || int.parse(experienceController.text.trim()) > 60)) {
        setState(() => message = t('Teacher registration requires qualification, subjects and experience from 0 to 60 years.', 'استاد کی درخواست کے لیے قابلیت، مضامین اور 0 سے 60 سال کا تجربہ درج کریں۔'));
        return;
      }
      if (requestedRole == 'parent' && (childAdmissionController.text.trim().isEmpty || relationshipController.text.trim().isEmpty)) {
        setState(() => message = t('Parent registration requires the child Admission Number and relationship.', 'والدین کی درخواست کے لیے بچے کا داخلہ نمبر اور رشتہ درج کرنا ضروری ہے۔'));
        return;
      }
    }

    setState(() {
      busy = true;
      message = '';
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (registering) {
        if (nameController.text.trim().length < 2) {
          throw FirebaseAuthException(code: 'invalid-display-name');
        }
        final result = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final user = result.user!;

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': email,
          'name': nameController.text.trim(),
          'phone': phoneController.text.trim(),
          'qualification': qualificationController.text.trim(),
          'subjects': subjectController.text.trim(),
          'currentClass': classController.text.trim(),
          'childAdmissionNo': childAdmissionController.text.trim(),
          'existingAdmissionNo': existingAdmissionController.text.trim(),
          'dateOfBirth': dobController.text.trim(),
          'gender': gender,
          'address': addressController.text.trim(),
          'emergencyContactName': emergencyNameController.text.trim(),
          'emergencyContactPhone': emergencyPhoneController.text.trim(),
          'guardianName': guardianNameController.text.trim(),
          'guardianPhone': guardianPhoneController.text.trim(),
          'previousSchool': previousSchoolController.text.trim(),
          'experienceYears': int.tryParse(experienceController.text.trim()) ?? 0,
          'relationshipToStudent': relationshipController.text.trim(),
          'occupation': occupationController.text.trim(),
          'requestedRole': requestedRole,
          'role': 'pending',
          'approvalStatus': 'pending',
          'profileCompleted': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await user.sendEmailVerification();
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;
        setState(() {
          message = t(
            'Verification link sent. Verify your email, then log in. Admin approval is also required.',
            'تصدیقی لنک بھیج دیا گیا ہے۔ ای میل کی تصدیق کرکے لاگ اِن کریں۔ ایڈمن کی منظوری بھی ضروری ہے۔',
          );
        });
      } else {
        final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = result.user!;

        if (!user.emailVerified) {
          await user.sendEmailVerification();
          await FirebaseAuth.instance.signOut();

          if (!mounted) return;
          setState(() {
            message = t(
              'Verify your email using the link sent to you. A new link has been sent.',
              'ای میل میں بھیجے گئے تصدیقی لنک کو کھولیں۔ نیا لنک بھی بھیج دیا گیا ہے۔',
            );
          });
          return;
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => message = authError(e.code, widget.urdu));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        message = t(
          'Could not complete the request. Check your internet and Firebase setup.',
          'درخواست مکمل نہیں ہوئی۔ انٹرنیٹ اور Firebase سیٹنگز چیک کریں۔',
        );
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        message = t(
          'Enter your email address above first.',
          'پہلے اوپر اپنا درست ای میل ایڈریس درج کریں۔',
        );
      });
      return;
    }

    setState(() {
      busy = true;
      message = '';
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() {
        message = t(
          'If an account exists for this email, a password reset link has been sent.',
          'اگر اس ای میل پر اکاؤنٹ موجود ہے تو پاس ورڈ ری سیٹ لنک بھیج دیا گیا ہے۔',
        );
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => message = authError(e.code, widget.urdu));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        message = t(
          'Could not send reset email. Check your internet and try again.',
          'ری سیٹ ای میل نہیں بھیجی جا سکی۔ انٹرنیٹ چیک کرکے دوبارہ کوشش کریں۔',
        );
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String authError(String code, bool urdu) {
    const en = {
      'invalid-display-name': 'Enter your full name (at least 2 characters).',
      'invalid-email': 'The email address is invalid.',
      'user-not-found': 'No account found. Please register first.',
      'wrong-password': 'Incorrect email or password.',
      'invalid-credential': 'Incorrect email or password.',
      'email-already-in-use': 'This email is already registered.',
      'weak-password': 'Use a stronger password (at least 6 characters).',
      'network-request-failed': 'Network error. Check your internet.',
      'too-many-requests': 'Too many attempts. Try again later.',
      'operation-not-allowed':
          'Email/password sign-in is disabled in Firebase.',
    };
    const ur = {
      'invalid-display-name': 'اپنا مکمل نام درج کریں (کم از کم دو حروف)۔',
      'invalid-email': 'ای میل کا پتہ درست نہیں۔',
      'user-not-found': 'اکاؤنٹ نہیں ملا۔ پہلے رجسٹریشن کریں۔',
      'wrong-password': 'ای میل یا پاس ورڈ غلط ہے۔',
      'invalid-credential': 'ای میل یا پاس ورڈ غلط ہے۔',
      'email-already-in-use': 'یہ ای میل پہلے سے رجسٹرڈ ہے۔',
      'weak-password': 'کم از کم 6 حروف کا مضبوط پاس ورڈ رکھیں۔',
      'network-request-failed': 'انٹرنیٹ کنکشن چیک کریں۔',
      'too-many-requests': 'بہت زیادہ کوششیں ہوئیں۔ بعد میں دوبارہ کریں۔',
      'operation-not-allowed':
          'Firebase میں Email/Password لاگ اِن فعال نہیں ہے۔',
    };
    return (urdu ? ur : en)[code] ?? (urdu ? 'خرابی: $code' : 'Error: $code');
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = widget.urdu;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => widget.onLanguageChanged(!isUrdu),
                        icon: const Icon(Icons.language),
                        label: Text(isUrdu ? 'English' : 'اردو'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Image.asset(
                      'assets/images/schoolpro_logo.png',
                      height: 110,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.school_rounded,
                        size: 76,
                        color: Color(0xFF176B5B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SchoolPro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('School Management System', 'اسکول مینجمنٹ سسٹم'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      registering
                          ? t('Create account', 'اکاؤنٹ بنائیں')
                          : t('Welcome back', 'خوش آمدید'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: isUrdu ? TextAlign.right : TextAlign.left,
                    ),
                    const SizedBox(height: 20),
                    if (registering) ...[
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: t('Full name', 'مکمل نام'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (value) => (value ?? '').trim().length < 2
                            ? t('Enter your full name.', 'اپنا مکمل نام درج کریں۔')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: t('Phone number', 'فون نمبر'),
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 12),
                      TextFormField(controller: dobController, decoration: InputDecoration(labelText: t('Date of birth (YYYY-MM-DD)', 'تاریخِ پیدائش (YYYY-MM-DD)')), validator: (v) => DateTime.tryParse((v ?? '').trim()) == null ? t('Enter date as YYYY-MM-DD.', 'تاریخ YYYY-MM-DD میں درج کریں۔') : null),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: gender,
                        decoration: InputDecoration(labelText: t('Gender', 'جنس')),
                        items: [
                          DropdownMenuItem(value: 'male', child: Text(t('Male', 'مرد'))),
                          DropdownMenuItem(value: 'female', child: Text(t('Female', 'عورت'))),
                          DropdownMenuItem(value: 'other', child: Text(t('Other', 'دیگر'))),
                          DropdownMenuItem(value: 'prefer_not_to_say', child: Text(t('Prefer not to say', 'بتانا نہیں چاہتے'))),
                        ],
                        onChanged: busy ? null : (v) { if (v != null) setState(() => gender = v); },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: addressController, maxLines: 2, decoration: InputDecoration(labelText: t('Residential address', 'رہائشی پتہ'))),
                      const SizedBox(height: 12),
                      TextFormField(controller: emergencyNameController, decoration: InputDecoration(labelText: t('Emergency contact name (optional)', 'ہنگامی رابطہ نام (اختیاری)'))),
                      const SizedBox(height: 12),
                      TextFormField(controller: emergencyPhoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Emergency contact phone (optional)', 'ہنگامی رابطہ فون (اختیاری)'))),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: requestedRole,
                        decoration: InputDecoration(
                          labelText: t('Applying as', 'درخواست کا کردار'),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        items: [
                          DropdownMenuItem(value: 'student', child: Text(t('Student', 'طالب علم'))),
                          DropdownMenuItem(value: 'teacher', child: Text(t('Teacher', 'استاد'))),
                          DropdownMenuItem(value: 'parent', child: Text(t('Parent', 'والدین'))),
                        ],
                        onChanged: busy ? null : (value) {
                          if (value != null) setState(() => requestedRole = value);
                        },
                      ),
                      if (requestedRole == 'teacher') ...[
                        const SizedBox(height: 12),
                        TextFormField(controller: qualificationController, decoration: InputDecoration(labelText: t('Qualification', 'تعلیمی قابلیت'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: subjectController, decoration: InputDecoration(labelText: t('Subjects you teach', 'مضامین'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: experienceController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Teaching experience (years)', 'تدریسی تجربہ (سال)'))),
                      ],
                      if (requestedRole == 'student') ...[
                        const SizedBox(height: 12),
                        TextFormField(controller: classController, decoration: InputDecoration(labelText: t('Requested current class / grade', 'درخواست کردہ جماعت'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: guardianNameController, decoration: InputDecoration(labelText: t('Guardian full name', 'سرپرست کا مکمل نام'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: guardianPhoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Guardian phone number', 'سرپرست کا فون نمبر'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: previousSchoolController, decoration: InputDecoration(labelText: t('Previous school (optional)', 'پچھلا اسکول (اختیاری)'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: existingAdmissionController, decoration: InputDecoration(labelText: t('Existing Admission No (if already enrolled)', 'پہلے سے داخل طالب علم کا موجودہ داخلہ نمبر (اگر ہو)'))),
                      ],
                      if (requestedRole == 'parent') ...[
                        const SizedBox(height: 12),
                        TextFormField(controller: childAdmissionController, decoration: InputDecoration(labelText: t('Child Admission Number (required)', 'بچے کا داخلہ نمبر (ضروری)'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: relationshipController, decoration: InputDecoration(labelText: t('Relationship to student', 'طالب علم سے رشتہ'))),
                        const SizedBox(height: 12),
                        TextFormField(controller: occupationController, decoration: InputDecoration(labelText: t('Occupation (optional)', 'پیشہ (اختیاری)'))),
                      ],
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: t('Email address', 'ای میل ایڈریس'),
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (!v.contains('@') || !v.contains('.')) {
                          return t(
                            'Enter a valid email address.',
                            'درست ای میل ایڈریس درج کریں۔',
                          );
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      autofillHints: registering
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: t('Password', 'پاس ورڈ'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => hidePassword = !hidePassword),
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if ((value ?? '').length < 6) {
                          return t(
                            'Password must be at least 6 characters.',
                            'پاس ورڈ کم از کم 6 حروف کا ہونا چاہیے۔',
                          );
                        }
                        return null;
                      },
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (!registering) ...[
                      Align(
                        alignment: isUrdu
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy ? null : resetPassword,
                          child: Text(
                            t('Forgot password?', 'پاس ورڈ بھول گئے؟'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                registering
                                    ? t('Create account', 'اکاؤنٹ بنائیں')
                                    : t('Login', 'لاگ اِن'),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              registering = !registering;
                              message = '';
                            }),
                      child: Text(
                        registering
                            ? t(
                                'Already registered? Login',
                                'اکاؤنٹ موجود ہے؟ لاگ اِن کریں',
                              )
                            : t(
                                'New user? Create an account',
                                'نئے صارف ہیں؟ اکاؤنٹ بنائیں',
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        'New accounts require school admin approval.',
                        'نئے اکاؤنٹس کے لیے اسکول ایڈمن کی منظوری ضروری ہے۔',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UserGate extends StatelessWidget {
  const UserGate({super.key, required this.user, required this.urdu});

  final User user;
  final bool urdu;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          debugPrint('SCHOOLPRO PROFILE ERROR: ${snapshot.error}');
          return ErrorScreen(
            message: urdu
                ? 'صارف کا ریکارڈ نہیں پڑھا جا سکا۔ Firestore rules چیک کریں۔'
                : 'Could not read user profile. Check Firestore rules.',
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return ProfileMissingScreen(urdu: urdu);
        }

        final data = snapshot.data!.data() ?? {};
        final role = (data['role'] ?? 'pending').toString().toLowerCase();

        if ((data['approvalStatus'] ?? '').toString().toLowerCase() == 'suspended') {
          return AccountSuspendedScreen(urdu: urdu);
        }
        if (role == 'rejected' || (data['approvalStatus'] ?? '').toString().toLowerCase() == 'rejected') {
          return AccountRejectedScreen(urdu: urdu);
        }

        final allowed = ['admin', 'teacher', 'student', 'parent'];
        final approvalStatus =
            (data['approvalStatus'] ?? '').toString().toLowerCase();
        final requestedRole =
            (data['requestedRole'] ?? '').toString().toLowerCase();
        final hasIssuedId = switch (role) {
          'student' => (data['admissionNo'] ?? '').toString().isNotEmpty && ((data['linkedStudentId'] ?? user.uid).toString().isNotEmpty),
          'teacher' => (data['teacherId'] ?? '').toString().isNotEmpty,
          'parent' => (data['parentId'] ?? '').toString().isNotEmpty && (data['linkedStudentId'] ?? '').toString().isNotEmpty,
          'admin' => true,
          _ => false,
        };

        // A role label alone must never unlock a non-admin account. The
        // approval state, requested role, and server-issued identifier must
        // all agree before a school dashboard is shown.
        final approvedNonAdmin = role == 'admin' ||
            (approvalStatus == 'approved' &&
                requestedRole == role &&
                hasIssuedId);
        if (!allowed.contains(role) || !approvedNonAdmin) {
          return PendingScreen(urdu: urdu, user: user);
        }

        if (role == 'admin') {
          return AdminClaimGate(user: user, urdu: urdu);
        }

        return DashboardScreen(
          user: user,
          role: role,
          urdu: urdu,
          name: (data['name'] ?? user.email ?? 'SchoolPro User').toString(),
        );
      },
    );
  }
}

class AdminClaimGate extends StatelessWidget {
  const AdminClaimGate({super.key, required this.user, required this.urdu});
  final User user;
  final bool urdu;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<IdTokenResult>(
      future: user.getIdTokenResult(true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        final isAdmin = snapshot.hasData &&
            snapshot.data!.claims?['admin'] == true;
        if (!isAdmin) {
          return Scaffold(
            body: Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 12),
                Text(urdu
                    ? 'ایڈمن اکاؤنٹ کی تصدیق نہیں ہوئی۔ براہِ کرم مجاز ایڈمن اکاؤنٹ سے لاگ اِن کریں۔'
                    : 'Admin authorization could not be verified. Sign in with an authorized admin account.',
                  textAlign: TextAlign.center),
                const SizedBox(height: 16),
                const SignOutButton(urdu: false),
              ]),
            )),
          );
        }
        return DashboardScreen(
          user: user,
          role: 'admin',
          urdu: urdu,
          name: user.displayName ?? user.email ?? 'SchoolPro Admin',
        );
      },
    );
  }
}

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, required this.user, required this.urdu});
  final User user;
  final bool urdu;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  final _address = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _guardianName = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _previousSchool = TextEditingController();
  final _qualification = TextEditingController();
  final _subjects = TextEditingController();
  final _experience = TextEditingController();
  final _relationship = TextEditingController();
  final _occupation = TextEditingController();
  String _gender = 'prefer_not_to_say';
  bool _loaded = false;
  bool _saving = false;
  String _error = '';

  String t(String en, String ur) => widget.urdu ? ur : en;

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _dob.dispose(); _address.dispose();
    _emergencyName.dispose(); _emergencyPhone.dispose(); _guardianName.dispose();
    _guardianPhone.dispose(); _previousSchool.dispose(); _qualification.dispose();
    _subjects.dispose(); _experience.dispose(); _relationship.dispose(); _occupation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.length < 2 || name.length > 100 || phone.length > 30) {
      setState(() => _error = t(
        'Enter a name (2–100 characters) and a phone number up to 30 characters.',
        'نام 2 سے 100 حروف اور فون نمبر زیادہ سے زیادہ 30 حروف میں درج کریں۔',
      ));
      return;
    }
    setState(() { _saving = true; _error = ''; });
    try {
      final dob = _dob.text.trim();
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob) || DateTime.tryParse(dob) == null || DateTime.parse(dob).isAfter(DateTime.now()) || _address.text.trim().length < 5) {
        throw StateError('Enter a valid date of birth and a complete address.');
      }
      final profile = <String,dynamic>{
        'name': name, 'phone': phone, 'dateOfBirth': dob, 'gender': _gender,
        'address': _address.text.trim(), 'emergencyContactName': _emergencyName.text.trim(),
        'emergencyContactPhone': _emergencyPhone.text.trim(),
      };
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).get();
      final role = (snapshot.data()?['role'] ?? '').toString();
      if (role == 'student') {
        profile.addAll({'guardianName':_guardianName.text.trim(),'guardianPhone':_guardianPhone.text.trim(),'previousSchool':_previousSchool.text.trim()});
      } else if (role == 'teacher') {
        final years = int.tryParse(_experience.text.trim());
        if (years == null || years < 0 || years > 60) throw StateError('Experience must be between 0 and 60 years.');
        profile.addAll({'qualification':_qualification.text.trim(),'subjects':_subjects.text.trim(),'experienceYears':years});
      } else if (role == 'parent') {
        profile.addAll({'relationshipToStudent':_relationship.text.trim(),'occupation':_occupation.text.trim()});
      }
      await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('updateOwnSchoolProfile').call({'profile': profile});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Profile updated.', 'پروفائل اپ ڈیٹ ہوگیا۔')),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _error = t(
        'Profile could not be saved. Check your connection and account permissions.',
        'پروفائل محفوظ نہیں ہو سکا۔ انٹرنیٹ اور اکاؤنٹ کی اجازت چیک کریں۔',
      ));
      debugPrint('SCHOOLPRO PROFILE SAVE ERROR: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('My profile', 'میرا پروفائل'))),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users')
            .doc(widget.user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(t(
            'Unable to load your profile.', 'آپ کا پروفائل نہیں کھل سکا۔')));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          if (!_loaded) {
            _name.text = (data['name'] ?? data['displayName'] ?? '').toString();
            _phone.text = (data['phone'] ?? '').toString();
            _dob.text = (data['dateOfBirth'] ?? '').toString();
            _address.text = (data['address'] ?? '').toString();
            _emergencyName.text = (data['emergencyContactName'] ?? '').toString();
            _emergencyPhone.text = (data['emergencyContactPhone'] ?? '').toString();
            _guardianName.text = (data['guardianName'] ?? '').toString();
            _guardianPhone.text = (data['guardianPhone'] ?? '').toString();
            _previousSchool.text = (data['previousSchool'] ?? '').toString();
            _qualification.text = (data['qualification'] ?? '').toString();
            _subjects.text = (data['subjects'] ?? '').toString();
            _experience.text = (data['experienceYears'] ?? 0).toString();
            _relationship.text = (data['relationshipToStudent'] ?? '').toString();
            _occupation.text = (data['occupation'] ?? '').toString();
            final storedGender = (data['gender'] ?? 'prefer_not_to_say').toString();
            _gender = ['male','female','other','prefer_not_to_say'].contains(storedGender) ? storedGender : 'prefer_not_to_say';
            _loaded = true;
          }
          final role = (data['role'] ?? '').toString();
          final schoolId = switch (role) {
            'student' => data['admissionNo'],
            'teacher' => data['teacherId'],
            'parent' => data['parentId'],
            _ => null,
          };
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.user.email ?? '', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${t('Role', 'کردار')}: $role'),
                if (schoolId != null) Text('${t('School ID', 'اسکول آئی ڈی')}: $schoolId'),
                Text('${t('Approval', 'منظوری')}: ${data['approvalStatus'] ?? '-'}'),
              ],
            ))),
            const SizedBox(height: 16),
            TextField(controller: _name, maxLength: 100,
              decoration: InputDecoration(labelText: t('Full name', 'پورا نام'))),
            TextField(controller: _phone, maxLength: 30, keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t('Phone', 'فون نمبر'))),
            TextField(controller: _dob, decoration: InputDecoration(labelText: t('Date of birth (YYYY-MM-DD)', 'تاریخِ پیدائش (YYYY-MM-DD)'))),
            DropdownButtonFormField<String>(value: _gender, decoration: InputDecoration(labelText: t('Gender', 'جنس')), items: [
              DropdownMenuItem(value:'male',child:Text(t('Male','مرد'))), DropdownMenuItem(value:'female',child:Text(t('Female','عورت'))),
              DropdownMenuItem(value:'other',child:Text(t('Other','دیگر'))), DropdownMenuItem(value:'prefer_not_to_say',child:Text(t('Prefer not to say','بتانا نہیں چاہتے'))),
            ], onChanged: (v) { if(v!=null) setState(()=>_gender=v); }),
            TextField(controller: _address, maxLines: 2, decoration: InputDecoration(labelText: t('Residential address', 'رہائشی پتہ'))),
            TextField(controller: _emergencyName, decoration: InputDecoration(labelText: t('Emergency contact name', 'ہنگامی رابطہ نام'))),
            TextField(controller: _emergencyPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Emergency contact phone', 'ہنگامی رابطہ فون'))),
            if (role == 'student') ...[
              TextField(controller:_guardianName, decoration:InputDecoration(labelText:t('Guardian name','سرپرست کا نام'))),
              TextField(controller:_guardianPhone, decoration:InputDecoration(labelText:t('Guardian phone','سرپرست کا فون'))),
              TextField(controller:_previousSchool, decoration:InputDecoration(labelText:t('Previous school','پچھلا اسکول'))),
            ],
            if (role == 'teacher') ...[
              TextField(controller:_qualification, decoration:InputDecoration(labelText:t('Qualification','تعلیمی قابلیت'))),
              TextField(controller:_subjects, decoration:InputDecoration(labelText:t('Subjects','مضامین'))),
              TextField(controller:_experience, keyboardType:TextInputType.number, decoration:InputDecoration(labelText:t('Experience (years)','تجربہ (سال)'))),
            ],
            if (role == 'parent') ...[
              TextField(controller:_relationship, decoration:InputDecoration(labelText:t('Relationship to student','طالب علم سے رشتہ'))),
              TextField(controller:_occupation, decoration:InputDecoration(labelText:t('Occupation','پیشہ'))),
            ],
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfileDocumentsScreen(user: widget.user, urdu: widget.urdu))), icon: const Icon(Icons.folder_shared), label: Text(t('Profile photo & documents', 'پروفائل تصویر اور دستاویزات'))),
                        FilledButton.icon(onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(t('Save profile', 'پروفائل محفوظ کریں'))),
          ]);
        },
      ),
    );
  }
}

class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key, required this.urdu});
  final bool urdu;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.pause_circle_outline, size: 56), const SizedBox(height: 12),
      Text(urdu ? 'یہ اکاؤنٹ عارضی طور پر معطل ہے۔ مزید معلومات کے لیے اسکول انتظامیہ سے رابطہ کریں۔' : 'This account is suspended. Contact school administration for assistance.', textAlign: TextAlign.center),
      const SizedBox(height: 16), const SignOutButton(urdu: false),
    ]),
  )));
}

class AccountRejectedScreen extends StatelessWidget {
  const AccountRejectedScreen({super.key, required this.urdu});

  final bool urdu;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                urdu
                    ? 'اکاؤنٹ کی درخواست مسترد ہوگئی'
                    : 'Account request rejected',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                urdu
                    ? 'آپ کا اکاؤنٹ منظور نہیں کیا گیا۔ مزید معلومات کے لیے اسکول انتظامیہ سے رابطہ کریں۔'
                    : 'Your account was not approved. Please contact the school administration for more information.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: Text(urdu ? 'لاگ آؤٹ' : 'Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileMissingScreen extends StatelessWidget {
  const ProfileMissingScreen({super.key, required this.urdu});

  final bool urdu;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_search, size: 64),
              const SizedBox(height: 16),
              Text(
                urdu
                    ? 'صارف کا ریکارڈ موجود نہیں۔ ایڈمن سے رابطہ کریں۔'
                    : 'User profile not found. Contact your school admin.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const SignOutButton(urdu: false),
            ],
          ),
        ),
      ),
    );
  }
}

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.urdu, this.user});

  final bool urdu;
  final User? user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SchoolPro')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 64),
              const SizedBox(height: 16),
              Text(
                urdu
                    ? 'آپ کا اکاؤنٹ منظوری کا منتظر ہے۔ اسکول ایڈمن سے رابطہ کریں۔'
                    : 'Your account is awaiting approval. Contact the school admin.',
                textAlign: TextAlign.center,
              ),
              if (user != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ProfileDocumentsScreen(user: user!, urdu: urdu),
                  )),
                  icon: const Icon(Icons.upload_file),
                  label: Text(urdu ? 'تصویر اور دستاویزات اپلوڈ کریں' : 'Upload profile photo and documents'),
                ),
              ],
              const SizedBox(height: 20),
              SignOutButton(urdu: urdu),
            ],
          ),
        ),
      ),
    );
  }
}

String? _adminCollectionFor(String label) {
  const collections = <String, String>{
    'Teachers': 'teachers',
    'Teacher Attendance': 'teacherAttendance',
    'Teacher Payroll': 'teacherPayroll',
    'Parents': 'parents',
    'Classes': 'classes',
    'Subjects': 'subjects',
    'Timetable': 'timetables',
    'Fees & Receipts': 'feeStructures',
    'Fee Payments': 'feePayments',
    'Exams': 'exams',
    'Results': 'results',
    'Homework': 'assignments',
    'Homework Submissions': 'homeworkSubmissions',
    'Expenses': 'expenses',
    'Announcements': 'notices',
    'Reports': 'reports',
    'School Settings': 'schoolSettings',
  };
  return collections[label];
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    required this.role,
    required this.urdu,
    required this.name,
  });

  final User user;
  final String role;
  final bool urdu;
  final String name;

  String label(String en, String ur) => urdu ? ur : en;

  List<Map<String, dynamic>> modules() {
    final common = <Map<String, dynamic>>[
      {'icon': Icons.people, 'en': 'Students', 'ur': 'طلبہ'},
      {'icon': Icons.co_present, 'en': 'Teachers', 'ur': 'اساتذہ'},
      {'icon': Icons.access_time, 'en': 'Teacher Attendance', 'ur': 'اساتذہ کی حاضری'},
      {'icon': Icons.account_balance_wallet_outlined, 'en': 'Teacher Payroll', 'ur': 'اساتذہ کی تنخواہیں'},
      {'icon': Icons.family_restroom, 'en': 'Parents', 'ur': 'والدین'},
      {'icon': Icons.class_, 'en': 'Classes', 'ur': 'کلاسیں'},
      {'icon': Icons.menu_book, 'en': 'Subjects', 'ur': 'مضامین'},
      {'icon': Icons.calendar_month, 'en': 'Timetable', 'ur': 'ٹائم ٹیبل'},
      {'icon': Icons.event_busy, 'en': 'Leave Requests', 'ur': 'چھٹی کی درخواستیں'},
      {'icon': Icons.analytics_outlined, 'en': 'Attendance Reports', 'ur': 'حاضری رپورٹس'},
      {'icon': Icons.fact_check, 'en': 'Attendance', 'ur': 'حاضری'},
      {'icon': Icons.payments, 'en': 'Fees & Receipts', 'ur': 'فیس اور رسیدیں'},
      {'icon': Icons.receipt_long, 'en': 'Fee Payments', 'ur': 'فیس ادائیگیاں'},
      {'icon': Icons.assessment, 'en': 'Exams', 'ur': 'امتحانات'},
      {'icon': Icons.grade, 'en': 'Results', 'ur': 'نتائج'},
      {'icon': Icons.insert_drive_file_outlined, 'en': 'Report Cards', 'ur': 'رپورٹ کارڈز'},
      {'icon': Icons.assignment, 'en': 'Homework', 'ur': 'ہوم ورک'},
      {'icon': Icons.assignment_turned_in, 'en': 'My Submissions', 'ur': 'میری جمع شدہ اسائنمنٹس'},
      {'icon': Icons.rate_review, 'en': 'Homework Submissions', 'ur': 'ہوم ورک کا جائزہ'},
      {'icon': Icons.account_balance_wallet, 'en': 'Expenses', 'ur': 'اخراجات'},
      {'icon': Icons.campaign, 'en': 'Announcements', 'ur': 'اعلانات'},
      {'icon': Icons.notifications_active, 'en': 'Notifications', 'ur': 'اطلاعات'},
      {'icon': Icons.analytics, 'en': 'Reports', 'ur': 'رپورٹس'},
      {'icon': Icons.settings, 'en': 'School Settings', 'ur': 'اسکول سیٹنگز'},
    ];

    switch (role) {
      case 'admin':
        return [
          ...common,
          {'icon': Icons.admin_panel_settings, 'en': 'User Approvals', 'ur': 'صارفین کی منظوری'},
          {'icon': Icons.account_tree_outlined, 'en': 'School Workflows', 'ur': 'اسکول انتظامی ورک فلو'},
          {'icon': Icons.rate_review, 'en': 'Homework Submissions', 'ur': 'ہوم ورک کا جائزہ'},
        ];
      case 'teacher':
        return common.where((m) => [
          'Classes', 'Subjects', 'Timetable', 'Attendance', 'Attendance Reports', 'Leave Requests', 'Exams',
          'Results', 'Homework', 'Homework Submissions', 'Teacher Attendance', 'Teacher Payroll', 'Announcements', 'Notifications',
        ].contains(m['en'])).toList();
      case 'student':
        return common.where((m) => [
          'Timetable', 'Attendance', 'Fees & Receipts', 'Exams',
          'Results', 'Report Cards', 'Homework', 'My Submissions', 'Announcements', 'Notifications',
        ].contains(m['en'])).toList();
      case 'parent':
        return common.where((m) => [
          'Timetable', 'Attendance', 'Fees & Receipts', 'Exams',
          'Results', 'Report Cards', 'Homework', 'My Submissions', 'Announcements', 'Notifications',
        ].contains(m['en'])).toList();
      default:
        return const [];
    }
  }

  String roleLabel() {
    const en = {
      'admin': 'Administrator',
      'teacher': 'Teacher',
      'student': 'Student',
      'parent': 'Parent',
    };
    const ur = {
      'admin': 'ایڈمن',
      'teacher': 'استاد',
      'student': 'طالب علم',
      'parent': 'والدین',
    };
    return (urdu ? ur : en)[role]!;
  }

  @override
  Widget build(BuildContext context) {
    final items = modules();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SchoolPro'),
        actions: [
          IconButton(
            tooltip: label('My profile', 'میرا پروفائل'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MyProfileScreen(
                  user: user,
                  urdu: urdu,
                ),
              ),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: label('Logout', 'لاگ آؤٹ'),
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.school, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    label('Welcome to SchoolPro', 'SchoolPro میں خوش آمدید'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(name),
                  Text('${label('Role', 'کردار')}: ${roleLabel()}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            label('School Management', 'اسکول مینجمنٹ'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (item['en'] == 'School Workflows' && role == 'admin') {
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminWorkflowsScreen()));
                    } else if (item['en'] == 'User Approvals' && role == 'admin') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => UserApprovalsScreen(urdu: urdu),
                        ),
                      );
                    } else if (item['en'] == 'Students' && role == 'admin') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StudentsScreen(urdu: urdu),
                        ),
                      );
                    } else if (item['en'] == 'Attendance' && role == 'admin') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AttendanceScreen(urdu: urdu),
                        ),
                      );
                    } else if (item['en'] == 'Leave Requests' && role == 'teacher') {
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeacherLeaveScreen(user: user, urdu: urdu)));
                    } else if (item['en'] == 'Attendance' && role == 'teacher') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TeacherAttendanceEntry(user: user, urdu: urdu),
                        ),
                      );
                    } else if (role == 'admin' && _adminCollectionFor(item['en']) != null) {
                      final collection = _adminCollectionFor(item['en'])!;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AdminCollectionScreen(
                            title: item['en'] as String,
                            collectionName: collection,
                            description: 'Manage $collection records in the SchoolPro Firestore database.',
                          ),
                        ),
                      );
                    } else if (role != 'admin') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RoleModuleScreen(
                            user: user,
                            role: role,
                            module: item['en'] as String,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(label('This module is not configured.', 'یہ ماڈیول ترتیب نہیں دیا گیا۔'))),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item['icon'] as IconData, size: 34),
                        const SizedBox(height: 12),
                        Text(
                          label(item['en'] as String, item['ur'] as String),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            label(
              'School records are shown only after the relevant modules and permissions are configured.',
              'اسکول کا حقیقی ریکارڈ متعلقہ ماڈیولز اور اجازتیں ترتیب دینے کے بعد دکھایا جائے گا۔',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class RoleModuleScreen extends StatelessWidget {
  const RoleModuleScreen({
    super.key,
    required this.user,
    required this.role,
    required this.module,
    required this.urdu,
  });

  final User user;
  final String role;
  final String module;
  final bool urdu;

  String t(String en, String ur) => urdu ? ur : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module)),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.hasError) return Center(child: Text(t('Could not load your profile.', 'آپ کا پروفائل نہیں کھل سکا۔')));
          if (!profileSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          final profile = profileSnapshot.data!.data() ?? <String, dynamic>{};
          final isParent = role == 'parent';
          final className = (profile['currentClass'] ?? '').toString();
          final teacherId = (profile['teacherId'] ?? '').toString();
          final studentDocIds = isParent
              ? ((profile['linkedStudentIds'] as List?)?.map((e) => e.toString()).toList() ?? <String>[(profile['linkedStudentId'] ?? '').toString()]).where((e) => e.isNotEmpty).toList()
              : (role == 'student' ? <String>[(profile['linkedStudentId'] ?? user.uid).toString()] : <String>[]);
          final studentDocId = studentDocIds.isEmpty ? '' : studentDocIds.first;
          if ((role == 'student' || isParent) && studentDocIds.isEmpty) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t('A verified student record is not linked to this account. Contact the school office.', 'اس اکاؤنٹ کے ساتھ تصدیق شدہ طالب علم ریکارڈ منسلک نہیں۔ اسکول آفس سے رابطہ کریں۔'), textAlign: TextAlign.center),
            ));
          }
          if (role == 'student' || isParent) {
            return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
              future: Future.wait(studentDocIds.map((id) => FirebaseFirestore.instance.collection('students').doc(id).get())),
              builder: (context, studentSnapshot) {
                if (studentSnapshot.hasError) return Center(child: Text(t('Student records could not be loaded. Check access permissions.', 'طالب علم کا ریکارڈ نہیں کھل سکا۔ رسائی کی اجازت چیک کریں۔')));
                if (!studentSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                final records = studentSnapshot.data!.where((d) => d.exists).toList();
                if (records.length != studentDocIds.length) return Center(child: Text(t('One or more linked student records were not found.', 'ایک یا زیادہ منسلک طالب علم ریکارڈ نہیں ملے۔')));
                final classes = records.map((d) => (d.data()?['className'] ?? '').toString()).where((e) => e.isNotEmpty).toSet().toList();
                return _buildRecords(context, profile, studentDocId, classes.isEmpty ? className : classes.first, teacherId, studentDocIds: studentDocIds, classNames: classes);
              },
            );
          }
          return _buildRecords(context, profile, '', className, teacherId);
        },
      ),
    );
  }

  Widget _buildRecords(BuildContext context, Map<String, dynamic> profile, String studentDocId, String className, String teacherId, {List<String> studentDocIds = const [], List<String> classNames = const []}) {
    final db = FirebaseFirestore.instance;
    late final Query<Map<String, dynamic>> query;
    String empty = t('No records found for this module.', 'اس ماڈیول کے لیے کوئی ریکارڈ موجود نہیں۔');
    switch (module) {
      case 'Teacher Attendance':
        query = db.collection('teacherAttendance').where('teacherUid', isEqualTo: user.uid).orderBy('date', descending: true).limit(200);
        break;
      case 'Teacher Payroll':
        query = db.collection('teacherPayroll').where('teacherUid', isEqualTo: user.uid).orderBy('month', descending: true).limit(120);
        break;
      case 'Attendance Reports':
        query = db.collection('attendance').where('markedBy', isEqualTo: user.uid).limit(500);
        break;
      case 'Attendance':
        query = studentDocIds.length > 1 ? db.collection('attendance').where('studentId', whereIn: studentDocIds.take(10).toList()).limit(100) : db.collection('attendance').where('studentId', isEqualTo: studentDocId).orderBy('date', descending: true).limit(100);
        break;
      case 'Fees & Receipts':
        query = studentDocIds.length > 1 ? db.collection('feePayments').where('studentId', whereIn: studentDocIds.take(10).toList()).limit(100) : db.collection('feePayments').where('studentId', isEqualTo: studentDocId).orderBy('createdAt', descending: true).limit(100);
        break;
      case 'Results':
        query = role == 'teacher'
            ? db.collection('results').where('teacherId', isEqualTo: teacherId).limit(100)
            : (studentDocIds.length > 1 ? db.collection('results').where('studentId', whereIn: studentDocIds.take(10).toList()).limit(100) : db.collection('results').where('studentId', isEqualTo: studentDocId).limit(100));
        break;
      case 'Report Cards':
        query = studentDocIds.length > 1
            ? db.collection('reports').where('reportType', isEqualTo: 'report_card').where('studentId', whereIn: studentDocIds.take(10).toList()).limit(100)
            : db.collection('reports').where('reportType', isEqualTo: 'report_card').where('studentId', isEqualTo: studentDocId).limit(100);
        break;
      case 'My Submissions':
        query = studentDocIds.length > 1 ? db.collection('homeworkSubmissions').where('studentId', whereIn: studentDocIds.take(10).toList()).limit(100) : db.collection('homeworkSubmissions').where('studentId', isEqualTo: studentDocId).limit(100);
        break;
      case 'Homework Submissions':
        query = db.collection('homeworkSubmissions').where('teacherId', isEqualTo: teacherId).limit(100);
        break;
      case 'Homework':
        query = role == 'teacher'
            ? db.collection('assignments').where('teacherId', isEqualTo: teacherId).limit(100)
            : (classNames.length > 1 ? db.collection('assignments').where('className', whereIn: classNames.take(10).toList()).limit(100) : db.collection('assignments').where('className', isEqualTo: className).limit(100));
        break;
      case 'Timetable':
        query = role == 'teacher'
            ? db.collection('timetables').where('teacherId', isEqualTo: teacherId).limit(100)
            : (classNames.length > 1 ? db.collection('timetables').where('className', whereIn: classNames.take(10).toList()).limit(100) : db.collection('timetables').where('className', isEqualTo: className).limit(100));
        break;
      case 'Exams':
        query = role == 'teacher'
            ? db.collection('exams').where('teacherId', isEqualTo: teacherId).limit(100)
            : (classNames.length > 1 ? db.collection('exams').where('className', whereIn: classNames.take(10).toList()).limit(100) : db.collection('exams').where('className', isEqualTo: className).limit(100));
        break;
      case 'Announcements':
        query = db.collection('notices').where('status', isEqualTo: 'published').limit(100);
        break;
      case 'Notifications':
        query = db.collection('notifications').where('recipientUid', isEqualTo: user.uid).limit(100);
        break;
      case 'Classes':
        query = role == 'teacher'
            ? db.collection('classes').where('classTeacherId', isEqualTo: teacherId).limit(50)
            : (classNames.length > 1 ? db.collection('classes').where('name', whereIn: classNames.take(10).toList()).limit(50) : db.collection('classes').where('name', isEqualTo: className).limit(50));
        break;
      case 'Subjects':
        query = role == 'teacher'
            ? db.collection('subjects').where('teacherId', isEqualTo: teacherId).limit(100)
            : (classNames.length > 1 ? db.collection('subjects').where('className', whereIn: classNames.take(10).toList()).limit(100) : db.collection('subjects').where('className', isEqualTo: className).limit(100));
        break;
      default:
        return Center(child: Text(empty));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t('Access denied or data query failed. Ask the school administrator to check role permissions and required indexes.', 'رسائی مسترد ہوئی یا ڈیٹا کی درخواست ناکام ہوئی۔ اسکول انتظامیہ سے رول اجازتیں اور مطلوبہ انڈیکس چیک کروائیں۔'))));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return Center(child: Text(empty));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final title = (data['title'] ?? data['subject'] ?? data['name'] ?? data['studentName'] ?? data['className'] ?? module).toString();
            final subtitle = data.entries
                .where((entry) => !['createdAt', 'updatedAt'].contains(entry.key))
                .take(5)
                .map((entry) => '${entry.key}: ${entry.value is Timestamp ? (entry.value as Timestamp).toDate().toLocal().toString().split('.').first : entry.value}')
                .join(' • ');
            return Card(child: ListTile(
              leading: Icon(_iconFor(module)),
              title: Text(title),
              subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: module == 'Homework' && role == 'student' && studentDocId.isNotEmpty
                  ? TextButton(
                      onPressed: () => _submitHomework(context, docs[index].id, data, studentDocId),
                      child: Text(t('Submit', 'جمع کرائیں')),
                    )
                  : module == 'Homework Submissions' && role == 'teacher'
                      ? TextButton(
                          onPressed: () => _reviewSubmission(context, docs[index].reference, data),
                          child: Text(t('Review', 'جائزہ')),
                        )
                      : module == 'Notifications'
                          ? IconButton(
                              tooltip: t('Mark as read', 'پڑھا ہوا نشان زد کریں'),
                              onPressed: data['isRead'] == true ? null : () => docs[index].reference.update({'isRead': true}),
                              icon: Icon(data['isRead'] == true ? Icons.done_all : Icons.mark_email_unread),
                            )
                          : null,
            ));
          },
        );
      },
    );
  }

  Future<void> _submitHomework(
    BuildContext context,
    String assignmentId,
    Map<String, dynamic> assignment,
    String studentDocId,
  ) async {
    final controller = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('Submit homework', 'ہوم ورک جمع کرائیں')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: t('Your answer / work', 'آپ کا جواب / کام'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t('Cancel', 'منسوخ'))),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text(t('Submit', 'جمع کرائیں')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (answer == null || answer.trim().isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      final existing = await db.collection('homeworkSubmissions')
          .where('studentId', isEqualTo: studentDocId)
          .where('assignmentId', isEqualTo: assignmentId)
          .limit(1).get();
      if (existing.docs.isNotEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('You have already submitted this homework.', 'آپ یہ ہوم ورک پہلے جمع کرا چکے ہیں۔'))),
        );
        return;
      }
      await db.collection('homeworkSubmissions').doc('${studentDocId}__$assignmentId').set({
        'studentId': studentDocId,
        'assignmentId': assignmentId,
        'assignmentTitle': (assignment['title'] ?? '').toString(),
        'teacherId': (assignment['teacherId'] ?? '').toString(),
        'studentName': (user.displayName ?? user.email ?? 'Student').toString(),
        'answer': answer.trim(),
        'status': 'submitted',
        'createdBy': user.uid,
        'submittedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Homework submitted successfully.', 'ہوم ورک کامیابی سے جمع ہوگیا۔'))),
      );
    } on FirebaseException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Submission failed: ${e.code}', 'جمع نہیں ہوا: ${e.code}'))),
      );
    }
  }

  Future<void> _reviewSubmission(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> submission,
  ) async {
    final marksController = TextEditingController(text: (submission['marks'] ?? '').toString());
    final feedbackController = TextEditingController(text: (submission['feedback'] ?? '').toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('Review homework', 'ہوم ورک کا جائزہ')),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text((submission['answer'] ?? '').toString()),
          const SizedBox(height: 12),
          TextField(controller: marksController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Marks', 'نمبر'))),
          TextField(controller: feedbackController, maxLines: 3, maxLength: 1000, decoration: InputDecoration(labelText: t('Feedback', 'رائے'))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('Cancel', 'واپس'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t('Save review', 'جائزہ محفوظ کریں'))),
        ],
      ),
    );
    final marksText = marksController.text.trim();
    final feedback = feedbackController.text.trim();
    marksController.dispose();
    feedbackController.dispose();
    if (result != true) return;
    final marks = int.tryParse(marksText);
    if (marksText.isNotEmpty && (marks == null || marks < 0)) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Marks must be a non-negative whole number.', 'نمبر صفر یا اس سے بڑا مکمل عدد ہونا چاہیے۔'))));
      return;
    }
    try {
      await reference.update({
        'status': 'reviewed',
        if (marks != null) 'marks': marks,
        'feedback': feedback,
        'reviewedBy': user.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Review saved.', 'جائزہ محفوظ ہوگیا۔'))));
    } on FirebaseException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Review failed: ${e.code}', 'جائزہ محفوظ نہیں ہوا: ${e.code}'))));
    }
  }

  IconData _iconFor(String value) => switch (value) {
    'Attendance' => Icons.fact_check,
    'Fees & Receipts' => Icons.receipt_long,
    'Results' => Icons.grade,
    'Homework' => Icons.assignment,
    'My Submissions' => Icons.assignment_turned_in,
    'Homework Submissions' => Icons.rate_review,
    'Timetable' => Icons.calendar_month,
    'Exams' => Icons.assessment,
    'Announcements' => Icons.campaign,
    'Classes' => Icons.class_,
    'Subjects' => Icons.menu_book,
    _ => Icons.school,
  };
}

class UserApprovalsScreen extends StatefulWidget {
  const UserApprovalsScreen({super.key, required this.urdu});
  final bool urdu;

  @override
  State<UserApprovalsScreen> createState() => _UserApprovalsScreenState();
}

class _UserApprovalsScreenState extends State<UserApprovalsScreen> {
  bool busy = false;
  String error = '';

  String t(String en, String ur) => widget.urdu ? ur : en;

  Future<void> showSubmittedDocuments(Map<String,dynamic> data) async {
    final docs = (data['uploadedDocuments'] as List? ?? const []).whereType<Map>().toList();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(t('Submitted profile documents','جمع کرائی گئی دستاویزات')),
      content: SizedBox(width:460, child: SingleChildScrollView(child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
        if ((data['photoUrl']??'').toString().isNotEmpty) ...[Text(t('Profile photo URL','پروفائل تصویر کا لنک')),SelectableText((data['photoUrl']??'').toString()),const Divider()],
        for(final item in docs) ...[Text((item['name']??'Document').toString(),style:const TextStyle(fontWeight:FontWeight.bold)),SelectableText((item['url']??'').toString()),const Divider()],
        if(docs.isEmpty && (data['photoUrl']??'').toString().isEmpty) Text(t('No documents uploaded.','ابھی کوئی دستاویز اپلوڈ نہیں ہوئی۔')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(t('Close','بند کریں')))],
    ));
  }

  Future<void> editRequest(String uid, Map<String,dynamic> data) async {
    if (busy) return;
    final fields = <String,TextEditingController>{
      'name':TextEditingController(text:(data['name']??'').toString()),
      'phone':TextEditingController(text:(data['phone']??'').toString()),
      'dateOfBirth':TextEditingController(text:(data['dateOfBirth']??'').toString()),
      'gender':TextEditingController(text:(data['gender']??'prefer_not_to_say').toString()),
      'address':TextEditingController(text:(data['address']??'').toString()),
      'currentClass':TextEditingController(text:(data['currentClass']??'').toString()),
      'guardianName':TextEditingController(text:(data['guardianName']??'').toString()),
      'guardianPhone':TextEditingController(text:(data['guardianPhone']??'').toString()),
      'previousSchool':TextEditingController(text:(data['previousSchool']??'').toString()),
      'qualification':TextEditingController(text:(data['qualification']??'').toString()),
      'subjects':TextEditingController(text:(data['subjects']??'').toString()),
      'experienceYears':TextEditingController(text:(data['experienceYears']??0).toString()),
      'childAdmissionNo':TextEditingController(text:(data['childAdmissionNo']??'').toString()),
      'existingAdmissionNo':TextEditingController(text:(data['existingAdmissionNo']??'').toString()),
      'relationshipToStudent':TextEditingController(text:(data['relationshipToStudent']??'').toString()),
      'occupation':TextEditingController(text:(data['occupation']??'').toString()),
    };
    try {
      final save = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(t('Edit registration request','درخواست میں ترمیم')),
        content: SizedBox(width:460, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min, children: [
          for(final e in fields.entries) if ((data['requestedRole']=='student' && ['currentClass','guardianName','guardianPhone','previousSchool','existingAdmissionNo'].contains(e.key)) || (data['requestedRole']=='teacher' && ['qualification','subjects','experienceYears'].contains(e.key)) || (data['requestedRole']=='parent' && ['childAdmissionNo','relationshipToStudent','occupation'].contains(e.key)) || ['name','phone','dateOfBirth','gender','address'].contains(e.key))
            Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:e.value,decoration:InputDecoration(labelText:e.key))),
        ]))),
        actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(t('Cancel','واپس'))),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(t('Save','محفوظ کریں')))],
      ));
      if (save != true) return;
      final dob = fields['dateOfBirth']!.text.trim();
      if (fields['name']!.text.trim().length<2 || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob) || DateTime.tryParse(dob)==null || fields['address']!.text.trim().length<5) {
        throw StateError(t('Name, valid date of birth and address are required.','نام، درست تاریخِ پیدائش اور پتہ ضروری ہیں۔'));
      }
      final update=<String,dynamic>{};
      for(final e in fields.entries){
        if(e.key=='experienceYears') update[e.key]=int.tryParse(e.value.text.trim())??0;
        else update[e.key]=e.value.text.trim();
      }
      update['updatedAt']=FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('users').doc(uid).update(update);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Registration request updated.','درخواست اپ ڈیٹ ہوگئی۔'))));
    } catch(e) { if(mounted) setState(()=>error='$e'); }
    finally { for(final c in fields.values){c.dispose();} }
  }

  Future<void> decide(String uid, String role) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final admin = FirebaseAuth.instance.currentUser;
      if (admin == null ||
          (await admin.getIdTokenResult(true)).claims?['admin'] != true) {
        throw StateError('Admin permission missing. Sign in again.');
      }

      final db = FirebaseFirestore.instance;
      final ref = db.collection('users').doc(uid);
      final userSnapshot = await ref.get();
      if (!userSnapshot.exists || userSnapshot.data()?['role'] != 'pending') {
        throw StateError('This request is no longer pending.');
      }
      final current = userSnapshot.data()!;
      final requested = (current['requestedRole'] ?? '').toString();
      if (role != 'rejected' && requested.isNotEmpty && requested != role) {
        throw StateError("Selected role does not match the requested role.");
      }
      String rejectionReason = '';
      if (role == 'rejected') {
        final controller = TextEditingController();
        final reason = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(t('Reject request', 'درخواست مسترد کریں')),
            content: TextField(controller: controller, maxLines: 3, decoration: InputDecoration(labelText: t('Reason (required)', 'وجہ (لازمی)'))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t('Cancel', 'واپس'))),
              FilledButton(onPressed: () { final v = controller.text.trim(); if (v.isNotEmpty) Navigator.pop(dialogContext, v); }, child: Text(t('Reject', 'مسترد کریں'))),
            ],
          ),
        );
        controller.dispose();
        if (reason == null || reason.trim().isEmpty) return;
        rejectionReason = reason.trim();
      }
      final approved = role != 'rejected';
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final existingAdmission = (current['existingAdmissionNo'] ?? '').toString().trim();
      final result = approved && role == 'student' && existingAdmission.isNotEmpty
          ? await functions.httpsCallable('attachStudentAccount').call({'uid': uid, 'admissionNo': existingAdmission})
          : approved
              ? await functions.httpsCallable('approveAndIssueSchoolId').call({'uid': uid, 'role': role})
              : await functions.httpsCallable('rejectSchoolRegistration').call({'uid': uid, 'reason': rejectionReason});
      final resultData = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? t('Account approved. ID: ${resultData['admissionNo'] ?? resultData['teacherId'] ?? resultData['parentId'] ?? ''}', 'اکاؤنٹ منظور ہوگیا۔ جاری کردہ آئی ڈی: ${resultData['admissionNo'] ?? resultData['teacherId'] ?? resultData['parentId'] ?? ''}')
                : t('Account rejected.', 'اکاؤنٹ مسترد ہوگیا۔'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(String uid) async {
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Review account', 'اکاؤنٹ کا جائزہ')),
        content: Text(
          t(
            'Choose the account role to approve, or reject this request.',
            'منظوری کے لیے کردار منتخب کریں یا درخواست مسترد کریں۔',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(t('Cancel', 'منسوخ')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'rejected'),
            child: Text(t('Reject', 'مسترد')),
          ),
          PopupMenuButton<String>(
            tooltip: t('Approve as', 'اس حیثیت سے منظور کریں'),
            onSelected: (value) => Navigator.pop(ctx, value),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'student',
                child: Text(t('Student', 'طالب علم')),
              ),
              PopupMenuItem(
                value: 'teacher',
                child: Text(t('Teacher', 'استاد')),
              ),
              PopupMenuItem(
                value: 'parent',
                child: Text(t('Parent', 'والدین')),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(t('Approve as…', 'منظوری دیں…')),
            ),
          ),
        ],
      ),
    );
    if (role == null || role == 'cancel' || !mounted) return;
    await decide(uid, role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('User Approvals', 'صارفین کی منظوری'))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  t(
                    'Unable to load requests. Check admin access and Firestore Rules.',
                    'درخواستیں نہیں کھل سکیں۔ ایڈمن اجازت اور Firestore Rules چیک کریں۔',
                  ),
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      t(
                        'No pending requests.',
                        'منظوری کے لیے کوئی درخواست موجود نہیں۔',
                      ),
                    ),
                  ),
                ),
              for (final doc in docs)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text((doc.data()['name'] ?? doc.data()['email'] ?? doc.id).toString()),
                    subtitle: Text('Email: ${doc.data()['email'] ?? '-'}\nRole: ${doc.data()['requestedRole'] ?? '-'} | Phone: ${doc.data()['phone'] ?? '-'}\nDOB: ${doc.data()['dateOfBirth'] ?? '-'} | Gender: ${doc.data()['gender'] ?? '-'}\nAddress: ${doc.data()['address'] ?? '-'}\nStudent: Guardian ${doc.data()['guardianName'] ?? '-'} / ${doc.data()['guardianPhone'] ?? '-'} | Class ${doc.data()['currentClass'] ?? '-'}\nTeacher: ${doc.data()['qualification'] ?? '-'} | ${doc.data()['subjects'] ?? '-'} | ${doc.data()['experienceYears'] ?? 0} years\nParent: Child ${doc.data()['childAdmissionNo'] ?? '-'} | ${doc.data()['relationshipToStudent'] ?? '-'}\nExisting Student Admission: ${doc.data()['existingAdmissionNo'] ?? '-'}\nUID: ${doc.id}'),
                    isThreeLine: true,
                    trailing: Wrap(mainAxisSize:MainAxisSize.min, children: [
                      if ((doc.data()['photoUrl']??'').toString().isNotEmpty || (doc.data()['uploadedDocuments'] as List? ?? const []).isNotEmpty)
                        IconButton(onPressed: busy ? null : () => showSubmittedDocuments(doc.data()), icon: const Icon(Icons.folder_open), tooltip:t('View document links','دستاویزات کے لنکس دیکھیں')),
                      IconButton(onPressed: busy ? null : () => editRequest(doc.id, doc.data()), icon: const Icon(Icons.edit_outlined), tooltip:t('Edit request','درخواست میں ترمیم')),
                      IconButton(onPressed: busy ? null : () => review(doc.id), icon: const Icon(Icons.fact_check), tooltip:t('Review','جائزہ')),
                    ]),
                    onTap: busy ? null : () => review(doc.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class TeacherAttendanceEntry extends StatelessWidget {
  const TeacherAttendanceEntry({super.key, required this.user, required this.urdu});
  final User user;
  final bool urdu;

  @override
  Widget build(BuildContext context) => FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Could not load teacher profile.')));
      if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final teacherId = (snapshot.data!.data()?['teacherId'] ?? '').toString();
      if (teacherId.isEmpty) return Scaffold(appBar: AppBar(), body: Center(child: Text(urdu ? 'استاد کی ID موجود نہیں۔' : 'Teacher ID is missing.')));
      return AttendanceScreen(urdu: urdu, teacherId: teacherId);
    },
  );
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.urdu, this.teacherId});
  final bool urdu;
  final String? teacherId;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime selectedDate = DateTime.now();
  final Map<String, String> statuses = {};
  bool saving = false;
  bool loadingExisting = false;
  String error = '';

  String t(String en, String ur) => widget.urdu ? ur : en;

  String get dateKey =>
      '${selectedDate.year.toString().padLeft(4, '0')}-'
      '${selectedDate.month.toString().padLeft(2, '0')}-'
      '${selectedDate.day.toString().padLeft(2, '0')}';

  CollectionReference<Map<String, dynamic>> get students =>
      FirebaseFirestore.instance.collection('students');

  CollectionReference<Map<String, dynamic>> get attendance =>
      FirebaseFirestore.instance.collection('attendance');

  @override
  void initState() {
    super.initState();
    loadExisting();
  }

  Future<void> loadExisting() async {
    setState(() {
      loadingExisting = true;
      error = '';
    });
    try {
      Query<Map<String, dynamic>> existingQuery = attendance.where('date', isEqualTo: dateKey);
      if (widget.teacherId != null) {
        existingQuery = existingQuery.where('markedBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid);
      }
      final result = await existingQuery.get();
      final loaded = <String, String>{};
      for (final doc in result.docs) {
        final data = doc.data();
        if (data['studentId'] is String && data['status'] is String) {
          loaded[data['studentId'] as String] = data['status'] as String;
        }
      }
      if (mounted) {
        setState(() {
          statuses
            ..clear()
            ..addAll(loaded);
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => error = t(
            'Could not load saved attendance (${e.code}).',
            'محفوظ حاضری نہیں کھل سکی (${e.code})۔',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loadingExisting = false);
    }
  }

  Future<void> chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      selectedDate = DateTime(picked.year, picked.month, picked.day);
      statuses.clear();
    });
    await loadExisting();
  }

  Future<void> saveAttendance(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (saving) return;
    final marked = docs.where((doc) => statuses.containsKey(doc.id)).toList();
    if (marked.isEmpty) {
      setState(
        () => error = t(
          'Choose a status for at least one student.',
          'کم از کم ایک طالب علم کی حاضری منتخب کریں۔',
        ),
      );
      return;
    }

    setState(() {
      saving = true;
      error = '';
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');
      final recordRefs = marked
          .map((doc) => attendance.doc('${dateKey}_${doc.id}'))
          .toList();

      final existingRecords = await Future.wait(
        recordRefs.map((ref) => ref.get()),
      );

      final batch = FirebaseFirestore.instance.batch();

      for (var i = 0; i < marked.length; i++) {
        final doc = marked[i];
        final data = doc.data();
        final ref = recordRefs[i];

        final recordData = <String, dynamic>{
          'studentId': doc.id,
          'studentName': data['name'] ?? '',
          'admissionNo': data['admissionNo'] ?? data['existingAdmissionNo'] ?? '',
          'className': data['className'] ?? '',
          'date': dateKey,
          'status': statuses[doc.id],
          'markedBy': uid,
        };

        if (existingRecords[i].exists) {
          recordData['updatedAt'] = FieldValue.serverTimestamp();
        } else {
          recordData['createdAt'] = FieldValue.serverTimestamp();
        }

        batch.set(ref, recordData, SetOptions(merge: true));
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Attendance saved for ${marked.length} student(s).',
                '${marked.length} طلبہ کی حاضری محفوظ ہوگئی۔',
              ),
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => error = t(
            'Save failed. Check permissions (${e.code}).',
            'حاضری محفوظ نہیں ہوئی۔ اجازتیں چیک کریں (${e.code})۔',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            'An unexpected error occurred.',
            'غیر متوقع خرابی پیش آئی۔',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const statusValues = ['Present', 'Absent', 'Leave'];
    String statusLabel(String value) {
      if (value == 'Present') return t('Present', 'حاضر');
      if (value == 'Absent') return t('Absent', 'غیر حاضر');
      return t('Leave', 'چھٹی');
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('Attendance', 'حاضری'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(t('Attendance date', 'حاضری کی تاریخ')),
              subtitle: Text(dateKey),
              trailing: const Icon(Icons.edit_calendar),
              onTap: chooseDate,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Select a status for each student, then save.',
              'ہر طالب علم کی حاضری منتخب کرکے محفوظ کریں۔',
            ),
          ),
          if (loadingExisting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: (widget.teacherId == null
                ? students.orderBy('name')
                : students.where('teacherId', isEqualTo: widget.teacherId).orderBy('name')).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  t(
                    'Could not load students. Check admin access.',
                    'طلبہ نہیں کھل سکے۔ ایڈمن کی اجازت چیک کریں۔',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    t(
                      'No students found. Add students first.',
                      'کوئی طالب علم موجود نہیں۔ پہلے طلبہ شامل کریں۔',
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  for (final doc in docs)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${doc.data()['name'] ?? ''}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              t(
                                'Admission: ${doc.data()['admissionNo'] ?? '-'}'
                                    ' • Class: ${doc.data()['className'] ?? '-'}',
                                'داخلہ: ${doc.data()['admissionNo'] ?? '-'}'
                                    ' • جماعت: ${doc.data()['className'] ?? '-'}',
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: statuses[doc.id],
                              decoration: InputDecoration(
                                labelText: t(
                                  'Attendance status',
                                  'حاضری کی حالت',
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              items: statusValues.map((value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(statusLabel(value)),
                                );
                              }).toList(),
                              onChanged: loadingExisting
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() => statuses[doc.id] = value);
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: saving || loadingExisting
                        ? null
                        : () => saveAttendance(docs),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(t('Save attendance', 'حاضری محفوظ کریں')),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key, required this.urdu});

  final bool urdu;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final classController = TextEditingController();
  final guardianNameController = TextEditingController();
  final phoneController = TextEditingController();
  final dobController = TextEditingController();
  final addressController = TextEditingController();
  final previousSchoolController = TextEditingController();
  final teacherIdController = TextEditingController();
  final searchController = TextEditingController();
  String gender = 'prefer_not_to_say';

  bool saving = false;
  String error = '';

  String t(String en, String ur) => widget.urdu ? ur : en;

  CollectionReference<Map<String, dynamic>> get students =>
      FirebaseFirestore.instance.collection('students');

  @override
  void dispose() {
    nameController.dispose();
    classController.dispose(); guardianNameController.dispose();
    phoneController.dispose(); dobController.dispose(); addressController.dispose();
    previousSchoolController.dispose(); teacherIdController.dispose(); searchController.dispose();
    super.dispose();
  }

  Future<void> saveStudent() async {
    if (!formKey.currentState!.validate() || saving) return;
    final dob = DateTime.tryParse(dobController.text.trim());
    if (dob == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dobController.text.trim()) || dob.isAfter(DateTime.now()) || addressController.text.trim().length < 5) {
      setState(() => error = t('Enter a valid date of birth and complete address.', 'درست تاریخِ پیدائش اور مکمل پتہ درج کریں۔'));
      return;
    }
    setState(() { saving = true; error = ''; });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('createStudentRecord').call({
        'name':nameController.text.trim(), 'className':classController.text.trim(),
        'guardianName':guardianNameController.text.trim(), 'guardianPhone':phoneController.text.trim(),
        'dateOfBirth':dobController.text.trim(), 'gender':gender, 'address':addressController.text.trim(),
        'previousSchool':previousSchoolController.text.trim(), 'teacherId':teacherIdController.text.trim(),
      });
      final data = Map<String,dynamic>.from(result.data as Map);
      nameController.clear(); classController.clear(); guardianNameController.clear(); phoneController.clear();
      dobController.clear(); addressController.clear(); previousSchoolController.clear(); teacherIdController.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Student created. Admission No: ${data['admissionNo']}', 'طالب علم کا ریکارڈ بن گیا۔ داخلہ نمبر: ${data['admissionNo']}'))));
    } on FirebaseFunctionsException catch (e) {
      setState(() => error = t('Could not create student (${e.code}): ${e.message ?? ''}', 'طالب علم کا ریکارڈ نہیں بنا (${e.code})'));
    } catch (e) {
      setState(() => error = t('Could not create student: $e', 'طالب علم کا ریکارڈ نہیں بنا: $e'));
    } finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> deleteStudent(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Deactivate student?', 'طالب علم کو غیر فعال کریں؟')),
        content: Text(
          t('The student account will be suspended if linked. Historical school records will be preserved.', 'اگر اکاؤنٹ منسلک ہے تو معطل ہوگا۔ سابقہ اسکول ریکارڈ محفوظ رہے گا۔'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'منسوخ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Deactivate', 'غیر فعال کریں')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final studentRef = students.doc(id);
      final studentSnap = await studentRef.get();
      final linkedUid = (studentSnap.data()?['linkedUserUid'] ?? '').toString();
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final userRef = linkedUid.isEmpty ? null : FirebaseFirestore.instance.collection('users').doc(linkedUid);
        final userSnap = userRef == null ? null : await tx.get(userRef);
        tx.update(studentRef, {'status':'inactive','deactivatedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
        if (userRef != null && userSnap != null && userSnap.exists) {
          tx.update(userRef, {'approvalStatus':'suspended','suspendedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
        }
      });
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('Deactivation failed: ${e.code}', 'حذف نہیں ہوسکا: ${e.code}'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(t('Students', 'طلبہ'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('Add student', 'طالب علم شامل کریں'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: t('Student name *', 'طالب علم کا نام *'),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? t('Enter a name.', 'نام درج کریں۔')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: classController,
                      decoration: InputDecoration(
                        labelText: t('Class / grade *', 'جماعت *'),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? t('Enter a class.', 'جماعت درج کریں۔')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(controller: guardianNameController, decoration: InputDecoration(labelText: t('Guardian full name *','سرپرست کا مکمل نام *')), validator: (v) => (v??'').trim().length < 2 ? t('Enter guardian name.','سرپرست کا نام درج کریں۔') : null),
                    TextFormField(controller: phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Parent/guardian phone *','والدین/سرپرست کا فون *')), validator: (v) => (v??'').trim().isEmpty ? t('Enter guardian phone.','سرپرست کا فون درج کریں۔') : null),
                    TextFormField(controller: dobController, decoration: InputDecoration(labelText: t('Date of birth (YYYY-MM-DD) *','تاریخِ پیدائش (YYYY-MM-DD) *'))),
                    DropdownButtonFormField<String>(value: gender, decoration: InputDecoration(labelText: t('Gender','جنس')), items: [DropdownMenuItem(value:'male',child:Text(t('Male','مرد'))),DropdownMenuItem(value:'female',child:Text(t('Female','عورت'))),DropdownMenuItem(value:'other',child:Text(t('Other','دیگر'))),DropdownMenuItem(value:'prefer_not_to_say',child:Text(t('Prefer not to say','بتانا نہیں چاہتے')))], onChanged:(v){if(v!=null)setState(()=>gender=v);}),
                    TextFormField(controller: addressController, maxLines:2, decoration: InputDecoration(labelText: t('Residential address *','رہائشی پتہ *'))),
                    TextFormField(controller: previousSchoolController, decoration: InputDecoration(labelText: t('Previous school (optional)','پچھلا اسکول (اختیاری)'))),
                    TextFormField(controller: teacherIdController, decoration: InputDecoration(labelText: t('Assigned Teacher ID (optional)','مقررہ ٹیچر آئی ڈی (اختیاری)'))),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: saving ? null : saveStudent,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(t('Create student and issue Admission No', 'طالب علم بنائیں اور داخلہ نمبر جاری کریں')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              labelText: t('Search students', 'طلبہ تلاش کریں'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: students.orderBy('name').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  t(
                    'Could not load students. Check Firestore rules and admin access.',
                    'طلبہ کا ریکارڈ نہیں پڑھا جاسکا۔ Firestore Rules اور ایڈمن اجازت چیک کریں۔',
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              final filtered = docs.where((doc) {
                final d = doc.data();
                final searchable = [
                  d['name'],
                  d['admissionNo'],
                  d['className'],
                ].join(' ').toLowerCase();
                return searchable.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    t(
                      'No student records yet.',
                      'ابھی طلبہ کا کوئی ریکارڈ نہیں۔',
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return Column(
                children: filtered.map((doc) {
                  final d = doc.data();
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text((d['name'] ?? '').toString()),
                      subtitle: Text(
                        '${t('Admission', 'داخلہ نمبر')}: ${d['admissionNo'] ?? ''}\n'
                        '${t('Class', 'جماعت')}: ${d['className'] ?? ''}\n'
                        '${t('Guardian phone', 'سرپرست کا فون')}: ${d['guardianPhone'] ?? '-'}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: t('Deactivate', 'غیر فعال کریں'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteStudent(doc.id),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key, required this.urdu});

  final bool urdu;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: () => FirebaseAuth.instance.signOut(),
      icon: const Icon(Icons.logout),
      label: Text(urdu ? 'لاگ آؤٹ' : 'Logout'),
    );
  }
}
