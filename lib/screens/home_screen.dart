import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'room_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  User? _userId;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAndAuth();
  }

  Future<void> _initializeFirebaseAndAuth() async {
    try {
      // Firebaseの初期化確認
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      // ユーザー情報の取得
      _userId = _auth.currentUser;
      if (_userId == null) {
        // 匿名ユーザーの場合、匿名ユーザーを作成
        await _auth.signInAnonymously();
        _userId = _auth.currentUser;
      } else {
        // ユーザー情報の取得
        await _updateUserData(_userId!);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('エラー: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createUserData(String uid) async {
    try {
      final userData = {
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'displayName': 'Player ${uid.substring(0, 2)}',
      };
      await _firestore.collection('users').doc(uid).set(userData);
    } catch (e) {
      print('ユーザー情報の作成に失敗しました: $e');
    }
  }

  Future<void> _updateUserData(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('ユーザー情報の更新に失敗しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/home_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RoomListScreen()),
              );
            },
            child: Container(
              width: 200,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.blue.shade900,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  'START',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        offset: Offset(0, 3),
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
