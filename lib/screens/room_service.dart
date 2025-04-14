import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // テスト用のメソッド
  Future<void> testConnection() async {
    try {
      await _firestore.collection('test').add({
        'timestamp': FieldValue.serverTimestamp(),
        'test': 'Hello Firebase!',
      });
      print('Firestore connection successful!');
    } catch (e) {
      print('Firestore connection error: $e');
    }
  }

  // 新しい部屋を作成
  Future<DocumentReference> createRoom({
    required String title,
    required List<String> roles,
    required int maxPlayers,
  }) async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }

      String userId = _auth.currentUser!.uid;
      String userName =
          _auth.currentUser!.displayName ?? 'プレイヤー${userId.substring(0, 4)}';

      // Firestoreに部屋データを登録
      return _firestore.collection('rooms').add({
        'title': title,
        'currentPlayers': 1,
        'maxPlayers': maxPlayers,
        'roles': roles,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': userId,
        'players': {
          userId: {
            'name': userName,
            'joinedAt': FieldValue.serverTimestamp(),
            'isHost': true,
          },
        },
      });
    } catch (e) {
      print('Firebase Error: $e');
      rethrow;
    }
  }
}
