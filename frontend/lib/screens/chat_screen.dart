import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/arc_motif.dart';
import '../config.dart';
import '../models/conversation_summary.dart';

/// Lets a parent widget (the sidebar) trigger actions on the live
/// ChatScreen instance kept alive inside the IndexedStack, without needing
/// direct access to the private State class.
abstract class ChatScreenController {
  void startNewChat();
  void switchToConversation(String conversationId);
}

class ChatScreen extends StatefulWidget {
  final ValueChanged<String>? onConversationChanged;
  final List<ConversationSummary> conversations;
  final bool loadingConversations;
  final String? activeConversationId;
  const ChatScreen({
    super.key,
    this.onConversationChanged,
    this.conversations = const [],
    this.loadingConversations = false,
    this.activeConversationId,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver
    implements ChatScreenController {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = []; // newest first (list is reversed)
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  bool _isConnected = false;
  bool _waitingForAI = false;
  bool _showCrisisOverlay = false;
  String _crisisMessage = '';
  // True once the user has scrolled away from the latest message, so we
  // don't yank their view back down mid-read.
  bool _userScrolledAway = false;
  // The active conversation thread. Null until the server assigns one (via
  // the "session" message) or we load a previously-stored one from disk.
  String? _conversationId;
  // If a reply doesn't show up within this long, something's gone stale
  // (mobile browsers commonly freeze background-tab WebSocket connections
  // without actually closing them) - we reconnect rather than leaving the
  // UI hanging silently forever.
  Timer? _replyTimeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mobile browsers routinely suspend a backgrounded tab's WebSocket
    // handling to save battery - the connection can look "alive" client-side
    // while actually being frozen, so a reply sent while the tab was
    // backgrounded never gets processed until something wakes it up. Force
    // a clean reconnect whenever the app comes back to the foreground so
    // that doesn't require the person to notice and manually retry.
    if (state == AppLifecycleState.resumed) {
      _reconnectFresh();
    }
  }

  Future<void> _reconnectFresh() async {
    _replyTimeoutTimer?.cancel();
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        // This was the actual bug: without resetting this, _sendMessage's
        // guard against double-sends would permanently block every future
        // message after a timeout-triggered reconnect, since nothing ever
        // told it the original wait was over.
        _waitingForAI = false;
      });
    }
    await _connect();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // List is reversed, so "latest" sits at offset 0.
    _userScrolledAway = _scrollController.position.pixels > 50;
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _connect() async {
    final token = await ApiService.getToken();
    if (!mounted) return;
    if (token == null) {
      setState(() => _isConnected = false);
      return;
    }
    // Running as Windows desktop / Chrome, not an Android emulator, so we
    // talk to the backend on localhost directly. If we have a stored
    // conversation ID, ask the server to continue that thread; otherwise
    // it mints a fresh one and tells us via the "session" message.
    final storedConversationId = await ApiService.getConversationId();
    if (!mounted) return;
    final conversationParam = storedConversationId != null
        ? '&conversation=$storedConversationId'
        : '';
    final wsUrl =
        Uri.parse(AppConfig.wsUrl('/ws/chat?token=$token$conversationParam'));
    try {
      _channel = WebSocketChannel.connect(wsUrl);
      if (!mounted) return;
      setState(() => _isConnected = true);
      _channelSubscription = _channel!.stream.listen(
        _handleIncoming,
        onError: (_) {
          if (mounted) setState(() => _isConnected = false);
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _handleIncoming(dynamic data) {
    // The screen may have been disposed (e.g. user switched tabs) between
    // the WebSocket delivering data and this callback running - bail out
    // rather than calling setState on a dead widget.
    if (!mounted) return;

    final json = jsonDecode(data as String);
    final type = json['type'] as String;

    if (type == 'session') {
      final id = json['conversation_id'] as String?;
      if (id != null) {
        _conversationId = id;
        ApiService.setConversationId(id);
        widget.onConversationChanged?.call(id);
      }
      return;
    }

    if (type == 'history') {
      // One-time batch replay of persisted chat history on (re)connect.
      final rawMessages =
          (json['messages'] as List).cast<Map<String, dynamic>>();
      final replayed = rawMessages.map((m) {
        final sender = switch (m['type']) {
          'user_message' => MessageSender.user,
          'crisis_alert' => MessageSender.system,
          _ => MessageSender.ai,
        };
        return ChatMessage(
          m['text'] as String,
          sender,
          DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as int) * 1000),
        );
      }).toList();
      setState(() {
        // rawMessages arrives oldest-first; the display list is newest-first.
        _messages.insertAll(0, replayed.reversed);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
      return;
    }

    final text = json['text'] as String;
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int) * 1000);

    setState(() {
      if (type == 'crisis_alert') {
        _showCrisisOverlay = true;
        _crisisMessage = text;
        _messages.insert(0, ChatMessage(text, MessageSender.system, timestamp));
      } else if (type == 'ai_response') {
        _waitingForAI = false;
        _replyTimeoutTimer?.cancel();
        _messages.insert(0, ChatMessage(text, MessageSender.ai, timestamp));
      }
    });
    if (!_userScrolledAway)
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    // Also guard against sending a second message before the first reply
    // has arrived - avoids piling up requests if someone taps send
    // impatiently while the connection is slow or stale.
    if (text.isEmpty || _channel == null || _waitingForAI) return;
    final now = DateTime.now();
    final payload = jsonEncode({
      'type': 'user_message',
      'text': text,
      'timestamp': now.millisecondsSinceEpoch ~/ 1000,
    });
    _channel!.sink.add(payload);
    setState(() {
      _messages.insert(0, ChatMessage(text, MessageSender.user, now));
      _waitingForAI = true;
    });
    _controller.clear();
    if (!_userScrolledAway)
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());

    // If nothing comes back in a reasonable time, the connection is
    // probably stale (see didChangeAppLifecycleState) rather than the AI
    // actually taking that long - reconnect automatically instead of
    // leaving the "thinking" indicator spinning forever.
    _replyTimeoutTimer?.cancel();
    _replyTimeoutTimer = Timer(const Duration(seconds: 25), () {
      if (mounted && _waitingForAI) _handleStaleConnection();
    });
  }

  Future<void> _handleStaleConnection() async {
    await _reconnectFresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Connection needed a refresh - please send your message again")),
      );
    }
  }

  void _dismissCrisisOverlay() => setState(() => _showCrisisOverlay = false);

  void _showRecentChats() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _RecentChatsSheet(
        conversations: widget.conversations,
        loading: widget.loadingConversations,
        activeConversationId: widget.activeConversationId,
        onSelect: (id) {
          Navigator.pop(sheetContext);
          switchToConversation(id);
        },
        onNewChat: () {
          Navigator.pop(sheetContext);
          startNewChat();
        },
      ),
    );
  }

  @override
  Future<void> startNewChat() async {
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    await ApiService.clearConversationId();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _conversationId = null;
      _isConnected = false;
      _waitingForAI = false;
    });
    await _connect();
  }

  @override
  Future<void> switchToConversation(String conversationId) async {
    if (conversationId == _conversationId) return;
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    await ApiService.setConversationId(conversationId);
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _conversationId = conversationId;
      _isConnected = false;
      _waitingForAI = false;
    });
    await _connect();
  }

  @override
  void dispose() {
    // Cancel the subscription first so no late event can fire a callback
    // against this (about to be dead) widget, then close the socket.
    WidgetsBinding.instance.removeObserver(this);
    _replyTimeoutTimer?.cancel();
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your coach'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Recent chats',
            onPressed: _showRecentChats,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'New chat',
            onPressed: startNewChat,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? AppColors.tide : AppColors.line,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? _EmptyChatState(onPromptTap: (p) => _controller.text = p)
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.only(top: 12),
                        controller: _scrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) =>
                            _buildBubble(_messages[index]),
                      ),
              ),
              if (_waitingForAI) const _ThinkingIndicator(),
              _buildInputBar(),
            ],
          ),
          if (_showCrisisOverlay)
            CrisisOverlay(
                onDismiss: _dismissCrisisOverlay, message: _crisisMessage),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.sender == MessageSender.user;
    final isSystem = msg.sender == MessageSender.system;
    final alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final Color bg;
    final Color textColor;
    final Border? border;
    if (isSystem) {
      bg = AppColors.alertTint;
      textColor = AppColors.alert;
      border = Border.all(color: AppColors.alert.withOpacity(0.25));
    } else if (isUser) {
      bg = AppColors.tide;
      textColor = Colors.white;
      border = null;
    } else {
      bg = AppColors.surface;
      textColor = AppColors.charcoal;
      border = Border.all(color: AppColors.line);
    }

    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            topLeft: Radius.circular(4),
            bottomLeft: Radius.circular(18),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (isSystem)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_border, size: 13, color: AppColors.alert),
                  const SizedBox(width: 4),
                  Text(
                    'Crisis support',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.alert,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: bg, borderRadius: borderRadius, border: border),
            child: Text(
              msg.text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: textColor, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(
              DateFormat('HH:mm').format(msg.timestamp),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.line),
              ),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Type how you\'re feeling...',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.tide,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sendMessage,
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(Icons.arrow_upward_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile equivalent of the desktop sidebar's "RECENT CHATS" list - there's
/// no sidebar on narrow screens, so this is the only way to get back into a
/// previous conversation there.
class _RecentChatsSheet extends StatelessWidget {
  final List<ConversationSummary> conversations;
  final bool loading;
  final String? activeConversationId;
  final ValueChanged<String> onSelect;
  final VoidCallback onNewChat;

  const _RecentChatsSheet({
    required this.conversations,
    required this.loading,
    required this.activeConversationId,
    required this.onSelect,
    required this.onNewChat,
  });

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d').format(t);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Expanded(
                    child: Text('Recent chats',
                        style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: onNewChat,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('New chat'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: BreathingArc(size: 22)),
                  )
                : conversations.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Your chats will show up here.',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: conversations.length,
                        itemBuilder: (context, i) {
                          final c = conversations[i];
                          final selected = c.id == activeConversationId;
                          return Material(
                            color: selected
                                ? AppColors.tideLight
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => onSelect(c.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                child: Row(
                                  children: [
                                    Icon(Icons.forum_outlined,
                                        size: 18,
                                        color: selected
                                            ? AppColors.tide
                                            : AppColors.mutedText),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        c.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(_relativeTime(c.lastAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Shown instead of a blank screen when a conversation has no messages yet -
/// a warm greeting plus a few example prompts, so the first thing someone
/// sees isn't just empty white space.
class _EmptyChatState extends StatelessWidget {
  final ValueChanged<String> onPromptTap;
  const _EmptyChatState({required this.onPromptTap});

  static const _prompts = [
    "I've been feeling anxious lately",
    "I'm not sure how to say this, but...",
    "Can we just talk for a bit?",
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArcMotif(size: 64, strokeWidth: 6),
            const SizedBox(height: 20),
            Text(
              "I'm here whenever you're ready",
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing you say here needs a reason. Start wherever feels right.',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ..._prompts.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onPromptTap(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Text(p,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small "Alongside is thinking..." row shown between sending a message and
/// receiving the AI's reply - uses the arc motif rather than a generic spinner.
class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const BreathingArc(size: 18),
          const SizedBox(width: 10),
          Text('Thinking...', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Full-screen overlay shown when the backend's crisis keyword filter fires.
/// Deliberately modal (requires an explicit tap to dismiss) so it can't be
/// missed or swiped away accidentally.
class CrisisOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  final String message;

  const CrisisOverlay(
      {super.key, required this.onDismiss, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.harbor.withOpacity(0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.alertTint, shape: BoxShape.circle),
                child: Icon(Icons.favorite, color: AppColors.alert, size: 26),
              ),
              const SizedBox(height: 18),
              Text(
                "We're glad you told us",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.mutedText, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: onDismiss, child: const Text('I understand')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum MessageSender { user, ai, system }

class ChatMessage {
  final String text;
  final MessageSender sender;
  final DateTime timestamp;

  ChatMessage(this.text, this.sender, this.timestamp);
}
