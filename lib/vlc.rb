require 'net/telnet'
require 'lib/player'

class VLC
	
	def initialize(server)
		@updating = false
		@players = Hash.new
		@server = server
		@pidfile = File.join(server.config_dir, "vlc.pid")
		@info = OrderHash.new
		@looped = Hash.new
		start_vlc
	end
	
	def start_update
		if !@updating
			if @players.size > 0
				Thread.new do
					@updating = true
					while @updating
						update_info
						sleep 4
						@updating = @players.size > 0
						playerlist = players.values 
						playerlist.each do | player |
							if player.ended?
								player.stop	
							end
						end
					end
				end
			end
		end
	end
	
	def player(id = nil)
		if !id
			player = Player.new(self)
			id = player.player_id
			@players[id] = player
		end
		@players[id]
	end
	
	def players
		@players
	end
	
	def init(player_id)
		options = ["del #{player_id}", "new #{player_id} broadcast enabled", "setup #{player_id} option sout-keep", "setup #{player_id} option audio-filter=normalizer", "setup #{player_id} option volume=200"]
		if server.settings.subtitles?
			options += ["setup #{player_id} option sub-autodetect-fuzzy=3", "setup #{player_id} option sout-transcode-soverlay", "setup #{player_id} option freetype-yuvp"]
		end
		if server.settings.subtitle_font
			options += ["setup #{player_id} option freetype-font=\"#{server.settings.subtitle_font}\""]
		end
		if server.settings.subtitle_path
			options += ["setup #{player_id} option sub-autodetect-path=\"#{server.settings.subtitle_path}\""]
		end
		telnet_commands(options)
		update_info
	end
	
	def set_option(player_id, option, value = nil)
		telnet_commands("setup #{player_id} option #{option}#{value ? "=#{value}" : ""}")
	end
	
	def loop(player_id, looped)
		@looped[player_id] = looped
		telnet_commands("setup #{player_id} #{@looped[player_id] ? "loop" : "unloop"}")
	end
	
	def looped?(player_id)
		@looped[player_id] || false
	end
	
	def set_output(player_id, output)
		telnet_commands("setup #{player_id} output #{output}")
		update_info
	end
	
	def clear_playlist(player_id)
		telnet_commands("inputdel #{player_id} all")
		update_info
	end
	
	def server
		@server
	end
	
	def vlc_info
		@info
	end
	
	def play(player_id)
		telnet_commands("control #{player_id} play")
		update_info
		start_update
	end
	
	def stop(player_id)
		telnet_commands("control #{player_id} stop")
		telnet_commands("del #{player_id}")
		@players.delete(player_id)
		@looped.delete(player_id)
		players = @players.keys
		players.each do | player |
			@players.delete(player) if !vlc_info[player]
		end
		@updating = players.size > 0
	end
	
	def currently_playing(player_id)
		vlc_info[player_id].currently_playing
	end
	
	def playlistindex(player_id)
		vlc_info[player_id].playlistindex ? vlc_info[player_id].playlistindex.to_i : 1 
	end
	
	def play_playlist_item(player_id, index)
		telnet_commands("control #{player_id} play #{index}")
		update_info
	end
	
	def next_playlist_item(player_id)
		if playlistindex(player_id) && playlist(player_id)
			if playlistindex(player_id) < playlist(player_id).size
				telnet_commands("control #{player_id} play #{playlistindex(player_id) + 1}")
				update_info
			end
		end
	end
	
	def previous_playlist_item(player_id)
		if playlistindex(player_id) && playlist(player_id)
			if playlistindex(player_id) > 1
				telnet_commands("control #{player_id} play #{playlistindex(player_id) - 1}")
				update_info
			end
		end
	end
	
	def position(player_id)
		position = vlc_info[player_id].position
		if position
			return position.gsub(",", ".").to_f
		end
		nil
	end
	
	def duration(player_id)
		duration = vlc_info[player_id].duration
		if duration
			return duration.to_i / 1000000
		end
		nil
	end
	
	def position_percent(player_id)
		percent = position(player_id, info)
		if percent
			return percent * 100
		end
		nil
	end
	
	def started?(player_id)
		vlc_info[player_id] != nil && vlc_info[player_id].position != nil
	end
	
	def playlist(player_id)
		vlc_info[player_id].playlist
	end
	
	def seekable?(player_id)
		seekable = vlc_info[player_id].seekable
		seekable = seekable ? seekable.to_i == 1 : false
		return seekable
	end
	
	def running
		@running
	end
	
	def running_for_real
		response = server.settings.vlc ? telnet_commands("show", false, true) : ""
		return response != nil && response != ""
	end
	
	def add_to_playlist(player_id, filenames)
                filenames = [filenames] if filenames.instance_of?(String)
                filenames.collect!{|item| item = "input \"#{Common.is_dvd?(item) ? "dvdsimple://" : ""}#{item}\""}
                str = ""
                while filenames.size > 0
                        input = filenames.shift
                        if str.length + input.length + 1 < 1000
                                str += " #{input}"
                        else
                                telnet_commands(["setup #{player_id} #{str}"])  
                                str = " #{input}"
                        end
                end
                if str != ""
                        telnet_commands(["setup #{player_id} #{str}"])
                end
                update_info
        end
	
	def seek(client_id, position)
		telnet_commands("control #{client_id} seek #{position * 100}")
		update_info
	end
	
	def next_free_port
		vlc_info["next_free_port"]
	end
	
	def start_vlc
		if Common.windows_os?
			vlc_crashdata = File.join(ENV["appdata"], "vlc", "crashdump")
			begin
				FileUtils.rm_rf(vlc_crashdata) if File.writable?(vlc_crashdata) && File.exists?(vlc_crashdata)
				server.log("Removed VLC crashdump #{vlc_crashdata}")
			rescue Exception => ex
			end
		end
		if can_restart
			@running = false
			stop_vlc
			@vlc_startup = Time.now
			if server.settings.vlc && File.exists?(server.settings.vlc)
				Thread.new do
					cmd = "\"#{server.settings.vlc}\" -Vdummy --intf=#{server.settings.new_vlc && server.settings.new_vlc.to_i == 1 ? "old" : ""}telnet --telnet-host=localhost --telnet-port=4212 --telnet-password=knots"
					if !Common.windows_os?
						cmd +=" -d --pidfile=#{@pidfile} 2> /dev/null"
					else
						cmd += " --no-qt-privacy-ask --no-qt-error-dialogs"
					end
					server.log("Starting VLC with: #{cmd}")
					IO.popen(cmd)
					Process.wait
				end
				(server.settings.vlc_timeout ? server.settings.vlc_timeout.to_i : 10).times do | i |
					server.log("Waiting for VLC to start", 0, true)
					sleep 1
					if running_for_real
						server.log("VLC started properly", 0, true)
						@running = true
						@updating = false
						return true
					end
				end
				server.log("VLC failed to start properly. Knots will not work.", 0, true)
			else
				server.log("VLC path missing, so not starting it. Knots will not work.", 0, true)
			end
		end
		false
	end
	
	def can_restart
		return !@vlc_startup || Time.now - @vlc_startup > 6
	end
	
	def stop_vlc(force = false)
		telnet_commands("shutdown") if force
		@autorestart = !force
		pid = Common.load_file(@pidfile)
		if pid
			begin
				Process.kill(9, pid.to_i)
			rescue Exception => ex
			ensure
				FileUtils.rm(@pidfile)
			end
		end
	end
	
	def playback_started?(client_id)
		update_info
		return vlc_info[client_id] && vlc_info[client_id]["state"] == "playing"
	end
	
	private
	
	def update_info
		info = telnet_commands("show")
		@info = OrderHash.new
		if info
			info = info.split("\n")
			info.pop
			info = info.join("\n")
			clients = info.scan(/\n\s{8}(\S.*)\n/).flatten
			clients.size.times do | i |
				s = info.index(clients[i])
				e = i == clients.size - 1 ? info.size : info.index(clients[i + 1])
				data = info[s..(e-1)]
				@info[clients[i]] = OrderHash.new
				@info[clients[i]]["playlist"] = data.scan(/inputs(.*)output/m).flatten.first.strip.split("\n").collect!{|item| item = item.scan(/\d.:\s(.*)/i).flatten.first}
				data.scan(/instance(.*)/m).flatten.first.strip.split("\n").each do | option |
					option = option.split(":")
					if option.size == 2
						option[0] = "seekable" if option[0].strip == "can-seek"
						option[0] = "duration" if option[0].strip == "length"
						@info[clients[i]][option[0].strip] = option[1].strip
					end
				end
				@info[clients[i]]["currently_playing"] = @info[clients[i]].playlist[@info[clients[i]].playlistindex.to_i - 1] 
				ports = info.scan(/dst=.{0,}:(\d*)\//).flatten.collect!{|port| port = port.to_i}
				range_start = (server.settings.vlc_port_range_start ? server.settings.vlc_port_range_start.to_i : 19780)
				while ports.include?(range_start)
					range_start += 1
				end
				@info["next_free_port"] = range_start
			end
		else
			stop_updating
		end
	end
	
	def stop_updating
		if @updating
			@updating = false
			@players.each_key do | player |
				stop(player)
			end
			@players.clear
		end
	end
	
	def telnet_commands(cmdlist, quit = false, starting = false)
		cmdlist = [cmdlist] if cmdlist.instance_of?(String)
		server.log("VLC telnet commands: #{cmdlist.join(", ")}", 2)
		begin
			output = ""
			cmdlist.insert(0, "knots")
			cmdlist.push("quit")
			vlc_telnet = Net::Telnet::new("Host" => "localhost", "Timeout" => 10, "Port" => 4212)
			cmdlist.each do | cmd |
				if cmd.strip != ""
					val = vlc_telnet.cmd(cmd)
					output += val if val
				end
			end
			server.log("VLC telnet response: #{output}", 2)
			return output
		rescue Exception => e
			if e.message.index("connect(2)") || e.message.index("Connection refused") || e.message.index("timed out") || e.message.index("reset by peer")
				if !cmdlist.include?("shutdown") && !starting
					@running = false 
					if can_restart
						stop_updating
						server.log("VLC telnet error: #{e.message}", 0, true)
						if start_vlc
							server.log("VLC restart succesful", 0, true)
							return nil
						end
					end
				else
					return nil
				end
			end
			return nil
		ensure
			Common.close_io(vlc_telnet)
		end
	end
end
