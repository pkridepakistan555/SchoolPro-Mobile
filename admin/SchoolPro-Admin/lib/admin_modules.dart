import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

String? _validateModuleField({
  required String collection,
  required String keyName,
  required String value,
  required Map<String, TextEditingController> controllers,
}) {
  final v = value.trim();
  if (v.isEmpty) return null; // Required fields are checked separately.

  if (v.length > 2000) return 'Maximum 2000 characters';

  if (keyName == 'email') {
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(v)) return 'Enter a valid email address';
  }

  final dateFields = <String>{'date', 'startDate', 'endDate', 'dueDate'};
  if (dateFields.contains(keyName)) {
    final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!pattern.hasMatch(v)) return 'Use YYYY-MM-DD format';
    final parsed = DateTime.tryParse(v);
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-'
                '${parsed.month.toString().padLeft(2, '0')}-'
                '${parsed.day.toString().padLeft(2, '0')}' !=
            v) {
      return 'Enter a real calendar date';
    }
  }

  if (keyName == 'startDate' || keyName == 'endDate') {
    final otherKey = keyName == 'startDate' ? 'endDate' : 'startDate';
    final other = controllers[otherKey]?.text.trim() ?? '';
    if (other.isNotEmpty) {
      final a = DateTime.tryParse(keyName == 'startDate' ? v : other);
      final b = DateTime.tryParse(keyName == 'endDate' ? v : other);
      if (a != null && b != null && a.isAfter(b)) {
        return 'Start date must not be after end date';
      }
    }
  }

  final number = num.tryParse(v);
  if (number != null) {
    if (collection == 'teacherPayroll' && ['baseSalary','allowances','deductions','netSalary'].contains(keyName) && number < 0) {
      return 'Payroll amounts cannot be negative';
    }
    if (keyName == 'amount' && number <= 0) {
      return 'Amount must be greater than zero';
    }
    if (keyName == 'dueDay' &&
        (number < 1 || number > 31 || number != number.truncate())) {
      return 'Due day must be a whole number from 1 to 31';
    }
    if (keyName == 'marksObtained' && number < 0) {
      return 'Marks cannot be negative';
    }
    if (keyName == 'totalMarks' && number <= 0) {
      return 'Total marks must be greater than zero';
    }
  }

  if (collection == 'teacherPayroll' && keyName == 'month' && !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(v)) {
    return 'Salary month must use YYYY-MM';
  }
  if (collection == 'teacherPayroll' && keyName == 'paymentStatus' && !['pending','paid'].contains(v.toLowerCase())) {
    return 'Payment status must be pending or paid';
  }
  if (collection == 'teacherPayroll' && ['baseSalary','allowances','deductions','netSalary'].contains(keyName)) {
    final base = num.tryParse(keyName == 'baseSalary' ? v : (controllers['baseSalary']?.text.trim() ?? ''));
    final allowances = num.tryParse(keyName == 'allowances' ? v : (controllers['allowances']?.text.trim() ?? '')) ?? 0;
    final deductions = num.tryParse(keyName == 'deductions' ? v : (controllers['deductions']?.text.trim() ?? '')) ?? 0;
    final net = num.tryParse(keyName == 'netSalary' ? v : (controllers['netSalary']?.text.trim() ?? ''));
    if (base != null && allowances >= 0 && deductions >= 0 && net != null && (base + allowances - deductions - net).abs() > 0.01) {
      return 'Net salary must equal base salary + allowances - deductions';
    }
  }
  if (collection == 'teacherAttendance' && keyName == 'status' && !['present','absent','leave'].contains(v.toLowerCase())) {
    return 'Attendance status must be Present, Absent or Leave';
  }

  if (collection == 'results' &&
      (keyName == 'marksObtained' || keyName == 'totalMarks')) {
    final obtained = num.tryParse(
      keyName == 'marksObtained'
          ? v
          : (controllers['marksObtained']?.text.trim() ?? ''),
    );
    final total = num.tryParse(
      keyName == 'totalMarks'
          ? v
          : (controllers['totalMarks']?.text.trim() ?? ''),
    );
    if (obtained != null && total != null && obtained > total) {
      return 'Obtained marks cannot exceed total marks';
    }
  }

  return null;
}

class _FieldSpec {
  const _FieldSpec(
    this.keyName,
    this.label, {
    this.required = true,
    this.numeric = false,
  });

  final String keyName;
  final String label;
  final bool required;
  final bool numeric;
}

const Map<String, List<_FieldSpec>> _schemas = {
  'teachers': [
    _FieldSpec('name', 'Teacher name'),
    _FieldSpec('phone', 'Phone', required: false),
    _FieldSpec('dateOfBirth', 'Date of birth (YYYY-MM-DD)', required: false),
    _FieldSpec('gender', 'Gender', required: false),
    _FieldSpec('address', 'Address', required: false),
    _FieldSpec('emergencyContactName', 'Emergency contact name', required: false),
    _FieldSpec('emergencyContactPhone', 'Emergency contact phone', required: false),
    _FieldSpec('qualification', 'Qualification', required: false),
    _FieldSpec('subjects', 'Subjects', required: false),
    _FieldSpec('experienceYears', 'Experience years', required: false, numeric: true),
    _FieldSpec('status', 'Status (active/inactive)', required: false),
  ],
  'teacherAttendance': [
    _FieldSpec('teacherUid', 'Teacher Firebase UID'),
    _FieldSpec('teacherId', 'Teacher ID'),
    _FieldSpec('teacherName', 'Teacher name'),
    _FieldSpec('date', 'Date (YYYY-MM-DD)'),
    _FieldSpec('status', 'Status (Present/Absent/Leave)'),
    _FieldSpec('checkIn', 'Check-in time', required: false),
    _FieldSpec('checkOut', 'Check-out time', required: false),
    _FieldSpec('notes', 'Notes', required: false),
  ],
  'teacherPayroll': [
    _FieldSpec('teacherUid', 'Teacher Firebase UID'),
    _FieldSpec('teacherId', 'Teacher ID'),
    _FieldSpec('teacherName', 'Teacher name'),
    _FieldSpec('month', 'Salary month (YYYY-MM)'),
    _FieldSpec('baseSalary', 'Base salary (PKR)', numeric: true),
    _FieldSpec('allowances', 'Allowances (PKR)', numeric: true),
    _FieldSpec('deductions', 'Deductions (PKR)', numeric: true),
    _FieldSpec('netSalary', 'Net salary paid (PKR)', numeric: true),
    _FieldSpec('paymentStatus', 'Payment status (pending/paid)'),
    _FieldSpec('paidAt', 'Payment date', required: false),
    _FieldSpec('notes', 'Notes', required: false),
  ],
  'parents': [
    _FieldSpec('name', 'Parent name'),
    _FieldSpec('phone', 'Phone'),
    _FieldSpec('dateOfBirth', 'Date of birth (YYYY-MM-DD)', required: false),
    _FieldSpec('gender', 'Gender', required: false),
    _FieldSpec('address', 'Address', required: false),
    _FieldSpec('emergencyContactName', 'Emergency contact name', required: false),
    _FieldSpec('emergencyContactPhone', 'Emergency contact phone', required: false),
    _FieldSpec('relationshipToStudent', 'Relationship to student', required: false),
    _FieldSpec('occupation', 'Occupation', required: false),
    _FieldSpec('status', 'Status (active/inactive)', required: false),
  ],
  'classes': [
    _FieldSpec('name', 'Class name'),
    _FieldSpec('section', 'Section', required: false),
    _FieldSpec('room', 'Room', required: false),
    _FieldSpec('classTeacherId', 'Class teacher ID', required: false),
  ],
  'subjects': [
    _FieldSpec('name', 'Subject name'),
    _FieldSpec('className', 'Class'),
    _FieldSpec('subjectCode', 'Subject code', required: false),
    _FieldSpec('teacherId', 'Teacher ID', required: false),
  ],
  'timetables': [
    _FieldSpec('className', 'Class'),
    _FieldSpec('day', 'Day'),
    _FieldSpec('startTime', 'Start time'),
    _FieldSpec('endTime', 'End time'),
    _FieldSpec('subject', 'Subject'),
    _FieldSpec('teacherId', 'Teacher ID', required: false),
    _FieldSpec('room', 'Room', required: false),
  ],
  'exams': [
    _FieldSpec('name', 'Exam name'),
    _FieldSpec('className', 'Class'),
    _FieldSpec('teacherId', 'Teacher ID', required: false),
    _FieldSpec('term', 'Term', required: false),
    _FieldSpec('startDate', 'Start date (YYYY-MM-DD)', required: false),
    _FieldSpec('endDate', 'End date (YYYY-MM-DD)', required: false),
    _FieldSpec('status', 'Status', required: false),
  ],
  'results': [
    _FieldSpec('studentId', 'Student document ID'),
    _FieldSpec('studentName', 'Student name'),
    _FieldSpec('examId', 'Exam document ID'),
    _FieldSpec('teacherId', 'Teacher ID', required: false),
    _FieldSpec('subject', 'Subject'),
    _FieldSpec('marksObtained', 'Marks obtained', numeric: true),
    _FieldSpec('totalMarks', 'Total marks', numeric: true),
    _FieldSpec('remarks', 'Remarks', required: false),
  ],
  'assignments': [
    _FieldSpec('title', 'Assignment title'),
    _FieldSpec('className', 'Class'),
    _FieldSpec('teacherId', 'Teacher ID', required: false),
    _FieldSpec('subject', 'Subject'),
    _FieldSpec('description', 'Description', required: false),
    _FieldSpec('dueDate', 'Due date (YYYY-MM-DD)', required: false),
  ],
  'homeworkSubmissions': [
    _FieldSpec('studentId', 'Student document ID'),
    _FieldSpec('assignmentId', 'Assignment document ID'),
    _FieldSpec('teacherId', 'Teacher ID', required: false),
    _FieldSpec('answer', 'Student answer'),
    _FieldSpec('status', 'Status (submitted/reviewed/returned)'),
    _FieldSpec('marks', 'Marks', required: false, numeric: true),
    _FieldSpec('feedback', 'Teacher feedback', required: false),
  ],
  'feeStructures': [
    _FieldSpec('name', 'Fee name'),
    _FieldSpec('className', 'Class'),
    _FieldSpec('amount', 'Amount (PKR)', numeric: true),
    _FieldSpec('frequency', 'Billing frequency (monthly/term/annual/one-time)'),
    _FieldSpec('dueDay', 'Due day of month', required: false, numeric: true),
    _FieldSpec('description', 'Description', required: false),
  ],
  'feePayments': [
    _FieldSpec('studentId', 'Student document ID'),
    _FieldSpec('studentName', 'Student name'),
    _FieldSpec('feeStructureId', 'Fee structure document ID'),
    _FieldSpec('amount', 'Amount paid (PKR)', numeric: true),
    _FieldSpec('month', 'Fee month (YYYY-MM)'),
    _FieldSpec('method', 'Payment method', required: false),
    _FieldSpec('notes', 'Notes', required: false),
  ],
  'expenses': [
    _FieldSpec('title', 'Expense title'),
    _FieldSpec('category', 'Category'),
    _FieldSpec('amount', 'Amount (PKR)', numeric: true),
    _FieldSpec('date', 'Date (YYYY-MM-DD)'),
    _FieldSpec('notes', 'Notes', required: false),
  ],
  'notices': [
    _FieldSpec('title', 'Notice title'),
    _FieldSpec('message', 'Notice message'),
    _FieldSpec('audience', 'Audience', required: false),
    _FieldSpec('status', 'Status (draft/published)', required: false),
  ],
  'reports': [
    _FieldSpec('title', 'Report title'),
    _FieldSpec('reportType', 'Report type'),
    _FieldSpec('description', 'Description', required: false),
  ],
  'schoolSettings': [
    _FieldSpec('name', 'School name'),
    _FieldSpec('phone', 'School phone', required: false),
    _FieldSpec('address', 'School address', required: false),
    _FieldSpec('email', 'School email', required: false),
    _FieldSpec('academicYear', 'Academic year', required: false),
  ],
};

class AdminCollectionScreen extends StatefulWidget {
  const AdminCollectionScreen({
    super.key,
    required this.title,
    required this.collectionName,
    required this.description,
  });

  final String title;
  final String collectionName;
  final String description;

  @override
  State<AdminCollectionScreen> createState() => _AdminCollectionScreenState();
}

class _AdminCollectionScreenState extends State<AdminCollectionScreen> {
  final _search = TextEditingController();

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection(widget.collectionName);

  List<_FieldSpec> get _fields =>
      _schemas[widget.collectionName] ??
      const [
        _FieldSpec('name', 'Name'),
        _FieldSpec('description', 'Description', required: false),
      ];

  bool get _readOnly => widget.collectionName == 'adminAuditLogs';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showForm({
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    if (_readOnly || (widget.collectionName == 'feePayments' && existing != null)) return;

    final controllers = <String, TextEditingController>{};
    final formKey = GlobalKey<FormState>();
    final current = existing?.data() ?? <String, dynamic>{};

    for (final field in _fields) {
      final value = current[field.keyName];
      controllers[field.keyName] = TextEditingController(
        text: value == null ? '' : value.toString(),
      );
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null ? 'Add ${widget.title} record' : 'Edit record',
        ),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: controllers[field.keyName],
                      keyboardType: field.numeric
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: field.label,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (raw) {
                        final value = (raw ?? '').trim();
                        if (field.required && value.isEmpty) {
                          return 'This field is required';
                        }
                        if (field.numeric &&
                            value.isNotEmpty &&
                            num.tryParse(value) == null) {
                          return 'Enter a valid number';
                        }
                        return _validateModuleField(
                          collection: widget.collectionName,
                          keyName: field.keyName,
                          value: value,
                          controllers: controllers,
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please sign in again.')),
                );
                return;
              }

              final data = <String, dynamic>{};
              for (final field in _fields) {
                final raw = controllers[field.keyName]!.text.trim();
                if (raw.isEmpty && !field.required) continue;
                data[field.keyName] = field.numeric ? num.parse(raw) : raw;
              }

              try {
                if (existing == null) {
                  data['createdAt'] = FieldValue.serverTimestamp();
                  data['createdBy'] = user.uid;
                  data['updatedAt'] = FieldValue.serverTimestamp();
                  if (widget.collectionName == 'feePayments') {
                    // Immutable receipt number and payment are committed atomically.
                    final db = FirebaseFirestore.instance;
                    final counterRef = db.collection('systemCounters').doc('feeReceipt');
                    final paymentRef = _collection.doc();
                    final issuedReceipt = await db.runTransaction<String>((transaction) async {
                      final counter = await transaction.get(counterRef);
                      final next = ((counter.data()?['value'] as num?) ?? 0).toInt() + 1;
                      if (next < 1 || next > 999999) {
                        throw StateError('Receipt counter limit reached.');
                      }
                      final serial = next.toString().padLeft(6, '0');
                      final receiptNo = 'FEE-${DateTime.now().year}-$serial';
                      transaction.set(counterRef, {
                        'value': next,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                      transaction.set(paymentRef, {...data, 'receiptNo': receiptNo});
                      final auditRef = db.collection('adminAuditLogs').doc();
                      transaction.set(auditRef, {
                        'action': 'fee_receipt_issued',
                        'receiptNo': receiptNo,
                        'paymentId': paymentRef.id,
                        'studentId': data['studentId'],
                        'amount': data['amount'],
                        'actorUid': user.uid,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      return receiptNo;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fee payment saved. Receipt: $issuedReceipt')),
                      );
                    }
                  } else {
                    await _collection.add(data);
                  }
                } else {
                  // Preserve immutable creation metadata during edits.
                  final oldData = existing.data();
                  if (oldData.containsKey('createdAt')) {
                    data['createdAt'] = oldData['createdAt'];
                  }
                  if (oldData.containsKey('createdBy')) {
                    data['createdBy'] = oldData['createdBy'];
                  }
                  data['updatedAt'] = FieldValue.serverTimestamp();
                  final reference = _collection.doc(existing.id);
                  if (widget.collectionName == 'teachers' || widget.collectionName == 'parents') {
                    final userRef = FirebaseFirestore.instance.collection('users').doc(existing.id);
                    final syncKeys = <String>{'name','phone','dateOfBirth','gender','address','emergencyContactName','emergencyContactPhone','qualification','subjects','experienceYears','relationshipToStudent','occupation'};
                    final userUpdate = Map<String,dynamic>.fromEntries(data.entries.where((entry) => syncKeys.contains(entry.key)));
                    await FirebaseFirestore.instance.runTransaction((transaction) async {
                      final userSnap = await transaction.get(userRef);
                      transaction.update(reference, data);
                      if (userSnap.exists && (userUpdate.isNotEmpty || data['status'] == 'inactive' || data['status'] == 'active')) transaction.update(userRef, {
                        ...userUpdate,
                        if (data['status'] == 'inactive') 'approvalStatus': 'suspended',
                        if (data['status'] == 'active' && ['teacher','parent'].contains(userSnap.data()?['role'])) 'approvalStatus': 'approved',
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    });
                  } else {
                    await reference.update(data);
                  }
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Save failed. Check Firebase Rules and fields. $error',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record saved successfully.')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final query = _collection.limit(200);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!_readOnly)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => _showForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add record'),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(widget.description),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search loaded records',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (_readOnly)
                  const Text(
                    'Read-only screen: records cannot be edited or deleted here.',
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: query.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: SingleChildScrollView(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lock_outline, size: 42),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Data is unavailable. Firebase Rules may deny this collection.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    SelectableText(snapshot.error.toString()),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final needle = _search.text.trim().toLowerCase();
                      final docs = (snapshot.data?.docs ?? []).where((doc) {
                        if (needle.isEmpty) return true;
                        return '${doc.id} ${jsonEncode(doc.data())}'
                            .toLowerCase()
                            .contains(needle);
                      }).toList();

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No matching records.'),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final label =
                              (data['name'] ??
                                      data['title'] ??
                                      data['studentName'] ??
                                      doc.id)
                                  .toString();

                          return Card(
                            child: ExpansionTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(label),
                              subtitle: Text('ID: ${doc.id}'),
                              trailing:
                                  (_readOnly ||
                                      widget.collectionName == 'feePayments')
                                  ? const Icon(Icons.visibility_outlined)
                                  : PopupMenuButton<String>(
                                      onSelected: (action) {
                                        if (action == 'edit') {
                                          _showForm(existing: doc);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                      ],
                                    ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: SelectableText(
                                    const JsonEncoder.withIndent('  ')
                                        .convert(data),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
