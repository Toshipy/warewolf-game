import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:werewolf_game/screens/room_service.dart';
import 'chat_room_screen.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  final RoomService _roomService = RoomService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _rooms = [];

  // 人数に応じた役職を返す関数
  List<String> _getRolesByPlayerCount(int count) {
    switch (count) {
      case 4:
        return ['市民', '市民', '狩人', '人狼'];
      case 5:
        return ['市民', '市民', '市民', '狩人', '人狼'];
      case 6:
        return ['市民', '市民', '占い師', '狩人', '人狼', '人狼'];
      case 7:
        return ['市民', '市民', '市民', '占い師', '狩人', '人狼', '人狼'];
      case 8:
        return ['市民', '市民', '市民', '霊能者', '占い師', '狩人', '人狼', '人狼'];
      case 9:
        return ['市民', '市民', '市民', '霊能者', '占い師', '狩人', '人狼', '人狼', '狂人'];
      default:
        return ['市民', '市民', '狩人', '人狼'];
    }
  }

  // 役職リストを文字列に変換する関数
  String _getRolesDescription(List<String> roles) {
    Map<String, int> roleCounts = {};
    for (var role in roles) {
      roleCounts[role] = (roleCounts[role] ?? 0) + 1;
    }

    return roleCounts.entries
        .map((entry) {
          return '${entry.key}×${entry.value}';
        })
        .join('、');
  }

  void _showCreateRoomDialog(BuildContext context) {
    int maxPlayers = 4;
    List<String> roles = _getRolesByPlayerCount(4);
    final titleController = TextEditingController(text: '');
    bool isCreating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('部屋を作る'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: '部屋のタイトル',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isCreating,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: '最大人数',
                        border: OutlineInputBorder(),
                      ),
                      value: maxPlayers,
                      items:
                          [4, 5, 6, 7, 8, 9]
                              .map(
                                (number) => DropdownMenuItem<int>(
                                  value: number,
                                  child: Text(number.toString() + '人'),
                                ),
                              )
                              .toList(),
                      onChanged:
                          isCreating
                              ? null
                              : (value) {
                                if (value != null) {
                                  setState(() {
                                    maxPlayers = value;
                                    roles = _getRolesByPlayerCount(value);
                                  });
                                }
                              },
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.brown.shade100,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '役職構成：${_getRolesDescription(roles)}',
                        style: TextStyle(
                          color: Colors.brown.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isCreating
                          ? null
                          : () {
                            Navigator.of(context).pop();
                          },
                  child: Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed:
                      isCreating
                          ? null
                          : () async {
                            setState(() {
                              isCreating = true;
                            });
                            try {
                              DocumentReference roomRef = await _roomService
                                  .createRoom(
                                    title: titleController.text.trim(),
                                    maxPlayers: maxPlayers,
                                    roles: roles,
                                  );

                              Navigator.of(context).pop();

                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ChatRoomScreen(
                                          roomId: roomRef.id,
                                          roomTitle:
                                              titleController.text.trim(),
                                        ),
                                  ),
                                );
                              }
                            } catch (e, stackTrace) {
                              print('Error: $e');
                              print('StackTrace: $stackTrace');
                              if (context.mounted) {
                                setState(() {
                                  isCreating = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('エラー: ${e.toString()}'),
                                  ),
                                );
                              }
                            }
                          },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCreating) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                      ],
                      Text(isCreating ? '作成中...' : '作成する'),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _testFirebaseConnection();
    _loadRooms();
  }

  Future<void> _testFirebaseConnection() async {
    await _roomService.testConnection();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rooms = await _roomService.getRooms();
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'ルーム情報の取得に失敗しました: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown.shade900,
        leading: IconButton(
          icon: Icon(Icons.home, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'ルーム一覧',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          // image: DecorationImage(
          //   image: AssetImage('assets/images/background_pattern.jpg'),
          //   fit: BoxFit.cover,
          // ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(padding: const EdgeInsets.symmetric(vertical: 20)),

              // 機能ボタンエリア
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        _showCreateRoomDialog(context);
                      },
                      child: Container(
                        width: 250,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade900,
                              Colors.blue.shade900,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.amber.shade900,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '部屋を作る',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 1),
                                  color: Colors.black,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 更新ボタン
                    GestureDetector(
                      onTap: _isLoading ? null : _loadRooms,
                      child: Container(
                        width: 60,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade800,
                              Colors.green.shade600,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.amber.shade900,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child:
                              _isLoading
                                  ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(
                                    Icons.refresh,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ルーム一覧
              Expanded(
                child: ListView.builder(
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    return _buildRoomCard(_rooms[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.brown.shade900.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade900, width: 2),
      ),
      child: Column(
        children: [
          // 部屋のタイトル
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.amber.shade900, width: 1),
              ),
            ),
            child: Text(
              room['title'] ?? '誰でも歓迎',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // 役職ボタン一覧
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 5,
              runSpacing: 5,
              children:
                  room['roles'].map<Widget>((role) {
                    Color roleColor;
                    if (role == '人狼') {
                      roleColor = Colors.red;
                    } else if (role == '純愛者') {
                      roleColor = Colors.blue;
                    } else {
                      roleColor = Colors.orange;
                    }

                    return Container(
                      width: 70,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.brown.shade800,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.brown.shade600,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          role,
                          style: TextStyle(
                            color: roleColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),

          // 入室ボタン
          GestureDetector(
            onTap: () async {
              try {
                await _roomService.joinRoom(room['id']);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => ChatRoomScreen(
                            roomId: room['id'],
                            roomTitle: room['title'],
                          ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Container(
              width: 120,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade800, Colors.teal.shade600],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.shade700, width: 1),
              ),
              child: Center(
                child: Text(
                  '入室 ${room['currentPlayers']}/${room['maxPlayers']}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
