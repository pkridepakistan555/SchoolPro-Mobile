import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Uploads identity/education documents and profile images to the user's
/// private Firebase Storage namespace. Only metadata/URLs are stored in Firestore.
class ProfileDocumentsScreen extends StatefulWidget {
  const ProfileDocumentsScreen({super.key, required this.user, this.urdu = false});
  final User user;
  final bool urdu;
  @override
  State<ProfileDocumentsScreen> createState() => _ProfileDocumentsScreenState();
}

class _ProfileDocumentsScreenState extends State<ProfileDocumentsScreen> {
  bool _busy = false;
  String _message = '';
  String t(String en, String ur) => widget.urdu ? ur : en;

  Future<void> _upload({required bool imageOnly}) async {
    if (_busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: imageOnly ? FileType.image : FileType.custom,
        allowedExtensions: imageOnly ? null : ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Selected file is empty.');
      final limit = imageOnly ? 5 * 1024 * 1024 : 10 * 1024 * 1024;
      if (bytes.length > limit) throw Exception('File exceeds the allowed size.');
      final ext = (file.extension ?? '').toLowerCase();
      final isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
      if (imageOnly && !isImage) throw Exception('Choose an image file.');
      if (!imageOnly && !(isImage || ext == 'pdf')) throw Exception('Only PDF or image files are allowed.');
      setState(() { _busy = true; _message = ''; });
      final uid = widget.user.uid;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final folder = imageOnly ? 'userProfiles' : 'userDocuments';
      final path = '$folder/$uid/${stamp}_${file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
      final contentType = ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      if (imageOnly) {
        await userRef.update({'photoUrl': url, 'updatedAt': FieldValue.serverTimestamp()});
      } else {
        await userRef.update({
          'uploadedDocuments': FieldValue.arrayUnion([{
            'name': file.name, 'url': url, 'storagePath': path,
            'contentType': contentType, 'uploadedAt': Timestamp.now(),
          }]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) setState(() => _message = t('Upload completed successfully.', 'فائل کامیابی سے اپلوڈ ہوگئی۔'));
    } catch (e) {
      if (mounted) setState(() => _message = '${t('Upload failed: ', 'اپلوڈ ناکام: ')}$e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Profile photo & documents', 'پروفائل تصویر اور دستاویزات'))),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() ?? <String, dynamic>{};
        final photo = (data['photoUrl'] ?? '').toString();
        final docs = (data['uploadedDocuments'] as List?) ?? const [];
        return ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: CircleAvatar(radius: 44, backgroundImage: photo.isEmpty ? null : NetworkImage(photo), child: photo.isEmpty ? const Icon(Icons.person, size: 42) : null)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : () => _upload(imageOnly: true), icon: const Icon(Icons.add_a_photo), label: Text(t('Upload / change profile photo', 'پروفائل تصویر اپلوڈ یا تبدیل کریں'))),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : () => _upload(imageOnly: false), icon: const Icon(Icons.upload_file), label: Text(t('Upload ID / education document (PDF or image)', 'شناختی / تعلیمی دستاویز اپلوڈ کریں (PDF یا تصویر)'))),
          if (_busy) const LinearProgressIndicator(),
          if (_message.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(_message)),
          const Divider(height: 28),
          Text(t('Uploaded documents', 'اپلوڈ شدہ دستاویزات'), style: Theme.of(context).textTheme.titleLarge),
          if (docs.isEmpty) Text(t('No documents uploaded yet.', 'ابھی کوئی دستاویز اپلوڈ نہیں ہوئی۔')),
          for (final raw in docs) if (raw is Map) ListTile(
            leading: Icon((raw['contentType'] ?? '').toString() == 'application/pdf' ? Icons.picture_as_pdf : Icons.image),
            title: Text((raw['name'] ?? 'Document').toString()),
            subtitle: Text((raw['uploadedAt'] ?? '').toString()),
            trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () {
              final url = (raw['url'] ?? '').toString();
              if (url.isNotEmpty) showDialog(context: context, builder: (_) => AlertDialog(content: SelectableText(url)));
            }),
          ),
        ]);
      },
    ),
  );
}
