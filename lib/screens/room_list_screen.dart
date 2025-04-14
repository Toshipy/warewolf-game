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

  @override
  void initState() {
    super.initState();
    _testFirebaseConnection();
  }

  Future<void> _testFirebaseConnection() async {
    await _roomService.testConnection();
  }

  // ルームリストのデータ
  final List<Map<String, dynamic>> _rooms = [
    {
      'ruleMatching': 78,
      'playerCount': '6/13',
      'likeCount': 1386,
      'playerRecruitment': '誰でも歓迎',
      'languageLevel': '一般',
      'roles': ['市民', '市民', '占い師', '霊能者', '狩人', '人狼', '人狼', '狂信者'],
    },
    {
      'ruleMatching': 73,
      'playerCount': '3/13',
      'likeCount': 2248,
      'playerRecruitment': '誰でも歓迎',
      'languageLevel': '目上相手',
      'roles': [
        '市民',
        '市民',
        '占い師',
        '霊能者',
        '狩人',
        '猫又',
        'パン屋',
        '呪われし者',
        '人狼',
        '人狼',
        '狂信者',
        '黒猫',
        '純愛者',
      ],
    },
  ];

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
                    Container(
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
                        child: Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 24,
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
          Container(
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
                '入室 ${room['playerCount']}',
                style: TextStyle(
                  color: Colors.white,
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

void _showCreateRoomDialog(BuildContext context) {
  int maxPlayers = 9;
  List<String> roles = ['市民', '市民', '占い師', '霊能者', '狩人', '人狼', '人狼', '狂信者'];
  final titleController = TextEditingController(text: '新しい部屋');
  final _roomService = RoomService();
  bool isCreating = false;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StatefulBuilder(
        // StatefulBuilderを追加
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
                    enabled: !isCreating, // 作成中は入力を無効化
                  ),
                  const SizedBox(height: 20),

                  // 最大人数選択
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: '最大人数',
                      border: OutlineInputBorder(),
                    ),
                    value: maxPlayers,
                    items:
                        [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
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
                              // 作成中は変更を無効化
                              if (value != null) {
                                maxPlayers = value;
                              }
                            },
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
                          // 作成中は無効化
                          Navigator.of(context).pop();
                        },
                child: Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed:
                    isCreating
                        ? null // 作成中は無効化
                        : () async {
                          setState(() {
                            isCreating = true; // 作成開始
                          });
                          try {
                            // Loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('部屋を作成中...')),
                            );

                            // Firestoreに部屋を作成
                            DocumentReference roomRef = await _roomService
                                .createRoom(
                                  title: titleController.text.trim(),
                                  maxPlayers: maxPlayers,
                                  roles: roles,
                                );

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('部屋を作成しました')),
                              );

                              // チャットルーム画面に遷移
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
                            }
                          } catch (e, stackTrace) {
                            print('Error: $e');
                            print('StackTrace: $stackTrace');
                            if (context.mounted) {
                              setState(() {
                                isCreating = false; // エラー時は作成状態を解除
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('エラー: ${e.toString()}')),
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
