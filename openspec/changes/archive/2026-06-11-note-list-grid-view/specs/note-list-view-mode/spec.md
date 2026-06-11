## ADDED Requirements

### Requirement: View mode toggle button
The system SHALL display a view mode toggle button at the leading position of the note list panel AppBar. The button icon SHALL reflect the current view mode (list icon for list view, grid icon for waterfall view). Tapping the button SHALL show a popup menu with all available view mode options.

#### Scenario: Toggle button shows current view mode icon
- **WHEN** the current view mode is list view
- **THEN** the leading button displays a list view icon (`Icons.view_list`)

#### Scenario: Toggle button shows grid icon in waterfall mode
- **WHEN** the current view mode is waterfall view
- **THEN** the leading button displays a grid icon (`Icons.grid_view`)

#### Scenario: Tapping toggle opens popup menu
- **WHEN** user taps the view mode toggle button
- **THEN** a popup menu appears with two options: "列表视图" and "瀑布流视图"
- **AND** the current active view mode is visually indicated (checkmark or highlight)

#### Scenario: Selecting a different view mode
- **WHEN** user selects "瀑布流视图" from the popup menu while in list view
- **THEN** the note list switches to waterfall layout immediately
- **AND** the toggle button icon updates to reflect the new mode

### Requirement: List view mode
The system SHALL display notes in a vertical list using `ListView.builder` where each note is rendered as a `ListTile` with title (1 line), content preview (2 lines), and date. This is the default view mode.

#### Scenario: Default view on first launch
- **WHEN** the app launches for the first time with no saved preference
- **THEN** the note list displays in list view mode

#### Scenario: List view item layout
- **WHEN** a note is displayed in list view
- **THEN** it shows as a single-row ListTile with title, preview, and date
- **AND** supports swipe-to-delete and tap-to-open

### Requirement: Waterfall view mode
The system SHALL display notes in a 2-column masonry grid layout using `MasonryGridView.builder`. Each note card SHALL display title (max 2 lines), content preview (max 4 lines), and date. Card height SHALL adapt to content.

#### Scenario: Waterfall view card layout
- **WHEN** a note is displayed in waterfall view
- **THEN** it shows as a card with rounded corners and border
- **AND** the card contains title (max 2 lines, ellipsis overflow), content preview (max 4 lines, ellipsis overflow), and date

#### Scenario: Waterfall view card selection
- **WHEN** a note is selected (its id matches the active tab)
- **THEN** the card background is highlighted (same as list view selection)

#### Scenario: Waterfall view card tap
- **WHEN** user taps a card in waterfall view
- **THEN** the note opens in the editor (same behavior as list view tap)

#### Scenario: Waterfall view card delete
- **WHEN** a card in waterfall view has a delete action triggered
- **THEN** the note is deleted with the same confirmation/behavior as list view

### Requirement: View mode persistence
The system SHALL persist the selected view mode preference across app restarts using SharedPreferences with key `note_list_view_mode`.

#### Scenario: View preference saved on change
- **WHEN** user switches from list view to waterfall view
- **THEN** the preference `note_list_view_mode` is saved as "waterfall"

#### Scenario: View preference restored on launch
- **WHEN** the app launches and a saved view preference exists
- **THEN** the note list displays in the previously selected view mode

#### Scenario: No saved preference defaults to list
- **WHEN** the app launches and no view preference is saved
- **THEN** the note list displays in list view mode
