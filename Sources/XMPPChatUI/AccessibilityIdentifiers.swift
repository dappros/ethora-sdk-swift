import Foundation

/// Stable accessibility identifiers exposed by ``XMPPChatUI`` views for UI
/// tests and Maestro flows.
///
/// On iOS, `.accessibilityIdentifier(...)` is the equivalent of Compose's
/// `Modifier.testTag(...)` — purely metadata, not user-visible, but consumed
/// by XCUITest, ViewInspector, and Maestro (which resolves an `id:` selector
/// against the accessibility identifier on iOS targets).
///
/// String values intentionally match Android's ``ChatInputTestTags`` /
/// ``RoomListViewTestTags`` / ``MessageBubbleTestTags`` constants so a
/// single Maestro YAML flow exercises the same intent on either platform.
/// Do not change a value without updating both consumers.
public enum ChatInputAccessibilityID {
    public static let inputField = "chat_input"
    public static let sendButton = "chat_send_button"
    public static let attachButton = "chat_attach_button"
}

public enum MessageBubbleAccessibilityID {
    public static let mediaContent = "chat_message_image"
}

public enum RoomListAccessibilityID {
    public static let roomsList = "rooms_list"
    public static let roomRow = "room_row"
    public static let searchInput = "rooms_search_input"
    public static let createRoomButton = "create_room_button"
}
