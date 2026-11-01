import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class AdminWorkflowsScreen extends StatefulWidget {
  const AdminWorkflowsScreen({super.key});
  @override State<AdminWorkflowsScreen> createState() => _AdminWorkflowsScreenState();
}
class _AdminWorkflowsScreenState extends State<AdminWorkflowsScreen> {
  final _uid = TextEditingController();
  final _admissions = TextEditingController();
  final _studentUid = TextEditingController();
  final _studentAdmission = TextEditingController();
  bool _busy = false;
  String _message = '';
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  @override void dispose() { _uid.dispose(); _admissions.dispose(); _studentUid.dispose(); _studentAdmission.dispose(); super.dispose(); }
  Future<void> _linkChildren() async {
    final uid = _uid.text.trim();
    final numbers = _admissions.text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (uid.isEmpty || numbers.isEmpty) { setState(() => _message = 'Enter parent UID and one or more Admission Numbers.'); return; }
    if (numbers.length > 10) { setState(() => _message = 'A parent can be linked to a maximum of 10 students.'); return; }
    setState(() { _busy = true; _message = ''; });
    try {
      final result = await _functions.httpsCallable('setParentStudentLinks').call({'uid': uid, 'admissionNumbers': numbers});
      setState(() => _message = 'Linked ${((result.data as Map)['linkedStudentIds'] as List).length} student(s) successfully.');
    } catch (e) { setState(() => _message = 'Could not link students: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _attachStudentAccount() async {
    final uid = _studentUid.text.trim();
    final admissionNo = _studentAdmission.text.trim();
    if (uid.isEmpty || admissionNo.isEmpty) { setState(() => _message = 'Enter pending student Firebase UID and the existing Admission Number.'); return; }
    setState(() { _busy = true; _message = ''; });
    try {
      await _functions.httpsCallable('attachStudentAccount').call({'uid':uid,'admissionNo':admissionNo});
      if (mounted) setState(() => _message = 'Student login attached to Admission No $admissionNo. The existing student record and history were preserved.');
    } catch (e) { if (mounted) setState(() => _message = 'Could not attach student login: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _review(String id, String decision) async {
    final note = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${decision.toUpperCase()} leave request'),
      content: TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Admin note (optional)')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, note.text.trim()), child: const Text('Confirm'))],
    ));
    note.dispose(); if (value == null) return;
    setState(() { _busy = true; _message = ''; });
    try { await _functions.httpsCallable('reviewTeacherLeaveRequest').call({'requestId': id, 'decision': decision, 'note': value}); setState(() => _message = 'Leave request $decision.'); }
    catch (e) { setState(() => _message = 'Review failed: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('School administration workflows')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Parent multi-child linking', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Enter the approved parent account UID and one or more existing Admission Numbers separated by commas or new lines.'),
        const SizedBox(height: 12), TextField(controller: _uid, decoration: const InputDecoration(labelText: 'Parent Firebase UID')),
        const SizedBox(height: 8), TextField(controller: _admissions, maxLines: 3, decoration: const InputDecoration(labelText: 'Admission Numbers')),
        const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : _linkChildren, child: const Text('Verify and link children')),
      ]))),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Attach an existing student record to a login', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Use this after a student has registered and verified email, when the school already created their Admission Number manually. The callable verifies the pending account and reuses the existing student record.'),
        const SizedBox(height: 12), TextField(controller: _studentUid, decoration: const InputDecoration(labelText: 'Pending student Firebase UID')),
        const SizedBox(height: 8), TextField(controller: _studentAdmission, decoration: const InputDecoration(labelText: 'Existing Admission Number')),
        const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : _attachStudentAccount, child: const Text('Verify and attach student login')),
      ]))),
      const SizedBox(height: 16), Text('Teacher leave requests', style: Theme.of(context).textTheme.titleLarge),
      StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: FirebaseFirestore.instance.collection('leaveRequests').where('status', isEqualTo: 'pending').snapshots(), builder: (context, snap) {
        if (snap.hasError) return Text('Unable to load leave requests: ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const ListTile(title: Text('No pending leave requests.'));
        return Column(children: snap.data!.docs.map((d) { final x=d.data(); return Card(child: ListTile(
          title: Text('${x['teacherName'] ?? x['teacherId'] ?? 'Teacher'} — ${x['startDate'] ?? ''} to ${x['endDate'] ?? ''}'),
          subtitle: Text((x['reason'] ?? '').toString()),
          trailing: Wrap(children: [IconButton(tooltip:'Approve', onPressed:_busy?null:()=>_review(d.id,'approved'), icon:const Icon(Icons.check_circle_outline)), IconButton(tooltip:'Reject', onPressed:_busy?null:()=>_review(d.id,'rejected'), icon:const Icon(Icons.cancel_outlined))]),
        )); }).toList());
      }),
      if (_busy) const LinearProgressIndicator(), if (_message.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: SelectableText(_message)),
    ]),
  );
}
