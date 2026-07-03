import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'chat_screen.dart';
import 'mood_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';
import 'today_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/arc_motif.dart';
import '../widgets/sign_out_dialog.dart';
import '../widgets/profile_sheet.dart';

/// Below this width we use the floating pill bottom nav (phone pattern);
/// at or above it we switch to a sidebar (desktop/tablet pattern). One
/// codebase, native-feeling layout on either surface.
const double _desktopBreakpoint = 900;

// Tab indices, referenced from a few places below.
const _tabToday = 0;
const _tabChat = 1;
const _tabMood = 2;
const _tabVault = 3;
const _tabSettings = 4;

typedef _NavItem = ({IconData icon, IconData activeIcon, String label});

class _Conversation {
  final String id;
  final String title;
  final DateTime lastAt;
  _Conversation(this.id, this.title, this.lastAt);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = _tabToday;
  bool _sidebarCollapsed = false;
  final _chatKey = GlobalKey<State<ChatScreen>>();
  late final List<Widget> _screens;

  double? _latestMoodScore;
  DateTime? _latestMoodTime;
  bool _loadingMood = true;
  int _streak = 0;

  String? _activeConversationId;
  List<_Conversation> _conversations = [];
  bool _loadingConversations = true;

  static const List<_NavItem> _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Today'),
    (icon: Icons.forum_outlined, activeIcon: Icons.forum, label: 'Chat'),
    (icon: Icons.insights_outlined, activeIcon: Icons.insights, label: 'Mood'),
    (icon: Icons.lock_outline, activeIcon: Icons.lock, label: 'Vault'),
    (icon: Icons.tune, activeIcon: Icons.tune, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      TodayScreen(
        latestMoodScore: _latestMoodScore,
        latestMoodTime: _latestMoodTime,
        loadingMood: _loadingMood,
        streak: _streak,
        onMoodLogged: _refreshMoodSnapshot,
        onNavigate: (i) => setState(() => _currentIndex = i),
      ),
      ChatScreen(key: _chatKey, onConversationChanged: _onConversationChanged),
      const MoodScreen(),
      const VaultScreen(),
      const SettingsScreen(),
    ];
    _refreshMoodSnapshot();
    _refreshStreak();
    _refreshConversations();
  }

  void _onConversationChanged(String id) {
    setState(() => _activeConversationId = id);
    _refreshConversations();
  }

  Future<void> _refreshStreak() async {
    try {
      final data = await ApiService.get('/mood/streak') as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _streak = (data?['streak'] as num?)?.toInt() ?? 0;
        _rebuildTodayScreen();
      });
    } catch (_) {
      // leave streak at its last known value rather than erroring the UI
    }
  }

  Future<void> _refreshMoodSnapshot() async {
    try {
      final data = await ApiService.get('/mood/history?days=7') as List<dynamic>?;
      if (!mounted) return;
      if (data != null && data.isNotEmpty) {
        setState(() {
          _latestMoodScore = (data.first['score'] as num).toDouble();
          _latestMoodTime = DateTime.tryParse(data.first['time'] as String)?.toLocal();
          _loadingMood = false;
          _rebuildTodayScreen();
        });
      } else {
        setState(() {
          _latestMoodScore = null;
          _loadingMood = false;
          _rebuildTodayScreen();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMood = false);
    }
    // A logged check-in can extend the streak, so refresh both together.
    _refreshStreak();
  }

  // TodayScreen takes mood data as constructor params rather than fetching
  // its own copy, so the shell stays the single source of truth (it's also
  // what feeds the sidebar's mood snapshot). Rebuild its slot in _screens
  // whenever that data changes.
  void _rebuildTodayScreen() {
    _screens[_tabToday] = TodayScreen(
      latestMoodScore: _latestMoodScore,
      latestMoodTime: _latestMoodTime,
      loadingMood: _loadingMood,
      streak: _streak,
      onMoodLogged: _refreshMoodSnapshot,
      onNavigate: (i) => setState(() => _currentIndex = i),
    );
  }

  Future<void> _refreshConversations() async {
    try {
      final data = await ApiService.get('/chat/conversations') as List<dynamic>?;
      if (!mounted) return;
      setState(() {
        _conversations = (data ?? [])
            .map((c) => _Conversation(
                  c['id'] as String,
                  (c['title'] as String).trim().isEmpty ? 'New chat' : c['title'] as String,
                  DateTime.parse(c['last_at'] as String).toLocal(),
                ))
            .toList();
        _loadingConversations = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingConversations = false);
    }
  }

  void _onNavSelect(int index) {
    setState(() => _currentIndex = index);
    _refreshMoodSnapshot();
    if (index == _tabChat) _refreshConversations();
  }

  void _handleNewChat() {
    setState(() => _currentIndex = _tabChat);
    (_chatKey.currentState as ChatScreenController?)?.startNewChat();
  }

  void _handleSelectConversation(String id) {
    setState(() {
      _currentIndex = _tabChat;
      _activeConversationId = id;
    });
    (_chatKey.currentState as ChatScreenController?)?.switchToConversation(id);
  }

  Future<void> _handleSignOut() async {
    final confirmed = await confirmSignOut(context);
    if (confirmed && mounted) {
      context.read<AuthService>().logout();
    }
  }

  void _collapseSidebarIfExpanded() {
    if (!_sidebarCollapsed) setState(() => _sidebarCollapsed = true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(
                  collapsed: _sidebarCollapsed,
                  onToggleCollapse: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  currentIndex: _currentIndex,
                  items: _items,
                  latestMoodScore: _latestMoodScore,
                  latestMoodTime: _latestMoodTime,
                  loadingMood: _loadingMood,
                  activeConversationId: _activeConversationId,
                  conversations: _conversations,
                  loadingConversations: _loadingConversations,
                  onSelect: _onNavSelect,
                  onNewChat: _handleNewChat,
                  onSelectConversation: _handleSelectConversation,
                  onSignOut: _handleSignOut,
                ),
                Expanded(
                  // Tapping into the main content area tucks the sidebar
                  // away if it's expanded - a Listener rather than a
                  // GestureDetector.onTap so it never competes with or
                  // blocks taps on buttons/fields inside the content itself.
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _collapseSidebarIfExpanded(),
                    child: IndexedStack(index: _currentIndex, children: _screens),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.harbor,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.harbor.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_items.length, (i) {
                  final selected = i == _currentIndex;
                  final item = _items[i];
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _onNavSelect(i),
                      // Long-press the Chat tab as a quick "New chat" shortcut
                      // on mobile, where there's no sidebar button for it.
                      onLongPress: i == _tabChat ? _handleNewChat : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white.withOpacity(0.14) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              color: selected ? AppColors.ember : Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(height: 3),
                            // maxLines/overflow/softWrap here are the actual
                            // fix - without them "Settings" wraps to a second
                            // line at 5-item widths and blows out the fixed
                            // container height (the overflow you saw).
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Desktop/tablet sidebar: brand mark, a prominent New chat action, nav,
/// recent conversations, a live glance at the latest mood check-in, and
/// account controls. Collapsible down to an icon-only rail, and also
/// auto-collapses when the person taps into the main content area.
class _Sidebar extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final int currentIndex;
  final List<_NavItem> items;
  final double? latestMoodScore;
  final DateTime? latestMoodTime;
  final bool loadingMood;
  final String? activeConversationId;
  final List<_Conversation> conversations;
  final bool loadingConversations;
  final ValueChanged<int> onSelect;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelectConversation;
  final VoidCallback onSignOut;

  const _Sidebar({
    required this.collapsed,
    required this.onToggleCollapse,
    required this.currentIndex,
    required this.items,
    required this.latestMoodScore,
    required this.latestMoodTime,
    required this.loadingMood,
    required this.activeConversationId,
    required this.conversations,
    required this.loadingConversations,
    required this.onSelect,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onSignOut,
  });

  String _moodTimeLabel() {
    if (latestMoodTime == null) return '';
    final now = DateTime.now();
    final sameDay = now.year == latestMoodTime!.year &&
        now.month == latestMoodTime!.month &&
        now.day == latestMoodTime!.day;
    return sameDay
        ? 'Today, ${DateFormat('HH:mm').format(latestMoodTime!)}'
        : DateFormat('MMM d').format(latestMoodTime!);
  }

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
    final auth = context.watch<AuthService>();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: collapsed ? 76 : 264,
      color: AppColors.harbor,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 18, vertical: 24),
      child: ClipRect(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
            children: [
              if (!collapsed)
                Expanded(
                  child: Row(
                    children: [
                      const ArcMotif(size: 30, strokeWidth: 4),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Alongside',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 19),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const ArcMotif(size: 26, strokeWidth: 4),
              if (!collapsed)
                IconButton(
                  onPressed: onToggleCollapse,
                  tooltip: 'Collapse sidebar',
                  icon: const Icon(Icons.chevron_left, color: Colors.white54, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          if (collapsed) ...[
            const SizedBox(height: 12),
            Center(
              child: IconButton(
                onPressed: onToggleCollapse,
                tooltip: 'Expand sidebar',
                icon: const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // New chat
          Material(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onNewChat,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14, vertical: 13),
                child: collapsed
                    ? const Icon(Icons.edit_outlined, color: Colors.white, size: 18)
                    : const Row(
                        children: [
                          Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                          SizedBox(width: 10),
                          Text('New chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Nav
          ...List.generate(items.length, (i) {
            final selected = i == currentIndex;
            final item = items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: selected ? Colors.white.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 12),
                    child: collapsed
                        ? Icon(
                            selected ? item.activeIcon : item.icon,
                            size: 20,
                            color: selected ? AppColors.ember : Colors.white70,
                          )
                        : Row(
                            children: [
                              Icon(
                                selected ? item.activeIcon : item.icon,
                                size: 19,
                                color: selected ? AppColors.ember : Colors.white70,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                item.label,
                                style: TextStyle(
                                  color: selected ? Colors.white : Colors.white70,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            );
          }),
          if (!collapsed) ...[
            const SizedBox(height: 20),
            Text(
              'RECENT CHATS',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: loadingConversations
                  ? const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: BreathingArc(size: 16),
                    )
                  : conversations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Your chats will show up here.',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: conversations.length,
                          itemBuilder: (context, i) {
                            final c = conversations[i];
                            final selected = c.id == activeConversationId;
                            return Material(
                              color: selected ? Colors.white.withOpacity(0.1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => onSelectConversation(c.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: selected ? Colors.white : Colors.white70,
                                            fontSize: 12.5,
                                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _relativeTime(c.lastAt),
                                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ] else
            const Spacer(),
          const SizedBox(height: 14),
          // Live mood snapshot
          if (!collapsed)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: loadingMood
                  ? const SizedBox(
                      height: 20,
                      child: Center(child: BreathingArc(size: 18)),
                    )
                  : latestMoodScore == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No check-in yet',
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "See how you're doing",
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Text(
                              latestMoodScore!.toStringAsFixed(0),
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                            ),
                            Text('/10', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Latest check-in',
                                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    _moodTimeLabel(),
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showProfileSheet(context, onGoToSettings: () => onSelect(_tabSettings)),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.tide,
                  child: Text(
                    (auth.email ?? '?').isNotEmpty ? auth.email![0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    auth.email ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                IconButton(
                  onPressed: onSignOut,
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout, color: Colors.white54, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ],
      ),
      ),
    );
  }
}
