## MODIFIED Requirements

### Requirement: Extract first media source from note content
The system SHALL parse a note's delta JSON content and extract the source path and optional thumbnail path of the first embedded image or video. `MediaInfo` SHALL 新增 `thumbnail` 字段（String?）。提取 SHALL 返回包含 `source`、`isVideo`、`thumbnail` 的 `MediaInfo` 对象。

#### Scenario: Extract first image source
- **WHEN** a note contains delta ops including `{"insert": {"image": "{\"source\":\"/path/to/img.png\",\"width\":400}"}}`
- **THEN** the extraction returns `MediaInfo` with source `"/path/to/img.png"`, isVideo `false`, and thumbnail `null`

#### Scenario: Extract first video source with thumbnail
- **WHEN** a note contains delta ops including `{"insert": {"video": "{\"source\":\"/path/to/vid.mp4\",\"width\":400,\"thumbnail\":\"/path/to/thumb.jpg\"}"}}`
- **THEN** the extraction returns `MediaInfo` with source `"/path/to/vid.mp4"`, isVideo `true`, and thumbnail `"/path/to/thumb.jpg"`

#### Scenario: Extract first video source without thumbnail
- **WHEN** a note contains delta ops including `{"insert": {"video": "{\"source\":\"/path/to/vid.mp4\",\"width\":400}"}}`
- **THEN** the extraction returns `MediaInfo` with source `"/path/to/vid.mp4"`, isVideo `true`, and thumbnail `null`

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
The system SHALL display a thumbnail in the `leading` position of each note's `ListTile` when the note contains an image or video. Image thumbnails SHALL be 48x48 with rounded corners. Video thumbnails with a `thumbnail` path SHALL display the actual video frame image with a play icon overlay. Video thumbnails without a `thumbnail` path SHALL show a play icon on a grey background. Notes without media SHALL NOT display a thumbnail in the leading position.

#### Scenario: Image thumbnail in list view
- **WHEN** a note containing an image is displayed in list view
- **THEN** a 48x48 rounded-corner thumbnail is shown at the leading position
- **AND** the thumbnail displays the image using `Image.file` or `Image.network`

#### Scenario: Video with thumbnail in list view
- **WHEN** a note containing a video with a thumbnail path is displayed in list view
- **THEN** a 48x48 rounded-corner thumbnail is shown at the leading position
- **AND** the thumbnail displays the video frame image using `Image.file`
- **AND** a play icon is overlaid on the thumbnail

#### Scenario: Video without thumbnail in list view
- **WHEN** a note containing a video without a thumbnail path is displayed in list view
- **THEN** a 48x48 grey rounded-corner placeholder is shown at the leading position
- **AND** a play icon is overlaid on the placeholder

#### Scenario: No thumbnail in list view
- **WHEN** a note has no image or video content
- **THEN** no thumbnail is displayed in the leading position

### Requirement: Display thumbnail in waterfall view
The system SHALL display a thumbnail at the top of each note's waterfall card when the note contains an image or video. The thumbnail SHALL fill the card width with a max height of 120px, clipped to the card's rounded corners. Video thumbnails with a `thumbnail` path SHALL display the actual video frame image with a play icon overlay. Video thumbnails without a `thumbnail` path SHALL show a play icon on a grey background.

#### Scenario: Image thumbnail in waterfall view
- **WHEN** a note containing an image is displayed in waterfall view
- **THEN** a thumbnail is shown at the top of the card
- **AND** the thumbnail fills the card width with max height 120px
- **AND** corners are clipped to match the card's border radius

#### Scenario: Video with thumbnail in waterfall view
- **WHEN** a note containing a video with a thumbnail path is displayed in waterfall view
- **THEN** the video frame image is shown at the top of the card
- **AND** a play icon overlay is displayed
- **AND** the thumbnail fills the card width with max height 120px

#### Scenario: Video without thumbnail in waterfall view
- **WHEN** a note containing a video without a thumbnail path is displayed in waterfall view
- **THEN** a grey placeholder with play icon is shown at the top of the card
- **AND** the placeholder fills the card width with max height 120px

#### Scenario: No thumbnail in waterfall view
- **WHEN** a note has no image or video content
- **THEN** no thumbnail is shown at the top of the card
