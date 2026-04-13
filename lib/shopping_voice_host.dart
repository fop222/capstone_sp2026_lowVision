typedef AsyncVoiceCallback = Future<void> Function();

/// Registered by [AisleScannerVlmScreen] (full set) or [GroceryListDetailScreen]
/// (add-item only when not inside a VLM trip).
class ShoppingVoiceHost {
  ShoppingVoiceHost({
    this.onEndShopping,
    this.onScanAisleSign,
    this.onScanShelf,
    this.onOpenShoppingList,
    this.onOpenAddItem,
  });

  final AsyncVoiceCallback? onEndShopping;
  final AsyncVoiceCallback? onScanAisleSign;
  final AsyncVoiceCallback? onScanShelf;
  final AsyncVoiceCallback? onOpenShoppingList;
  final AsyncVoiceCallback? onOpenAddItem;

  static ShoppingVoiceHost? current;

  void mount() => current = this;

  void unmount() {
    if (identical(current, this)) current = null;
  }
}

/// True while [AisleScannerVlmScreen] is mounted so nested screens (e.g. add
/// items) do not replace the active voice host.
class VlmShoppingSession {
  VlmShoppingSession._();

  static bool active = false;
}
