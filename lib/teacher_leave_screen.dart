import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TeacherLeaveScreen extends StatefulWidget {
  const TeacherLeaveScreen({super.key, required this.user, this.urdu = false});
  final User user; final bool urdu;
  @override State<TeacherLeaveScreen> createState()=>_TeacherLeaveScreenState();
}
class _TeacherLeaveScreenState extends State<TeacherLeaveScreen> {
  final _reason=TextEditingController(); final _start=TextEditingController(); final _end=TextEditingController(); bool _busy=false; String _message='';
  String t(String a,String b)=>widget.urdu?b:a;
  @override void dispose(){_reason.dispose();_start.dispose();_end.dispose();super.dispose();}
  Future<void> _submit() async {
    final reason=_reason.text.trim(), start=_start.text.trim(), end=_end.text.trim();
    final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final parsedStart = DateTime.tryParse(start);
    final parsedEnd = DateTime.tryParse(end);
    if(reason.length<5||!datePattern.hasMatch(start)||!datePattern.hasMatch(end)||parsedStart==null||parsedEnd==null||parsedEnd.isBefore(parsedStart)){setState(()=>_message=t('Enter valid dates (YYYY-MM-DD), an end date not before the start date, and a reason of at least 5 characters.','درست تاریخیں (YYYY-MM-DD)، شروع سے پہلے نہ ہونے والی اختتامی تاریخ، اور کم از کم 5 حروف کی وجہ درج کریں۔'));return;}
    setState(()=>_busy=true);
    try {
      final db=FirebaseFirestore.instance; final profile=await db.collection('users').doc(widget.user.uid).get(); final p=profile.data()??{};
      if(p['role']!='teacher'||p['approvalStatus']!='approved'||(p['teacherId']??'').toString().isEmpty) throw StateError('Only approved teachers can request leave.');
      await db.collection('leaveRequests').add({'teacherUid':widget.user.uid,'teacherId':p['teacherId'],'teacherName':p['name']??p['displayName']??'','reason':reason,'startDate':start,'endDate':end,'status':'pending','createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
      _reason.clear();_start.clear();_end.clear();setState(()=>_message=t('Leave request submitted.','چھٹی کی درخواست جمع ہوگئی۔'));
    }catch(e){setState(()=>_message='${t('Could not submit: ','جمع نہیں ہو سکی: ')}$e');}finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Leave requests','چھٹی کی درخواستیں'))),body:ListView(padding:const EdgeInsets.all(16),children:[
    TextField(controller:_start,decoration:InputDecoration(labelText:t('Start date (YYYY-MM-DD)','شروع ہونے کی تاریخ (YYYY-MM-DD)'))),const SizedBox(height:8),
    TextField(controller:_end,decoration:InputDecoration(labelText:t('End date (YYYY-MM-DD)','اختتامی تاریخ (YYYY-MM-DD)'))),const SizedBox(height:8),
    TextField(controller:_reason,maxLines:3,decoration:InputDecoration(labelText:t('Reason','وجہ'))),const SizedBox(height:12),
    FilledButton(onPressed:_busy?null:_submit,child:Text(t('Submit request','درخواست جمع کریں'))),if(_busy)const LinearProgressIndicator(),if(_message.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(_message)),
    const Divider(height:28),Text(t('My requests','میری درخواستیں'),style:Theme.of(context).textTheme.titleLarge),
    StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('leaveRequests').where('teacherUid',isEqualTo:widget.user.uid).snapshots(),builder:(c,s){if(s.hasError)return Text(s.error.toString());if(!s.hasData)return const Center(child:CircularProgressIndicator());return Column(children:s.data!.docs.map((d){final x=d.data();return ListTile(leading:const Icon(Icons.event_note),title:Text('${x['startDate']??''} — ${x['endDate']??''}'),subtitle:Text('${x['reason']??''}\n${x['adminNote']??''}'),trailing:Text((x['status']??'').toString()));}).toList());}),
  ]));
}
