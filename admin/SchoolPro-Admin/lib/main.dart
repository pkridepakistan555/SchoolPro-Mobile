import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_modules.dart';

import 'firebase_options.dart';
import 'profile_documents_screen.dart';
import 'admin_workflows_screen.dart';
import 'admin_reporting_screen.dart';
import 'admin_printing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SchoolProAdminApp());
}

class SchoolProAdminApp extends StatelessWidget {
  const SchoolProAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SchoolPro Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B55)),
        useMaterial3: true,
      ),
      home: const AuthRouter(),
    );
  }
}

class AuthRouter extends StatelessWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) return const AdminLoginScreen();

        return AdminAccessGate(user: user);
      },
    );
  }
}

class AdminAccessGate extends StatelessWidget {
  const AdminAccessGate({super.key, required this.user});

  final User user;

  Future<bool> _isAdmin() async {
    final token = await user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        if (snapshot.hasError || snapshot.data != true) {
          return const AccessDeniedScreen();
        }

        return const AdminDashboard();
      },
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

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('Login failed. Please try again.');
      }

      final token = await user.getIdTokenResult(true);

      if (token.claims?['admin'] != true) {
        await FirebaseAuth.instance.signOut();
        throw Exception('یہ اکاؤنٹ Admin کے طور پر مجاز نہیں ہے۔');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = switch (e.code) {
            'invalid-credential' ||
            'wrong-password' ||
            'user-not-found' => 'ای میل یا پاس ورڈ درست نہیں۔',
            'invalid-email' => 'درست ای میل درج کریں۔',
            'too-many-requests' =>
              'بہت زیادہ کوششیں ہوئیں۔ کچھ دیر بعد دوبارہ کوشش کریں۔',
            'network-request-failed' => 'انٹرنیٹ کنکشن چیک کریں۔',
            _ => 'لاگ اِن نہیں ہو سکا (${e.code})',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings,
                        size: 64,
                        color: Color(0xFF176B55),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'SchoolPro Admin',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'صرف مجاز منتظمین کے لیے',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Admin Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null ||
                              !value.contains('@') ||
                              value.trim().isEmpty) {
                            return 'درست ای میل درج کریں۔';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _hidePassword,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'پاس ورڈ درج کریں۔'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_busy ? 'Please wait...' : 'Admin Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gpp_bad_outlined, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Admin Access Denied',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'اس اکاؤنٹ کے پاس مطلوبہ Admin اجازت موجود نہیں۔',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Admin';

    void openScreen(Widget screen) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    Widget module({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 250,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(subtitle),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget collectionModule({
      required IconData icon,
      required String title,
      required String subtitle,
      required String collection,
    }) {
      return module(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => openScreen(
          AdminCollectionScreen(
            title: title,
            collectionName: collection,
            description: subtitle,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SchoolPro Admin Panel'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text('Signed in as: $email'),
                const SizedBox(height: 20),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.verified_user_outlined),
                    title: Text('Admin verification successful'),
                    subtitle: Text('Firebase custom claim admin = true'),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Core Management',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    module(
                      icon: Icons.how_to_reg,
                      title: 'User Approvals',
                      subtitle: 'Review pending accounts',
                      onTap: () => openScreen(const UserApprovalsScreen()),
                    ),
                    module(
                      icon: Icons.account_tree_outlined,
                      title: 'School administration workflows',
                      subtitle: 'Parent multi-child links and teacher leave reviews',
                      onTap: () => openScreen(const AdminWorkflowsScreen()),
                    ),
                    module(
                      icon: Icons.folder_shared,
                      title: 'Admin profile documents',
                      subtitle: 'Upload admin profile photo and files',
                      onTap: () { final u = FirebaseAuth.instance.currentUser; if (u != null) openScreen(ProfileDocumentsScreen(user: u)); },
                    ),
                    module(
                      icon: Icons.school_outlined,
                      title: 'Students',
                      subtitle: 'View and add student records',
                      onTap: () => openScreen(const StudentsManagementScreen()),
                    ),
                    module(
                      icon: Icons.fact_check_outlined,
                      title: 'Attendance',
                      subtitle: 'Mark and review attendance',
                      onTap: () =>
                          openScreen(const AttendanceManagementScreen()),
                    ),
                    collectionModule(
                      icon: Icons.people_outline,
                      title: 'Teachers',
                      subtitle: 'Teacher records (read-only preview)',
                      collection: 'teachers',
                    ),
                    collectionModule(
                      icon: Icons.family_restroom,
                      title: 'Parents',
                      subtitle: 'Parent records (read-only preview)',
                      collection: 'parents',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Staff HR & Payroll', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  collectionModule(icon: Icons.access_time, title: 'Teacher Attendance', subtitle: 'Daily staff attendance, check-in and check-out', collection: 'teacherAttendance'),
                  collectionModule(icon: Icons.account_balance_wallet_outlined, title: 'Teacher Payroll', subtitle: 'Monthly salary, allowances, deductions and payment status', collection: 'teacherPayroll'),
                ]),
                const SizedBox(height: 24),
                Text(
                  'Academic Management',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    collectionModule(
                      icon: Icons.class_outlined,
                      title: 'Classes',
                      subtitle: 'Class and section records',
                      collection: 'classes',
                    ),
                    collectionModule(
                      icon: Icons.menu_book_outlined,
                      title: 'Subjects',
                      subtitle: 'Subject records',
                      collection: 'subjects',
                    ),
                    collectionModule(
                      icon: Icons.calendar_month_outlined,
                      title: 'Timetable',
                      subtitle: 'Class schedules',
                      collection: 'timetables',
                    ),
                    collectionModule(
                      icon: Icons.assignment_outlined,
                      title: 'Exams',
                      subtitle: 'Exam schedules and records',
                      collection: 'exams',
                    ),
                    collectionModule(
                      icon: Icons.grade_outlined,
                      title: 'Results & Report Cards',
                      subtitle: 'Academic results',
                      collection: 'results',
                    ),
                    collectionModule(
                      icon: Icons.task_outlined,
                      title: 'Assignments',
                      subtitle: 'Assignments and homework',
                      collection: 'assignments',
                    ),
                    collectionModule(
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'Homework Submissions',
                      subtitle: 'Review submitted student work and feedback',
                      collection: 'homeworkSubmissions',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Finance & Communication',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    collectionModule(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Fee Setup & Dues',
                      subtitle: 'Fee structures and outstanding dues',
                      collection: 'feeStructures',
                    ),
                    collectionModule(
                      icon: Icons.receipt_long_outlined,
                      title: 'Fee Payments & Receipts',
                      subtitle: 'Payment records',
                      collection: 'feePayments',
                    ),
                    collectionModule(
                      icon: Icons.payments_outlined,
                      title: 'Expenses & Accounts',
                      subtitle: 'School expense records',
                      collection: 'expenses',
                    ),
                    collectionModule(
                      icon: Icons.campaign_outlined,
                      title: 'Notices',
                      subtitle: 'Announcements',
                      collection: 'notices',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Administration & Reporting',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    module(
                      icon: Icons.assessment_outlined,
                      title: 'Reports & PDF / CSV Exports',
                      subtitle: 'Generate report cards, finance and attendance reports',
                      onTap: () => openScreen(const AdminReportingScreen()),
                    ),
                    collectionModule(
                      icon: Icons.bar_chart_outlined,
                      title: 'Saved Reports',
                      subtitle: 'View generated report records',
                      collection: 'reports',
                    ),
                    collectionModule(
                      icon: Icons.settings_outlined,
                      title: 'School Settings',
                      subtitle: 'School configuration records',
                      collection: 'schoolSettings',
                    ),
                    collectionModule(
                      icon: Icons.security_outlined,
                      title: 'Admin Audit Logs',
                      subtitle: 'Administrative activity records',
                      collection: 'adminAuditLogs',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'اہم نوٹ: Admin Web میں منظور شدہ collections کے '
                      'ریکارڈ دیکھنے، شامل کرنے، ترمیم اور حذف کرنے کے '
                      'فارمز موجود ہیں۔ Fee Payments میں رسید نمبر خودکار '
                      'طور پر transaction کے ذریعے جاری ہوتا ہے اور ادائیگی '
                      'ریکارڈ append-only رہتا ہے۔ PDF/پرنٹنگ، CSV export، '
                      'اور مکمل مالیاتی reconciliation ابھی الگ کام ہیں۔',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AttendanceManagementScreen extends StatefulWidget {
  const AttendanceManagementScreen({super.key});

  @override
  State<AttendanceManagementScreen> createState() =>
      _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState
    extends State<AttendanceManagementScreen> {
  DateTime _date = DateTime.now();
  String? _className;
  final Map<String, String> _statuses = {};
  final Set<String> _saving = {};

  String get _dateKey =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        _date = selected;
        _statuses.clear();
      });
    }
  }

  Future<void> _saveStudent(
    QueryDocumentSnapshot<Map<String, dynamic>> student,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> existing,
  ) async {
    final id = student.id;
    if (_saving.contains(id)) return;

    final data = student.data();
    final status = _statuses[id] ?? 'Present';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _message('Admin session expired. Sign in again.');
      return;
    }

    setState(() => _saving.add(id));
    try {
      final matches = existing
          .where(
            (doc) =>
                doc.data()['studentId'] == id && doc.data()['date'] == _dateKey,
          )
          .toList();

      if (matches.isNotEmpty) {
        await matches.first.reference.update({
          'status': status,
          'markedBy': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('attendance').add({
          'studentId': id,
          'studentName': (data['name'] ?? '').toString(),
          'admissionNo': (data['admissionNo'] ?? '').toString(),
          'className': (data['className'] ?? '').toString(),
          'date': _dateKey,
          'status': status,
          'markedBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        _message('Attendance saved: ${data['name'] ?? 'Student'}');
      }
    } catch (e) {
      if (mounted) _message('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final studentsQuery = FirebaseFirestore.instance
        .collection('students')
        .orderBy('name')
        .limit(500);

    final attendanceQuery = FirebaseFirestore.instance
        .collection('attendance')
        .where('date', isEqualTo: _dateKey);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Management'),
        actions: [
          IconButton(
            tooltip: 'Choose date',
            onPressed: _chooseDate,
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available),
                    title: Text('Attendance date: $_dateKey'),
                    subtitle: const Text(
                      'Choose a date, select a class, then save each student.',
                    ),
                    trailing: OutlinedButton(
                      onPressed: _chooseDate,
                      child: const Text('Change date'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: studentsQuery.snapshots(),
                    builder: (context, studentSnapshot) {
                      if (studentSnapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load students: '
                            '${studentSnapshot.error}',
                          ),
                        );
                      }
                      if (!studentSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allStudents = studentSnapshot.data!.docs;
                      final classes =
                          allStudents
                              .map(
                                (d) => (d.data()['className'] ?? '')
                                    .toString()
                                    .trim(),
                              )
                              .where((c) => c.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort();

                      final selectedClass = classes.contains(_className)
                          ? _className
                          : null;
                      final students = allStudents.where((d) {
                        final c = (d.data()['className'] ?? '')
                            .toString()
                            .trim();
                        return selectedClass == null || c == selectedClass;
                      }).toList();

                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: selectedClass,
                            decoration: const InputDecoration(
                              labelText: 'Filter by class / section',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('All classes'),
                              ),
                              ...classes.map(
                                (c) => DropdownMenuItem<String>(
                                  value: c,
                                  child: Text(c),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _className = v;
                            }),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: attendanceQuery.snapshots(),
                              builder: (context, attendanceSnapshot) {
                                if (attendanceSnapshot.hasError) {
                                  return Center(
                                    child: Text(
                                      'Could not load attendance: '
                                      '${attendanceSnapshot.error}',
                                    ),
                                  );
                                }
                                if (!attendanceSnapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final records = attendanceSnapshot.data!.docs;
                                final recordByStudent =
                                    <
                                      String,
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                    >{};
                                for (final record in records) {
                                  final id = record.data()['studentId'];
                                  if (id is String) {
                                    recordByStudent[id] = record;
                                  }
                                }

                                final present = students
                                    .where(
                                      (d) =>
                                          (recordByStudent[d.id]
                                                  ?.data()['status'] ??
                                              '') ==
                                          'Present',
                                    )
                                    .length;
                                final absent = students
                                    .where(
                                      (d) =>
                                          (recordByStudent[d.id]
                                                  ?.data()['status'] ??
                                              '') ==
                                          'Absent',
                                    )
                                    .length;
                                final leave = students
                                    .where(
                                      (d) =>
                                          (recordByStudent[d.id]
                                                  ?.data()['status'] ??
                                              '') ==
                                          'Leave',
                                    )
                                    .length;

                                return Column(
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Chip(
                                          label: Text(
                                            'Students: ${students.length}',
                                          ),
                                        ),
                                        Chip(label: Text('Present: $present')),
                                        Chip(label: Text('Absent: $absent')),
                                        Chip(label: Text('Leave: $leave')),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: students.isEmpty
                                          ? const Center(
                                              child: Text('No students found.'),
                                            )
                                          : ListView.separated(
                                              itemCount: students.length,
                                              separatorBuilder: (_, _) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final student = students[index];
                                                final data = student.data();
                                                final saved =
                                                    recordByStudent[student.id];
                                                final currentStatus =
                                                    _statuses[student.id] ??
                                                    (saved?.data()['status']
                                                            as String? ??
                                                        'Present');

                                                return ListTile(
                                                  title: Text(
                                                    (data['name'] ?? 'Student')
                                                        .toString(),
                                                  ),
                                                  subtitle: Text(
                                                    'Admission: ${data['admissionNo'] ?? '-'}'
                                                    ' • Class: ${data['className'] ?? '-'}'
                                                    '${saved == null ? ' • Not saved' : ' • Saved'}',
                                                  ),
                                                  trailing: SizedBox(
                                                    width: 235,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Expanded(
                                                          child: DropdownButton<String>(
                                                            isExpanded: true,
                                                            value:
                                                                currentStatus,
                                                            items: const [
                                                              DropdownMenuItem(
                                                                value:
                                                                    'Present',
                                                                child: Text(
                                                                  'Present',
                                                                ),
                                                              ),
                                                              DropdownMenuItem(
                                                                value: 'Absent',
                                                                child: Text(
                                                                  'Absent',
                                                                ),
                                                              ),
                                                              DropdownMenuItem(
                                                                value: 'Leave',
                                                                child: Text(
                                                                  'Leave',
                                                                ),
                                                              ),
                                                            ],
                                                            onChanged:
                                                                _saving
                                                                    .contains(
                                                                      student
                                                                          .id,
                                                                    )
                                                                ? null
                                                                : (v) {
                                                                    if (v !=
                                                                        null) {
                                                                      setState(() {
                                                                        _statuses[student.id] =
                                                                            v;
                                                                      });
                                                                    }
                                                                  },
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip:
                                                              'Save attendance',
                                                          onPressed:
                                                              _saving.contains(
                                                                student.id,
                                                              )
                                                              ? null
                                                              : () =>
                                                                    _saveStudent(
                                                                      student,
                                                                      records,
                                                                    ),
                                                          icon:
                                                              _saving.contains(
                                                                student.id,
                                                              )
                                                              ? const SizedBox(
                                                                  width: 18,
                                                                  height: 18,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                )
                                                              : const Icon(
                                                                  Icons
                                                                      .save_outlined,
                                                                ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardModule extends StatelessWidget {
  const DashboardModule({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Open →'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UserApprovalsScreen extends StatefulWidget {
  const UserApprovalsScreen({super.key});

  @override
  State<UserApprovalsScreen> createState() => _UserApprovalsScreenState();
}

class _UserApprovalsScreenState extends State<UserApprovalsScreen> {
  final Set<String> _busyUsers = <String>{};

  Future<void> _editPending(String uid, Map<String,dynamic> data) async {
    final fields = <String,TextEditingController>{
      'name':TextEditingController(text:(data['name']??'').toString()),
      'phone':TextEditingController(text:(data['phone']??'').toString()),
      'dateOfBirth':TextEditingController(text:(data['dateOfBirth']??'').toString()),
      'gender':TextEditingController(text:(data['gender']??'prefer_not_to_say').toString()),
      'address':TextEditingController(text:(data['address']??'').toString()),
      'emergencyContactName':TextEditingController(text:(data['emergencyContactName']??'').toString()),
      'emergencyContactPhone':TextEditingController(text:(data['emergencyContactPhone']??'').toString()),
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
    var saving = false;
    try {
      final save = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => StatefulBuilder(
        builder: (ctx,setDialogState) => AlertDialog(
          title: const Text('Edit pending registration'),
          content: SizedBox(width:520, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min, children: [
            for (final entry in fields.entries) if ((data['requestedRole'] == 'student' && ['currentClass','guardianName','guardianPhone','previousSchool','existingAdmissionNo'].contains(entry.key)) || (data['requestedRole'] == 'teacher' && ['qualification','subjects','experienceYears'].contains(entry.key)) || (data['requestedRole'] == 'parent' && ['childAdmissionNo','relationshipToStudent','occupation'].contains(entry.key)) || ['name','phone','dateOfBirth','gender','address','emergencyContactName','emergencyContactPhone'].contains(entry.key))
              Padding(padding: const EdgeInsets.only(bottom:8), child: TextField(controller:entry.value, maxLines: entry.key=='address'?2:1, decoration:InputDecoration(labelText:entry.key))),
          ]))),
          actions: [TextButton(onPressed:saving?null:()=>Navigator.pop(ctx,false),child:const Text('Cancel')), FilledButton(onPressed:saving?null:() async {
            if(fields['name']!.text.trim().length<2 || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(fields['dateOfBirth']!.text.trim()) || fields['address']!.text.trim().length<5){
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('Name, valid YYYY-MM-DD date of birth and address are required.'))); return;
            }
            setDialogState(()=>saving=true);
            Navigator.pop(ctx,true);
          },child:const Text('Save registration changes'))],
        ),
      ));
      if (save != true) return;
      final updates = <String,dynamic>{};
      for (final entry in fields.entries) {
        if (entry.key == 'experienceYears') { updates[entry.key] = int.tryParse(entry.value.text.trim()) ?? 0; }
        else { updates[entry.key] = entry.value.text.trim(); }
      }
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Pending registration updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update registration: $e')));
    } finally { for(final c in fields.values){c.dispose();} }
  }

  Future<void> _decide(
    String uid,
    String role,
    Map<String, dynamic> userData,
  ) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null || !['student', 'teacher', 'parent', 'rejected'].contains(role)) return;

    String rejectionReason = '';
    if (role == 'rejected') {
      final controller = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('درخواست مسترد کریں'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'وجہ (لازمی)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('واپس'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: const Text('مسترد کریں'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null || reason.trim().isEmpty || !mounted) return;
      rejectionReason = reason.trim();
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('اکاؤنٹ منظور کریں؟'),
          content: Text(
            'ای میل: ${userData['email'] ?? 'موجود نہیں'}\n'
            'کردار: $role\n\n${role == 'student' && (userData['existingAdmissionNo'] ?? '').toString().trim().isNotEmpty ? 'موجودہ Admission No ${userData['existingAdmissionNo']} سے لاگ اِن منسلک ہوگا۔' : 'منظوری کے ساتھ server سے منفرد ID جاری ہوگی۔'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('واپس'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('منظور اور ID جاری کریں'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    setState(() => _busyUsers.add(uid));
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final approved = role != 'rejected';
      final existingAdmission = (userData['existingAdmissionNo'] ?? '').toString().trim();
      final attachExistingStudent = approved && role == 'student' && existingAdmission.isNotEmpty;
      final callable = attachExistingStudent ? 'attachStudentAccount' : (approved ? 'approveAndIssueSchoolId' : 'rejectSchoolRegistration');
      final payload = attachExistingStudent ? {'uid':uid,'admissionNo':existingAdmission} : (approved ? {'uid': uid, 'role': role} : {'uid': uid, 'reason': rejectionReason});
      final response = await functions.httpsCallable(callable).call(payload);
      final issued = Map<String, dynamic>.from(response.data as Map);

      if (mounted) {
        final id = issued['admissionNo'] ?? issued['teacherId'] ?? issued['parentId'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(role == 'rejected'
                ? 'درخواست مسترد کر دی گئی۔'
                : 'اکاؤنٹ منظور ہوگیا۔ جاری کردہ ID: $id'),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firebase کارروائی ناکام: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUsers.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'pending')
        .limit(100);

    return Scaffold(
      appBar: AppBar(title: const Text('User Approvals')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(
                    'درخواستیں لوڈ نہیں ہو سکیں۔\n'
                    'ممکنہ وجہ: Firestore permission-denied یا نیٹ ورک مسئلہ۔\n'
                    '${snapshot.error}',
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('اس وقت کوئی زیرِ منظوری اکاؤنٹ موجود نہیں۔'),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final busy = _busyUsers.contains(doc.id);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (data['email'] ?? 'ای میل موجود نہیں').toString(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text('User ID: ${doc.id}'),
                          Text('Name: ${data['name'] ?? data['displayName'] ?? '-'} | Phone: ${data['phone'] ?? '-'}'),
                          Text('Requested role: ${data['requestedRole'] ?? '-'} | Date of birth: ${data['dateOfBirth'] ?? '-'} | Gender: ${data['gender'] ?? '-'}'),
                          Text('Address: ${data['address'] ?? '-'}'),
                          if ((data['emergencyContactName'] ?? '').toString().isNotEmpty || (data['emergencyContactPhone'] ?? '').toString().isNotEmpty)
                            Text('Emergency contact: ${data['emergencyContactName'] ?? '-'} / ${data['emergencyContactPhone'] ?? '-'}'),
                          if (data['requestedRole'] == 'student') Text('Requested class: ${data['currentClass'] ?? '-'} | Guardian: ${data['guardianName'] ?? '-'} / ${data['guardianPhone'] ?? '-'} | Previous school: ${data['previousSchool'] ?? '-'} | Existing Admission No: ${data['existingAdmissionNo'] ?? '-'}'),
                          if (data['requestedRole'] == 'teacher') Text('Qualification: ${data['qualification'] ?? '-'} | Subjects: ${data['subjects'] ?? '-'} | Experience: ${data['experienceYears'] ?? 0} years'),
                          if (data['requestedRole'] == 'parent') Text('Child Admission No: ${data['childAdmissionNo'] ?? '-'} | Relationship: ${data['relationshipToStudent'] ?? '-'} | Occupation: ${data['occupation'] ?? '-'}'),
                          if (data['createdAt'] is Timestamp)
                            Text(
                              'درخواست: ${(data['createdAt'] as Timestamp).toDate()}',
                            ),
                          if ((data['photoUrl'] ?? '').toString().isNotEmpty || (data['uploadedDocuments'] as List? ?? const []).isNotEmpty)
                            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('تصویر اور دستاویزات دیکھیں'),
                              onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
                                title: const Text('Submitted profile documents'),
                                content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if ((data['photoUrl'] ?? '').toString().isNotEmpty) ...[
                                    const Text('Profile photo URL'),
                                    SelectableText((data['photoUrl'] ?? '').toString()),
                                    TextButton.icon(onPressed: () => openDocumentUrl((data['photoUrl'] ?? '').toString()), icon: const Icon(Icons.open_in_new), label: const Text('Open profile photo')),
                                    const Divider(),
                                  ],
                                  for (final item in (data['uploadedDocuments'] as List? ?? const [])) if (item is Map) ...[
                                    Text((item['name'] ?? 'Document').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    SelectableText((item['url'] ?? '').toString()),
                                    TextButton.icon(onPressed: () => openDocumentUrl((item['url'] ?? '').toString()), icon: const Icon(Icons.open_in_new), label: const Text('Open / download document')),
                                    const Divider(),
                                  ],
                                ]))),
                                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                              )),
                            )),
                          const SizedBox(height: 12),
                          if (busy)
                            const LinearProgressIndicator()
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(onPressed: () => _editPending(doc.id, data), icon: const Icon(Icons.edit), label: const Text('Edit request')),
                                for (final role in [
                                  'student',
                                  'teacher',
                                  'parent',
                                ])
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _decide(doc.id, role, data),
                                    child: Text('منظور: $role'),
                                  ),
                                OutlinedButton(
                                  onPressed: () =>
                                      _decide(doc.id, 'rejected', data),
                                  child: const Text('مسترد کریں'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class StudentsManagementScreen extends StatefulWidget {
  const StudentsManagementScreen({super.key});

  @override
  State<StudentsManagementScreen> createState() =>
      _StudentsManagementScreenState();
}

class _StudentsManagementScreenState extends State<StudentsManagementScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showStudentDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text((data['name'] ?? 'Student').toString()),
        content: SingleChildScrollView(
          child: SelectableText(
            'Student ID: ${doc.id}\n'
            'Admission No: ${data['admissionNo'] ?? '-'}\n'
            'Class: ${data['className'] ?? '-'}\n'
            'Guardian: ${data['guardianName'] ?? '-'} / ${data['guardianPhone'] ?? '-'}\n'
            'DOB: ${data['dateOfBirth'] ?? '-'} | Gender: ${data['gender'] ?? '-'}\n'
            'Address: ${data['address'] ?? '-'}\n'
            'Previous school: ${data['previousSchool'] ?? '-'}\n'
            'Assigned Teacher ID: ${data['teacherId'] ?? '-'}\n'
            'Linked login UID: ${data['linkedUserUid'] ?? 'Not linked'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editStudent(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: (data['name'] ?? '').toString());
    final className = TextEditingController(
      text: (data['className'] ?? '').toString(),
    );
    final guardianPhone = TextEditingController(text: (data['guardianPhone'] ?? '').toString());
    final guardianName = TextEditingController(text: (data['guardianName'] ?? '').toString());
    final dob = TextEditingController(text: (data['dateOfBirth'] ?? '').toString());
    final gender = TextEditingController(text: (data['gender'] ?? '').toString());
    final address = TextEditingController(text: (data['address'] ?? '').toString());
    final previousSchool = TextEditingController(text: (data['previousSchool'] ?? '').toString());
    final teacherId = TextEditingController(text: (data['teacherId'] ?? '').toString());
    var saving = false;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit Student'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: name,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Student name *',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter student name'
                            : null,
                      ),
                      TextFormField(
                        controller: className,
                        maxLength: 50,
                        decoration: const InputDecoration(
                          labelText: 'Class / section *',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter class'
                            : null,
                      ),
                      TextFormField(controller: dob, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD)')),
                      TextFormField(controller: gender, decoration: const InputDecoration(labelText: 'Gender')),
                      TextFormField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address')),
                      TextFormField(controller: guardianName, decoration: const InputDecoration(labelText: 'Guardian name')),
                      TextFormField(controller: guardianPhone, maxLength: 25, decoration: const InputDecoration(labelText: 'Guardian phone')),
                      TextFormField(controller: previousSchool, decoration: const InputDecoration(labelText: 'Previous school')),
                      TextFormField(
                        controller: teacherId,
                        maxLength: 50,
                        decoration: const InputDecoration(labelText: 'Assigned Teacher ID'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => saving = true);
                        try {
                          final updates = <String,dynamic>{
                            'name': name.text.trim(),
                            'className': className.text.trim(),
                            'guardianPhone': guardianPhone.text.trim(),
                            'guardianName': guardianName.text.trim(),
                            'dateOfBirth': dob.text.trim(),
                            'gender': gender.text.trim(),
                            'address': address.text.trim(),
                            'previousSchool': previousSchool.text.trim(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          };
                          final linkedUid = (data['linkedUserUid'] ?? '').toString();
                          final userRef = linkedUid.isEmpty ? null : FirebaseFirestore.instance.collection('users').doc(linkedUid);
                          await FirebaseFirestore.instance.runTransaction((transaction) async {
                            final userSnap = userRef == null ? null : await transaction.get(userRef);
                            transaction.update(doc.reference, updates);
                            if (userRef != null && userSnap != null && userSnap.exists) transaction.update(userRef, {
                              'name': name.text.trim(), 'currentClass': className.text.trim(),
                              'guardianPhone': guardianPhone.text.trim(), 'guardianName': guardianName.text.trim(),
                              'dateOfBirth': dob.text.trim(), 'gender': gender.text.trim(),
                              'address': address.text.trim(), 'previousSchool': previousSchool.text.trim(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          });
                          await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('assignTeacherToStudent').call({
                            'studentId': doc.id, 'teacherId': teacherId.text.trim(),
                          });
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('Update failed: $e')),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
      );

      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student updated successfully.')),
        );
      }
    } finally {
      name.dispose();
      className.dispose();
      guardianPhone.dispose(); guardianName.dispose(); dob.dispose(); gender.dispose();
      address.dispose(); previousSchool.dispose(); teacherId.dispose();
    }
  }

  Future<void> _deleteStudent(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final studentName = (data['name'] ?? 'this student').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate student?'),
        content: Text(
          'Deactivate "$studentName"? Linked login access will be suspended. '
          'Attendance, fee and result history will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final linkedUid = (data['linkedUserUid'] ?? '').toString();
      final userRef = linkedUid.isEmpty ? null : FirebaseFirestore.instance.collection('users').doc(linkedUid);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final userSnap = userRef == null ? null : await transaction.get(userRef);
        transaction.update(doc.reference, {'status':'inactive','deactivatedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
        if (userRef != null && userSnap != null && userSnap.exists) {
          transaction.update(userRef, {'approvalStatus':'suspended','suspendedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
        }
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student deactivated. Historical records were preserved.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _addStudent() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final className = TextEditingController();
    final guardianName = TextEditingController();
    final guardianPhone = TextEditingController();
    final dob = TextEditingController();
    final address = TextEditingController();
    final previousSchool = TextEditingController();
    final teacherId = TextEditingController();
    final emergencyName = TextEditingController();
    final emergencyPhone = TextEditingController();
    var gender = 'prefer_not_to_say';
    var saving = false;

    final result = await showDialog<Map<String,dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Student — Admission No is issued automatically'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(controller: name, maxLength: 100, decoration: const InputDecoration(labelText: 'Student name *'), validator: (v) => v == null || v.trim().length < 2 ? 'Enter student name' : null),
                  TextFormField(controller: className, maxLength: 80, decoration: const InputDecoration(labelText: 'Class / section *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter class' : null),
                  TextFormField(controller: guardianName, maxLength: 100, decoration: const InputDecoration(labelText: 'Guardian name *'), validator: (v) => v == null || v.trim().length < 2 ? 'Enter guardian name' : null),
                  TextFormField(controller: guardianPhone, maxLength: 30, decoration: const InputDecoration(labelText: 'Guardian phone *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter guardian phone' : null),
                  TextFormField(controller: dob, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD) *'), validator: (v) => DateTime.tryParse((v ?? '').trim()) == null ? 'Enter date of birth' : null),
                  DropdownButtonFormField<String>(value: gender, decoration: const InputDecoration(labelText: 'Gender'), items: const [DropdownMenuItem(value:'male',child:Text('Male')),DropdownMenuItem(value:'female',child:Text('Female')),DropdownMenuItem(value:'other',child:Text('Other')),DropdownMenuItem(value:'prefer_not_to_say',child:Text('Prefer not to say'))], onChanged: (v) { if(v!=null) setDialogState(()=>gender=v); }),
                  TextFormField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address *'), validator: (v) => v == null || v.trim().length < 5 ? 'Enter complete address' : null),
                  TextFormField(controller: previousSchool, decoration: const InputDecoration(labelText: 'Previous school (optional)')),
                  TextFormField(controller: teacherId, decoration: const InputDecoration(labelText: 'Assigned Teacher ID (optional)')),
                  TextFormField(controller: emergencyName, decoration: const InputDecoration(labelText: 'Emergency contact name (optional)')),
                  TextFormField(controller: emergencyPhone, decoration: const InputDecoration(labelText: 'Emergency contact phone (optional)')),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: saving ? null : () async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(()=>saving=true);
              Navigator.pop(dialogContext, {
                'name':name.text.trim(),'className':className.text.trim(),
                'guardianName':guardianName.text.trim(),'guardianPhone':guardianPhone.text.trim(),
                'dateOfBirth':dob.text.trim(),'gender':gender,'address':address.text.trim(),
                'previousSchool':previousSchool.text.trim(),'teacherId':teacherId.text.trim(),
                'emergencyContactName':emergencyName.text.trim(),'emergencyContactPhone':emergencyPhone.text.trim(),
              });
            }, child: saving ? const CircularProgressIndicator() : const Text('Create and issue Admission No')),
          ],
        ),
      ),
    );
    if (result != null) {
      try {
        final response = await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('createStudentRecord').call(result);
        final issued = Map<String,dynamic>.from(response.data as Map);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Student created. Admission No: ${issued['admissionNo']}')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Student creation failed: $e')));
      }
    }
    name.dispose(); className.dispose(); guardianName.dispose(); guardianPhone.dispose();
    dob.dispose(); address.dispose(); previousSchool.dispose(); teacherId.dispose();
    emergencyName.dispose(); emergencyPhone.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsQuery = FirebaseFirestore.instance
        .collection('students')
        .orderBy('name')
        .limit(200);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Students Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStudent,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Student'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search name, admission number or class',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: studentsQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Could not load students.\n'
                              'Check your admin permissions and Firestore rules.\n\n'
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ?? [];
                      final filtered = docs.where((doc) {
                        final d = doc.data();
                        final haystack =
                            [d['name'], d['admissionNo'], d['className']]
                                .map((v) => (v ?? '').toString().toLowerCase())
                                .join(' ');
                        return haystack.contains(_search);
                      }).toList();

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No student records found.\n'
                            'Use Add Student to create the first record.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text('No matching students.'),
                        );
                      }

                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final d = doc.data();
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.school_outlined),
                              ),
                              title: Text(
                                (d['name'] ?? 'Unnamed student').toString(),
                              ),
                              subtitle: Text(
                                'Admission: ${d['admissionNo'] ?? '-'}'
                                '  •  Class: ${d['className'] ?? '-'}',
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Student actions',
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _editStudent(doc);
                                  } else if (action == 'delete') {
                                    _deleteStudent(doc);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert),
                              ),
                              onTap: () => _showStudentDetails(context, doc),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
