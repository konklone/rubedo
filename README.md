# Not Maintained

This project is incredibly old, and not maintained.

## Using Rubedo

  1. Install Icecast, SQLite3, Libogg, Libvorbis, Libshout, a few Ruby gems.
  2. Pick a folder everyone has access to, like a shared network drive, for everyone to put their music (MP3s, OGGs) in.
  3. Copy config.yml.example to config.yml, and edit it to include your details.
  4. Start Icecast.
  5. Run rubedo.rb.
  6. Start queueing songs in your browser.
  7. Listen to the radio, via the play button in-browser, or by streaming it into a media player.
  

## Dependencies

* Icecast: http://icecast.org/download.php
* libogg, libvorbis: http://xiph.org/downloads/
* libshout: http://icecast.org/download.php  
* sqlite3: http://www.sqlite.org/download.html
* Ruby Gems: ruby-shout, activerecord, sqlite3-ruby


## Configuring

Rubedo's configuration is contained in config.yml, with full descriptions of parameters.  You should at least change:
  
* music_folder - Where you're putting all your music.  This can be an absolute or relative (from rubedo.rb) path to the directory where all songs will be stored. 
* radio_name - The name of your radio station, displayed on the frontend and used to title the radio stream.


## Queueing Up Songs

Click on any song on the lefthand list of available songs to queue that song.  You can search through the songs available using the "Find" box.  The search checks the song's ID3 title, filename, and directory path.

The righthand side of Rubedo shows what's currently playing, and below that what songs are queued to play next.  when a song is playing, the links "Stream" and "Download" will appear.  "Stream" is a link to the stream, the URL of which you can paste into your music player.  "Download" is a direct link to the song being played (can be disabled in config.yml).

If no song is queued, Rubedo will play a random song.  If you queue a song while there are no queued songs, the song playing will be immediately interrupted by the song you have queued (can be disabled in config.yml).


## Listening to the Radio

You can use a builtin flash player to listen to the radio in-browser.  Otherwise, you can stream it into the player of your choice.  The stream URL can be found as the "Stream" link on the top right corner of the "Now Playing" box.

In Winamp:
  Press Ctrl+L, paste the URL into the box that appears, and press OK.
  
In iTunes:
  Go to Advanced->Open Stream in the menu, paste the URL into the box that appears, and press OK.  This will create an entry in the Library for this stream, with the name of whatever you specified as [radio_name] in config.yml.

In Windows Media Player:
  Press Ctrl+U, paste the URL into the box that appears, and press OK.

In Amarok:
  Press Ctrl+O, paste the URL into the box that appears, and press OK.  The stream will appear at the end of your current playlist, double click its name to play it.
