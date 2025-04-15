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
  bool _isLoading = false;
  User? _userId;
  String? _errorMessage;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ログイン用のController
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // 登録用のController
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerNameController = TextEditingController();

  String _currentState = 'home';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerNameController.dispose();
    super.dispose();
  }

  Future<void> _initializeFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  Future<void> _login() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await _initializeFirebase();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _loginEmailController.text,
        password: _loginPasswordController.text,
      );

      if (userCredential.user != null) {
        await _updateUserData(userCredential.user!);
        setState(() {
          _userId = userCredential.user;
          _currentState = 'loggedIn';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'ログインに失敗しました: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _register() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await _initializeFirebase();

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _registerEmailController.text,
        password: _registerPasswordController.text,
      );

      if (userCredential.user != null) {
        await _createUserData(
          userCredential.user!.uid,
          _registerNameController.text,
        );
        setState(() {
          _userId = userCredential.user;
          _currentState = 'loggedIn';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '登録に失敗しました: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createUserData(String uid, String displayName) async {
    try {
      final userData = {
        'userId': uid,
        'displayName': displayName,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('users').doc(uid).set(userData);
    } catch (e) {
      print('ユーザー情報の作成に失敗しました: $e');
      rethrow;
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

  Widget _buildAuthForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentState == 'login') ...[
            TextField(
              controller: _loginEmailController,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _loginPasswordController,
              decoration: const InputDecoration(
                labelText: 'パスワード',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _login,
              child: Text(_isLoading ? 'ログイン中...' : 'ログイン'),
            ),
            TextButton(
              onPressed: () => setState(() => _currentState = 'register'),
              child: const Text('新規登録はこちら'),
            ),
          ] else if (_currentState == 'register') ...[
            TextField(
              controller: _registerNameController,
              decoration: const InputDecoration(
                labelText: 'ニックネーム',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _registerEmailController,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _registerPasswordController,
              decoration: const InputDecoration(
                labelText: 'パスワード',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _register,
              child: Text(_isLoading ? '登録中...' : '登録'),
            ),
            TextButton(
              onPressed: () => setState(() => _currentState = 'login'),
              child: const Text('ログインはこちら'),
            ),
          ],
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
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
          child:
              _isLoading
                  ? const CircularProgressIndicator()
                  : _currentState == 'loggedIn'
                  ? GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RoomListScreen(),
                        ),
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
                            offset: const Offset(0, 3),
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
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  : _currentState == 'login' || _currentState == 'register'
                  ? _buildAuthForm()
                  : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // タイトル
                      const Text(
                        'Werewolf Game',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(2, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 50),
                      // ログインボタン
                      _buildHomeButton(
                        'ログイン',
                        Colors.blue.shade900,
                        () => setState(() => _currentState = 'login'),
                      ),
                      const SizedBox(height: 20),
                      // 新規登録ボタン
                      _buildHomeButton(
                        '新規登録',
                        Colors.green.shade900,
                        () => setState(() => _currentState = 'register'),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildHomeButton(String text, Color color, VoidCallback onPressed) {
    return Container(
      width: 200,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
          elevation: 5,
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
