#!/usr/local/bin/ruby

require 'yaml'
require 'fileutils'
require 'rubygems'
require 'sqlite3'
require 'camping'
require 'id3/id3'

Camping.goes :Rubedo

module Rubedo
  def self.config
    @config ||= YAML::load_file('config.yml')
  end
  
  def self.create
    Models.create_schema
    puts "Flushing out old songs, probably won't take long..."
    Helpers.flush_songs
    puts "Initializing database with any new songs, could take a while..."
    Helpers.scour_songs
    Models::Play.delete_all("queued_at IS NULL")
  end
  
  WEB_FOLDER = File.join(File.expand_path(File.dirname(__FILE__)), "web")
  LOG_FOLDER = File.join(File.expand_path(File.dirname(__FILE__)), "log")
  DB_FOLDER = File.join(File.expand_path(File.dirname(__FILE__)), "db")
  
  MUSIC_FOLDER = File.exists?(config["music_folder"]) ? config["music_folder"] : "./music"
  RADIO_NAME = config["radio_name"]
  PUBLIC_STREAM_SUFFIX = ":#{config['icecast']['port']}#{config['icecast']['mount']}"
end

module Rubedo::Models
  class Song < Base
    validates_presence_of :filename, :title
    
    def self.available(filter = nil)
      if filter.blank?
        Song.find :all, :order => "upper(title) asc"
      else
        Song.find :all, :conditions => ["title like ? or title like ? or filename like ? or filename like ? or filename like ?", "#{filter}%", "% #{filter}%", "#{filter}%", "% #{filter}%", "%\/#{filter}%"], :order => "upper(title) asc"
      end
    end
  end
  
  class Play < Base
    belongs_to :song
    validates_presence_of :filename, :title
    def self.now_playing; (Play.find :first, :conditions => 'played_at IS NOT NULL', :order => 'played_at desc', :limit => 1); end
    def self.next_up; (Play.find :all, :conditions => 'queued_at IS NOT NULL', :order => 'queued_at asc'); end
  end

  class CreateTables < V 0.4
    def self.up
      create_table :rubedo_songs do |t|
        t.column :id, :integer
        t.column :filename, :text
        t.column :title, :text
        t.column :play_count, :integer, :default => 0
        t.column :last_played_at, :datetime
      end
      create_table :rubedo_plays do |t|
        t.column :id, :integer
        t.column :filename, :text
        t.column :title, :text
        t.column :song_id, :integer
        t.column :queued_at, :datetime
        t.column :played_at, :datetime
      end
    end
  end
end

module Rubedo::Controllers
  class Index < R '/'
    def get
      # scour songs every time someone visits the index
      Rubedo::Helpers.scour_songs
    
      (@now_playing, @next_up) = [Play.now_playing, Play.next_up]
      @available = Song.available
      render :home
    end
  end
  
  class Songs < R '/song/(\d+)'
    # Queues a song, and returns the updated queue partial
    def post(id)
      if @song = Song.find_by_id(id)
        Play.create(:song => @song, :filename => @song.filename, :title => @song.title, :queued_at => Time.now)
      end
      
      @next_up = Play.next_up
      render :_queue
    end
  end
  
  class Plays < R '/play/(\d+)/delete'
    # deletes a play from the queue, returns the updated queue partial
    def post(id)
      if @play = Play.find_by_id(id)
        @play.destroy
      end
      
      @next_up = Play.next_up
      render :_queue
    end
  end
  
  # Partial feeder
  class Partial < R '/partial/(\w+)'
    def get(partial)
      case partial
      when "queue"
        @next_up = Play.next_up
        render :_queue
      when "now_playing"
        @now_playing = Play.now_playing
        render :_now_playing
      when "radio"
        @now_playing = Play.now_playing
        @next_up = Play.next_up
        render :_radio
      when "available"
        @available = Song.available(@input[:filter])
        render :_available
      end
    end
  end
  
  # Sends a song directly from the music directory
  # Will only work if the song is currently playing
  class Download < R '/download/(.*)'
    def get(filename)
      if Rubedo.config["allow_download"] and filename and File.exists?(File.join(MUSIC_FOLDER, filename)) and filename == Play.now_playing.filename
        case File.extname(filename)
        when ".mp3"
          @headers['Content-Type'] = 'audio/x-mp3'
        when ".ogg"
          @headers['Content-Type'] = 'application/ogg'
        end
        @headers['Content-Disposition'] = "attachment;filename=\"#{filename}\""
        File.read(File.join(MUSIC_FOLDER, filename))
      else
        redirect Index
      end
    end
  end
  
  # All Rubedo-specific Javascript is contained at the bottom of this file
  class Javascript < R '/rubedo.js'
    def get
      @headers['Content-Type'] = 'text/javascript'
      File.read(__FILE__).gsub(/.*__END__/m, '')
    end
  end
  
  # catch all, make /web folder public
  class Public < R '/([\w\.]+)'
    def get(file)
      redirect Index unless File.exists?(File.join(WEB_FOLDER, file))
      
      case File.extname(file)
      when ".js"
        @headers['Content-Type'] = 'text/javascript'
      when ".css"
        @headers['Content-Type'] = 'text/css'
      when ".gif"
        @headers['Content-Type'] = 'image/gif'
      when ".swf"
        @headers['Content-Type'] = 'application/x-shockwave-flash'
      when ".ico"
        @headers['Content-Type'] = 'image/vnd.microsoft.icon'
      else
        @headers['Content-Type'] = 'text/plain'
      end
      #@headers['X-Sendfile'] = File.join(WEB_FOLDER, file)
      File.read(File.join(WEB_FOLDER, file))
    end
  end
  
end

module Rubedo::Views
  def layout
    html do
      head do
        title Rubedo::RADIO_NAME
        link :href => "/rubedo.css", :rel => 'stylesheet', :type => 'text/css'
        text "<!--[if lte IE 7]>"
        style :type => 'text/css' do
          %Q{
            #radio #queue div.list {height: 350px;}
            #songs div.list {height: 525px;}
          }
        end
        text "<![endif]-->"
        link :href => R(Public, "favicon.ico"), :rel => 'shortcut icon'
        script :type => "text/javascript", :src => R(Javascript)
        script :type => "text/javascript", :src => "/mootools.js"
      end
      body :onload => "poll();" do
        div :id => "title" do
          a Rubedo::RADIO_NAME, :href => R(Index)
        end
        div @flash, :id => "flash" if @flash
        div :id => "main" do
          self << yield
        end
        div :id => "footer" do
          text "<a href='http://www.thoughtbot.com/projects/rubedo'>Rubedo</a> is powered by <a href='http://code.whytheluckystiff.net/camping' title='(A Microframework)'>Camping</a>. (c) 2008"
        end
      end
    end
  end
  
  def home
    div :id => "songs" do
      div.header do
        div.title {text "Songs"}
        div.search do
          img :id => "spinner", :src => R(Public, "spinner.gif")
          span "Find"
          input :type => "text", :size => "15", :onkeyup => "filter();", :id => "search"
        end
      end
      div :id => "available" do
        _available
      end
    end
    
    div :id => "radio" do
      _radio
    end
  end
  
  def _radio
    div :id => "playing" do
      div.banner do
        div.now "Now Playing"
        div.links do
          div do
            _ice
          end
          div.middle do text " &#149; " end
          div do
            a "Stream", :href => "http://#{@env['SERVER_NAME']}#{Rubedo::PUBLIC_STREAM_SUFFIX}"
          end
        end
      end
      div :id => 'now_playing' do 
        _now_playing
      end
    end
  
    div :id => "queue" do
      _queue
    end
  end
  
  def _queue
    div.queue @next_up.any? ? "Queued" : "Queue is currently empty."
    div.list do
      @next_up.each_with_index do |play, i|
        cycle = i % 2 == 0 ? 'dark' : 'light'
        format = File.extname(play[:filename]) == ".ogg" ? "ogg" : "mp3"
        div :class => "queued #{cycle} #{format}" do
          span.title truncate("#{play.title}", 65)
          a.delete :onclick => "unqueue(#{play.id}); return false", :href => "#" do
            img :src => R(Public, "delete.gif")
          end
          span.queued "#{time_ago(play.queued_at)} ago "
        end
      end
    end
  end
  
  def _now_playing
    if @now_playing
      if Rubedo.config["allow_download"]
        a @now_playing.title, :href => R(Download, @now_playing.filename)
      else
        a @now_playing.title
      end
    else
      text "&nbsp;"
    end
  end
  
  def _available
    @available.each_with_index do |song, i|
      cycle = i % 2 == 0 ? 'dark' : 'light'
      format = File.extname(song[:filename]) == ".ogg" ? "ogg" : "mp3"
      div :class => "song #{cycle} #{format}" do
        a song[:title], :onclick => "queue('#{song.id}'); return false", :href => "#"
      end
    end
    if @available.empty?
      br
      span.insufficient "No songs found."
    end
  end
  
  def _ice
    object :width => "20", :height => "19", :data => "ice.swf?StreamURL=http://#{@env['SERVER_NAME']}#{Rubedo::PUBLIC_STREAM_SUFFIX}", :type => "application/x-shockwave-flash" do
      param :name => "src", :value => "ice.swf?StreamURL=http://#{@env['SERVER_NAME']}#{Rubedo::PUBLIC_STREAM_SUFFIX}"
    end
  end
  
end

module Rubedo::Helpers
  # Find any songs in the music directory that Rubedo doesn't know about and add them to the table
  def self.scour_songs
    # Do one database query now and make a hash, to keep this function O(n)
    songs = Rubedo::Models::Song.find(:all).inject({}) do |files, song| 
      files[song.filename] = 1
      files
    end
    wd = Dir.pwd
    Dir.chdir Rubedo::MUSIC_FOLDER
    Dir.glob("**/*.{mp3,ogg}").each do |filename|
      unless songs[filename]
        begin
          Rubedo::Models::Song.create(:title => song_title(filename), :filename => filename)
          puts "Added #{filename} to database."
        rescue 
          puts "Error adding #{filename} to database, moving on."
        end
      end
    end
    Dir.chdir wd
  end
  
  # Delete any entries in the database which refer to songs which have been removed from the music folder
  def self.flush_songs
    songs = Rubedo::Models::Song.find(:all)
    songs.each do |song|
      unless File.exists?(File.join(Rubedo::MUSIC_FOLDER, song.filename))
        song.destroy
        Rubedo::Models::Play.find(:all, :conditions => ["song_id = ?", song.id]).each {|play| play.destroy}
        
        puts "Flushed #{song.filename} from database."
      end
    end
  end

  def self.song_title(path)
    return nil unless path
    # quick title for oggs
    unless path.match(/\.mp3$/)
      return File.basename(path, File.extname(path)).gsub(/^[^A-Za-z]+\s+(\w)/, "\\1")
    end
    
    m = ID3::AudioFile.new(path)
    
    title, artist, song_title = [nil] * 3
    if m.tagID3v2 and m.tagID3v2.any?
      if m.tagID3v2["ARTIST"] and m.tagID3v2["ARTIST"]["encoding"] and m.tagID3v2["ARTIST"]["encoding"] == 0
        artist = m.tagID3v2["ARTIST"]["text"] if m.tagID3v2["ARTIST"]["text"]
      end
      if m.tagID3v2["TITLE"] and m.tagID3v2["TITLE"]["encoding"] and m.tagID3v2["TITLE"]["encoding"] == 0
        song_title = m.tagID3v2["TITLE"]["text"] if m.tagID3v2["TITLE"]["text"]
      end
    end
    if artist.nil? and title.nil? and m.tagID3v1 and m.tagID3v1.any?
      artist = m.tagID3v1["ARTIST"] if m.tagID3v1["ARTIST"]
      song_title = m.tagID3v1["TITLE"] if m.tagID3v1["TITLE"]
    end
    title = "#{artist} - #{song_title}" if artist and song_title
    
    # Fall back on the filename with the extension stripped, and any leading numbers/punctuation stripped
    title ||= File.basename(path, File.extname(path)).gsub(/^[^A-Za-z]+\s+(\w)/, "\\1")
    
    title
  end
  
  # This is a much stripped down version of ActionView's time_ago_in_words, credit goes solidly to David Heinemeier Hanssen.
  def time_ago(from_time)
    to_time = Time.now
    distance_in_minutes = (((to_time - from_time).abs)/60).round
    distance_in_seconds = ((to_time - from_time).abs).round

    case distance_in_minutes
      when 0          then 'less than a minute'
      when 1          then '1 minute'
      when 2..45      then "#{distance_in_minutes} minutes"
      when 46..90     then '1 hour'
      when 90..1440   then "#{(distance_in_minutes.to_f / 60.0).round} hours"
      else                 'over a day'
    end
  end
  
  # Also stolen from ActionView.
  def truncate(text, length = 30, truncate_string = "...")
    if text.nil? then return end
    l = length - truncate_string.chars.length
    (text.chars.length > length ? text.chars[0...l] + truncate_string : text).to_s
  end
end

# This code will be run if rubedo is run using "ruby rubedo.rb", but not when run using "camping rubedo.rb"
if __FILE__ == $0
  
  config = Rubedo.config
  
  config["frontend_port"] ||= 80
  config["start_source_client"] = true if config["start_source_client"].nil?
  
  FileUtils.mkdir_p(Rubedo::LOG_FOLDER)
  FileUtils.mkdir_p(Rubedo::DB_FOLDER)
  
  Rubedo::Models::Base.establish_connection :adapter  => "sqlite3", :database => File.join(Rubedo::DB_FOLDER, "rubedo.db"), :timeout => 200
  Rubedo::Models::Base.logger = Logger.new(File.join(Rubedo::LOG_FOLDER, config["frontend_log_file"])) unless config["frontend_log_file"].blank?
  
  Rubedo.create
  
  server_type = nil
  server = nil
  begin
    require 'mongrel'
    require 'mongrel/camping'
    server_type = :mongrel
    #server = Mongrel::Camping::start("0.0.0.0", config["frontend_port"], "/", Rubedo)
    server = Mongrel::HttpServer.new("0.0.0.0", config["frontend_port"])
    server.register("/", Mongrel::Camping::CampingHandler.new(Rubedo))
    
    puts "** Rubedo is running at http://localhost:#{config['frontend_port']}"
  rescue LoadError 
    require 'webrick/httpserver'
    require 'camping/webrick'
    server_type = :webrick
    server = WEBrick::HTTPServer.new :BindAddress => "0.0.0.0", :Port => config["frontend_port"]
    server.mount "/", WEBrick::CampingHandler, Rubedo
  end  
  
  dj = nil
  if config["start_source_client"]
    # Spawn the source client process on its own
    dj = Process.fork do
      require 'dj'
      DJ.new.start
    end
  end
  
  if server_type == :mongrel
    [:INT, :TERM].each {|sig| trap(sig) {server.stop}}
    server.run.join
  elsif server_type == :webrick
    [:INT, :TERM].each {|sig| trap(sig) {server.shutdown}}
    server.start  
  end
  
  # kill source client upon exit if we are tied to it
  Process.kill("KILL", dj) if dj
end

__END__
function poll() {
  setInterval("var check_now = new Ajax('/partial/now_playing', {update: 'now_playing', method: 'get'}).request();", 5000);
  setInterval("var check_queue = new Ajax('/partial/queue', {update: 'queue', method: 'get'}).request();", 5000);
}
function queue(id) {var res = new Ajax('/song/' + id, {update: 'queue', method: 'post'}).request();}
function unqueue(id) {var res = new Ajax('/play/' + id + '/delete', {update: 'queue', method: 'post'}).request();}

function filter() {
  search = $("search");
  if (search.zid) 
    clearTimeout(search.zid);
  
  if (last_search != search.value) {
    search.zid = setTimeout(function() {
      $('spinner').style.display = "inline";
      var filter = new Ajax("/partial/available?filter=" + $('search').value, {update: 'available', method: 'get', onComplete: function() {$('spinner').style.display = "none";}}).request();
    }, 500);
    last_search = search;
  }
}

last_search = "";