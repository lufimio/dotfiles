#!/usr/bin/env python3

import argparse
import glob
import io
import os
import re
import shutil
import sys
import tempfile
import eyed3
from PIL import Image, ImageStat
import requests
from yt_dlp import YoutubeDL

# Try importing syncedlyrics if available; otherwise fall back gracefully
try:
    import syncedlyrics
except ImportError:
    syncedlyrics = None


def sanitize(name):
    return re.sub(r'[\\/:*?"<>|\r\n\t]', "_", name)


def is_solid_bar(img_region, tolerance=10):
    """Checks if a region/crop of an image is composed of a solid color."""
    stat = ImageStat.Stat(img_region)
    return all(std < tolerance for std in stat.stddev)


def crop_padded_cover(image_bytes):
    """Detects solid letterbox/pillarbox bars around a square center and crops it."""
    try:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except Exception as e:
        print(f"Failed to open image for processing: {e}", file=sys.stderr)
        return None

    width, height = img.size
    if width == height:
        return None

    if width > height:
        side_bar_width = (width - height) // 2
        left_bar = img.crop((0, 0, side_bar_width, height))
        right_bar = img.crop((width - side_bar_width, 0, width, height))

        if is_solid_bar(left_bar) and is_solid_bar(right_bar):
            cropped_img = img.crop((side_bar_width, 0, side_bar_width + height, height))
            output = io.BytesIO()
            cropped_img.save(output, format="JPEG", quality=95)
            return output.getvalue()

    elif height > width:
        side_bar_height = (height - width) // 2
        top_bar = img.crop((0, 0, width, side_bar_height))
        bottom_bar = img.crop((0, height - side_bar_height, width, height))

        if is_solid_bar(top_bar) and is_solid_bar(bottom_bar):
            cropped_img = img.crop((0, side_bar_height, width, side_bar_height + width))
            output = io.BytesIO()
            cropped_img.save(output, format="JPEG", quality=95)
            return output.getvalue()

    return None


def fetch_cover_art_archive(release_id):
    """Attempts to fetch front cover image directly from Cover Art Archive."""
    url = f"https://coverartarchive.org/release/{release_id}/front"
    headers = {"User-Agent": "MyAudioTagger/1.0 ( contact@example.com )"}
    try:
        res = requests.get(url, headers=headers, timeout=5, allow_redirects=True)
        if res.status_code == 200:
            return res.content
    except Exception:
        pass
    return None


def process_audio_cover(audiofile, mb_release_id=None):
    """Prioritizes MusicBrainz square cover; falls back to cropping embedded cover."""
    if mb_release_id:
        print(
            f"Attempting to fetch cover art from Cover Art Archive for release: {
                mb_release_id
            }..."
        )
        mb_cover_bytes = fetch_cover_art_archive(mb_release_id)
        if mb_cover_bytes:
            try:
                img = Image.open(io.BytesIO(mb_cover_bytes)).convert("RGB")
                w, h = img.size
                if abs(w - h) <= 5:
                    print(
                        "Found square MusicBrainz cover art. Replacing embedded image..."
                    )
                    audiofile.tag.images.set(
                        3, mb_cover_bytes, "image/jpeg", "Front Cover"
                    )
                    return "MusicBrainz (Cover Art Archive)"
            except Exception as e:
                print(
                    f"Error checking MusicBrainz cover dimensions: {e}", file=sys.stderr
                )

    if not audiofile.tag.images:
        return "None"

    for img_frame in audiofile.tag.images:
        cropped_data = crop_padded_cover(img_frame.image_data)
        if cropped_data:
            print("Detected solid side padding on cover art. Cropping to square...")
            img_frame.image_data = cropped_data
            img_frame.mime_type = "image/jpeg"
            return "YouTube / Embedded (Cropped)"

    return "YouTube / Embedded (Original)"


def fetch_musicbrainz_metadata(title, artist):
    """Queries MusicBrainz API for detailed recording metadata."""
    url = "https://musicbrainz.org/ws/2/recording/"
    headers = {"User-Agent": "MyAudioTagger/1.0 ( contact@example.com )"}
    query = (
        f'recording:"{title}" AND artist:"{artist}"'
        if artist
        else f'recording:"{title}"'
    )
    params = {
        "query": query,
        "fmt": "json",
        "limit": 1,
        "inc": "releases+genres+tags+artist-credits",
    }

    metadata = {
        "title": None,
        "artist": None,
        "album": None,
        "year": None,
        "genres": [],
        "url": None,
        "release_id": None,
    }

    try:
        res = requests.get(url, headers=headers, params=params, timeout=5)
        if res.status_code == 200:
            data = res.json()
            recordings = data.get("recordings", [])
            if recordings:
                rec = recordings[0]
                metadata["url"] = f"https://musicbrainz.org/recording/{rec['id']}"
                metadata["title"] = rec.get("title")

                artist_credits = rec.get("artist-credit", [])
                if artist_credits:
                    metadata["artist"] = "".join(
                        [
                            a.get("name", "") + a.get("joinphrase", "")
                            for a in artist_credits
                        ]
                    )

                releases = rec.get("releases", [])
                if releases:
                    first_rel = releases[0]
                    metadata["album"] = first_rel.get("title")
                    metadata["release_id"] = first_rel.get("id")
                    rel_date = first_rel.get("date", "")
                    if rel_date and len(rel_date) >= 4:
                        metadata["year"] = rel_date[:4]

                genres = [g.get("name") for g in rec.get("genres", []) if g.get("name")]
                tags = [t.get("name") for t in rec.get("tags", []) if t.get("name")]
                all_genres = list(dict.fromkeys(genres + tags))
                if all_genres:
                    metadata["genres"] = all_genres
    except Exception as e:
        print(f"MusicBrainz lookup error: {e}", file=sys.stderr)

    return metadata


def fetch_lrclib_search(title, artist):
    """Fallback search on LRCLIB using freeform search query if exact match fails."""
    url = "https://lrclib.net/api/search"
    headers = {"User-Agent": "MyAudioTagger/1.0"}

    queries = [f"{title} {artist}".strip(), title]
    for q in queries:
        try:
            res = requests.get(url, params={"q": q}, headers=headers, timeout=5)
            if res.status_code == 200:
                results = res.json()
                if isinstance(results, list) and len(results) > 0:
                    for item in results:
                        synced = item.get("syncedLyrics")
                        plain = item.get("plainLyrics")
                        if synced:
                            return synced, plain
                    return None, results[0].get("plainLyrics")
        except Exception:
            continue
    return None, None


def vtt_to_lrc(vtt_content):
    """Converts WebVTT subtitle formatting into standard LRC synchronized lyrics format."""
    lrc_lines = []
    time_pattern = re.compile(
        r"^(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})\s+-->\s+(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})"
    )

    lines = vtt_content.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        match = time_pattern.match(line)
        if match:
            hours = int(match.group(1) or 0)
            minutes = int(match.group(2)) + (hours * 60)
            seconds = int(match.group(3))
            millis = int(match.group(4)[:2])

            timestamp = f"[{minutes:02d}:{seconds:02d}.{millis:02d}]"

            text_lines = []
            i += 1
            while (
                i < len(lines)
                and lines[i].strip()
                and not time_pattern.match(lines[i].strip())
            ):
                raw_text = lines[i].strip()
                cleaned_text = re.sub(r"<[^>]+>", "", raw_text)
                if cleaned_text and cleaned_text not in text_lines:
                    text_lines.append(cleaned_text)
                i += 1

            if text_lines:
                combined_text = " ".join(text_lines)
                lrc_lines.append(f"{timestamp} {combined_text}")
            continue
        i += 1

    return "\n".join(lrc_lines)


def fetch_youtube_captions_for_file(title, artist, temp_base_filepath):
    """Queries YouTube search for local file metadata and downloads native captions without video."""
    search_term = f"ytsearch1:{title} {artist}".strip()
    print(f"Searching YouTube for captions: '{title} {artist}'...")

    tmp_dir = os.path.dirname(temp_base_filepath)
    sub_outtmpl = os.path.join(tmp_dir, "yt_file_search.%(ext)s")

    yt_sub_opts = {
        "skip_download": True,
        "writesubtitles": True,
        "writeautomaticsub": False,
        "subtitlesformat": "best",
        "subtitleslangs": ["orig", ".*-orig", "en"],
        "outtmpl": sub_outtmpl,
        "quiet": True,
        "no_warnings": True,
    }

    try:
        with YoutubeDL(yt_sub_opts) as ydl:
            ydl.download([search_term])

        downloaded_subs = glob.glob(
            os.path.join(tmp_dir, "yt_file_search*.vtt")
        ) + glob.glob(os.path.join(tmp_dir, "yt_file_search*.lrc"))
        if downloaded_subs:
            src_sub = downloaded_subs[0]
            with open(src_sub, "r", encoding="utf-8") as f:
                content = f.read()

            synced_lrc = (
                vtt_to_lrc(content)
                if (src_sub.endswith(".vtt") or "WEBVTT" in content)
                else content
            )
            # Clean up temporary search subtitle files
            for sf in downloaded_subs:
                if os.path.exists(sf):
                    os.remove(sf)
            return synced_lrc
    except Exception as e:
        print(f"Error fetching YouTube captions for local file: {e}", file=sys.stderr)

    return None


def handle_lyrics_pipeline(
    temp_base_filepath, target_base_filepath, audiofile, title, artist, provider="all"
):
    """Priority pipeline with discrete providers -> YouTube Captions -> Unsynced Plain Lyrics."""
    target_lrc_path = f"{target_base_filepath}.lrc"
    synced_lrc = None
    plain_text = None
    lyrics_source = "None"

    if provider == "none":
        print("Lyrics downloading disabled via --lyrics-provider none.")
        return "None"

    search_query = f"{title} {artist}".strip()

    # Provider: Specific or All syncedlyrics providers
    if provider != "youtube" and syncedlyrics:
        syncedlyrics_providers = None if provider == "all" else [provider]
        provider_name = (
            "syncedlyrics ("
            + (provider if provider != "all" else "multi-provider")
            + ")"
        )
        print(f"Searching via {provider_name} for '{search_query}'...")
        try:
            synced_lrc = syncedlyrics.search(
                search_query, synced_only=True, providers=syncedlyrics_providers
            )
            if synced_lrc:
                lyrics_source = provider_name
                print(f"Found synced lyrics via {provider_name}!")
                plain_text = re.sub(r"\[\d+:\d+\.\d+\]", "", synced_lrc).strip()
        except Exception as e:
            print(f"syncedlyrics error ({provider}): {e}", file=sys.stderr)

    # Provider: Direct LRCLIB API Fallback
    if not synced_lrc and provider in ["all", "lrclib"]:
        print("Searching LRCLIB direct search API...")
        synced_lrc, plain_text = fetch_lrclib_search(title, artist)
        if synced_lrc:
            lyrics_source = "LRCLIB API"
            print("Found synced lyrics via LRCLIB search!")
            plain_text = re.sub(r"\[\d+:\d+\.\d+\]", "", synced_lrc).strip()

    # Provider: YouTube Captions (handles both downloaded URLs and local files)
    if not synced_lrc and provider in ["all", "youtube"]:
        print("Checking YouTube captions...")
        downloaded_subs = glob.glob(
            f"{glob.escape(temp_base_filepath)}*.lrc"
        ) + glob.glob(f"{glob.escape(temp_base_filepath)}*.vtt")
        if downloaded_subs:
            src_sub = downloaded_subs[0]
            try:
                with open(src_sub, "r", encoding="utf-8") as f:
                    content = f.read()

                synced_lrc = (
                    vtt_to_lrc(content)
                    if (src_sub.endswith(".vtt") or "WEBVTT" in content)
                    else content
                )
                if synced_lrc:
                    lyrics_source = "YouTube Captions (Converted)"
                    print("Converted and loaded YouTube captions!")
                    plain_text = re.sub(r"\[\d+:\d+\.\d+\]", "", synced_lrc).strip()
            except Exception as e:
                print(f"Error processing YouTube subtitles: {e}", file=sys.stderr)

        # Fallback for local files: perform an on-demand YouTube search for captions
        if not synced_lrc:
            yt_caption_res = fetch_youtube_captions_for_file(
                title, artist, temp_base_filepath
            )
            if yt_caption_res:
                synced_lrc = yt_caption_res
                lyrics_source = "YouTube Captions (On-demand Search)"
                print("Found and converted YouTube captions via search!")
                plain_text = re.sub(r"\[\d+:\d+\.\d+\]", "", synced_lrc).strip()

    # Unsynced plain lyrics fallback
    if not synced_lrc and provider != "youtube":
        print("No synced lyrics found. Checking for unsynced plain lyrics...")
        if not plain_text and syncedlyrics:
            try:
                syncedlyrics_providers = None if provider == "all" else [provider]
                plain_text = syncedlyrics.search(
                    search_query, plain_only=True, providers=syncedlyrics_providers
                )
            except Exception:
                pass
        if plain_text:
            lyrics_source = f"Unsynced Plain Lyrics ({provider})"
            print("Found unsynced plain lyrics.")

    if synced_lrc:
        try:
            with open(target_lrc_path, "w", encoding="utf-8") as f_out:
                f_out.write(synced_lrc)
            print(f"Saved synchronized lyrics file: {target_lrc_path}")
        except Exception as e:
            print(f"Failed to write .lrc file: {e}", file=sys.stderr)

    if plain_text:
        audiofile.tag.lyrics.set(plain_text)

    return lyrics_source


def print_summary_table(summary_data):
    """Prints a structured summary table showing sources of information."""
    print("\n" + "=" * 60)
    print("                     PROCESSING SUMMARY                     ")
    print("=" * 60)
    print(f"{'FIELD':<18} | {'VALUE':<20} | {'SOURCE':<18}")
    print("-" * 60)
    for field, data in summary_data.items():
        val = str(data["value"])
        if len(val) > 20:
            val = val[:17] + "..."
        src = str(data["source"])
        if len(src) > 18:
            src = src[:15] + "..."
        print(f"{field:<18} | {val:<20} | {src:<18}")
    print("=" * 60 + "\n")


def process_mp3_file(
    filepath,
    initial_info=None,
    output_dir=None,
    original_filepath=None,
    non_interactive=False,
    lyrics_provider="all",
):
    """Processes, tags, crops cover, and moves final files out of temp processing."""
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}", file=sys.stderr)
        return

    audiofile = eyed3.load(filepath)
    if audiofile is None:
        print(f"Could not read tags from {filepath}", file=sys.stderr)
        return
    if audiofile.tag is None:
        audiofile.initTag()

    initial_info = initial_info or {}
    base_file_title = os.path.splitext(os.path.basename(filepath))[0]

    fallback_title = audiofile.tag.title or initial_info.get("title") or base_file_title
    fallback_artist = audiofile.tag.artist or initial_info.get("artist") or ""
    fallback_year = (
        str(audiofile.tag.recording_date) if audiofile.tag.recording_date else None
    ) or initial_info.get("year")
    fallback_genre = (
        audiofile.tag.genre.name
        if audiofile.tag.genre
        else initial_info.get("genre", "")
    )
    webpage_url = initial_info.get("webpage_url")

    print(
        f"\nSearching MusicBrainz for: '{fallback_title}' (Artist: '{
            fallback_artist
        }')..."
    )
    mb_data = fetch_musicbrainz_metadata(fallback_title, fallback_artist)

    sources = {
        "title": "MusicBrainz" if mb_data.get("title") else "YouTube/Filename",
        "artist": "MusicBrainz" if mb_data.get("artist") else "YouTube/Existing ID3",
        "album": "MusicBrainz" if mb_data.get("album") else "User/Default",
        "year": "MusicBrainz" if mb_data.get("year") else "YouTube/Existing ID3",
        "genre": "MusicBrainz" if mb_data.get("genres") else "YouTube/Existing ID3",
    }

    default_title = mb_data.get("title") or fallback_title
    default_artist = mb_data.get("artist") or fallback_artist
    default_album = mb_data.get("album") or audiofile.tag.album or default_title
    default_year = mb_data.get("year") or fallback_year

    mb_genres = mb_data.get("genres", [])
    default_genre = ", ".join(mb_genres) if mb_genres else fallback_genre

    if non_interactive:
        print("Non-interactive mode enabled. Accepting defaults:")
        audiofile.tag.title = default_title
        audiofile.tag.artist = default_artist
        audiofile.tag.album = default_album
        year_input = default_year
        genre_input = default_genre
    else:
        user_title = input(f"Title ({default_title}): ")
        if user_title:
            default_title = user_title
            sources["title"] = "User Input"

        user_artist = input(f"Artist ({default_artist}): ")
        if user_artist:
            default_artist = user_artist
            sources["artist"] = "User Input"

        user_album = input(f"Album ({default_album}): ")
        if user_album:
            default_album = user_album
            sources["album"] = "User Input"

        year_input = input(f"Year ({default_year or ''}): ") or default_year
        if year_input != default_year:
            sources["year"] = "User Input"

        genre_input = (
            input(f"Genre(s) [comma-separated] ({default_genre}): ") or default_genre
        )
        if genre_input != default_genre:
            sources["genre"] = "User Input"

        audiofile.tag.title = default_title
        audiofile.tag.artist = default_artist
        audiofile.tag.album = default_album

    if year_input:
        try:
            audiofile.tag.recording_date = str(int(year_input))
        except ValueError:
            print(f"Invalid year: {year_input}", file=sys.stderr)

    if genre_input:
        genre_list = [g.strip() for g in genre_input.split(",") if g.strip()]
        audiofile.tag.genre = (
            "/".join(genre_list) if len(genre_list) > 1 else genre_input
        )

    if webpage_url:
        audiofile.tag.audio_source_url = webpage_url

    if mb_data.get("url"):
        print(f"Adding MusicBrainz URL: {mb_data['url']}")
        existing_comments = [c.text for c in audiofile.tag.comments]
        comment_text = f"MusicBrainz: {mb_data['url']}"
        if comment_text not in existing_comments:
            audiofile.tag.comments.set(comment_text)

    cover_source = process_audio_cover(
        audiofile, mb_release_id=mb_data.get("release_id")
    )

    target_directory = output_dir or os.getcwd()
    os.makedirs(target_directory, exist_ok=True)
    target_base_name = os.path.join(
        target_directory,
        f"{sanitize(audiofile.tag.title)} - {sanitize(audiofile.tag.artist)}",
    )

    temp_base_no_ext = os.path.splitext(filepath)[0]
    lyrics_source = handle_lyrics_pipeline(
        temp_base_no_ext,
        target_base_name,
        audiofile,
        audiofile.tag.title,
        audiofile.tag.artist,
        provider=lyrics_provider,
    )

    audiofile.tag.save()

    final_mp3_path = f"{target_base_name}.mp3"

    if original_filepath and os.path.exists(original_filepath):
        abs_original = os.path.abspath(original_filepath)
        abs_final = os.path.abspath(final_mp3_path)
        if abs_original != abs_final:
            os.remove(abs_original)

    shutil.move(filepath, final_mp3_path)

    summary = {
        "Title": {"value": audiofile.tag.title, "source": sources["title"]},
        "Artist": {"value": audiofile.tag.artist, "source": sources["artist"]},
        "Album": {"value": audiofile.tag.album, "source": sources["album"]},
        "Year": {"value": year_input or "N/A", "source": sources["year"]},
        "Genre": {"value": genre_input or "N/A", "source": sources["genre"]},
        "Cover Art": {"value": "Embedded", "source": cover_source},
        "Lyrics": {"value": ".lrc / USLT", "source": lyrics_source},
        "MusicBrainz Link": {
            "value": mb_data.get("url") or "None",
            "source": "MusicBrainz API" if mb_data.get("url") else "N/A",
        },
    }
    print_summary_table(summary)
    print(f"Saved final file: {final_mp3_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Download, crop, tag, and synchronize lyrics for MP3 files."
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="YouTube URLs or paths to local MP3 files.",
    )
    parser.add_argument(
        "-y",
        "--yes",
        "--non-interactive",
        dest="non_interactive",
        action="store_true",
        help="Automatically accept all MusicBrainz/tag defaults without prompting.",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        dest="output_dir",
        default=None,
        help="Directory to save the resulting MP3 and .lrc files.",
    )
    parser.add_argument(
        "--lyrics-provider",
        choices=[
            "all",
            "lrclib",
            "netease",
            "megalobiz",
            "musixmatch",
            "kuwo",
            "lsp",
            "deezer",
            "apple",
            "youtube",
            "none",
        ],
        default="all",
        help="Specify the preferred provider for fetching synced lyrics (default: all).",
    )

    args = parser.parse_args()

    target_out_dir = os.path.abspath(args.output_dir) if args.output_dir else None

    with tempfile.TemporaryDirectory(prefix="mp3_processor_") as tmp_dir:
        print(f"Temporary working directory set to: {tmp_dir}")

        ydl_opts = {
            "extract_flat": "discard_in_playlist",
            "final_ext": "mp3",
            "format": "ba[acodec^=mp3]/ba/b",
            "fragment_retries": 10,
            "ignoreerrors": "only_download",
            "outtmpl": {
                "default": os.path.join(tmp_dir, "%(title)s - %(uploader)s.%(ext)s"),
                "pl_thumbnail": "",
            },
            "writesubtitles": True,
            "writeautomaticsub": False,
            "subtitlesformat": "best",
            "subtitleslangs": ["orig", ".*-orig", "en"],
            "postprocessors": [
                {
                    "key": "FFmpegExtractAudio",
                    "nopostoverwrites": False,
                    "preferredcodec": "mp3",
                    "preferredquality": "5",
                },
                {"already_have_thumbnail": False, "key": "EmbedThumbnail"},
                {
                    "key": "FFmpegConcat",
                    "only_multi_video": True,
                    "when": "playlist",
                },
            ],
            "retries": 10,
            "warn_when_outdated": True,
            "writethumbnail": True,
        }

        for item in args.inputs:
            if os.path.isfile(item):
                print(f"\n--- Processing Local File: {item} ---")
                temp_mp3 = os.path.join(tmp_dir, os.path.basename(item))
                with open(item, "rb") as f_in, open(temp_mp3, "wb") as f_out:
                    f_out.write(f_in.read())
                process_mp3_file(
                    temp_mp3,
                    output_dir=target_out_dir or os.path.dirname(os.path.abspath(item)),
                    original_filepath=item,
                    non_interactive=args.non_interactive,
                    lyrics_provider=args.lyrics_provider,
                )
            else:
                print(f"\n--- Downloading & Processing URL: {item} ---")
                with YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(item, download=True)
                    if not info:
                        print(f"Failed to extract info for {item}", file=sys.stderr)
                        continue
                    entries = info.get("entries") or [info]
                    for entry in entries:
                        if not entry:
                            continue
                        try:
                            filename = entry.get("_filename") or ydl.prepare_filename(
                                entry
                            )
                        except Exception:
                            continue
                        base, ext = os.path.splitext(filename)
                        if not os.path.exists(filename) and ext != ".mp3":
                            filename = base + ".mp3"

                        yt_info = {
                            "title": entry.get("title"),
                            "artist": entry.get("uploader")
                            or entry.get("channel")
                            or entry.get("creator"),
                            "year": entry.get("release_year")
                            or (entry.get("upload_date") or "")[:4]
                            or None,
                            "genre": entry.get("genre"),
                            "webpage_url": entry.get("webpage_url") or item,
                        }
                        process_mp3_file(
                            filename,
                            initial_info=yt_info,
                            output_dir=target_out_dir or os.getcwd(),
                            non_interactive=args.non_interactive,
                            lyrics_provider=args.lyrics_provider,
                        )
