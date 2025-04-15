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
  final ScrollController _scrollController = ScrollController();
  String? _displayName;
  bool _isGameStarted = false;

  @override
  void initState() {
    super.initState();
    _initializeDisplayName();
    _checkGameStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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

  Future<void> _checkGameStatus() async {
    _firestore.collection('rooms').doc(widget.roomId).snapshots().listen((
      snapshot,
    ) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final isStarted = data['isStarted'] ?? false;
        if (isStarted != _isGameStarted) {
          setState(() {
            _isGameStarted = isStarted;
          });
        }
      }
    });
  }

  Future<void> _startGame() async {
    try {
      final roomRef = _firestore.collection('rooms').doc(widget.roomId);
      final roomDoc = await roomRef.get();
      final roomData = roomDoc.data() as Map<String, dynamic>;
      final players = roomData['players'] as Map<String, dynamic>;
      final maxPlayers = roomData['maxPlayers'] as int;
      final isStarted = roomData['isStarted'] ?? false;

      print('Debug: プレイヤー数: ${players.length}, 最大プレイヤー数: $maxPlayers');
      print('Debug: ゲーム開始状態: $isStarted');

      if (players.length == maxPlayers && !isStarted) {
        // トランザクションで一括処理を行う
        await _firestore.runTransaction((transaction) async {
          // 再度ゲーム開始状態をチェック
          final freshDoc = await transaction.get(roomRef);
          if (freshDoc.data()?['isStarted'] == true) {
            print('Debug: 他のプレイヤーによってすでにゲームが開始されています');
            return;
          }

          print('Debug: プレイヤー数が最大に達しました');
          // 役職の割り当て
          final roles = _assignRoles(players.length);
          final playerEntries = players.entries.toList();

          print('Debug: 割り当てられた役職: $roles');

          // 各プレイヤーに役職を割り当て
          for (var i = 0; i < playerEntries.length; i++) {
            transaction.update(roomRef, {
              'players.${playerEntries[i].key}.role': roles[i],
            });
          }

          // ゲーム開始フラグを設定
          transaction.update(roomRef, {'isStarted': true});

          // システムメッセージを追加
          final messageRef = roomRef.collection('messages').doc();
          transaction.set(messageRef, {
            'type': 'system',
            'text': 'ゲームが開始されました！',
            'timestamp': FieldValue.serverTimestamp(),
          });
        });

        print('Debug: ゲームを開始しました');
      } else {
        print('Debug: プレイヤー数が不足しているか、すでにゲームが開始されています');
      }
    } catch (e) {
      print('Error starting game: $e');
    }
  }

  List<String> _assignRoles(int playerCount) {
    final roles = <String>[];
    // 人狼の数を決定（プレイヤー数の約1/4）
    final werewolfCount = (playerCount / 4).ceil();

    // 人狼を追加
    for (var i = 0; i < werewolfCount; i++) {
      roles.add('人狼');
    }

    // 村人を追加
    for (var i = 0; i < playerCount - werewolfCount; i++) {
      roles.add('市民');
    }

    // 役職をシャッフル
    roles.shuffle();
    return roles;
  }

  Future<void> _startGameWithBatch(
    List<MapEntry<String, dynamic>> players,
    String roomId,
  ) async {
    final batch = _firestore.batch();

    // 役職の割り当て
    final roles = _assignRoles(players.length);
    for (var i = 0; i < players.length; i++) {
      final playerRef = _firestore.collection('rooms').doc(roomId);
      batch.update(playerRef, {'players.${players[i].key}.role': roles[i]});
    }

    // ゲーム開始フラグを設定
    final roomRef = _firestore.collection('rooms').doc(roomId);
    batch.update(roomRef, {'isStarted': true});

    // システムメッセージを追加
    final messageRef = roomRef.collection('messages').doc();
    batch.set(messageRef, {
      'type': 'system',
      'text': 'ゲームが開始されました！',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 一括で更新を実行
    await batch.commit();
    print('Debug: ゲームを開始しました');
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
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('エラーが発生しました'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                // 新しいメッセージが来たら自動スクロール
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollController,
                  reverse: false,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    if (message['type'] == 'system') {
                      // システムメッセージの表示
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              message['text'] ?? '',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
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

          // 参加人数の表示（ゲーム開始前のみ）
          if (!_isGameStarted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              decoration: BoxDecoration(color: Colors.brown.shade900),
              child: StreamBuilder<DocumentSnapshot>(
                stream:
                    _firestore
                        .collection('rooms')
                        .doc(widget.roomId)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Text('読み込み中...');
                  final roomData =
                      snapshot.data!.data() as Map<String, dynamic>? ?? {};
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '参加人数: ${roomData['currentPlayers'] ?? 0} / ${roomData['maxPlayers'] ?? 0}',
                      style: const TextStyle(color: Colors.white),
                    ),
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

                // ゲーム開始条件をチェック
                final isHost =
                    roomData['players'][_auth.currentUser?.uid]?['isHost'] ==
                    true;
                if (!_isGameStarted &&
                    sortedPlayers.length == (roomData['maxPlayers'] as int) &&
                    isHost &&
                    !(roomData['isStarted'] ?? false)) {
                  // 非同期処理を遅延実行
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _startGame();
                  });
                }

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: sortedPlayers.length,
                  itemBuilder: (context, index) {
                    final player = sortedPlayers[index];
                    return PlayerAvatar(
                      displayName: player.value['displayName'] ?? '？？？',
                      isHost: player.value['isHost'] ?? false,
                      role: player.value['role'],
                      isCurrentUser: player.key == _auth.currentUser?.uid,
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
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        _sendMessage();
                      }
                    },
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
        // ホストの場合、他のプレイヤーがいるかチェック
        final otherPlayers =
            players.entries
                .where((entry) => entry.key != _auth.currentUser?.uid)
                .toList();

        if (otherPlayers.isNotEmpty) {
          // 他のプレイヤーがいる場合は退出できない
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('他のプレイヤーがいる場合、ホストは退出できません'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // 他のプレイヤーがいない場合は部屋を削除
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
  final String? role;
  final bool isCurrentUser;

  const PlayerAvatar({
    super.key,
    required this.displayName,
    required this.isHost,
    this.role,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isCurrentUser && role != null)
            Text(
              role!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          ),
        ],
      ),
    );
  }
}
