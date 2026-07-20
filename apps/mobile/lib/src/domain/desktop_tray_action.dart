enum DesktopTrayTransportAction { previous, togglePlayPause, next }

const defaultDesktopTrayTransportActions = <DesktopTrayTransportAction>{
  DesktopTrayTransportAction.previous,
  DesktopTrayTransportAction.togglePlayPause,
  DesktopTrayTransportAction.next,
};

Set<DesktopTrayTransportAction> desktopTrayTransportActionsFromStorage(
  List<String>? storedActions,
) {
  if (storedActions == null) {
    return Set<DesktopTrayTransportAction>.of(
      defaultDesktopTrayTransportActions,
    );
  }

  final storedNames = storedActions.map((value) => value.trim()).toSet();
  return <DesktopTrayTransportAction>{
    for (final action in DesktopTrayTransportAction.values)
      if (storedNames.contains(action.name)) action,
  };
}

List<String> desktopTrayTransportActionsToStorage(
  Iterable<DesktopTrayTransportAction> actions,
) {
  final selectedActions = actions.toSet();
  return <String>[
    for (final action in DesktopTrayTransportAction.values)
      if (selectedActions.contains(action)) action.name,
  ];
}
