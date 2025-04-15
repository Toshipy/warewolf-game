import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomTitle;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.roomTitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _initializeDisplayName();
  }

  Future<void> _initializeDisplayName() async {
    try {
      final userDoc =
          await _firestore
              .collection('users')
              .doc(_auth.currentUser?.uid)
              .get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        setState(() {
          _displayName = userData?['displayName'];
        });
      }
    } catch (e) {
      print('Error getting display name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown.shade900,
        automaticallyImplyLeading: false,
        title: Text(
          widget.roomTitle,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // チャットメッセージ表示エリア
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _firestore
                      .collection('rooms')
                      .doc(widget.roomId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('エラーが発生しました'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    return MessageBubble(
                      senderName: message['senderName'] ?? '？？？',
                      text: message['text'] ?? '',
                      isMe: message['senderId'] == _auth.currentUser?.uid,
                    );
                  },
                );
              },
            ),
          ),

          // プレイヤー一覧
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.brown.shade800,
              border: Border(
                top: BorderSide(color: Colors.amber.shade900, width: 2),
              ),
            ),
            child: StreamBuilder<DocumentSnapshot>(
              stream:
                  _firestore.collection('rooms').doc(widget.roomId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final roomData = snapshot.data!.data() as Map<String, dynamic>?;
                if (roomData == null) {
                  return const Center(child: Text('部屋の情報がありません'));
                }

                final players =
                    (roomData['players'] as Map<dynamic, dynamic>?)
                        ?.cast<String, dynamic>() ??
                    {};

                // プレイヤーを入室順に並び替え
                final sortedPlayers =
                    players.entries.toList()..sort((a, b) {
                      final aTime =
                          (a.value['joinedAt'] as Timestamp?)
                              ?.millisecondsSinceEpoch ??
                          0;
                      final bTime =
                          (b.value['joinedAt'] as Timestamp?)
                              ?.millisecondsSinceEpoch ??
                          0;
                      return aTime.compareTo(bTime);
                    });

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: sortedPlayers.length,
                  itemBuilder: (context, index) {
                    final player = sortedPlayers[index];
                    return PlayerAvatar(
                      displayName: player.value['displayName'] ?? '？？？',
                      isHost: player.value['isHost'] ?? false,
                    );
                  },
                );
              },
            ),
          ),

          // メッセージ入力エリア
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            decoration: BoxDecoration(color: Colors.brown.shade900),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
                TextButton(
                  onPressed: _leaveRoom,
                  child: Text(
                    '退出',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      await _firestore
          .collection('rooms')
          .doc(widget.roomId)
          .collection('messages')
          .add({
            'text': _messageController.text.trim(),
            'senderId': _auth.currentUser?.uid,
            'senderName': _displayName ?? '？？？',
            'timestamp': FieldValue.serverTimestamp(),
          });

      _messageController.clear();
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  Future<void> _leaveRoom() async {
    try {
      // 部屋の情報を取得
      final roomDoc =
          await _firestore.collection('rooms').doc(widget.roomId).get();
      if (!roomDoc.exists) {
        // 部屋が存在しない場合は単に画面を閉じる
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final roomData = roomDoc.data();
      if (roomData == null) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final players = roomData['players'] as Map<String, dynamic>? ?? {};
      final currentPlayer = players[_auth.currentUser?.uid];

      if (currentPlayer?['isHost'] == true) {
        // ホストの場合、部屋全体を削除
        await _firestore.collection('rooms').doc(widget.roomId).delete();
      } else {
        // 一般プレイヤーの場合、プレイヤーのみを削除
        await _firestore.collection('rooms').doc(widget.roomId).update({
          'players.${_auth.currentUser?.uid}': FieldValue.delete(),
          'currentPlayers': FieldValue.increment(-1),
        });
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error leaving room: $e');
      // エラーが発生しても画面を閉じる
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class MessageBubble extends StatelessWidget {
  final String senderName;
  final String text;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.senderName,
    required this.text,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue.shade700 : Colors.grey.shade700,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(text, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class PlayerAvatar extends StatelessWidget {
  final String displayName;
  final bool isHost;

  const PlayerAvatar({
    super.key,
    required this.displayName,
    required this.isHost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            backgroundColor: Colors.brown.shade900,
            child: Text(
              displayName.characters.first,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            displayName,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            maxLines: 1,
            // overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
