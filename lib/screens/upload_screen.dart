import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_ap/screens/assets_violations_screen.dart';
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
  List<QueryDocumentSnapshot> myAssets = [];

  @override
  void initState() {
    super.initState();
    _fetchAssets();
  }

  Future<void> _fetchAssets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('assets')
        .where('ownerId', isEqualTo: user.uid)
        .orderBy('uploadedAt', descending: true)
        .get();

    setState(() {
      myAssets = snapshot.docs;
    });
  }

  // Future<void> _pickAndUpload() async {
  //   final result = await FilePicker.platform.pickFiles(type: FileType.media);

  //   if (result != null) {
  //     final file = result.files.first;
  //     setState(() {
  //       isUploading = true;
  //       uploadProgress = 0.0;
  //       uploadStatus = 'Initializing upload...';
  //     });

  //     await Future.delayed(const Duration(milliseconds: 500));
  //     setState(() {
  //       uploadProgress = 0.3;
  //       uploadStatus = 'Extracting fingerprint...';
  //     });

  //     await Future.delayed(const Duration(milliseconds: 800));
  //     setState(() {
  //       uploadProgress = 0.7;
  //       uploadStatus = 'Securing in database...';
  //     });

  //     final user = FirebaseAuth.instance.currentUser;
  //     if (user != null) {
  //       final docRef = FirebaseFirestore.instance.collection('assets').doc();
  //       await docRef.set({
  //         'assetId': docRef.id,
  //         'fileName': file.name,
  //         'fileSize': file.size,
  //         'uploadedAt': FieldValue.serverTimestamp(),
  //         'ownerId': user.uid,
  //         'status': 'active',
  //       });
  //     }

  //     await Future.delayed(const Duration(milliseconds: 500));
  //     setState(() {
  //       uploadProgress = 1.0;
  //       uploadStatus = 'Upload Complete!';
  //       isUploading = false;
  //     });

  //     _fetchAssets();

  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('${file.name} is now protected!')),
  //       );
  //     }
  //   }
  // }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      withData: true, // important for web — loads bytes into memory
    );

    if (result != null) {
      final file = result.files.first;
      final bytes = file.bytes; // web uses bytes, not path

      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file bytes.')),
        );
        return;
      }

      setState(() {
        isUploading = true;
        uploadProgress = 0.0;
        uploadStatus = 'Initializing upload...';
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Create Firestore doc first to get the ID
      final docRef = FirebaseFirestore.instance.collection('assets').doc();
      final assetId = docRef.id;

      setState(() {
        uploadProgress = 0.2;
        uploadStatus = 'Uploading to secure storage...';
      });

      // Upload actual file bytes to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('assets')
          .child(user.uid)
          .child('$assetId-${file.name}');

      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(
          contentType: file.extension != null
              ? 'image/${file.extension}'
              : 'application/octet-stream',
        ),
      );

      // Listen to upload progress
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() {
          uploadProgress = 0.2 + (progress * 0.6); // scale to 20%-80%
          uploadStatus = 'Uploading... ${(progress * 100).toInt()}%';
        });
      });

      // Wait for upload to complete and get download URL
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        uploadProgress = 0.9;
        uploadStatus = 'Securing in database...';
      });

      // Now save metadata to Firestore including the storage URL
      await docRef.set({
        'assetId': assetId,
        'fileName': file.name,
        'fileSize': file.size,
        'uploadedAt': FieldValue.serverTimestamp(),
        'ownerId': user.uid,
        'status': 'active',
        'storagePath':
            storageRef.fullPath, // ← this is what onAssetUploaded needs
        'downloadUrl': downloadUrl,
      });

      setState(() {
        uploadProgress = 1.0;
        uploadStatus = 'Upload Complete!';
        isUploading = false;
      });

      _fetchAssets();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} is now protected!')),
        );
      }
    }
  }

  Future<void> _deleteAsset(String docId, String fileName) async {
    // confirm before deleting
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
      _fetchAssets();
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

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Protected Assets (${myAssets.length})',
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF35858E)),
                  onPressed: _fetchAssets,
                  tooltip: 'Refresh',
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Asset list
            Expanded(
              child: myAssets.isEmpty
                  ? const Center(
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
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: myAssets.length,
                      itemBuilder: (ctx, i) {
                        final doc = myAssets[i];
                        final asset = doc.data() as Map<String, dynamic>;
                        final assetId = asset['assetId'] as String? ?? doc.id;
                        final fileName =
                            asset['fileName'] as String? ?? 'Unknown File';
                        final fileSize = asset['fileSize'] as int?;
                        final isVid = _isVideo(fileName);

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AssetViolationsScreen(
                                assetId: assetId,
                                fileName: fileName,
                              ),
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
                                // file type icon
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF35858E,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isVid ? Icons.videocam : Icons.image,
                                    color: const Color(0xFF35858E),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // file info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              color: Colors.green.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                                // view violations hint
                                const Column(
                                  children: [
                                    Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFF35858E),
                                    ),
                                    Text(
                                      'violations',
                                      style: TextStyle(
                                        color: Color(0xFF35858E),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                // delete button
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                    size: 22,
                                  ),
                                  onPressed: () =>
                                      _deleteAsset(doc.id, fileName),
                                  tooltip: 'Delete asset',
                                ),
                              ],
                            ),
                          ),
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
