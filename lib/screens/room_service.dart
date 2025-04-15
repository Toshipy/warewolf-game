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

  // 部屋一覧を取得
  Future<List<Map<String, dynamic>>> getRooms() async {
    try {
      final querySnapshot =
          await _firestore
              .collection('rooms')
              .orderBy('createdAt', descending: true)
              .get();

      // 取得したデータをリストに変換
      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Firestore Error: $e');
      rethrow;
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

      // ユーザー情報を取得
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();
      String userName = userData?['displayName'] ?? '？？？';

      // Firestoreに部屋データを登録
      return _firestore
          .collection('rooms')
          .add({
            'title': title,
            'currentPlayers': 1,
            'maxPlayers': maxPlayers,
            'roles': roles,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': userId,
            'players': {
              userId: {
                'displayName': userName,
                'joinedAt': FieldValue.serverTimestamp(),
                'isHost': true,
              },
            },
          })
          .then((roomRef) async {
            // 入室メッセージを追加
            await roomRef.collection('messages').add({
              'text': '${userName}が入室しました',
              'senderId': 'system',
              'senderName': 'システム',
              'timestamp': FieldValue.serverTimestamp(),
              'type': 'system',
            });
            return roomRef;
          });
    } catch (e) {
      print('Firebase Error: $e');
      rethrow;
    }
  }

  Future<void> joinRoom(String roomId) async {
    try {
      if (_auth.currentUser == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // ユーザー情報を取得
      final userDoc =
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .get();
      final userData = userDoc.data();
      if (userData == null) {
        throw Exception('ユーザー情報が見つかりません');
      }

      // 部屋の情報を取得して現在の人数をチェック
      final roomDoc = await _firestore.collection('rooms').doc(roomId).get();
      if (!roomDoc.exists) {
        throw Exception('部屋が存在しません');
      }

      final roomData = roomDoc.data();
      if (roomData == null) {
        throw Exception('部屋の情報が取得できません');
      }

      if (roomData['currentPlayers'] >= roomData['maxPlayers']) {
        throw Exception('部屋が満員です');
      }

      // 入室処理
      await _firestore.collection('rooms').doc(roomId).update({
        'players.${_auth.currentUser!.uid}': {
          'displayName': userData['displayName'],
          'joinedAt': FieldValue.serverTimestamp(),
          'isHost': false,
        },
        'currentPlayers': FieldValue.increment(1),
      });

      // 入室メッセージを追加
      await _firestore
          .collection('rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'text': '${userData['displayName']}が入室しました',
            'senderId': 'system',
            'senderName': 'システム',
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'system',
          });
    } catch (e) {
      print('入室エラー: $e');
      rethrow;
    }
  }
}
