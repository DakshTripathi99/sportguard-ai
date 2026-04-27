import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:SportGuard/screens/violation_detail_screen.dart';
import 'package:SportGuard/screens/assets_violations_screen.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool isUploading = false;
  double uploadProgress = 0.0;
  String uploadStatus = '';
  Stream<QuerySnapshot>? _assetsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _assetsStream = FirebaseFirestore.instance
          .collection('assets')
          .where('orgId', isEqualTo: user.uid)
          .snapshots();
    });
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    final fileBytes = file.bytes;

    if (fileBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Could not read file.')),
        );
      }
      return;
    }

    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
      uploadStatus = 'Initializing upload...';
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('assets')
        .child(user.uid)
        .child(file.name);

    try {
      final ext = file.extension?.toLowerCase() ?? '';
      final isVid = _isVideo(file.name);
      final contentType = ext.isEmpty
          ? 'application/octet-stream'
          : isVid
          ? 'video/$ext'
          : 'image/$ext';

      final uploadTask = storageRef.putData(
        fileBytes,
        SettableMetadata(contentType: contentType),
      );

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() {
          uploadProgress = progress;
          uploadStatus = 'Uploading... ${(progress * 100).toInt()}%';
        });
      });

      await uploadTask;

      setState(() {
        uploadProgress = 1.0;
        uploadStatus = 'Upload complete! Scan starting...';
        isUploading = false;
      });

      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => uploadStatus = '');
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} is now protected!')),
        );
      }
    } catch (e) {
      setState(() {
        isUploading = false;
        uploadStatus = 'Failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAsset(String docId, String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Asset',
          style: TextStyle(color: Color(0xFF1E2A3A)),
        ),
        content: Text(
          'Are you sure you want to delete "$fileName"?\nAll associated violations will remain in the system.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF35858E)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('assets').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$fileName deleted.')));
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  bool _isVideo(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
  }

  /// Safe string extraction — never throws, never casts
  String _safeString(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final v = data[key];
    if (v == null) return fallback;
    return v.toString();
  }

  /// Safe int extraction — handles int, double, or string from Firestore
  int? _safeInt(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Widget _buildAssetCard(QueryDocumentSnapshot doc) {
    try {
      final asset = doc.data() as Map<String, dynamic>;
      final assetId = _safeString(asset, 'assetId', fallback: doc.id);
      final filePath = _safeString(asset, 'filePath');
      final fileName = asset['fileName'] != null
          ? _safeString(asset, 'fileName')
          : (filePath.isNotEmpty ? filePath.split('/').last : 'Unknown File');
      final fileSize = _safeInt(asset, 'fileSize');
      final isVid = _isVideo(fileName);

      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AssetViolationsScreen(assetId: assetId, fileName: fileName),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF35858E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVid ? Icons.videocam : Icons.image,
                  color: const Color(0xFF35858E),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Protected',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (fileSize != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatFileSize(fileSize),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Column(
                children: [
                  Icon(Icons.chevron_right, color: Color(0xFF35858E)),
                  Text(
                    'violations',
                    style: TextStyle(color: Color(0xFF35858E), fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 22,
                ),
                onPressed: () => _deleteAsset(doc.id, fileName),
                tooltip: 'Delete asset',
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // Single bad document never crashes the whole list
      debugPrint('Asset card error for ${doc.id}: $e');
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Asset ${doc.id} could not be displayed.',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEC9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF35858E),
        centerTitle: true,
        title: InkWell(
          onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.security, color: Color(0xFFC2D099), size: 24),
              SizedBox(width: 8),
              Text(
                'SportGuard AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Upload button
            SizedBox(
              width: double.infinity,
              height: 110,
              child: OutlinedButton(
                onPressed: isUploading ? null : _pickAndUpload,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF35858E), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_upload,
                      color: Color(0xFF35858E),
                      size: 36,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isUploading
                          ? 'Uploading...'
                          : 'Tap to Upload Image or Video',
                      style: const TextStyle(
                        color: Color(0xFF35858E),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (isUploading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: uploadProgress,
                backgroundColor: Colors.grey[300],
                color: const Color(0xFF35858E),
              ),
            ],
            if (uploadStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                uploadStatus,
                style: const TextStyle(
                  color: Color(0xFF35858E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Live asset list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _assetsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF35858E),
                      ),
                    );
                  }

                  // ── Show the actual error on screen (not just in console) ──
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load assets:\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _initStream,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF35858E),
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Protected Assets (${docs.length})',
                            style: const TextStyle(
                              color: Color(0xFF1E2A3A),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Live indicator dot
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Live',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (docs.isEmpty)
                        const Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_open,
                                  color: Color(0xFF35858E),
                                  size: 60,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No assets yet. Upload your first file!',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (ctx, i) => _buildAssetCard(docs[i]),
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
    );
  }
}
