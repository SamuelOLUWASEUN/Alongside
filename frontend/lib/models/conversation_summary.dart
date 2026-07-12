class ConversationSummary {
  final String id;
  final String title;
  final DateTime lastAt;
  final bool pinned;
  ConversationSummary(this.id, this.title, this.lastAt, {this.pinned = false});
}
