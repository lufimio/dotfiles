#!/usr/bin/env python
from argparse import ArgumentParser
from datetime import datetime
from pathlib import Path
from plumbum.cmd import mpc, rm, ls, cp
from time import sleep
from os.path import exists

parser = ArgumentParser(description='A simple program to move music files from my MPD music store to my phone.')
parser.add_argument('action', choices=['help', 'ls', 'list', 'cp', 'copy', 'refresh', 'rm', 'remove', 'queue'], nargs='?', default='help')

parser.add_argument('--mpd-host', type=Path, default='/home/lufimio/.mpd/socket', help='Where mpc should look to communicate with the mpd daemon')
parser.add_argument('--mpd-music-dir', type=Path, default='/home/lufimio/Music/', help='Where this program should look for the source music files')
parser.add_argument('--output-dir', type=Path, default='/home/lufimio/Downloads/ios/', help='Where this program should move the music files to')
parser.add_argument('--insert', action='store_true', help='If enabled, the queue action will queue the song to be played next')

parser.add_argument('-d', '--delay', type=float, help='The number of minutes to wait between each set')
parser.add_argument('-s', '--seperate-by-likes', action='store_true', help='If enabled, each set will be seperated by both ranking and likes instead of just ranking')
parser.add_argument('--filename-only', action='store_true', help='If enabled, does not print the rating when listing songs')


# rating can be -1 or positive int; -1 is unrated
# like can be None, -1, 0, 1, 2; None is *, -1 is unrated, rest are valid
def parse_rating(string):
    parsed = [int(i) for i in string.split(':')]
    if len(parsed) not in [1, 2]:
        raise ValueError(f'invalid number of specifiers: expected 1 or 2, got {len(parsed)}')
    return (parsed[0], None if len(parsed) == 1 else parsed[1])


def parse_views(string):
    if string[0] in ['>', '<']:
        return int(string[1:]) * (-1 if string[0] == '<' else 1)
    return -int(string)



filters = parser.add_argument_group('Filters', 'Format: rating[:like] - A rating of -1 is unrated, similarly a like of -1 is unrated, ommitting it allows any rating')
filters.add_argument('-ge', type=parse_rating, help='select ratings greater than or equal to value')
filters.add_argument('-gt', type=parse_rating, help='select ratings greater than value')
filters.add_argument('-le', type=parse_rating, help='select ratings less than or equal to value')
filters.add_argument('-lt', type=parse_rating, help='select ratings less than value')
filters.add_argument('-eq', action='extend', nargs='+', type=parse_rating, help='select ratings equal to value')
filters.add_argument('-ne', action='extend', nargs='+', type=parse_rating, help='remove ratings equal to value')
filters.add_argument('-views', action='extend', nargs=1, type=parse_views, help='select view count less than value (default, prefix with < or > to change)')

args = parser.parse_args()
if args.action == 'help':
    parser.print_help()
    exit()


class Song:
    def __init__(self, filename, rating, like, views):
        self.filename = filename
        self.rating = rating
        self.like = like
        self.views = views

    def ge(self, rating, like):
        return self.rating > rating or self.rating == rating and (like is None or self.like >= like)

    def gt(self, rating, like):
        return self.rating > rating or self.rating == rating and (like is None or self.like > like)

    def le(self, rating, like):
        return self.rating < rating or self.rating == rating and (like is None or self.like <= like)

    def lt(self, rating, like):
        return self.rating < rating or self.rating == rating and (like is None or self.like < like)

    def eq(self, rating, like):
        return self.rating == rating and (like is None or self.like == like)

    def filter_views(self, views):
        if views < 0:
            return self.views < -views
        return self.views > views

    def __eq__(self, other):
        return self.rating == other.rating and self.like == other.like

    def __lt__(self, other):
        return self.rating < other.rating or self.rating == other.rating and self.like < other.like


mpd_songs = mpc["--host", args.mpd_host, "--format", "%file%", "listall"]().splitlines()
songs: list[Song] = []
for song_path in mpd_songs:
    stickers = mpc['--host', args.mpd_host, 'sticker', song_path, 'list']().splitlines()

    ratings = list(filter(lambda x: 'rating' in x, stickers))
    likes = list(filter(lambda x: 'like' in x, stickers))
    views = list(filter(lambda x: 'playCount' in x, stickers))

    rating = int(ratings[0].split('=')[1]) if ratings else -1
    like = int(likes[0].split('=')[1]) if likes else -1
    view = int(views[0].split('=')[1]) if views else 0

    songs.append(Song(song_path, rating, like, view))

filtered_songs: list[Song] = [] if args.ge or args.gt or args.le or args.lt or args.eq else songs[:]
if args.ge:
    filtered_songs.extend([song for song in songs if song.ge(*args.ge)])
if args.gt:
    filtered_songs.extend([song for song in songs if song.gt(*args.gt)])
if args.le:
    filtered_songs.extend([song for song in songs if song.le(*args.le)])
if args.lt:
    filtered_songs.extend([song for song in songs if song.lt(*args.lt)])
if args.eq:
    filtered_songs.extend([song for song in songs if any(song.eq(r, l) for r, l in args.eq)])
if args.ne:
    filtered_songs = [song for song in filtered_songs if not any(song.eq(r, l) for r, l in args.ne)]
if args.views:
    filtered_songs = [song for song in filtered_songs if all(song.filter_views(v) for v in args.views)]
filtered_songs.sort()

if args.delay is None:
    song_stages = [filtered_songs]
else:
    song_stages = [[filtered_songs[0]]]
    for song in filtered_songs[1:]:
        if (args.seperate_by_likes and song == song_stages[-1][0]) or (not args.seperate_by_likes and song.rating == song_stages[-1][0].rating):
            song_stages[-1].append(song)
        else:
            song_stages.append([song])

finished_songs = 0
for i, song_set in enumerate(song_stages):
    if args.action in ['ls', 'list']:
        print(*[song.filename if args.filename_only else f'{song.rating}:{song.like} [{song.views}] - {song.filename}' for song in song_set], sep='\n')
    elif args.action in ['rm', 'remove']:
        rm[*[f'{args.output_dir / song.filename}' for song in song_set if exists(f'{args.output_dir / song.filename}')]]()
    elif args.action in ['cp', 'copy']:
        cp[*[f'{args.mpd_music_dir / song.filename}' for song in song_set], args.output_dir]()
    elif args.action == 'refresh':
        rm[*[f'{args.output_dir / song.filename}' for song in song_set if exists(f'{args.output_dir / song.filename}')]]()
        sleep(60)
        cp[*[f'{args.mpd_music_dir / song.filename}' for song in song_set], args.output_dir]()
    elif args.action == 'queue':
        mpc['--host', args.mpd_host, 'insert' if args.insert else 'add', *[f'{args.mpd_music_dir / song.filename}' for song in song_set]]()

    if args.delay is not None and args.action not in ['ls', 'list']:
        finished_songs += len(song_set)
        print(f'[{datetime.now().strftime('%I:%M %p')}] - processed {song_set[-1].rating}{f':{song_set[-1].like}' if args.seperate_by_likes else ''} - set {i + 1} of {len(song_stages)} - processed {finished_songs} out of {len(filtered_songs)} songs')
        if i < len(song_stages) - 1:
            sleep(args.delay * 60)
