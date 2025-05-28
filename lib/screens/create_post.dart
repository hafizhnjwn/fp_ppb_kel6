// File: lib/screens/create_post_screen.dart
import 'dart:convert'; // For Imgur/FastAPI response parsing
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <<< ADD THIS LINE
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fp_pbb_kel6/services/firestore_service.dart'; // Ensure this path is correct
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  bool _isLoading = false;
  final FirestoreService _firestoreService = FirestoreService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // --- Imgur Client ID - IMPORTANT: Store this securely, NOT in code for production ---
  // --- Consider using flutter_dotenv to load it from a .env file ---
  final String _imgurClientId = "YOUR_IMGUR_CLIENT_ID"; // REPLACE OR LOAD FROM ENV

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 85);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image picking failed: $e")),
      );
    }
  }

  // REMOVE _uploadImageToFirebaseStorage method entirely if not using it.

  Future<String?> _uploadImageToImgur(File image) async {
    if (_imgurClientId == "YOUR_IMGUR_CLIENT_ID" || _imgurClientId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Imgur Client ID not configured.")),
        );
      }
      return null;
    }

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.imgur.com/3/image'),
    );
    request.headers['Authorization'] = 'Client-ID $_imgurClientId';
    request.files.add(await http.MultipartFile.fromPath(
      'image', // field name for Imgur API
      image.path,
      filename: path.basename(image.path), // Optional: send filename
    ));

    try {
      setState(() { _isLoading = true; }); // Show loading specifically for upload
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      setState(() { _isLoading = false; }); // Hide loading

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true && jsonResponse['data'] != null && jsonResponse['data']['link'] != null) {
          return jsonResponse['data']['link'];
        } else {
          print("Imgur upload failed: API returned success false or missing link. ${response.body}");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Imgur upload error: ${jsonResponse['data']?['error'] ?? 'Unknown error'}")),
            );
          }
          return null;
        }
      } else {
        print("Imgur upload failed: ${response.statusCode} ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Imgur upload error: ${response.statusCode}")),
          );
        }
        return null;
      }
    } catch (e) {
      print("Imgur upload exception: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imgur upload exception: $e")),
        );
      }
      return null;
    }
  }

  Future<String?> _uploadImageToFastAPI(File image) async {
    // 1. Define your FastAPI server's upload endpoint URL
    const String fastApiUploadUrl = "YOUR_FASTAPI_SERVER_URL/upload_image/"; // e.g., http://10.0.2.2:8000/upload for Android emulator

    var request = http.MultipartRequest('POST', Uri.parse(fastApiUploadUrl));
    request.files.add(await http.MultipartFile.fromPath(
      'file', // This 'file' key must match what your FastAPI endpoint expects
      image.path,
      filename: path.basename(image.path),
    ));
    // request.fields['user_id'] = _currentUser?.uid ?? 'unknown'; // Optional: send other data

    try {
      setState(() { _isLoading = true; });
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      setState(() { _isLoading = false; });

      if (response.statusCode == 200) { // Or 201, depending on your FastAPI response
        final jsonResponse = jsonDecode(response.body);
        // Assuming your FastAPI returns a JSON like: {"image_url": "http://yourserver.com/path/to/image.jpg"}
        return jsonResponse['image_url'];
      } else {
        print("FastAPI upload failed: ${response.statusCode} ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("FastAPI upload error: ${response.statusCode}")),
          );
        }
        return null;
      }
    } catch (e) {
      print("FastAPI upload exception: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("FastAPI upload exception: $e")),
        );
      }
      return null;
    }
  }


  Future<void> _submitPost() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an image.")),
      );
      return;
    }
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in. Cannot post.")),
      );
      return;
    }

    setState(() { _isLoading = true; }); // General loading for the whole submit process

    // CHOOSE ONE UPLOAD METHOD:
    String? imageUrl = await _uploadImageToImgur(_imageFile!);
    // OR
    // String? imageUrl = await _uploadImageToFastAPI(_imageFile!);

    if (imageUrl != null) {
      try {
        String username = _currentUser!.displayName ?? "Anonymous";
        DocumentSnapshot userData = await _firestoreService.getUserData(_currentUser!.uid);
        if (userData.exists && (userData.data() as Map<String, dynamic>).containsKey('username')) {
          username = (userData.data() as Map<String, dynamic>)['username'];
        }

        // Now save the imageUrl (from Imgur/FastAPI) to Cloud Firestore
        await _firestoreService.createPost(
          userId: _currentUser!.uid,
          username: username,
          imageUrl: imageUrl, // This is the URL from Imgur/FastAPI
          caption: _captionController.text.trim(),
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Post created successfully!")),
        );
        setState(() {
          _imageFile = null;
          _captionController.clear();
        });
        Navigator.pop(context);
      } catch (e) {
        print("Error creating post in Firestore: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving post details: $e")),
        );
      }
    } else {
      // Error message for upload failure is handled within the upload methods
      print("Image upload returned null. Post not created.");
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
  }

  // _showImageSourceActionSheet remains the same as before

  // build method remains largely the same, just ensure it calls the correct methods
  // and doesn't reference firebase_storage
  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.of(bc).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(bc).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create New Post"),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submitPost,
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2,))
                : const Text("Share", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () => _showImageSourceActionSheet(context),
              child: Container(
                height: MediaQuery.of(context).size.width * 0.8,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  border: Border.all(color: Colors.grey[700]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _imageFile != null
                    ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(_imageFile!, fit: BoxFit.cover))
                    : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 60, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text("Tap to select an image", style: TextStyle(color: Colors.grey[400])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(
                  hintText: "Write a caption...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[850],
                  hintStyle: TextStyle(color: Colors.grey[500])
              ),
              maxLines: 4,
              minLines: 1,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}