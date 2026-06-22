import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../models/chat_message.dart';
import '../services/ai_cmo_engine.dart';
import '../services/ai_gateway_service.dart';

class AiCmoScreen extends StatefulWidget {
  const AiCmoScreen({Key? key}) : super(key: key);

  @override
  State<AiCmoScreen> createState() => _AiCmoScreenState();
}

class _AiCmoScreenState extends State<AiCmoScreen> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  
  bool _isTyping = false;
  int _defaultResponseIndex = 0;
  bool _isLoading = true;

  // Daily checklist tasks state from Rule Engine
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    // Add initial bot messages
    _messages.add(ChatMessage(
      text: 'Chào bạn! 👋 Tôi là **AI CMO** — trợ lý ảo tăng trưởng của bạn. Tôi đã phân tích số liệu mới nhất.',
      isUser: false,
      time: DateTime.now().subtract(const Duration(minutes: 2)),
    ));
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      final suggestions = await AiCmoEngine.instance.runRuleEngine('default_user');
      
      // Map Rule Engine outputs to UI tasks
      final List<Map<String, dynamic>> mappedTasks = suggestions.map((s) {
        String title = 'Gợi ý mới';
        Color color = Colors.purple;
        String emoji = '💡';

        if (s['rule_id'] == 'R1_underperform') {
          title = 'Tối ưu kênh ${s['data']['channel']}';
          color = Colors.blue;
          emoji = '📊';
        } else if (s['rule_id'] == 'R4_fomo_alert') {
          title = 'Cảnh báo FOMO ${s['data']['asset']}';
          color = Colors.orange;
          emoji = '⚠️';
        } else if (s['rule_id'] == 'R5_data_reminder') {
          title = 'Cập nhật dữ liệu';
          color = Colors.amber;
          emoji = '⏰';
        } else if (s['rule_id'] == 'R7_competitor_plan') {
          title = 'Kế hoạch đối thủ';
          color = Colors.redAccent;
          emoji = '⚔️';
        }

        return {
          'title': title,
          'desc': s['content'] ?? 'Kiểm tra chi tiết trong hội thoại.',
          'done': false,
          'emoji': emoji,
          'color': color,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _tasks = mappedTasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('AiCmoScreen Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSendMessage(String text) {
    if (text.trim().isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        time: DateTime.now(),
      ));
      _isTyping = true;
    });
    _inputController.clear();
    _scrollToBottom();

    // Determine task type based on content (Simulating Backend Logic)
    String taskType = 'chat';
    if (text.toLowerCase().contains('plan') || 
        text.toLowerCase().contains('kế hoạch') || 
        text.toLowerCase().contains('marketing')) {
      taskType = 'marketing_plan';
    }

    // Call Unified AI Gateway
    AiGatewayService.instance.processAiRequest(
      prompt: text,
      taskType: taskType,
    ).then((response) {
      if (!mounted) return;

      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          text: response,
          isUser: false,
          time: DateTime.now(),
        ));
      });
      _scrollToBottom();
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          text: 'Lỗi Gateway: $e',
          isUser: false,
          time: DateTime.now(),
        ));
      });
      _scrollToBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 1. Chat Header
          Container(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 40, bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgSecondary,
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.brandPurple.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Text('🤖', style: TextStyle(fontSize: 20)),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppTheme.colorSafe,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.bgSecondary, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'AI CMO',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '● Online — Sẵn sàng tư vấn',
                      style: TextStyle(fontSize: 10, color: AppTheme.colorSafe, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.brandPurple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'VIRTUAL EXPERT',
                    style: TextStyle(
                      color: AppTheme.brandPurple,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Chat messages & recommendations scroll area
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              physics: const BouncingScrollPhysics(),
              children: [
                // Daily Recommendations section
                const Text(
                  '📋 Gợi ý hôm nay',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                GlassCard(
                  child: Column(
                    children: _tasks.map((task) {
                      final int idx = _tasks.indexOf(task);
                      return Padding(
                        padding: EdgeInsets.only(bottom: idx == _tasks.length - 1 ? 0 : 10.0),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: task['color'].withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(task['emoji'], style: const TextStyle(fontSize: 16)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      text: task['title'],
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                        decoration: task['done'] ? TextDecoration.lineThrough : null,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: ' — ${task['desc']}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.normal,
                                            color: AppTheme.textSecondary,
                                            decoration: task['done'] ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Checkbox button
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  task['done'] = !task['done'];
                                });
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: task['done'] ? AppTheme.colorSafe : Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: task['done'] ? AppTheme.colorSafe : Colors.white.withOpacity(0.12),
                                    width: 1.0,
                                  ),
                                ),
                                child: task['done']
                                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  '💬 Chat với AI CMO',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),

                // Chat bubble list
                ..._messages.map((msg) => _buildChatBubble(msg)),

                // Typing indicator
                if (_isTyping) _buildTypingBubble(),
              ],
            ),
          ),

          // 3. Suggestion chips horizontally scrollable
          Container(
            height: 38,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              children: ['💡 Gợi ý content', '📊 Phân tích đối thủ', '🎯 Tối ưu ads', '📈 Báo cáo tuần'].map((text) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    backgroundColor: AppTheme.glassBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: AppTheme.glassBorder, width: 1.0),
                    ),
                    label: Text(
                      text,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _handleSendMessage(text),
                  ),
                );
              }).toList(),
            ),
          ),

          // 4. Message Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgSecondary,
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Hỏi AI CMO bất cứ điều gì...',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 13.5),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (text) => _handleSendMessage(text),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _handleSendMessage(_inputController.text),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final bool isUser = message.isUser;
    final timeStr = '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}';

    // Simple rich text formatting parser:
    // **text** -> bold
    // \n -> newline
    List<TextSpan> parseText(String rawText) {
      final List<TextSpan> spans = [];
      final RegExp regExp = RegExp(r'\*\*(.*?)\*\*');
      int lastIndex = 0;

      for (final Match match in regExp.allMatches(rawText)) {
        if (match.start > lastIndex) {
          spans.add(TextSpan(text: rawText.substring(lastIndex, match.start)));
        }
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ));
        lastIndex = match.end;
      }
      if (lastIndex < rawText.length) {
        spans.add(TextSpan(text: rawText.substring(lastIndex)));
      }
      return spans;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brandPurple.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Text('🤖', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.brandCyan.withOpacity(0.15) : AppTheme.glassBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: isUser ? const Radius.circular(14) : Radius.zero,
                  bottomRight: isUser ? Radius.zero : const Radius.circular(14),
                ),
                border: Border.all(
                  color: isUser ? AppTheme.brandCyan.withOpacity(0.24) : AppTheme.glassBorder,
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: parseText(message.text),
                      style: TextStyle(
                        fontSize: 13,
                        color: isUser ? AppTheme.brandCyan : AppTheme.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      timeStr,
                      style: const TextStyle(fontSize: 8.5, color: AppTheme.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brandPurple.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Text('🤖', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.glassBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(
                color: AppTheme.glassBorder,
                width: 1.0,
              ),
            ),
            child: const SizedBox(
              width: 30,
              height: 12,
              child: _BouncingDots(),
            ),
          ),
        ],
      ),
    );
  }
}

// Bouncing dots widget for typing indicator
class _BouncingDots extends StatefulWidget {
  const _BouncingDots({Key? key}) : super(key: key);

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double offset = index * 0.2;
            final double progress = (_controller.value - offset) % 1.0;
            final double y = -sin(progress * pi) * 4.0;
            return Transform.translate(
              offset: Offset(0, y),
              child: Container(
                width: 4.5,
                height: 4.5,
                decoration: const BoxDecoration(
                  color: AppTheme.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
