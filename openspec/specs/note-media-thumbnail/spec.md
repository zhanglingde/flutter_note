## ADDED Requirements

### Requirement: Extract first media source from note content
The system SHALL parse a note's delta JSON content and extract the source path of the first embedded image or video. The extraction SHALL iterate through delta ops and find the first operation whose `insert` value is a Map containing either an `image` or `video` key. The source SHALL be extracted from the JSON-encoded string value.

#### Scenario: Extract first image source
- **WHEN** a note contains delta ops including `{"insert": {"image": "{\"source\":\"/path/to/img.png\",\"width\":400}"}}`
- **THEN** the extraction returns `"/path/to/img.png"` and the media type is `image`

#### Scenario: Extract first video source
- **WHEN** a note contains delta ops including `{"insert": {"video": "{\"source\":\"/path/to/vid.mp4\",\"width\":400}"}}`
- **THEN** the extraction returns `"/path/to/vid.mp4"` and the media type is `video`

#### Scenario: No media in note
- **WHEN** a note's delta content contains no image or video embeds
- **THEN** the extraction returns null

#### Scenario: Image appears before video
- **WHEN** a note contains both image and video embeds, with the image appearing first in the delta
- **THEN** the extraction returns the image source (first media wins)

#### Scenario: Network URL source
- **WHEN** the source is a URL starting with `http://` or `https://`
- **THEN** the source is returned as-is for network image/video loading

### Requirement: Display thumbnail in list view
The system SHALL display a thumbnail in the `leading` position of each note's `ListTile` when the note contains an image or video. Image thumbnails SHALL be 48x48 with rounded corners. Video thumbnails SHALL show a play icon on a grey background. Notes without media SHALL NOT display a thumbnail in the leading position.

#### Scenario: Image thumbnail in list view
- **WHEN** a note containing an image is displayed in list view
- **THEN** a 48x48 rounded-corner thumbnail is shown at the leading position
- **AND** the thumbnail displays the image using `Image.file` or `Image.network`

#### Scenario: Video thumbnail in list view
- **WHEN** a note containing a video is displayed in list view
- **THEN** a 48x48 grey rounded-corner placeholder is shown at the leading position
- **AND** a play icon is overlaid on the placeholder

#### Scenario: No thumbnail in list view
- **WHEN** a note has no image or video content
- **THEN** no thumbnail is displayed in the leading position

### Requirement: Display thumbnail in waterfall view
The system SHALL display a thumbnail at the top of each note's waterfall card when the note contains an image or video. The thumbnail SHALL fill the card width with a max height of 120px, clipped to the card's rounded corners. Video thumbnails SHALL show a play icon overlay.

#### Scenario: Image thumbnail in waterfall view
- **WHEN** a note containing an image is displayed in waterfall view
- **THEN** a thumbnail is shown at the top of the card
- **AND** the thumbnail fills the card width with max height 120px
- **AND** corners are clipped to match the card's border radius

#### Scenario: Video thumbnail in waterfall view
- **WHEN** a note containing a video is displayed in waterfall view
- **THEN** a grey placeholder with play icon is shown at the top of the card
- **AND** the placeholder fills the card width with max height 120px

#### Scenario: No thumbnail in waterfall view
- **WHEN** a note has no image or video content
- **THEN** no thumbnail is shown at the top of the card
