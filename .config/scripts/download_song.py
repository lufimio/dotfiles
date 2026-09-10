#!/usr/bin/env python3

from yt_dlp import YoutubeDL
import eyed3
import os
import re
import sys

ydl_opts = {'extract_flat': 'discard_in_playlist',
            'final_ext': 'mp3',
            'format': 'ba[acodec^=mp3]/ba/b',
            'fragment_retries': 10,
            'ignoreerrors': 'only_download',
            'outtmpl': {'default': '%(title)s - %(uploader)s.%(ext)s', 'pl_thumbnail': ''},
            'postprocessors': [{'key': 'FFmpegExtractAudio',
                                'nopostoverwrites': False,
                                'preferredcodec': 'mp3',
                                'preferredquality': '5'},
                               {'already_have_thumbnail': False, 'key': 'EmbedThumbnail'},
                               {'key': 'FFmpegConcat',
                                'only_multi_video': True,
                                'when': 'playlist'}],
            'retries': 10,
            'warn_when_outdated': True,
            'writethumbnail': True}

URLS = sys.argv[1:]
if not URLS:
    sys.exit(f'Usage: {sys.argv[0]} <url> [url ...]')


def sanitize(name):
    return re.sub(r'[\\/:*?"<>|\r\n\t]', '_', name)

with YoutubeDL(ydl_opts) as ydl:
    for url in URLS:
        info = ydl.extract_info(url, download=True)

        entries = info.get('entries') or [info]
        for entry in entries:
            if not entry:
                continue
            try:
                filename = entry.get('_filename') or ydl.prepare_filename(entry)
            except Exception:
                continue
            base, ext = os.path.splitext(filename)
            if not os.path.exists(filename) and ext != '.mp3':
                filename = base + '.mp3'
            if not os.path.exists(filename):
                print(f'File not found: {filename}', file=sys.stderr)
                continue

            audiofile = eyed3.load(filename)
            if audiofile is None:
                print(f'Could not read tags from {filename}', file=sys.stderr)
                continue
            if audiofile.tag is None:
                audiofile.initTag()

            title = entry.get('title') or os.path.splitext(os.path.basename(filename))[0]
            artist = entry.get('uploader') or entry.get('channel') or entry.get('creator')
            year = entry.get('release_year') or (entry.get('upload_date') or '')[:4] or None
            genre = entry.get('genre')

            audiofile.tag.title = input(f'Title ({title}): ') or title
            audiofile.tag.artist = input(f'Artist ({artist}): ') or artist
            audiofile.tag.album = input(f'Album ({audiofile.tag.title}): ') or audiofile.tag.title
            year = input(f'Year ({year}): ') or year
            genre = input(f'Genre ({genre}): ') or genre

            if year:
                try:
                    audiofile.tag.recording_date = str(int(year))
                except ValueError:
                    print(f'Invalid year: {year}', file=sys.stderr)
            if genre:
                audiofile.tag.genre = genre
            audiofile.tag.save()

            new_name = os.path.join(
                os.path.dirname(filename),
                f'{sanitize(audiofile.tag.title)} - {sanitize(audiofile.tag.artist)}.mp3',
            )
            if new_name != filename:
                os.rename(filename, new_name)

