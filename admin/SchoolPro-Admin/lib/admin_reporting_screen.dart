
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_printing.dart';

/// Admin-only operational reports. PDF output uses the browser's print dialog
/// (Save as PDF); CSV files are generated locally from the same verified query.
class AdminReportingScreen extends StatefulWidget {
  const AdminReportingScreen({super.key});

  @override
  State<AdminReportingScreen> createState() => _AdminReportingScreenState();
}

class _AdminReportingScreenState extends State<AdminReportingScreen> {
  final _studentId = TextEditingController();
  final _examId = TextEditingController();
  final _paymentId = TextEditingController();
  final _from = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  final _to = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  bool _busy = false;
  String _message = '';
  List<List<String>> _lastCsv = [];
  String _lastCsvName = 'schoolpro-report.csv';
  String _lastHtml = '';

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String _escape(Object? value) => (value ?? '').toString()
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;').replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  bool get _validRange {
    final a = DateTime.tryParse(_from.text.trim());
    final b = DateTime.tryParse(_to.text.trim());
    return a != null && b != null && !b.isBefore(a) &&
        ((b.year - a.year) * 12 + b.month - a.month) < 60 &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_from.text.trim()) &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_to.text.trim());
  }

  @override
  void dispose() {
    _studentId.dispose(); _examId.dispose(); _paymentId.dispose(); _from.dispose(); _to.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() { _busy = true; _message = ''; });
    try { await task(); }
    catch (e) { if (mounted) setState(() => _message = 'Report failed: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _generateReportCard() => _run(() async {
    final enteredId = _studentId.text.trim();
    if (enteredId.isEmpty) throw StateError('Enter the Student document ID or Admission Number.');
    var studentSnap = await _db.collection('students').doc(enteredId).get();
    if (!studentSnap.exists) {
      final matches = await _db.collection('students').where('admissionNo', isEqualTo: enteredId).limit(2).get();
      if (matches.docs.length != 1) throw StateError('Student record was not found or the Admission Number is duplicated.');
      studentSnap = matches.docs.single;
    }
    final id = studentSnap.id;
    final student = studentSnap.data()!;
    final exam = _examId.text.trim();
    Query<Map<String, dynamic>> query = _db.collection('results').where('studentId', isEqualTo: id);
    if (exam.isNotEmpty) query = query.where('examId', isEqualTo: exam);
    final resultSnap = await query.limit(201).get();
    if (resultSnap.docs.length > 200) throw StateError('More than 200 result entries were found. Filter by one Exam ID to generate a complete report card.');
    final rows = resultSnap.docs.map((d) => d.data()).toList();
    if (rows.isEmpty) throw StateError('No results found for this student and exam filter.');
    final obtained = rows.fold<double>(0, (v, r) => v + ((r['marksObtained'] as num?)?.toDouble() ?? 0));
    final total = rows.fold<double>(0, (v, r) => v + ((r['totalMarks'] as num?)?.toDouble() ?? 0));
    if (total <= 0 || rows.any((r) => ((r['totalMarks'] as num?)?.toDouble() ?? 0) <= 0 ||
        ((r['marksObtained'] as num?)?.toDouble() ?? 0) < 0 ||
        ((r['marksObtained'] as num?)?.toDouble() ?? 0) > ((r['totalMarks'] as num?)?.toDouble() ?? 0))) {
      throw StateError('One or more result entries contain invalid marks. Correct them before issuing a report card.');
    }
    final percentage = obtained / total * 100;
    final grade = percentage >= 90 ? 'A+' : percentage >= 80 ? 'A' : percentage >= 70 ? 'B' : percentage >= 60 ? 'C' : percentage >= 50 ? 'D' : 'F';
    final name = (student['name'] ?? student['studentName'] ?? 'Student').toString();
    final admission = (student['admissionNo'] ?? '').toString();
    final tableRows = rows.map((r) => '<tr><td>${_escape(r['subject'])}</td><td>${_escape(r['marksObtained'])}</td><td>${_escape(r['totalMarks'])}</td><td>${_escape(r['remarks'])}</td></tr>').join();
    final htmlText = _document('Student Report Card', '''
      <h1>SchoolPro — Student Report Card</h1>
      <p><b>Student:</b> ${_escape(name)} &nbsp; <b>Admission No:</b> ${_escape(admission)}</p>
      <p><b>Class:</b> ${_escape(student['className'])} &nbsp; <b>Exam:</b> ${_escape(exam.isEmpty ? 'All available results' : exam)}</p>
      <table><thead><tr><th>Subject</th><th>Marks</th><th>Total</th><th>Remarks</th></tr></thead><tbody>$tableRows</tbody></table>
      <h2>Total: ${obtained.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} (${percentage.toStringAsFixed(2)}%) — Grade $grade</h2>
      <p>Generated: ${DateTime.now().toIso8601String()}</p>''');
    final reportId = '${id}_${exam.isEmpty ? 'all' : exam}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await _db.collection('reports').doc('report_card_$reportId').set({
      'reportType': 'report_card', 'studentId': id, 'studentName': name,
      'admissionNo': admission, 'className': student['className'] ?? '',
      'examId': exam, 'subjects': rows, 'obtainedMarks': obtained,
      'totalMarks': total, 'percentage': percentage, 'grade': grade,
      'generatedBy': FirebaseAuth.instance.currentUser?.uid,
      'generatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      _lastHtml = htmlText;
      _lastCsv = [['Subject','Marks Obtained','Total Marks','Remarks'], ...rows.map((r) => [
        (r['subject'] ?? '').toString(), (r['marksObtained'] ?? '').toString(),
        (r['totalMarks'] ?? '').toString(), (r['remarks'] ?? '').toString()])];
      _lastCsvName = 'report-card-${reportId}.csv';
      _message = 'Report card saved to Firestore. ${rows.length} subject entries; ${percentage.toStringAsFixed(2)}%; Grade $grade. Use Print / Save as PDF.';
    });
  });

  String? _monthKey(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value)) return value;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}';
    final match = RegExp(r'^([A-Za-z]+)\s+(\d{4})$').firstMatch(value);
    if (match != null) {
      const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
      final monthName = match.group(1)!.toLowerCase();
      if (monthName.length < 3) return null;
      final index = months.indexOf(monthName.substring(0, 3));
      if (index >= 0) return '${match.group(2)}-${(index + 1).toString().padLeft(2, '0')}';
    }
    return null;
  }

  List<String> _monthsInRange(DateTime from, DateTime to) {
    final months = <String>[];
    var cursor = DateTime(from.year, from.month);
    final last = DateTime(to.year, to.month);
    while (!cursor.isAfter(last) && months.length < 60) {
      months.add('${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}');
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return months;
  }

  Future<void> _generateReceipt() => _run(() async {
    final id = _paymentId.text.trim();
    if (id.isEmpty) throw StateError('Enter the fee payment document ID.');
    final paymentSnap = await _db.collection('feePayments').doc(id).get();
    if (!paymentSnap.exists) throw StateError('Fee payment record was not found.');
    final payment = paymentSnap.data()!;
    final receiptNo = (payment['receiptNo'] ?? '').toString();
    final studentId = (payment['studentId'] ?? '').toString();
    if (!RegExp(r'^FEE-[0-9]{4}-[0-9]{6}$').hasMatch(receiptNo) || studentId.isEmpty) {
      throw StateError('This payment does not contain a valid issued receipt number or student link.');
    }
    final studentSnap = await _db.collection('students').doc(studentId).get();
    final student = studentSnap.data() ?? <String,dynamic>{};
    final settings = await _db.collection('schoolSettings').limit(1).get();
    final school = settings.docs.isEmpty ? <String,dynamic>{} : settings.docs.first.data();
    final created = payment['createdAt'] is Timestamp ? (payment['createdAt'] as Timestamp).toDate().toLocal().toString().split('.').first : '—';
    final htmlText = _document('Fee Receipt $receiptNo', '''
      <div class="receipt"><h1>${_escape(school['name'] ?? 'SchoolPro')}</h1>
      <p>${_escape(school['address'] ?? '')}<br>${_escape(school['phone'] ?? '')}</p>
      <h2>OFFICIAL FEE RECEIPT</h2><hr>
      <p><b>Receipt No:</b> ${_escape(receiptNo)}<br><b>Date:</b> ${_escape(created)}</p>
      <p><b>Student:</b> ${_escape(payment['studentName'] ?? student['name'] ?? '')}<br>
      <b>Admission No:</b> ${_escape(student['admissionNo'] ?? '')}<br>
      <b>Class:</b> ${_escape(student['className'] ?? '')}</p>
      <table><tbody><tr><th>Fee Period</th><td>${_escape(payment['month'] ?? '')}</td></tr>
      <tr><th>Payment Method</th><td>${_escape(payment['method'] ?? '—')}</td></tr>
      <tr><th>Amount Paid</th><td><b>PKR ${_escape(payment['amount'])}</b></td></tr></tbody></table>
      <p>Notes: ${_escape(payment['notes'] ?? '')}</p><p style="margin-top:45px">_________________________<br>Authorized Signature</p>
      <p>Computer-generated receipt. Payment records are immutable.</p></div>''').replaceAll('</style>', '@page{size:80mm auto;margin:5mm}.receipt{max-width:80mm;margin:auto;font-size:12px}h1,h2{text-align:center}table{font-size:12px}</style>');
    if (!mounted) return;
    setState(() {
      _lastHtml = htmlText;
      _lastCsv = [['Receipt No','Student ID','Student Name','Admission No','Fee Period','Amount PKR','Method','Created At'], [
        receiptNo, studentId, (payment['studentName'] ?? student['name'] ?? '').toString(),
        (student['admissionNo'] ?? '').toString(), (payment['month'] ?? '').toString(),
        (payment['amount'] ?? '').toString(), (payment['method'] ?? '').toString(), created,
      ]];
      _lastCsvName = 'receipt-$receiptNo.csv';
      _message = 'Receipt loaded. Use Print / Save as PDF; select an 80mm thermal printer in print settings if required.';
    });
  });

  Future<void> _financeReport() => _run(() async {
    if (!_validRange) throw StateError('Enter a valid date range in YYYY-MM-DD format.');
    final from = DateTime.parse(_from.text.trim());
    final to = DateTime.parse(_to.text.trim()).add(const Duration(days: 1));
    final payments = await _db.collection('feePayments')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('createdAt', isLessThan: Timestamp.fromDate(to))
        .orderBy('createdAt').limit(2000).get();
    final expenses = await _db.collection('expenses')
        .where('date', isGreaterThanOrEqualTo: _from.text.trim())
        .where('date', isLessThanOrEqualTo: _to.text.trim())
        .orderBy('date').limit(2000).get();
    final paid = payments.docs.where((d) {
      final v = d.data()['createdAt'];
      final date = v is Timestamp ? v.toDate() : null;
      return date != null && !date.isBefore(from) && date.isBefore(to);
    }).toList();
    final spent = expenses.docs.where((d) {
      final date = DateTime.tryParse((d.data()['date'] ?? '').toString());
      return date != null && !date.isBefore(from) && date.isBefore(to);
    }).toList();
    final totalPaid = paid.fold<double>(0, (v,d) => v + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
    final totalSpent = spent.fold<double>(0, (v,d) => v + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
    final receiptCounts = <String,int>{};
    for (final d in paid) { final no=(d.data()['receiptNo'] ?? '').toString(); receiptCounts[no]=(receiptCounts[no] ?? 0)+1; }
    final duplicateReceipts = receiptCounts.entries.where((e) => e.key.isEmpty || e.value > 1).toList();

    // Monthly dues are calculated only for fee structures explicitly marked
    // frequency=monthly. Legacy structures without frequency are not guessed.
    final months = _monthsInRange(from, to.subtract(const Duration(days: 1)));
    final studentsSnap = await _db.collection('students').limit(3000).get();
    final structuresSnap = await _db.collection('feeStructures').limit(500).get();
    final monthlyStructures = structuresSnap.docs.where((d) =>
      (d.data()['frequency'] ?? '').toString().toLowerCase() == 'monthly').toList();
    final paidByStudentMonthStructure = <String,double>{};
    final studentDataById = {for (final d in studentsSnap.docs) d.id: d.data()};
    final monthlyStructureIds = monthlyStructures.map((d) => d.id).toSet();
    final monthlyStructureById = {for (final d in monthlyStructures) d.id: d.data()};
    var unallocatedPayments = 0.0;
    for (final d in payments.docs) {
      final x=d.data(); final month=_monthKey(x['month']);
      final student=(x['studentId']??'').toString();
      final structure=(x['feeStructureId']??'').toString();
      final studentData = studentDataById[student];
      final structureData = monthlyStructureById[structure];
      final sameClass = studentData != null && structureData != null &&
          (studentData['className'] ?? studentData['currentClass'] ?? '').toString() ==
          (structureData['className'] ?? '').toString();
      if(month!=null && months.contains(month) && sameClass && monthlyStructureIds.contains(structure)){
        final key='$student|$month|$structure';
        paidByStudentMonthStructure[key]=(paidByStudentMonthStructure[key]??0)+((x['amount'] as num?)?.toDouble()??0);
      } else { unallocatedPayments += ((x['amount'] as num?)?.toDouble() ?? 0); }
    }
    final dueRows=<List<String>>[];
    var expectedMonthly=0.0, allocatedMonthlyPayments=0.0, outstandingMonthly=0.0;
    for(final studentDoc in studentsSnap.docs){
      final student=studentDoc.data();
      if(['inactive','deleted'].contains((student['status']??'').toString())) continue;
      final className=(student['className']??student['currentClass']??'').toString();
      final applicable=monthlyStructures.where((f)=>(f.data()['className']??'').toString()==className).toList();
      if(applicable.isEmpty) continue;
      for(final month in months){
        for(final structureDoc in applicable){
          final structure=structureDoc.data();
          final amount=(structure['amount'] as num?)?.toDouble()??0;
          final key='${studentDoc.id}|$month|${structureDoc.id}';
          final paidForMonth=paidByStudentMonthStructure[key]??0;
          final due=(amount-paidForMonth).clamp(0,double.infinity).toDouble();
          expectedMonthly+=amount; allocatedMonthlyPayments+=paidForMonth; outstandingMonthly+=due;
          if(due>0) dueRows.add([(student['name']??'').toString(),(student['admissionNo']??'').toString(),className,month,(structure['name']??structureDoc.id).toString(),amount.toStringAsFixed(2),paidForMonth.toStringAsFixed(2),due.toStringAsFixed(2)]);
        }
      }
    }
    final htmlText = _document('Finance Reconciliation', '''
      <h1>SchoolPro — Finance Collection & Expense Report</h1>
      <p><b>Period:</b> ${_escape(_from.text)} to ${_escape(_to.text)}</p>
      <table><tbody><tr><th>Fee payments</th><td>${paid.length}</td><td>PKR ${totalPaid.toStringAsFixed(2)}</td></tr>
      <tr><th>Expenses</th><td>${spent.length}</td><td>PKR ${totalSpent.toStringAsFixed(2)}</td></tr>
      <tr><th>Net cash movement</th><td></td><td>PKR ${(totalPaid-totalSpent).toStringAsFixed(2)}</td></tr>
      <tr><th>Duplicate / missing receipt numbers</th><td colspan="2">${duplicateReceipts.length}</td></tr>
      <tr><th>Expected monthly fees (configured structures)</th><td colspan="2">PKR ${expectedMonthly.toStringAsFixed(2)}</td></tr>
      <tr><th>Payments allocated by student/month</th><td colspan="2">PKR ${allocatedMonthlyPayments.toStringAsFixed(2)}</td></tr>
      <tr><th>Estimated outstanding monthly dues</th><td colspan="2">PKR ${outstandingMonthly.toStringAsFixed(2)}</td></tr>
      <tr><th>Payments missing fee structure / month reference</th><td colspan="2">PKR ${unallocatedPayments.toStringAsFixed(2)}</td></tr></tbody></table>
      <p>Monthly dues include only active students with matching fee structures explicitly marked frequency=monthly. Payments are allocated only when they include the matching feeStructureId and month. Legacy or non-monthly structures are excluded. Query limits: 2,000 payments, 2,000 expenses, 3,000 students and 500 fee structures.</p>''');
    final csv = <List<String>>[['Type','Document ID','Date','Description','Amount PKR','Receipt No']];
    for (final d in paid) { final x=d.data(); csv.add(['Fee Payment',d.id,(x['createdAt'] as Timestamp).toDate().toIso8601String(),(x['studentName']??x['studentId']??'').toString(),(x['amount']??'').toString(),(x['receiptNo']??'').toString()]); }
    for (final d in spent) { final x=d.data(); csv.add(['Expense',d.id,(x['date']??'').toString(),(x['title']??x['category']??'').toString(),(x['amount']??'').toString(),'']); }
    csv.add([]); csv.add(['Outstanding monthly dues','Admission No','Class','Month','Fee Structure','Expected PKR','Paid PKR','Due PKR']); csv.addAll(dueRows);
    await _db.collection('reports').add({
      'reportType':'finance_reconciliation','title':'Finance report ${_from.text} to ${_to.text}',
      'fromDate':_from.text,'toDate':_to.text,'paymentCount':paid.length,
      'expenseCount':spent.length,'totalPaid':totalPaid,'totalExpenses':totalSpent,
      'netCashMovement':totalPaid-totalSpent,'duplicateOrMissingReceipts':duplicateReceipts.length,
      'expectedMonthlyFees':expectedMonthly,'allocatedMonthlyPayments':allocatedMonthlyPayments,
      'estimatedOutstandingMonthlyDues':outstandingMonthly,'dueStudentMonthCount':dueRows.length,
      'unallocatedPayments':unallocatedPayments,
      'generatedBy':FirebaseAuth.instance.currentUser?.uid,'generatedAt':FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() { _lastHtml=htmlText; _lastCsv=csv; _lastCsvName='finance-reconciliation-${_from.text}-${_to.text}.csv';
      _message='Finance report saved. Collections PKR ${totalPaid.toStringAsFixed(2)}; expenses PKR ${totalSpent.toStringAsFixed(2)}; estimated monthly dues PKR ${outstandingMonthly.toStringAsFixed(2)}; duplicate/missing receipts: ${duplicateReceipts.length}; unallocated payments PKR ${unallocatedPayments.toStringAsFixed(2)}. Bank balances and non-monthly dues are not included.'; });
  });

  Future<void> _attendanceReport() => _run(() async {
    if (!_validRange) throw StateError('Enter a valid date range in YYYY-MM-DD format.');
    final docs = await _db.collection('attendance')
        .where('date', isGreaterThanOrEqualTo: _from.text.trim())
        .where('date', isLessThanOrEqualTo: _to.text.trim())
        .orderBy('date').limit(3000).get();
    if (docs.docs.length == 3000) throw StateError('Attendance report reached the 3,000-record query cap. Narrow the date range and run again.');
    final filtered = docs.docs.where((d) {
      final date=DateTime.tryParse((d.data()['date']??'').toString());
      return date!=null && !date.isBefore(DateTime.parse(_from.text)) && !date.isAfter(DateTime.parse(_to.text));
    }).toList();
    final counts=<String,int>{'Present':0,'Absent':0,'Leave':0};
    for(final d in filtered){ final status=(d.data()['status']??'Other').toString(); counts[status]=(counts[status]??0)+1; }
    final htmlText=_document('Attendance Report','''<h1>SchoolPro — Attendance Summary</h1><p><b>Period:</b> ${_escape(_from.text)} to ${_escape(_to.text)}</p><table><thead><tr><th>Status</th><th>Count</th></tr></thead><tbody>${counts.entries.map((e)=>'<tr><td>${_escape(e.key)}</td><td>${e.value}</td></tr>').join()}</tbody></table><p>Total records: ${filtered.length}</p>''');
    final csv=<List<String>>[['Date','Student ID','Student Name','Class','Status','Marked By'],...filtered.map((d){final x=d.data();return [(x['date']??'').toString(),(x['studentId']??'').toString(),(x['studentName']??'').toString(),(x['className']??'').toString(),(x['status']??'').toString(),(x['markedBy']??'').toString()];})];
    await _db.collection('reports').add({'reportType':'attendance_summary','fromDate':_from.text,'toDate':_to.text,'counts':counts,'totalRecords':filtered.length,'generatedBy':FirebaseAuth.instance.currentUser?.uid,'generatedAt':FieldValue.serverTimestamp()});
    if(!mounted)return;
    setState(()=>_lastHtml=htmlText);
    setState(()=>_lastCsv=csv);
    setState(()=>_lastCsvName='attendance-${_from.text}-${_to.text}.csv');
    setState(()=>_message='Attendance report saved. ${filtered.length} records: ${counts.entries.map((e)=>'${e.key} ${e.value}').join(', ')}.');
  });

  String _document(String title, String body) => '''<!doctype html><html><head><meta charset="utf-8"><title>${_escape(title)}</title><style>body{font-family:Arial,sans-serif;margin:32px;color:#17212b}h1{color:#176b55}table{border-collapse:collapse;width:100%;margin-top:20px}td,th{border:1px solid #9aa4ad;padding:9px;text-align:left}th{background:#edf3f1}p{line-height:1.6}@media print{button{display:none}body{margin:15mm}}</style></head><body>$body</body></html>''';

  String _csvValue(String value) => '"${value.replaceAll('"','""')}"';
  void _downloadCsv() {
    if (_lastCsv.isEmpty) return;
    final csv = _lastCsv.map((row) => row.map(_csvValue).join(',')).join('\r\n');
    downloadCsvFile('\uFEFF$csv', _lastCsvName);
  }
  void _printPdf() {
    if (_lastHtml.isEmpty) return;
    if (!printHtmlDocument(_lastHtml)) {
      setState(() => _message = 'Allow pop-ups for this site, then try Print / Save as PDF again.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reports, Report Cards & Exports')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Student report card', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Enter the Student document ID or Admission Number. Exam ID is optional; leave blank to include all saved results.'),
        const SizedBox(height: 10), TextField(controller: _studentId, decoration: const InputDecoration(labelText: 'Student document ID or Admission Number')),
        const SizedBox(height: 8), TextField(controller: _examId, decoration: const InputDecoration(labelText: 'Exam document ID (optional)')),
        const SizedBox(height: 10), FilledButton.icon(onPressed: _busy?null:_generateReportCard, icon: const Icon(Icons.school), label: const Text('Generate and save report card')),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fee receipt printing', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Enter an existing immutable payment document ID to print its official receipt or save it as PDF.'),
        const SizedBox(height: 10), TextField(controller: _paymentId, decoration: const InputDecoration(labelText: 'Fee payment document ID')),
        const SizedBox(height: 10), FilledButton.icon(onPressed: _busy ? null : _generateReceipt, icon: const Icon(Icons.receipt_long), label: const Text('Load receipt')),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Finance reconciliation & attendance reports', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Date filters use YYYY-MM-DD. Finance report includes recorded collections, expenses and receipt-number checks; attendance report summarizes saved attendance.'),
        const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From date'))), const SizedBox(width: 10), Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To date')))]),
        const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: _busy ? null : () { _financeReport(); }, icon: const Icon(Icons.account_balance), label: const Text('Finance report')), OutlinedButton.icon(onPressed: _busy ? null : () { _attendanceReport(); }, icon: const Icon(Icons.fact_check), label: const Text('Attendance report'))]),
      ]))),
      if (_busy) const LinearProgressIndicator(),
      if (_message.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(_message))),
      if (_lastHtml.isNotEmpty) Wrap(spacing: 10, children: [FilledButton.icon(onPressed: _printPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('Print / Save as PDF')), OutlinedButton.icon(onPressed: _downloadCsv, icon: const Icon(Icons.download), label: const Text('Download CSV'))]),
    ]),
  );

}
