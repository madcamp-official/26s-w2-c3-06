import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/room_summary.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../room/room_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _codeController = TextEditingController();
  List<RoomSummary> _publicRooms = List.of(mockPublicRooms);
  bool _isRefreshing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _publicRooms = List.of(mockPublicRooms);
      _isRefreshing = false;
    });
  }

  void _openRoom({required String code, required bool isHost}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoomScreen(roomCode: code, isHost: isHost)),
    );
  }

  void _handleCreateRoom() {
    _openRoom(code: '8421', isHost: true);
  }

  void _handleJoinByCode() {
    final code = _codeController.text.trim();
    if (code.length != 4) return;
    _openRoom(code: code, isHost: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('로비')),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('공개방 목록', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: _isRefreshing ? null : _handleRefresh,
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _publicRooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final room = _publicRooms[index];
                    return _PublicRoomTile(
                      room: room,
                      onTap: () => _openRoom(code: room.code, isHost: false),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              AppButton(label: '방 만들기', icon: Icons.add, onPressed: _handleCreateRoom),
              const SizedBox(height: 12),
              SectionCard(
                title: '코드로 입장',
                child: Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _codeController,
                        hintText: '4자리 코드',
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppButton(label: '입장', fullWidth: false, onPressed: _handleJoinByCode),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicRoomTile extends StatelessWidget {
  final RoomSummary room;
  final VoidCallback onTap;

  const _PublicRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(room.title),
        subtitle: Text('방장 ${room.hostNickname} · ${room.playerCount}/${room.maxPlayers}명'),
        trailing: FilledButton(onPressed: onTap, child: const Text('입장')),
      ),
    );
  }
}
