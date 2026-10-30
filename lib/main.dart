import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final guardianController = TextEditingController();
  final addressController = TextEditingController();
  final educationController = TextEditingController();
  final classController = TextEditingController();
  String requestedRole = 'student';
  XFile? profileImage;
  List<XFile> supportingDocuments = [];
  bool registering = false;
  bool busy = false;
  bool hidePassword = true;
  String message = '';

  String t(String english, String urdu) => widget.urdu ? urdu : english;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    fullNameController.dispose();
    phoneController.dispose();
    guardianController.dispose();
    addressController.dispose();
    educationController.dispose();
    classController.dispose();
    super.dispose();
  }

  Future<void> pickSupportingDocuments() async {
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (!mounted) return;
      setState(() {
        supportingDocuments = picked.take(8).toList();
        message = picked.length > 8
            ? t(
                'Selected first 8 document images (maximum 8).',
                'پہلی 8 دستاویزی تصاویر منتخب کی گئی ہیں (زیادہ سے زیادہ 8)۔',
              )
            : '';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message = t(
            'Could not select document images.',
            'دستاویزات کی تصاویر منتخب نہیں ہو سکیں۔',
          ),
        );
      }
    }
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;

    setState(() {
      busy = true;
      message = '';
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (registering) {
        if (fullNameController.text.trim().isEmpty ||
            phoneController.text.trim().isEmpty ||
            profileImage == null) {
          setState(
            () => message = t(
              'Full name, phone number and profile photo are required for an application.',
              'درخواست کے لیے مکمل نام، فون نمبر اور پروفائل تصویر ضروری ہیں۔',
            ),
          );
          return;
        }
        final result = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final user = result.user!;
        String photoUrl = '';
        try {
          final imageRef = FirebaseStorage.instance.ref(
            'profileApplications/${user.uid}/profile.jpg',
          );
          await imageRef.putData(
            await profileImage!.readAsBytes(),
            SettableMetadata(contentType: 'image/jpeg'),
          );
          photoUrl = await imageRef.getDownloadURL();
        } catch (uploadError) {
          await user.delete();
          rethrow;
        }
        final documentUrls = <String>[];
        for (var i = 0; i < supportingDocuments.length; i++) {
          final docRef = FirebaseStorage.instance.ref(
            'profileDocuments/${user.uid}/document_${i + 1}.jpg',
          );
          await docRef.putData(
            await supportingDocuments[i].readAsBytes(),
            SettableMetadata(contentType: 'image/jpeg'),
          );
          documentUrls.add(await docRef.getDownloadURL());
        }
        final profile = <String, dynamic>{
          'email': email,
          'name': fullNameController.text.trim(),
          'phone': phoneController.text.trim(),
          'guardianName': guardianController.text.trim(),
          'address': addressController.text.trim(),
          'educationOrClass': requestedRole == 'teacher'
              ? educationController.text.trim()
              : classController.text.trim(),
          'requestedRole': requestedRole,
          'role': 'pending',
          'approvalStatus': 'pending',
          'photoUrl': photoUrl,
          'documentUrls': documentUrls,
          'createdAt': FieldValue.serverTimestamp(),
          'profileComplete': true,
        };
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(profile);
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

  Future<void> pickProfilePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (picked != null && mounted) setState(() => profileImage = picked);
    } catch (e) {
      if (mounted) setState(() => message = 'Image selection failed: $e');
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
                      DropdownButtonFormField<String>(
                        initialValue: requestedRole,
                        decoration: InputDecoration(
                          labelText: t('Applying as', 'درخواست کی قسم'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'student',
                            child: Text(t('Student', 'طالب علم')),
                          ),
                          DropdownMenuItem(
                            value: 'teacher',
                            child: Text(t('Teacher', 'استاد')),
                          ),
                          DropdownMenuItem(
                            value: 'parent',
                            child: Text(t('Parent', 'والدین')),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(
                                () => requestedRole = v ?? 'student',
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: fullNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: t('Full name *', 'مکمل نام *'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            registering && (v == null || v.trim().isEmpty)
                            ? t(
                                'Enter your full name.',
                                'اپنا مکمل نام درج کریں۔',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: t('Mobile number *', 'موبائل نمبر *'),
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        validator: (v) =>
                            registering && (v == null || v.trim().length < 7)
                            ? t(
                                'Enter a valid mobile number.',
                                'درست موبائل نمبر درج کریں۔',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: guardianController,
                        decoration: InputDecoration(
                          labelText: t(
                            'Parent / guardian name',
                            'والد / سرپرست کا نام',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: t('Home address', 'گھر کا پتہ'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (requestedRole == 'teacher')
                        TextFormField(
                          controller: educationController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: t(
                              'Qualifications and experience',
                              'تعلیمی قابلیت اور تجربہ',
                            ),
                          ),
                        )
                      else if (requestedRole == 'student')
                        TextFormField(
                          controller: classController,
                          decoration: InputDecoration(
                            labelText: t(
                              'Requested class / grade',
                              'درخواست کردہ کلاس',
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : pickProfilePhoto,
                        icon: Icon(
                          profileImage == null
                              ? Icons.add_a_photo_outlined
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          profileImage == null
                              ? t(
                                  'Upload profile photo *',
                                  'پروفائل تصویر اپلوڈ کریں *',
                                )
                              : t(
                                  'Profile photo selected',
                                  'پروفائل تصویر منتخب ہوگئی',
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: busy ? null : pickSupportingDocuments,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(
                          supportingDocuments.isEmpty
                              ? t(
                                  'Upload supporting document photos (optional)',
                                  'معاون دستاویزات کی تصاویر اپلوڈ کریں (اختیاری)',
                                )
                              : t(
                                  '${supportingDocuments.length} document image(s) selected',
                                  '${supportingDocuments.length} دستاویزی تصاویر منتخب',
                                ),
                        ),
                      ),
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

        if (role == 'rejected' ||
            (data['approvalStatus'] ?? '').toString().toLowerCase() ==
                'rejected') {
          return AccountRejectedScreen(urdu: urdu);
        }

        final allowed = ['admin', 'teacher', 'student', 'parent'];

        if (!allowed.contains(role)) {
          return PendingScreen(urdu: urdu);
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
  const PendingScreen({super.key, required this.urdu});

  final bool urdu;

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
              const SizedBox(height: 20),
              SignOutButton(urdu: urdu),
            ],
          ),
        ),
      ),
    );
  }
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
      {'icon': Icons.class_, 'en': 'Classes', 'ur': 'کلاسیں'},
      {'icon': Icons.fact_check, 'en': 'Attendance', 'ur': 'حاضری'},
      {'icon': Icons.payments, 'en': 'Fees & Receipts', 'ur': 'فیس اور رسیدیں'},
      {
        'icon': Icons.assessment,
        'en': 'Exams & Results',
        'ur': 'امتحانات اور نتائج',
      },
      {'icon': Icons.menu_book, 'en': 'Homework', 'ur': 'ہوم ورک'},
      {'icon': Icons.campaign, 'en': 'Announcements', 'ur': 'اعلانات'},
      {
        'icon': Icons.badge_outlined,
        'en': 'My Profile / ID Card',
        'ur': 'میرا پروفائل / شناختی کارڈ',
      },
    ];

    switch (role) {
      case 'admin':
        return [
          ...common,
          {
            'icon': Icons.admin_panel_settings,
            'en': 'User Approvals',
            'ur': 'صارفین کی منظوری',
          },
        ];
      case 'teacher':
        return common
            .where(
              (m) => [
                'Classes',
                'Attendance',
                'Exams & Results',
                'Homework',
                'Announcements',
                'My Profile / ID Card',
              ].contains(m['en']),
            )
            .toList();
      case 'student':
        return common
            .where(
              (m) => [
                'Attendance',
                'Fees & Receipts',
                'Exams & Results',
                'Homework',
                'Announcements',
                'My Profile / ID Card',
              ].contains(m['en']),
            )
            .toList();
      default:
        return common
            .where(
              (m) => [
                'Attendance',
                'Fees & Receipts',
                'Exams & Results',
                'Homework',
                'Announcements',
                'My Profile / ID Card',
              ].contains(m['en']),
            )
            .toList();
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
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final d = snap.data?.data() ?? {};
                      final schoolId = (d['schoolId'] ?? d['admissionNo'] ?? '')
                          .toString();
                      if (schoolId.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Chip(
                          avatar: const Icon(Icons.badge_outlined),
                          label: Text(schoolId),
                        ),
                      );
                    },
                  ),
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
                    if (item['en'] == 'My Profile / ID Card') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProfileCardScreen(user: user, urdu: urdu),
                        ),
                      );
                    } else if (item['en'] == 'Announcements') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolDataModuleScreen(
                            collectionName: 'announcements',
                            titleEn: 'Announcements',
                            titleUr: 'اعلانات',
                            role: role,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else if (item['en'] == 'Teachers' && role == 'admin') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolDataModuleScreen(
                            collectionName: 'teachers',
                            titleEn: 'Teachers',
                            titleUr: 'اساتذہ',
                            role: role,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else if (item['en'] == 'Classes') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolDataModuleScreen(
                            collectionName: 'classes',
                            titleEn: 'Classes',
                            titleUr: 'کلاسیں',
                            role: role,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else if (item['en'] == 'Fees & Receipts') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolDataModuleScreen(
                            collectionName: 'fees',
                            titleEn: 'Fees & Receipts',
                            titleUr: 'فیس اور رسیدیں',
                            role: role,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else if (item['en'] == 'Exams & Results') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolDataModuleScreen(
                            collectionName: 'exams',
                            titleEn: 'Exams & Results',
                            titleUr: 'امتحانات اور نتائج',
                            role: role,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else if (item['en'] == 'Homework') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolDataModuleScreen(
                            collectionName: 'homework',
                            titleEn: 'Homework',
                            titleUr: 'ہوم ورک',
                            role: role,
                            urdu: urdu,
                          ),
                        ),
                      );
                    } else if (item['en'] == 'User Approvals' &&
                        role == 'admin') {
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
                    } else if (item['en'] == 'Attendance') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AttendanceScreen(urdu: urdu),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            label(
                              '${item['en']} module will be implemented next.',
                              '${item['ur']} کا ماڈیول اگلے مرحلے میں تیار ہوگا۔',
                            ),
                          ),
                        ),
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

  Future<void> review(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!mounted || !snap.exists) return;
    final applicant = snap.data() ?? <String, dynamic>{};
    final requested = (applicant['requestedRole'] ?? 'student').toString();
    final roleController = ValueNotifier<String>(
      ['student', 'teacher', 'parent'].contains(requested)
          ? requested
          : 'student',
    );
    final studentId = TextEditingController();
    final admissionNo = TextEditingController();
    final teacherId = TextEditingController();
    final className = TextEditingController(
      text: requested == 'student'
          ? (applicant['educationOrClass'] ?? '').toString()
          : '',
    );
    final rejectionReason = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(t('Review application', 'درخواست کا جائزہ')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${t('Name', 'نام')}: ${applicant['name'] ?? '-'}'),
                    Text(
                      '${t('Email', 'ای میل')}: ${applicant['email'] ?? '-'}',
                    ),
                    Text('${t('Phone', 'فون')}: ${applicant['phone'] ?? '-'}'),
                    Text(
                      '${t('Guardian', 'سرپرست')}: ${applicant['guardianName'] ?? '-'}',
                    ),
                    Text(
                      '${t('Address', 'پتہ')}: ${applicant['address'] ?? '-'}',
                    ),
                    Text(
                      '${t('Requested role', 'درخواست کردہ کردار')}: $requested',
                    ),
                    if (applicant['documentUrls'] is List &&
                        (applicant['documentUrls'] as List).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        t(
                          'Supporting document links (open/copy for review):',
                          'معاون دستاویزات کے لنکس (جائزے کے لیے کھولیں/کاپی کریں):',
                        ),
                      ),
                      for (final url
                          in (applicant['documentUrls'] as List)
                              .whereType<String>())
                        SelectableText(
                          url,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                    ],
                    const Divider(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: roleController.value,
                      decoration: InputDecoration(
                        labelText: t('Final role', 'حتمی کردار'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text(t('Student', 'طالب علم')),
                        ),
                        DropdownMenuItem(
                          value: 'teacher',
                          child: Text(t('Teacher', 'استاد')),
                        ),
                        DropdownMenuItem(
                          value: 'parent',
                          child: Text(t('Parent', 'والدین')),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text(
                            t('Reject application', 'درخواست مسترد کریں'),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          refresh(() => roleController.value = v ?? 'student'),
                    ),
                    if (roleController.value == 'student') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: studentId,
                        decoration: InputDecoration(
                          labelText: t(
                            'Student ID (manual) *',
                            'طالب علم آئی ڈی (خود درج کریں) *',
                          ),
                        ),
                        validator: (v) =>
                            roleController.value == 'student' &&
                                (v == null || v.trim().isEmpty)
                            ? t(
                                'Enter a Student ID.',
                                'طالب علم آئی ڈی درج کریں۔',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: admissionNo,
                        decoration: InputDecoration(
                          labelText: t(
                            'Admission Number (separate) *',
                            'داخلہ نمبر (الگ) *',
                          ),
                        ),
                        validator: (v) =>
                            roleController.value == 'student' &&
                                (v == null || v.trim().isEmpty)
                            ? t(
                                'Enter an admission number.',
                                'داخلہ نمبر درج کریں۔',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: className,
                        decoration: InputDecoration(
                          labelText: t('Class / grade *', 'کلاس / جماعت *'),
                        ),
                        validator: (v) =>
                            roleController.value == 'student' &&
                                (v == null || v.trim().isEmpty)
                            ? t(
                                'Enter the approved class.',
                                'منظور شدہ کلاس درج کریں۔',
                              )
                            : null,
                      ),
                    ],
                    if (roleController.value == 'teacher') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: teacherId,
                        decoration: InputDecoration(
                          labelText: t(
                            'Teacher ID (manual) *',
                            'ٹیچر آئی ڈی (خود درج کریں) *',
                          ),
                        ),
                        validator: (v) =>
                            roleController.value == 'teacher' &&
                                (v == null || v.trim().isEmpty)
                            ? t('Enter a Teacher ID.', 'ٹیچر آئی ڈی درج کریں۔')
                            : null,
                      ),
                    ],
                    if (roleController.value == 'rejected') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: rejectionReason,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: t(
                            'Reason / corrections required',
                            'وجہ / مطلوبہ اصلاحات',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'IDs are entered by the admin. Student ID and Admission Number are different fields; no ID is generated automatically.',
                        'آئی ڈیز ایڈمن خود درج کرے گا۔ طالب علم آئی ڈی اور داخلہ نمبر الگ ہیں؛ کوئی آئی ڈی خودکار نہیں بنے گی۔',
                      ),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel', 'منسوخ')),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx, {
                  'role': roleController.value,
                  'studentId': studentId.text.trim(),
                  'admissionNo': admissionNo.text.trim(),
                  'teacherId': teacherId.text.trim(),
                  'className': className.text.trim(),
                  'rejectionReason': rejectionReason.text.trim(),
                });
              },
              child: Text(t('Save decision', 'فیصلہ محفوظ کریں')),
            ),
          ],
        ),
      ),
    );
    roleController.dispose();
    studentId.dispose();
    admissionNo.dispose();
    teacherId.dispose();
    className.dispose();
    rejectionReason.dispose();
    if (result == null || !mounted) return;
    await decide(uid, applicant, result);
  }

  String _normalId(String value) => value.trim().toUpperCase();
  bool _validId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{2,30}$').hasMatch(value.trim());

  Future<void> decide(
    String uid,
    Map<String, dynamic> applicant,
    Map<String, String> decision,
  ) async {
    if (busy) return;
    final role = decision['role'] ?? 'rejected';
    final approved = role != 'rejected';
    final sid = decision['studentId'] ?? '';
    final admission = decision['admissionNo'] ?? '';
    final tid = decision['teacherId'] ?? '';
    final className = decision['className'] ?? '';
    if (role == 'student' &&
        (!_validId(sid) ||
            !_validId(admission) ||
            sid.toUpperCase() == admission.toUpperCase())) {
      setState(
        () => error = t(
          'Enter valid, different Student ID and Admission Number (2–30 letters/numbers, _ or -).',
          'درست اور الگ طالب علم آئی ڈی اور داخلہ نمبر درج کریں (2 تا 30 حروف/اعداد، _ یا -)۔',
        ),
      );
      return;
    }
    if (role == 'teacher' && !_validId(tid)) {
      setState(
        () => error = t(
          'Enter a valid Teacher ID (2–30 letters/numbers, _ or -).',
          'درست ٹیچر آئی ڈی درج کریں (2 تا 30 حروف/اعداد، _ یا -)۔',
        ),
      );
      return;
    }
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
      final userRef = db.collection('users').doc(uid);
      final studentRef = db.collection('students').doc(uid);
      final teacherRef = db.collection('teachers').doc(uid);
      final idValues = <String>[];
      if (role == 'student') idValues.addAll([sid, admission]);
      if (role == 'teacher') idValues.add(tid);
      final registryRefs = idValues
          .map((v) => db.collection('idRegistry').doc(_normalId(v)))
          .toList();

      // Check existing profiles as well as the registry, so older records are included.
      for (final value in idValues) {
        for (final field in [
          'schoolId',
          'studentId',
          'teacherId',
          'admissionNo',
        ]) {
          final matches = await db
              .collection('users')
              .where(field, isEqualTo: value)
              .limit(1)
              .get();
          if (matches.docs.any((d) => d.id != uid)) {
            throw StateError(
              t(
                'ID already exists: $value',
                'یہ آئی ڈی پہلے سے موجود ہے: $value',
              ),
            );
          }
        }
        if (role == 'student') {
          for (final field in ['studentId', 'admissionNo']) {
            final matches = await db
                .collection('students')
                .where(field, isEqualTo: value)
                .limit(1)
                .get();
            if (matches.docs.any((d) => d.id != uid)) {
              throw StateError(
                t(
                  'ID already exists in student records: $value',
                  'یہ آئی ڈی طلبہ کے ریکارڈ میں پہلے سے موجود ہے: $value',
                ),
              );
            }
          }
        }
        if (role == 'teacher') {
          final matches = await db
              .collection('teachers')
              .where('teacherId', isEqualTo: value)
              .limit(1)
              .get();
          if (matches.docs.any((d) => d.id != uid)) {
            throw StateError(
              t(
                'Teacher ID already exists: $value',
                'ٹیچر آئی ڈی پہلے سے موجود ہے: $value',
              ),
            );
          }
        }
      }

      await db.runTransaction((tx) async {
        final fresh = await tx.get(userRef);
        if (!fresh.exists || fresh.data()?['role'] != 'pending') {
          throw StateError('This request is no longer pending.');
        }
        final registrySnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in registryRefs) {
          registrySnapshots.add(await tx.get(ref));
        }
        if (registrySnapshots.any((d) => d.exists)) {
          throw StateError(
            t(
              'One of these IDs is already registered. Check the IDs and try again.',
              'ان میں سے کوئی آئی ڈی پہلے سے رجسٹر ہے۔ آئی ڈیز چیک کرکے دوبارہ کوشش کریں۔',
            ),
          );
        }
        final update = <String, dynamic>{
          'role': role,
          'approvalStatus': approved ? 'approved' : 'rejected',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': admin.uid,
          'rejectionReason': approved
              ? FieldValue.delete()
              : (decision['rejectionReason'] ?? ''),
        };
        if (role == 'student') {
          update.addAll({
            'studentId': sid,
            'schoolId': sid,
            'admissionNo': admission,
            'className': className,
            'cardIssuedAt': FieldValue.serverTimestamp(),
          });
        } else if (role == 'teacher') {
          update.addAll({
            'teacherId': tid,
            'schoolId': tid,
            'cardIssuedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.update(userRef, update);
        for (int i = 0; i < registryRefs.length; i++) {
          tx.set(registryRefs[i], {
            'value': _normalId(idValues[i]),
            'userId': uid,
            'kind': role == 'student'
                ? (i == 0 ? 'studentId' : 'admissionNo')
                : 'teacherId',
            'createdBy': admin.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (role == 'student') {
          tx.set(studentRef, {
            'userId': uid,
            'name': applicant['name'] ?? '',
            'studentId': sid,
            'admissionNo': admission,
            'className': className,
            'guardianPhone': applicant['phone'] ?? '',
            'guardianName': applicant['guardianName'] ?? '',
            'createdBy': admin.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'active': true,
          }, SetOptions(merge: true));
        } else if (role == 'teacher') {
          tx.set(teacherRef, {
            'userId': uid,
            'name': applicant['name'] ?? '',
            'teacherId': tid,
            'email': applicant['email'] ?? '',
            'phone': applicant['phone'] ?? '',
            'qualification': applicant['educationOrClass'] ?? '',
            'createdBy': admin.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'active': true,
          }, SetOptions(merge: true));
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? t(
                    'Account approved and records linked.',
                    'اکاؤنٹ منظور اور ریکارڈ منسلک ہوگئے۔',
                  )
                : t('Application rejected.', 'درخواست مسترد ہوگئی۔'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    t(
                      'Admin manually enters unique IDs. Student ID and Admission Number are separate. Approval also creates/updates the linked student or teacher record.',
                      'ایڈمن منفرد آئی ڈیز خود درج کرے گا۔ طالب علم آئی ڈی اور داخلہ نمبر الگ ہیں۔ منظوری کے ساتھ منسلک طالب علم یا استاد کا ریکارڈ بھی بنتا/اپ ڈیٹ ہوتا ہے۔',
                    ),
                  ),
                ),
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
                    title: Text(
                      (doc.data()['name'] ?? doc.data()['email'] ?? doc.id)
                          .toString(),
                    ),
                    subtitle: Text(
                      '${doc.data()['requestedRole'] ?? 'pending'} • ${doc.data()['email'] ?? ''}\n${doc.data()['phone'] ?? ''} • UID: ${doc.id}',
                    ),
                    isThreeLine: true,
                    leading: CircleAvatar(
                      backgroundImage:
                          (doc.data()['photoUrl'] is String &&
                              (doc.data()['photoUrl'] as String).isNotEmpty)
                          ? NetworkImage(doc.data()['photoUrl'] as String)
                          : null,
                      child:
                          (doc.data()['photoUrl'] is String &&
                              (doc.data()['photoUrl'] as String).isNotEmpty)
                          ? null
                          : const Icon(Icons.person),
                    ),
                    trailing: IconButton(
                      onPressed: busy ? null : () => review(doc.id),
                      icon: const Icon(Icons.fact_check),
                      tooltip: t('Review', 'جائزہ'),
                    ),
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

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.urdu});
  final bool urdu;

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
      final result = await attendance.where('date', isEqualTo: dateKey).get();
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
          'admissionNo': data['admissionNo'] ?? '',
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
            stream: students.orderBy('name').snapshots(),
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
                                'Student ID: ${doc.data()['studentId'] ?? '-'} • Admission: ${doc.data()['admissionNo'] ?? '-'}'
                                    ' • Class: ${doc.data()['className'] ?? '-'}',
                                'طالب علم آئی ڈی: ${doc.data()['studentId'] ?? '-'} • داخلہ: ${doc.data()['admissionNo'] ?? '-'}'
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
  final studentIdController = TextEditingController();
  final admissionController = TextEditingController();
  final classController = TextEditingController();
  final phoneController = TextEditingController();
  final searchController = TextEditingController();

  bool saving = false;
  String error = '';

  String t(String en, String ur) => widget.urdu ? ur : en;

  CollectionReference<Map<String, dynamic>> get students =>
      FirebaseFirestore.instance.collection('students');

  @override
  void dispose() {
    nameController.dispose();
    studentIdController.dispose();
    admissionController.dispose();
    classController.dispose();
    phoneController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> saveStudent() async {
    if (!formKey.currentState!.validate() || saving) return;
    final studentId = studentIdController.text.trim();
    final admissionNo = admissionController.text.trim();
    final validId = RegExp(r'^[A-Za-z0-9_-]{2,30}$');
    if (!validId.hasMatch(studentId) ||
        !validId.hasMatch(admissionNo) ||
        studentId.toUpperCase() == admissionNo.toUpperCase()) {
      setState(
        () => error = t(
          'Enter different valid Student ID and Admission Number (2–30 letters/numbers, _ or -).',
          'الگ الگ درست طالب علم آئی ڈی اور داخلہ نمبر درج کریں (2 تا 30 حروف/اعداد، _ یا -)۔',
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      final db = FirebaseFirestore.instance;
      final normalizedStudentId = studentId.toUpperCase();
      final normalizedAdmission = admissionNo.toUpperCase();
      for (final value in [studentId, admissionNo]) {
        for (final field in [
          'studentId',
          'admissionNo',
          'schoolId',
          'teacherId',
        ]) {
          final matches = await db
              .collection('users')
              .where(field, isEqualTo: value)
              .limit(1)
              .get();
          if (matches.docs.isNotEmpty) {
            throw StateError(
              t(
                'This ID already exists: $value',
                'یہ آئی ڈی پہلے سے موجود ہے: $value',
              ),
            );
          }
        }
        for (final field in ['studentId', 'admissionNo']) {
          final matches = await students
              .where(field, isEqualTo: value)
              .limit(1)
              .get();
          if (matches.docs.isNotEmpty) {
            throw StateError(
              t(
                'This ID already exists: $value',
                'یہ آئی ڈی پہلے سے موجود ہے: $value',
              ),
            );
          }
        }
      }
      final studentRef = students.doc();
      final registryRefs = [
        db.collection('idRegistry').doc(normalizedStudentId),
        db.collection('idRegistry').doc(normalizedAdmission),
      ];
      final adminUid = FirebaseAuth.instance.currentUser!.uid;
      await db.runTransaction((tx) async {
        final a = await tx.get(registryRefs[0]);
        final b = await tx.get(registryRefs[1]);
        if (a.exists || b.exists) {
          throw StateError(
            t(
              'One of these IDs is already registered.',
              'ان میں سے کوئی آئی ڈی پہلے سے رجسٹر ہے۔',
            ),
          );
        }
        tx.set(studentRef, {
          'name': nameController.text.trim(),
          'studentId': studentId,
          'admissionNo': admissionNo,
          'className': classController.text.trim(),
          'guardianPhone': phoneController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': adminUid,
          'active': true,
        });
        tx.set(registryRefs[0], {
          'value': normalizedStudentId,
          'kind': 'studentId',
          'studentDocId': studentRef.id,
          'createdBy': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(registryRefs[1], {
          'value': normalizedAdmission,
          'kind': 'admissionNo',
          'studentDocId': studentRef.id,
          'createdBy': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      nameController.clear();
      studentIdController.clear();
      admissionController.clear();
      classController.clear();
      phoneController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('Student saved.', 'طالب علم کا ریکارڈ محفوظ ہوگیا۔'),
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => error = t(
            'Could not save. Check Firestore permissions (${e.code}).',
            'ریکارڈ محفوظ نہیں ہوا۔ Firestore اجازتیں چیک کریں (${e.code})۔',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> deleteStudent(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Delete student?', 'طالب علم کا ریکارڈ حذف کریں؟')),
        content: Text(
          t('This action cannot be undone.', 'یہ عمل واپس نہیں ہوسکے گا۔'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'منسوخ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Delete', 'حذف کریں')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final ref = students.doc(id);
      final snap = await ref.get();
      final data = snap.data() ?? <String, dynamic>{};
      if ((data['userId'] ?? '').toString().isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t(
                  'This record is linked to a login account; do not delete it here.',
                  'یہ ریکارڈ لاگ اِن اکاؤنٹ سے منسلک ہے؛ اسے یہاں حذف نہ کریں۔',
                ),
              ),
            ),
          );
        }
        return;
      }
      final studentKey = (data['studentId'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final admissionKey = (data['admissionNo'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      await db.runTransaction((tx) async {
        if (studentKey.isNotEmpty) {
          tx.delete(db.collection('idRegistry').doc(studentKey));
        }
        if (admissionKey.isNotEmpty) {
          tx.delete(db.collection('idRegistry').doc(admissionKey));
        }
        tx.delete(ref);
      });
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('Delete failed: ${e.code}', 'حذف نہیں ہوسکا: ${e.code}'),
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
                      controller: studentIdController,
                      decoration: InputDecoration(
                        labelText: t('Student ID *', 'طالب علم آئی ڈی *'),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? t(
                              'Enter a Student ID.',
                              'طالب علم آئی ڈی درج کریں۔',
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: admissionController,
                      decoration: InputDecoration(
                        labelText: t(
                          'Admission number * (separate)',
                          'داخلہ نمبر * (الگ)',
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? t(
                              'Enter an admission number.',
                              'داخلہ نمبر درج کریں۔',
                            )
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
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: t(
                          'Parent/guardian phone',
                          'والدین/سرپرست کا فون',
                        ),
                      ),
                    ),
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
                      label: Text(t('Save student', 'ریکارڈ محفوظ کریں')),
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
                        tooltip: t('Delete', 'حذف کریں'),
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

class ProfileCardScreen extends StatelessWidget {
  const ProfileCardScreen({super.key, required this.user, required this.urdu});
  final User user;
  final bool urdu;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance.collection('users').doc(user.uid);
    String t(String en, String ur) => urdu ? ur : en;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('My Profile & ID Card', 'میرا پروفائل اور شناختی کارڈ')),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                t('Could not load profile.', 'پروفائل نہیں کھل سکا۔'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return Center(
              child: Text(
                t('Profile record not found.', 'پروفائل ریکارڈ نہیں ملا۔'),
              ),
            );
          }

          final d = snapshot.data!.data() ?? <String, dynamic>{};
          final photo = (d['photoUrl'] ?? '').toString();
          final role = (d['role'] ?? 'pending').toString();
          final id =
              (role == 'student'
                      ? (d['studentId'] ??
                            d['schoolId'] ??
                            t('Pending approval', 'منظوری کا انتظار'))
                      : role == 'teacher'
                      ? (d['teacherId'] ??
                            d['schoolId'] ??
                            t('Pending approval', 'منظوری کا انتظار'))
                      : role == 'parent'
                      ? t(
                          'No ID assigned to parent',
                          'والدین کو آئی ڈی جاری نہیں ہوتی',
                        )
                      : t('Pending approval', 'منظوری کا انتظار'))
                  .toString();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundImage: photo.isNotEmpty
                            ? NetworkImage(photo)
                            : null,
                        child: photo.isEmpty
                            ? const Icon(Icons.person, size: 48)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (d['name'] ?? user.email ?? 'SchoolPro User')
                            .toString(),
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        id,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        t(
                          'Digital school identity card',
                          'ڈیجیٹل اسکول شناختی کارڈ',
                        ),
                      ),
                      const Divider(height: 28),
                      _profileRow(context, t('Role', 'کردار'), role),
                      _profileRow(
                        context,
                        t('Email', 'ای میل'),
                        (d['email'] ?? user.email ?? '').toString(),
                      ),
                      _profileRow(
                        context,
                        t('Phone', 'فون'),
                        (d['phone'] ?? '-').toString(),
                      ),
                      _profileRow(
                        context,
                        t('Guardian', 'سرپرست'),
                        (d['guardianName'] ?? '-').toString(),
                      ),
                      _profileRow(
                        context,
                        t('Address', 'پتہ'),
                        (d['address'] ?? '-').toString(),
                      ),
                      if (role == 'student') ...[
                        _profileRow(
                          context,
                          t('Student ID', 'طالب علم آئی ڈی'),
                          (d['studentId'] ?? d['schoolId'] ?? '-').toString(),
                        ),
                        _profileRow(
                          context,
                          t('Admission Number', 'داخلہ نمبر'),
                          (d['admissionNo'] ?? '-').toString(),
                        ),
                        _profileRow(
                          context,
                          t('Class / grade', 'کلاس / جماعت'),
                          (d['className'] ?? d['educationOrClass'] ?? '-')
                              .toString(),
                        ),
                      ],
                      if (role == 'teacher')
                        _profileRow(
                          context,
                          t('Teacher ID', 'ٹیچر آئی ڈی'),
                          (d['teacherId'] ?? d['schoolId'] ?? '-').toString(),
                        ),
                      _profileRow(
                        context,
                        t('Class / qualification', 'کلاس / قابلیت'),
                        (d['educationOrClass'] ?? '-').toString(),
                      ),
                      _profileRow(
                        context,
                        t('Approval status', 'منظوری کی حالت'),
                        (d['approvalStatus'] ?? 'pending').toString(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: Text(t('Edit profile', 'پروفائل میں ترمیم کریں')),
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => ProfileEditDialog(
                      user: user,
                      urdu: urdu,
                      initialData: d,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'Your role, approval status and school ID are managed by the school administration.',
                  'آپ کا کردار، منظوری کی حالت اور اسکول شناختی نمبر انتظامیہ کے زیرِ انتظام ہیں۔',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class ProfileEditDialog extends StatefulWidget {
  const ProfileEditDialog({
    super.key,
    required this.user,
    required this.urdu,
    required this.initialData,
  });

  final User user;
  final bool urdu;
  final Map<String, dynamic> initialData;

  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  late final TextEditingController guardianController;
  late final TextEditingController addressController;
  late final TextEditingController classController;

  XFile? newPhoto;
  bool saving = false;
  String error = '';

  String t(String en, String ur) => widget.urdu ? ur : en;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    nameController = TextEditingController(text: (d['name'] ?? '').toString());
    phoneController = TextEditingController(
      text: (d['phone'] ?? '').toString(),
    );
    guardianController = TextEditingController(
      text: (d['guardianName'] ?? '').toString(),
    );
    addressController = TextEditingController(
      text: (d['address'] ?? '').toString(),
    );
    classController = TextEditingController(
      text: (d['educationOrClass'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    guardianController.dispose();
    addressController.dispose();
    classController.dispose();
    super.dispose();
  }

  Future<void> choosePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (picked != null && mounted) {
        setState(() {
          newPhoto = picked;
          error = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = t(
            'Could not select the image. Check gallery permissions.',
            'تصویر منتخب نہیں ہو سکی۔ گیلری کی اجازت چیک کریں۔',
          );
        });
      }
    }
  }

  Future<void> saveProfile() async {
    if (saving) return;

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (name.length < 2 || phone.length < 7) {
      setState(
        () => error = t(
          'Enter a valid name and phone number (at least 7 digits).',
          'درست نام اور فون نمبر درج کریں (کم از کم 7 ہندسے)۔',
        ),
      );
      return;
    }

    setState(() {
      saving = true;
      error = '';
    });

    try {
      final uid = widget.user.uid;
      final updates = <String, dynamic>{
        'name': name,
        'phone': phone,
        'guardianName': guardianController.text.trim(),
        'address': addressController.text.trim(),
        'educationOrClass': classController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newPhoto != null) {
        final ref = FirebaseStorage.instance.ref(
          'profileApplications/$uid/profile.jpg',
        );
        await ref.putData(
          await newPhoto!.readAsBytes(),
          SettableMetadata(contentType: 'image/jpeg'),
        );
        updates['photoUrl'] = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(updates);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('Profile saved successfully.', 'پروفائل کامیابی سے محفوظ ہوگیا۔'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = t(
          'Could not save profile. Check internet and Firebase permissions, then try again.',
          'پروفائل محفوظ نہیں ہو سکا۔ انٹرنیٹ اور Firebase اجازتیں چیک کرکے دوبارہ کوشش کریں۔',
        );
      });
      debugPrint('SCHOOLPRO PROFILE SAVE ERROR: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Edit profile', 'پروفائل میں ترمیم')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : choosePhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  newPhoto == null
                      ? t('Choose profile photo', 'پروفائل تصویر منتخب کریں')
                      : t('New photo selected', 'نئی تصویر منتخب ہوگئی'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t('Full name *', 'مکمل نام *'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: t('Phone number *', 'فون نمبر *'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: guardianController,
                decoration: InputDecoration(
                  labelText: t('Parent / guardian', 'والد / سرپرست'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('Home address', 'گھر کا پتہ'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: classController,
                decoration: InputDecoration(
                  labelText: t('Class / qualification', 'کلاس / قابلیت'),
                ),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: Text(t('Cancel', 'منسوخ')),
        ),
        FilledButton(
          onPressed: saving ? null : saveProfile,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Save changes', 'تبدیلیاں محفوظ کریں')),
        ),
      ],
    );
  }
}

class SchoolDataModuleScreen extends StatefulWidget {
  const SchoolDataModuleScreen({
    super.key,
    required this.collectionName,
    required this.titleEn,
    required this.titleUr,
    required this.role,
    required this.urdu,
  });
  final String collectionName, titleEn, titleUr, role;
  final bool urdu;
  @override
  State<SchoolDataModuleScreen> createState() => _SchoolDataModuleScreenState();
}

class _SchoolDataModuleScreenState extends State<SchoolDataModuleScreen> {
  final titleController = TextEditingController();
  final detailsController = TextEditingController();
  final classController = TextEditingController();
  final amountController = TextEditingController();
  bool saving = false;
  String error = '';
  String t(String en, String ur) => widget.urdu ? ur : en;
  bool get canCreate => widget.role == 'admin' || widget.role == 'teacher';

  @override
  void dispose() {
    titleController.dispose();
    detailsController.dispose();
    classController.dispose();
    amountController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (titleController.text.trim().isEmpty || saving) {
      setState(() => error = t('Title is required.', 'عنوان ضروری ہے۔'));
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await FirebaseFirestore.instance.collection(widget.collectionName).add({
        'title': titleController.text.trim(),
        'details': detailsController.text.trim(),
        'className': classController.text.trim(),
        if (amountController.text.trim().isNotEmpty)
          'amount': double.tryParse(amountController.text.trim()) ?? 0,
        'createdBy': FirebaseAuth.instance.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
      });
      titleController.clear();
      detailsController.clear();
      classController.clear();
      amountController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Record published.', 'ریکارڈ شائع ہوگیا۔'))),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () =>
              error = t('Save failed: ${e.code}', 'محفوظ نہیں ہوا: ${e.code}'),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> remove(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(id)
          .delete();
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: ${e.code}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.urdu ? widget.titleUr : widget.titleEn;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(widget.collectionName)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  t(
                    'Unable to load records. Confirm the Firestore rules are deployed and your role has access.',
                    'ریکارڈ نہیں کھل سکے۔ Firestore Rules اور کردار کی اجازت چیک کریں۔',
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (canCreate)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('Create new record', 'نیا ریکارڈ بنائیں'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: t('Title *', 'عنوان *'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: detailsController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: t(
                              'Details / instructions',
                              'تفصیل / ہدایات',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: classController,
                          decoration: InputDecoration(
                            labelText: t('Class (optional)', 'کلاس (اختیاری)'),
                          ),
                        ),
                        if (widget.collectionName == 'fees') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: t('Amount (PKR)', 'رقم (روپے)'),
                            ),
                          ),
                        ],
                        if (error.isNotEmpty)
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: saving ? null : save,
                          icon: const Icon(Icons.publish),
                          label: Text(
                            saving
                                ? t('Saving…', 'محفوظ ہو رہا ہے…')
                                : t('Publish / Save', 'شائع / محفوظ کریں'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t(
                      'No records have been published yet.',
                      'ابھی کوئی ریکارڈ شائع نہیں ہوا۔',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final doc in docs)
                Card(
                  child: ListTile(
                    leading: Icon(
                      widget.collectionName == 'announcements'
                          ? Icons.notifications_active_outlined
                          : Icons.article_outlined,
                    ),
                    title: Text(
                      (doc.data()['title'] ??
                              doc.data()['name'] ??
                              doc.data()['teacherId'] ??
                              '')
                          .toString(),
                    ),
                    subtitle: Text(
                      '${doc.data()['details'] ?? doc.data()['qualification'] ?? ''}${doc.data()['className'] == null || (doc.data()['className'] as String).isEmpty ? '' : '\nClass: ${doc.data()['className']}'}${doc.data()['teacherId'] == null ? '' : '\nTeacher ID: ${doc.data()['teacherId']}'}${doc.data()['email'] == null ? '' : '\n${doc.data()['email']}'}${doc.data()['phone'] == null ? '' : '\n${doc.data()['phone']}'}${doc.data()['amount'] == null ? '' : '\nPKR ${doc.data()['amount']}'}',
                    ),
                    isThreeLine: true,
                    trailing: widget.role == 'admin'
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => remove(doc.id),
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
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
