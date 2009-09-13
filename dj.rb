#!/usr/local/bin/ruby

require 'rubygems'
require 'logger'
require 'yaml'

require 'shout'
require 'sqlite3'

class DJ

  def initialize
    @config = YAML::load_file('config.yml')
    @log_folder = File.join(File.expand_path(File.dirname(__FILE__)), "log")
    @db_folder = File.join(File.expand_path(File.dirname(__FILE__)), "db")
  
    @shout = Shout.new
    @shout.host = @config["icecast"]["server"]
    @shout.port = @config["icecast"]["port"]
    @shout.user = @config["icecast"]["username"]
    @shout.pass = @config["icecast"]["password"]
    @shout.mount = @config["icecast"]["mount"]
    @shout.name = @config["radio_name"]
    # format can be changed per-song, but defaults to MP3
    @shout.format = Shout::MP3
    
    FileUtils.mkdir_p(@db_folder)
    @db = SQLite3::Database.new(File.join(@db_folder, "rubedo.db"))
    @db.busy_timeout(200)
    
    @mode = :user
    
    if @config["dj_log_file"] and @config["dj_log_file"].any?
      FileUtils.mkdir_p(@log_folder)
      @log = Logger.new(File.join(@log_folder, @config["dj_log_file"]), 'daily')
      @log.info("DJ started, begin logging.")
    end
  end

  def start
    connect
    play_songs
  end

  def connect
    begin
      @shout.connect
    rescue
      log.fatal "Couldn't connect to Icecast server." if log
      exit
    end
  end

  def play_songs
    loop do
      song = next_song!
      if song
        play song
        mark_done! song
      else
        play random_song
      end
    end
  end
  
  def play(song)
    # a nil song means there are no songs at all, so just slowly loop until one comes along
    if song.nil?
      sleep 500
      return nil
    end
    
    id, path, title = song
    song_path = File.join music_folder, path
    
    unless File.exists?(song_path)
      log.error "File didn't exist, moving on to the next song.  Full path was #{song_path}" if log
      return
    end
    
    # set MP3 or OGG format
    format = @shout.format
    case File.extname(path)
    when ".mp3"
      format = Shout::MP3
    when ".ogg"
      format = Shout::OGG
    else
      format = Shout::MP3
    end
    if format != @shout.format
      log.info "Switching stream formats, re-connecting." if log
      @shout.disconnect
      @shout.format = format
      @shout.connect
    end
    
    # allow interrupts?
    seek_interrupt = (@mode == :dj and @config["interrupt_empty_queue"])
    
    File.open(song_path) do |file|
      # set metadata (MP3 only)
      if @shout.format == Shout::MP3
        metadata = ShoutMetadata.new
        metadata.add 'song', title
        metadata.add 'filename', File.basename(path)
        @shout.metadata = metadata
      end
      
      log.info "Playing #{title}!" if log
      while data = file.read(16384)
        begin
          @shout.send data
          break if seek_interrupt and next_song
          @shout.sync
        rescue
          log.error "Error connecting to Icecast server.  Don't worry, reconnecting." if log
          @shout.disconnect
          @shout.connect
        end
      end
    end
  end
  
  # takes a random song off of the filesystem, making this source client independent of any web frontend
  def random_song
    @mode = :dj
    
    wd = Dir.pwd
    Dir.chdir music_folder
    songs = Dir.glob("**/*.{mp3,ogg}")
    path = songs[rand(songs.size)]
    Dir.chdir wd
    
    if path.blank?
      nil
    else
      [0, path, quick_title(path)]
    end
  end
  
  # This returns the filename of the next song to be played.  By default, it will NOT also set this as the next song to be played.  To do this, call next_song!
  def next_song(set_as_playing = false)
    @mode = :user
    
    play_id, filename, title, song_id = nil
    begin
      # this query will get a song which was cut off while playing first, and failing that, will get the next song on the queue which hasn't been played
      play_id, filename, title, song_id = db.get_first_row "select id, filename, title, song_id from rubedo_plays where queued_at IS NOT NULL order by queued_at asc limit 1"
      return nil unless play_id
    rescue
      log.error "Error at some point during finding #{'(and setting) ' if set_as_playing}next song.  Filename was: #{filename}\n#{$!}" if log
      return nil
    end

    mark_start!(play_id, song_id) if set_as_playing
    
    [play_id, filename, title]
  end
  
  def next_song!
    next_song(true)
  end
  
  # these functions are only called when the song was queued by a user (@mode == :user)
  def mark_start!(play_id, song_id)
    begin
      db.execute("update rubedo_plays set played_at = ?, queued_at = NULL WHERE id = ?", Time.now, play_id)
      count = db.get_first_value("select play_count from rubedo_songs where id = ?", song_id)
      db.execute("update rubedo_songs set last_played_at = ?, play_count = ?", Time.now, count + 1)
    rescue
      log.error "Error during marking a song as beginning.  Song ID: #{song_id}"
    end
  end
  
  def mark_done!(song)
    begin
      db.execute("delete from rubedo_plays where id = ?", song[0])
    rescue 
      log.error "Error marking song as done. Play ID: #{song[0]}"
    end
  end
  
  # getting the title of a song we may not have an entry for
  def quick_title(song)
    File.basename(song, File.extname(song)).gsub(/^[^A-Za-z]+\s+(\w)/, "\\1")
  end
  
  def log; @log; end
  def db; @db; end
  
  def music_folder
    music = @config["music_folder"]
    File.exists?(music) ? music : "./music"
  end
  
end

DJ.new.start if __FILE__ == $0