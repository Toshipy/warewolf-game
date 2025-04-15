import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

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
  Timer? _timer;
  int _remainingSeconds = 30;
  bool _isNightTime = false;
  bool _isVotingTime = false;
  int _currentDay = 1;
  String? _votedPlayerId;
  Map<String, int> _voteResults = {};
  Set<String> _executedPlayers = {};

  @override
  void initState() {
    super.initState();
    _initializeDisplayName();
    _checkGameStatus();
    // ゲーム状態と処刑プレイヤーの監視を開始
    _firestore.collection('rooms').doc(widget.roomId).snapshots().listen((
      snapshot,
    ) {
      if (snapshot.exists) {
        final gameState =
            (snapshot.data()?['gameState'] ?? {}) as Map<String, dynamic>;
        if (gameState.isNotEmpty) {
          setState(() {
            _isGameStarted = snapshot.data()?['isStarted'] ?? false;
            _isNightTime = gameState['isNightTime'] as bool;
            _isVotingTime = gameState['isVotingTime'] as bool;
            _currentDay = gameState['currentDay'] as int;
            if (_timer == null && _isGameStarted) {
              _startTimer();
            }
          });
        }
        final executed = (snapshot.data()?['executedPlayers'] as List<dynamic>?)?.cast<String>() ?? [];
        setState(() {
          _executedPlayers = executed.toSet();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  void _startTimer() {
    _timer?.cancel();

    // Firestoreにタイマーの初期状態を設定
    _firestore.collection('rooms').doc(widget.roomId).update({
      'gameState': {
        'isNightTime': _isNightTime,
        'isVotingTime': _isVotingTime,
        'currentDay': _currentDay,
        'remainingSeconds': _getPhaseSeconds(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
    });

    // ローカルのタイマーを開始
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTimer();
    });
  }

  int _getPhaseSeconds() {
    if (_isNightTime) return 10; // 夜時間: 10秒
    if (_isVotingTime) return 10; // 投票時間: 10秒
    return 30; // 話し合い時間: 30秒
  }

  void _showVotingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestore.collection('rooms').doc(widget.roomId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final roomData = snapshot.data!.data() as Map<String, dynamic>?;
            if (roomData == null) return const SizedBox.shrink();

            final players =
                (roomData['players'] as Map<dynamic, dynamic>?)
                    ?.cast<String, dynamic>() ??
                {};
            final currentUserId = _auth.currentUser?.uid;

            // 自分以外の生存しているプレイヤーのリストを作成
            final alivePlayers =
                players.entries
                    .where(
                      (player) =>
                          player.key != currentUserId &&
                          !_executedPlayers.contains(player.key),
                    )
                    .toList();

            return AlertDialog(
              title: const Text('投票'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('処刑するプレイヤーを選択してください'),
                  const SizedBox(height: 16),
                  ...alivePlayers.map(
                    (player) => ListTile(
                      title: Text(player.value['displayName'] ?? '不明'),
                      tileColor:
                          _votedPlayerId == player.key
                              ? Colors.blue.withOpacity(0.2)
                              : null,
                      onTap: () {
                        setState(() => _votedPlayerId = player.key);
                        _submitVote(player.key);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitVote(String targetPlayerId) async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      await _firestore.collection('rooms').doc(widget.roomId).update({
        'votes.$currentUserId': targetPlayerId,
      });
    } catch (e) {
      print('Error submitting vote: $e');
    }
  }

  Future<void> _processVoteResults() async {
    try {
      final roomDoc =
          await _firestore.collection('rooms').doc(widget.roomId).get();
      final roomData = roomDoc.data() as Map<String, dynamic>?;
      if (roomData == null) return;

      final votes =
          (roomData['votes'] as Map<dynamic, dynamic>?)
              ?.cast<String, String>() ??
          {};
      final voteCount = <String, int>{};

      // 投票を集計
      votes.values.forEach((targetId) {
        voteCount[targetId] = (voteCount[targetId] ?? 0) + 1;
      });

      // 最多得票者を特定
      int maxVotes = 0;
      String? executedPlayerId;
      voteCount.forEach((playerId, count) {
        if (count > maxVotes) {
          maxVotes = count;
          executedPlayerId = playerId;
        }
      });

      if (executedPlayerId != null) {
        final players =
            (roomData['players'] as Map<dynamic, dynamic>?)
                ?.cast<String, dynamic>() ??
            {};
        final executedPlayerName =
            players[executedPlayerId]?['displayName'] ?? '不明';
        final executedPlayerRole = players[executedPlayerId]?['role'] ?? '不明';

        // 処刑されたプレイヤーを記録
        _executedPlayers.add(executedPlayerId!);

        // 処刑結果を保存
        await _firestore.collection('rooms').doc(widget.roomId).update({
          'executedPlayers': FieldValue.arrayUnion([executedPlayerId]),
          'votes': {}, // 投票をリセット
        });

        // システムメッセージを送信
        await _firestore
            .collection('rooms')
            .doc(widget.roomId)
            .collection('messages')
            .add({
              'type': 'system',
              'text':
                  '⚠️ ${executedPlayerName}が処刑されました。\n役職: $executedPlayerRole',
              'timestamp': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      print('Error processing vote results: $e');
    }
  }

  void _updateTimer() async {
    final roomDoc =
        await _firestore.collection('rooms').doc(widget.roomId).get();
    final gameState =
        (roomDoc.data()?['gameState'] ?? {}) as Map<String, dynamic>;
    final lastUpdatedAt = gameState['lastUpdatedAt'] as Timestamp?;

    if (lastUpdatedAt != null) {
      final now = Timestamp.now();
      final elapsedSeconds = now.seconds - lastUpdatedAt.seconds;
      final remainingSeconds =
          (gameState['remainingSeconds'] as int) - elapsedSeconds;

      if (remainingSeconds <= 0) {
        _timer?.cancel();
        if (roomDoc.data()?['players'][_auth.currentUser?.uid]?['isHost'] ==
            true) {
          _switchPhase();
        }
      } else {
        setState(() {
          _remainingSeconds = remainingSeconds;
          _isNightTime = gameState['isNightTime'] as bool;
          _isVotingTime = gameState['isVotingTime'] as bool;
          _currentDay = gameState['currentDay'] as int;
        });
      }
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
      backgroundColor: _isNightTime ? Colors.black87 : null,
      body: Column(
        children: [
          // タイマー表示
          if (_isGameStarted)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: _getPhaseColor(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getPhaseIcon(), color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '${_currentDay}日目 ${_getPhaseText()} - 残り${_remainingSeconds}秒',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // チャットメッセージ表示エリア
          Expanded(
            child: Container(
              color: _isNightTime ? Colors.black54 : null,
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
            child: Row(
              children: [
                // スクロール可能なプレイヤーリスト
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream:
                        _firestore
                            .collection('rooms')
                            .doc(widget.roomId)
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final roomData =
                          snapshot.data!.data() as Map<String, dynamic>?;
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
                          roomData['players'][_auth
                              .currentUser
                              ?.uid]?['isHost'] ==
                          true;
                      if (!_isGameStarted &&
                          sortedPlayers.length ==
                              (roomData['maxPlayers'] as int) &&
                          isHost &&
                          !(roomData['isStarted'] ?? false)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _startGame();
                        });
                      }

                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: sortedPlayers.length,
                        itemBuilder: (context, index) {
                          final player = sortedPlayers[index];
                          return _buildPlayerAvatar(player);
                        },
                      );
                    },
                  ),
                ),
                // 役職表示（右側固定）
                if (_isGameStarted)
                  StreamBuilder<DocumentSnapshot>(
                    stream:
                        _firestore
                            .collection('rooms')
                            .doc(widget.roomId)
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();

                      final roomData =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      if (roomData == null) return const SizedBox.shrink();

                      final currentUserRole =
                          roomData['players'][_auth.currentUser?.uid]?['role']
                              as String?;
                      if (currentUserRole == null)
                        return const SizedBox.shrink();

                      return Container(
                        width: 80,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Colors.amber.shade900,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.brown.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              currentUserRole,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // 投票ボタン（投票時間中のみ表示）
          if (_isVotingTime &&
              !_executedPlayers.contains(_auth.currentUser?.uid))
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade800,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _showVotingDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade800,
                    ),
                    child: const Text('投票する'),
                  ),
                ],
              ),
            ),

          // メッセージ入力エリア（処刑されたプレイヤーは入力不可）
          if (!_executedPlayers.contains(_auth.currentUser?.uid))
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

  Color _getPhaseColor() {
    if (_isNightTime) return Colors.indigo.shade900;
    if (_isVotingTime) return Colors.red.shade800;
    return Colors.orange.shade800;
  }

  IconData _getPhaseIcon() {
    if (_isNightTime) return Icons.nightlight_round;
    if (_isVotingTime) return Icons.how_to_vote;
    return Icons.wb_sunny;
  }

  String _getPhaseText() {
    if (_isNightTime) return "夜";
    if (_isVotingTime) return "投票";
    return "昼";
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
        await _firestore.runTransaction((transaction) async {
          final freshDoc = await transaction.get(roomRef);
          if (freshDoc.data()?['isStarted'] == true) {
            print('Debug: 他のプレイヤーによってすでにゲームが開始されています');
            return;
          }

          print('Debug: プレイヤー数が最大に達しました');
          final roles = _assignRoles(players.length);
          final playerEntries = players.entries.toList();

          print('Debug: 割り当てられた役職: $roles');

          for (var i = 0; i < playerEntries.length; i++) {
            transaction.update(roomRef, {
              'players.${playerEntries[i].key}.role': roles[i],
            });
          }

          // ゲーム開始状態とゲーム状態を設定
          transaction.update(roomRef, {
            'isStarted': true,
            'gameState': {
              'isNightTime': false,
              'isVotingTime': false,
              'currentDay': 1,
              'remainingSeconds': 30,
              'lastUpdatedAt': FieldValue.serverTimestamp(),
            },
          });

          final messageRef = roomRef.collection('messages').doc();
          transaction.set(messageRef, {
            'type': 'system',
            'text': 'ゲームが開始されました！\n☀️ 1日目の昼がはじまります',
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

  // プレイヤー表示を更新
  Widget _buildPlayerAvatar(MapEntry<String, dynamic> player) {
    final isExecuted = _executedPlayers.contains(player.key);
    return Container(
      width: 60,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            children: [
              CircleAvatar(
                backgroundColor:
                    isExecuted ? Colors.grey : Colors.brown.shade900,
                child: Text(
                  player.value['displayName']?.toString().characters.first ??
                      '?',
                  style: TextStyle(
                    color: isExecuted ? Colors.black38 : Colors.white,
                  ),
                ),
              ),
              if (isExecuted)
                const Positioned.fill(
                  child: Icon(Icons.close, color: Colors.red, size: 32),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            player.value['displayName'] ?? '？？？',
            style: TextStyle(
              color: isExecuted ? Colors.grey : Colors.white,
              fontSize: 12,
              decoration: isExecuted ? TextDecoration.lineThrough : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _switchPhase() async {
    bool nextIsNight = _isNightTime;
    bool nextIsVoting = _isVotingTime;
    int nextDay = _currentDay;

    // フェーズの切り替え
    if (!_isNightTime && !_isVotingTime) {
      // 話し合い → 投票
      nextIsVoting = true;
    } else if (!_isNightTime && _isVotingTime) {
      // 投票結果を処理
      await _processVoteResults();
      // 投票 → 夜
      nextIsNight = true;
      nextIsVoting = false;
    } else {
      // 夜 → 昼（話し合い）
      nextIsNight = false;
      nextIsVoting = false;
      nextDay = _currentDay + 1;
    }

    // Firestoreの状態を更新
    await _firestore.collection('rooms').doc(widget.roomId).update({
      'gameState': {
        'isNightTime': nextIsNight,
        'isVotingTime': nextIsVoting,
        'currentDay': nextDay,
        'remainingSeconds': _getPhaseSeconds(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
    });

    // システムメッセージを追加
    String phaseMessage;
    if (nextIsNight) {
      phaseMessage = '🌙 ${_currentDay}日目の夜になりました';
    } else if (nextIsVoting) {
      phaseMessage = '🗳️ 投票の時間です（${_getPhaseSeconds()}秒）';
    } else {
      phaseMessage = '☀️ ${nextDay}日目の昼になりました';
    }

    await _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .collection('messages')
        .add({
          'type': 'system',
          'text': phaseMessage,
          'timestamp': FieldValue.serverTimestamp(),
        });

    // 新しいタイマーを開始
    _startTimer();
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
      width: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // プレイヤー名とアバター
          Column(
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
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          // 役職表示（右側に重ねて表示）
          if (isCurrentUser && role != null)
            Positioned(
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.brown.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  role!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
