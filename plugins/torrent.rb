class Torrent < Plugin
	
	def init
		server.require_3rdparty("rubytorrent")
	end
	
	def add_torrent
		if params["address"] && server.settings.upload_path && server.settings.tmpdir
			@torrents = server.restore("torrent", "torrents")
			if !@torrents
				@torrents = Hash.new
				server.store("torrent", "torrents", @torrents)
			end
			if !@torrents.has_key?(params["address"])
				begin
					mi = RubyTorrent::MetaInfo.from_location(params["address"])
					dir = Dir.pwd
					Dir.chdir(server.settings.upload_path)
					package = RubyTorrent::Package.new(mi, nil)
					Dir.chdir(dir)
					bt = RubyTorrent::BitTorrent.new(mi, package, :port => server.settings.bittorrent_port, :dlratelim => (server.settings.bittorrent_download_limit ? server.settings.bittorrent_download_limit.to_i : nil), :ulratelim => (server.settings.bittorrent_upload_limit ? server.settings.bittorrent_upload_limit.to_i : nil))
					bt.on_event(self, :complete){ remove_complete }
					@torrents[params["address"]] = bt
				rescue Exception => e
					#puts "Failed to load torrent: #{e.message}"
				end
			end
		end
		render(html("torrents"))
	end
	
	def method_allowed?(method_name, role)
		return role == "admin"
	end
	
	def remove_torrent
		@torrents = server.restore("torrent", "torrents")
		if params["torrent"] && @torrents
			bt = @torrents[params["torrent"]]
			if bt
				bt.shutdown
			end
			@torrents.delete(params["torrent"])
		end
		render(html("torrents"))
	end
	
	def render_remove_complete
		remove_complete
		refresh_torrents
	end
	
	def refresh_torrents
		@torrents = server.restore("torrent", "torrents")
		render(html("torrents"))
	end
	
	def remove_complete
		completed = Array.new
		torrents = server.restore("torrent", "torrents")
		torrents.each_pair do | name, torrent |
			completed.push(name) if torrent.complete?
		end
		completed.each do | complete |
			torrent = torrents[complete]
			torrents.delete(complete)
		end
		if completed.size > 0
			if !Common.array_part_of_string?(server.collection.scanned_paths, server.settings.upload_path) 
				server.collection.add_scan_path(server.settings.upload_path)
				server.collection.scan_path(server.settings.upload_path)
			elsif !server.collection.inotify_enabled?
				server.collection.scan_path(server.settings.upload_path)
			end
		end
	end
	
	def enabled
		return false #RUBY_VERSION < '1.9' && server.settings.upload_path && server.settings.tmpdir
	end
	
	def nice_name
		"Torrents"
	end
	
	def html_methods
		{"Torrents" => "index"}
	end
	
	def index
		
	end
end
