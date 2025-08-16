# mov2img

A Bash script utility for automatically extracting static images from screen recordings. This tool analyzes video files (MOV/MP4) to detect moments when the screen remains static and extracts those frames as PNG images - perfect for creating operation manuals and documentation.

[日本語版 README](README.ja.md)

## Features

- **Automatic Static Frame Detection**: Intelligently identifies moments when the screen remains unchanged
- **Configurable Threshold**: Adjustable sensitivity for detecting screen changes
- **Batch Processing**: Extracts multiple static frames from a single video
- **Customizable Output**: Configure output directory and file naming patterns
- **Frame Rate Control**: Process videos at your preferred frame rate for optimal performance
- **Verbose Mode**: Detailed logging for debugging and monitoring progress

## Requirements

- macOS / Linux with Bash
- `ffmpeg` and `ffprobe` (for video processing)
- `bc` (for floating-point calculations)

### Installation on macOS

```bash
brew install ffmpeg
```

## Usage

### Basic Usage

```bash
./mov2img.sh -i recording.mov
```

This will extract static frames from `recording.mov` and save them to `recording_frames/` directory.

### Advanced Usage

```bash
# Specify output directory and file prefix
./mov2img.sh -i tutorial.mp4 -o output_frames -n screenshot

# Adjust detection sensitivity (lower = more sensitive)
./mov2img.sh -i demo.mov -t 2

# Process at different frame rate and minimum duration
./mov2img.sh -i presentation.mov -f 15 -d 0.5

# Enable verbose output for debugging
./mov2img.sh -i recording.mov -v
```

### Parameters

| Parameter | Long Option | Description | Default |
|-----------|------------|-------------|---------|
| `-i` | `--input` | Input video file (required) | - |
| `-o` | `--output` | Output directory | `{input_name}_frames` |
| `-n` | `--name` | Base name for extracted images | `{output_dir_name}` |
| `-t` | `--threshold` | Difference threshold percentage | `3%` |
| `-f` | `--fps` | Processing frame rate | `30` |
| `-d` | `--duration` | Minimum static duration in seconds | `1.0` |
| `-v` | `--verbose` | Enable verbose output | `false` |
| `-h` | `--help` | Show help message | - |

## How It Works

1. **Frame Extraction**: The script extracts frames from the input video at the specified frame rate
2. **Frame Comparison**: Consecutive frames are compared to detect differences
3. **Static Period Detection**: When frame differences fall below the threshold for the minimum duration, a static period is identified
4. **Image Export**: The middle frame from each static period is saved as a PNG image

## Example Workflow

1. Record a screen capture of your application or tutorial
2. Run mov2img to extract key moments:
   ```bash
   ./mov2img.sh -i screen_recording.mov -n step
   ```
3. Find extracted images in `screen_recording_frames/`:
   - `step_0001.png`
   - `step_0002.png`
   - `step_0003.png`
   - ...

## Output Structure

```
output_directory/
├── {base_name}_0001.png
├── {base_name}_0002.png
├── {base_name}_0003.png
└── ...
```

## Tips

- **For tutorials**: Use a lower threshold (1-2%) to capture subtle UI changes
- **For presentations**: Use a higher threshold (5-10%) to ignore minor animations
- **For mobile recordings**: Adjust FPS to 15-20 for better performance
- **For long videos**: Use verbose mode to monitor progress

## Troubleshooting

### No frames extracted
- Try lowering the threshold value with `-t 1`
- Reduce the minimum duration with `-d 0.5`
- Check if the video has static moments lasting at least the minimum duration

### Too many frames extracted
- Increase the threshold value with `-t 5`
- Increase the minimum duration with `-d 2`

### Performance issues
- Reduce the processing frame rate with `-f 15`
- Ensure sufficient disk space for temporary frame storage

## License

This project is open source and available under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Author

Created by henoya

## Acknowledgments

- Built with `ffmpeg` for robust video processing
- Inspired by the need for efficient documentation creation from screen recordings