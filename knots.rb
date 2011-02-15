#!/usr/bin/env ruby
require 'webrick'
require 'webrick/https'
require 'fileutils'

include WEBrick

class Knots < WEBrick::HTTPServer
	ITEM_TYPE_VIDEO = 0
	ITEM_TYPE_AUDIO = 1
	ITEM_TYPE_VDR = 2
	ITEM_TYPE_MYTHTV = 3
	ITEM_TYPE_DREAMBOX = 4
	ITEM_TYPE_DBOX2 = 10
	ITEM_TYPE_DVD_DIR = 5
	ITEM_TYPE_DVD_IMAGE = 6
	ITEM_TYPE_DVD_DISC = 7
	ITEM_TYPE_IMAGE = 8
	ITEM_TYPE_URL = 9
	
	attr_accessor :force_auth
	
	def initialize
		set_globals
		Dir.chdir(@knots_dir)
		load_libs
		load_database
		load_settings
		load_logger
		startup_message
		load_mimes
		load_collection
		load_storage
		Socket.do_not_reverse_lookup = true
		load_discovery
		load_users
		start_vlc
		load_auth
		super(webrick_settings)
		load_plugins
		trap_signals
		dynknots_update
		@ssl = settings.webrick_ssl.to_i == 1
		@port = settings.webrick_port.to_i
		status_message
	end
	
	def set_globals
		@usercount = 0
		force_auth = false
		@started = Time.now
		@auth=nil
		@knots_dir = File.expand_path(File.dirname(__FILE__))
		if RUBY_VERSION >= "1.9.2"
			$LOAD_PATH.push(@knots_dir) if !$LOAD_PATH.include?(@knots_dir)
		end
		@dynknots_updating = false
		@cache = Hash.new
		@cache_enabled = true
	end
	
	def startup_message
		puts("")
		log("Welcome to Knots - http://wiki.maemo.org/Knots2", 0, true)
		log("Starting Knots in #{@knots_dir} with ruby #{RUBY_VERSION}", 0, true)
		log("Settings for Knots:\n\nYou can change these settings from the command line with #{!Common.windows_os? ? "./scripts/setup setting value" : "ruby\\bin\\ruby.exe scripts\\setup setting value"}\n\n#{Common.humanize_hash(settings, false, "\t")}\n\n", 0, true) if settings.devel && settings.devel.to_i == 1
	end
	
	def status_message
		log("You can access the server with http#{settings.webrick_ssl && settings.webrick_ssl.to_i == 1 ? "s" : ""}://#{settings.webrick_host && settings.webrick_host != "0.0.0.0" && settings.webrick_host != "*" ? settings.webrick_host : "localhost"}:#{settings.webrick_port}", 0, true)
		log("Press ctrl-c to close the server", 0, true)
	end
	
	def trap_signals
		signals = ["INT", "TERM"]
		signals += ["QUIT", "HUP"] if !Common.windows_os?
		signals.each do | signal |
			trap(signal) do
				close_server if !@closing
			end
		end
	end
	
	def load_libs
		require 'lib/session'
		require 'lib/plugin'
		require 'lib/db'
		require 'digest/md5'
		if RUBY_VERSION < "1.9"
			require 'lib/ohash'
			$KCODE = "U"
		else
			require 'lib/ohash2'
		end
		require 'lib/collection'
		require 'lib/common'
		require 'lib/discovery'
		require 'lib/vlc'
		require_3rdparty 'facter'
	end
	
	def knots_dir
		@knots_dir
	end
	
	def enable_cache(enable)
		current = @cache_enabled 
		@cache_enabled = enable
		return current
	end
	
	
	def require_3rdparty(name)
		begin
			require name
		rescue Exception => e
			path = File.join(@knots_dir, "lib", "other", name)
			$LOAD_PATH.push(path) if !$LOAD_PATH.include?(path)
			require name
		end
	end
	
	def ssl?
		return @ssl
	end
	
	def port
		return @port
	end
	
	def dynknots_address
		@dynknots_address
	end
	
	def dynknots_update(force = false)
		@dynknots_updating = false if force
		if !@dynknots_updating
			if settings.dynknots_key
				@dynknots_updating = true
				Thread.new do
					while true
						if !settings.dynknots_last_update || Time.now.to_f - settings.dynknots_last_update.to_f > 7180
							begin
								data = Common.fetch("http://nakkiboso.com/knots2/dynknots.php?action=update&code=#{settings.dynknots_key}&port=#{settings.webrick_port}&ssl=#{settings.webrick_ssl.to_i == 0 ? "false" : "true"}&name=#{CGI::escape(settings.server_name)}").body
								if data && data.strip == "OK"
									update = db.settings.by_key("dynknots_last_update").first || db.settings.new
									update.key = "dynknots_last_update"
									update.value = Time.now.to_f.to_s
									update.save
									load_settings
									log("Dynknots updated.", 2)
								else
									errorcodes = {
										"ERROR0" => "Please fill all the field.",
										"ERROR1" => "Username is already taken. Please login or create a new account.",
										"ERROR3" => "Login failed.",
										"ERROR99" => "Service database error. Please try again later."
									}
									log("Dynknots not updated: #{data ? (errorcodes[data] || data) : "Unknown error"}", 2)
								end
							rescue Exception => ex
								log("Dynknots not updated. #{ex.message}", 2)
							end
						else
							log("Skipping dynknots update.", 2)
						end
						@dynknots_address = get_current_dynknots_address
						sleep 7200
					end
				end
			end
		end
	end
	
	def start_vlc
		@vlc = VLC.new(self)
	end
	
	def load_discovery
		@discover = Discovery.new(self)
	end
	
	def load_storage
		@storage = Hash.new
	end
	
	def store(plugin, key, value)
		@storage[plugin] = Hash.new if !@storage[plugin]
		@storage[plugin][key] = value
	end
	
	def restore(plugin, key)
		@storage[plugin][key] if @storage[plugin]
	end
	
	def load_users
		@users = OrderHash.new
		db.users.all.each do | user |
			rights = OrderHash.new
			if user.role && user.role.to_i == 1
				categories = Array.new
				media = Array.new
				categories.push(-1)
				media.push(-1)
				db.rights.sql("SELECT category FROM rights WHERE user=#{user.id} AND category IS NOT NULL").each do | right |
					categories.push(right.category)
				end
				db.rights.sql("SELECT media FROM rights WHERE user=#{user.id} AND media IS NOT NULL").each do | right |
					media.push(right.media)
				end
				rights.categories = categories.join(",")
				rights.media = media.join(",")
				rights.role = "guest"
				rights.guest = true
				rights.admin = false
			else
				rights.role = "admin"
				rights.guest = false
				rights.admin = true
			end
			@users[user.user] = rights
		end
		@usercount = db.users.sql("SELECT id FROM users WHERE temporary IS NULL").size
	end
	
	def usercount
		@usercount
	end
	
	def get_user(user)
		return @users[user]
	end
	
	def load_mimes
		WEBrick::HTTPUtils::DefaultMimeTypes["swf"] = "application/x-shockwave-flash"
		WEBrick::HTTPUtils::DefaultMimeTypes["ico"] = "image/vnd.microsoft.icon"
		if defined?(WEBrick::HTTPResponse::BUFSIZE) && WEBrick::HTTPResponse::BUFSIZE < 16384
			log("Setting bigger buffer size, ignore the following two warnings", 0, true)
			WEBrick::HTTPResponse.const_set(:BUFSIZE, 16384)
			WEBrick::HTTPRequest.const_set(:BUFSIZE, 16384)
			log("Enabling BIGINT for XMLRPC, ignore the following warning", 0, true)
			XMLRPC::Config.const_set(:ENABLE_BIGINT, true)
		end
	end
	
	def vlc
		@vlc
	end
	
	def player(id = nil)
		@vlc.player(id)
	end
	
	def players
		@vlc.players
	end
	
	def load_database
		@database = Common.load_database
	end
	
	def load_plugins
		load "lib/plugin.rb" if RUBY_VERSION < "1.9.0"
		load "lib/common.rb"
		load "lib/collection.rb"
		load "lib/player.rb"
		load "lib/vlc.rb"
		@plugins = OrderHash.new
		Dir.entries("plugins").delete_if{|filename| File.extname(filename).downcase != ".rb"}.sort.each do | plugin |
			load File.join("plugins", plugin)
			require File.join("plugins", File.basename(plugin, ".*"))
			class_name = File.basename(plugin.scan(/[a-z.]/i).flatten.join, ".*").capitalize
			cls = Object.const_get(class_name).new(self)
			if cls.enabled
				cls.init
				@plugins[cls.plugin_name] = cls
				mount_point = class_name != "Root" ? "/#{class_name.downcase}" : "/"
				mount(mount_point, cls.class)
			end
		end
	end
	
	def load_auth
		if settings.webrick_ssl == "1" || (settings.force_auth && settings.force_auth == "1")
			admin = db.users.sql("SELECT * FROM users WHERE temporary IS NULL AND role = 0").first
			if !admin
				log("Disabling auth, no admin users", 0, true)
				disable_auth
				return
			end
			users = db.users.all
			
			if users.size > 0
				a = WEBrick::HTTPAuth::BasicAuth
				userdb = Hash.new
				userdb.extend(WEBrick::HTTPAuth::UserDB)
				userdb.auth_type = a
				realm = "Knots"
				users.each do | user |
					userdb.set_passwd(realm, user.user, user.pass)
				end
				@auth = a.new({
					:Realm        => realm,
					:UserDB       => userdb,
					:NonceExpirePeriod   => 60,
					:NonceExpireDelta    => 5,
				})
				log("Auth enabled. #{users.size} user(s).")
			else
				disable_auth
				log("Auth not enabled. 0 users.")
			end
		end
	end
	
	def auth
		@auth
	end
	
	def disable_auth
		@auth = nil
	end
	
	def load_file(filename)
		data = @cache[filename]
		if !data
			data = Common.load_file(filename)
			if (!settings.devel || settings.devel.to_i == 0) && @cache_enabled
				@cache[filename] = data if data && data.length < 50000
			end
		end
		data
	end
	
	def load_logger
		@log = Log.new(File.join(config_dir, "knots.log"), settings.log_level.to_i)
	end
	
	def log(str, log_level = 1, output = false)
		@log.log(log_level, str)		
		if output || (settings.devel && settings.devel.to_i == 1 && log_level <= settings.log_level.to_i)
			puts "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] #{str}"
		end
	end
	
	def load_collection
		@collection = Collection.new(self)
	end
	
	def started
		@started
	end
	
	def webrick_settings
		return {:DoNotReverseLookup => 0, :Port => settings.webrick_port, :SSLCertName => [ ["CN", settings.webrick_ssl_host || WEBrick::Utils::getservername] ], :SSLVerifyClient => ::OpenSSL::SSL::VERIFY_NONE, :SSLEnable => settings.webrick_ssl.to_i == 1, :SSLCertificate => OpenSSL::X509::Certificate.new(File.open(File.join(@knots_dir, "cert", "server.crt")).read), :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.open(File.join(@knots_dir, "cert", "server.key")).read), :ServerType => (!settings.webrick_daemon || settings.webrick_daemon.to_i != 1) ? WEBrick::SimpleServer : WEBrick::Daemon, :BindAddress => settings.webrick_host == "*" ? "" : settings.webrick_host,:Logger => @log, :AccessLog => [[ File.open(File.join(config_dir, "knots_access.log"), 'w'), AccessLog::COMBINED_LOG_FORMAT ]]}
	end
	
	def load_settings
		@settings = database.settings.all.combine("key", "value")
	end
	
	def settings
		@settings
	end
	
	def collection
		@collection
	end
	
	def plugins
		@plugins
	end
	
	def config_dir
		return Common.config_dir
	end
	
	def database
		@database
	end
	
	alias :db :database
	
	def close_server
		@closing = true
		log("Shutdown in progress. Please wait.", 0, true)
		begin
			Timeout.timeout(15) do
				begin
					shutdown
					@vlc.stop_vlc(true)
					@collection.logout_opensubtitles
					minutes = ((Time.now - @started) / 60).to_i
					log("Clean shutdown. Knots ran for #{minutes} minute#{minutes != 1 ? "s" : ""}.", 0, true)
				rescue Exception => ex
					log("Knots did not close in time. Forcing shutdown.", 0, true)
					Process.exit!
				end
			end
		end
	end
	
	def get_current_dynknots_address
		begin
			data = Common.fetch("http://nakkiboso.com/knots2/dynknots.php?action=resolve&code=#{CGI::escape(settings.dynknots_key)}").body
			return data.strip if data && data.index("/")
		rescue Exception => ex
		end
		nil
	end
end
