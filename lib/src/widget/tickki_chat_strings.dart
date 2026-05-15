/// All user-facing copy in the drop-in chat widget. Override for
/// i18n by passing a populated instance to `TickkiChatWidget.show`.
///
/// Defaults are English. Every field has a sensible English default
/// so partial localization is fine — pass only the strings you've
/// translated and the rest fall back.
class TickkiChatStrings {
  const TickkiChatStrings({
    this.title = 'Chat with us',
    this.onlineLabel = 'Online',
    this.offlineLabel = "We'll get back to you",
    this.inputPlaceholder = 'Type a message…',
    this.sendButton = 'Send',
    this.attachButton = 'Attach file',
    this.preChatTitle = 'Before we start',
    this.preChatSubtitle = 'Tell us a bit about you so we can help.',
    this.preChatNameLabel = 'Name',
    this.preChatEmailLabel = 'Email',
    this.preChatSubmit = 'Start chat',
    this.errorGeneric = 'Something went wrong. Please try again.',
    this.errorRateLimited =
        'Too many messages too fast — slow down a bit and retry.',
    this.errorNoConnection =
        "Can't reach the chat server. Check your connection.",
    this.emptyHistory = 'Start the conversation. An agent will reply soon.',
    this.typingIndicator = 'Agent is typing…',
  });

  final String title;
  final String onlineLabel;
  final String offlineLabel;
  final String inputPlaceholder;
  final String sendButton;
  final String attachButton;
  final String preChatTitle;
  final String preChatSubtitle;
  final String preChatNameLabel;
  final String preChatEmailLabel;
  final String preChatSubmit;
  final String errorGeneric;
  final String errorRateLimited;
  final String errorNoConnection;
  final String emptyHistory;
  final String typingIndicator;
}
