# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash script utility for extracting static images from screen recordings. The script analyzes video files (MOV/MP4) to detect moments when the screen remains static and automatically extracts those frames as PNG images, useful for creating operation manuals and documentation.

## Input/output language settings

The language of output to the screen, during processing, and display of processing results should be translated into Japanese as much as possible.

If individual support is required
- `CLAUDE.md`
  - In English
  - Create a file translated into Japanese as `CLAUDE.ja.md`
  - If changes are made to CLAUDE.md, translate the changes into Japanese and reflect them in CLAUDE.ja.md
- `CLAUDE.ja.md`
  - The Japanese translation file is for user reference only and is not used in the context of execution.
  - If there are additional changes other than those reflected in CLAUDE.md, ask the user how to respond to each part.
    - Response options
      - Translate into English and rewrite or add the corresponding part of CLAUDE.md
      - Leave it as it is as a memo
      - Ask the user to enter the process details and execute the process.

## Formatting Markdown files

- If a file name, absolute path, or relative path is written in the text, use code notation, such as `CLAUDE.ja.md`, especially for file paths within a project.

## Common Commands

### Running the Script
```bash
# Basic usage - extract frames from a video
./mov2img.sh -i recording.mov

# With custom parameters
./mov2img.sh -i recording.mp4 -o frames -n screenshot -t 5 -f 15

# With verbose output for debugging
./mov2img.sh -i tutorial.mov -t 2 -d 0.5 -v
```

### Script Parameters
- `-i, --input`: Input video file (required)
- `-o, --output`: Output folder name
- `-n, --name`: Base name for extracted images
- `-t, --threshold`: Difference threshold percentage (default: 3%)
- `-f, --fps`: Processing frame rate (default: 30)
- `-d, --duration`: Minimum static duration in seconds (default: 1.0)
- `-v, --verbose`: Enable verbose output

## Dependencies

The script requires:
- `ffmpeg` - For video processing and frame extraction
- `ffprobe` - For video analysis
- `bc` - For floating-point calculations

Install on macOS:
```bash
brew install ffmpeg
```

## Architecture

The script follows a modular architecture with these main components:

1. **Argument Parsing** (`parse_args`): Handles command-line arguments and sets defaults
2. **Environment Validation** (`validate_environment`): Checks for dependencies and input file validity
3. **Frame Extraction** (`extract_static_frames`): Core logic that:
   - Extracts frames at specified FPS using ffmpeg
   - Compares consecutive frames to detect static periods
   - Saves the middle frame from each static period as an output image
4. **Cleanup**: Automatically removes temporary files on script exit

The script uses a temporary directory for frame processing and implements proper error handling with trap-based cleanup.