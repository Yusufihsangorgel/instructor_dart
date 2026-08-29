/// Role of a chat message.
enum MessageRole { system, user, assistant }

/// A single chat message sent to the model.
final class Message {
  const Message(this.role, this.content);

  /// A message with [MessageRole.system].
  const Message.system(String content) : this(MessageRole.system, content);

  /// A message with [MessageRole.user].
  const Message.user(String content) : this(MessageRole.user, content);

  /// A message with [MessageRole.assistant].
  const Message.assistant(String content)
      : this(MessageRole.assistant, content);

  final MessageRole role;
  final String content;

  @override
  bool operator ==(Object other) =>
      other is Message && role == other.role && content == other.content;

  @override
  int get hashCode => Object.hash(role, content);

  @override
  String toString() => '${role.name}: $content';
}
