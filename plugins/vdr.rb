class Vdr < Plugin
	
	def nice_name
		"VDR"
	end
	
	def html_methods
		{"EPG" => "epg"}
	end
	
	def index
		
	end
	
	def epg
		store("epg_data", OrderHash.new) if !restore("epg_data")
		i = 1
		while server.settings["vdr#{i}"] != nil
			fetch_epg(i, server.settings["vdr#{i}"].split(","))
			i += 1
		end
		@epg = restore("epg_data")
	end
	
	def epg_dates
		@dates = dates_for_channel(params["channel"], restore("epg_data")[params["vdr"].to_s.to_i])
	end
	
	def epg_programs
		@programs = programs_for_date(params["channel"], params["date"], restore("epg_data")[params["vdr"].to_s.to_i])
	end
	
	def enabled
		return server.settings.vdr1 != nil && server.settings.vdr1.strip != "" && server.settings.netcat && server.settings.netcat.strip != ""
	end
	
	def set_timer
		begin
			@result = add_timer(server.settings["vdr#{params["vdr"]}"].split(","), CGI::unescape(params["channel"]), params["date"], params["time"], CGI::unescape(params["program"]))
		rescue Exception => ex
			#puts ex.backtrace.join("\n")
		end
	end
	
	def method_allowed?(method_name, role)
		return role == "admin"
	end
	
	def search
		tokens = params["search"].split(" ")
		@programs = Array.new
		restore("epg_data").each_pair do | name, epg |
			epg[0].each_pair do | channel, info |
				info.each do | program |
					match = true	
					data = (channel + program.join("")).downcase
					tokens.each do | token |
						if !data.index(token.downcase)
							match = false
							break
						end
					end
					if match
						@programs.push(([name, channel] + program).flatten)
					end
				end
			end
		end
	end
	
	def dates_for_channel(channel_name, epg_data)
		dates = Array.new
		if epg_data[0][channel_name]
			epg_data[0][channel_name].each do | channel |
				date = channel[0].strftime("%Y-%m-%d")
				if !dates.index(date)
					dates.push(date)
				end
			end
		end
		return dates.sort
	end
	
	def programs_for_date(channel_name, date, epg_data, just_currently_running = false)
		programs = Array.new
		if epg_data[0][channel_name]
			t = Time.now
			date = date.split("-").collect!{|i| i = i.to_i}
			date = Time.local(date[0], date[1], date[2], 0, 0)
			if date.year == t.year && date.month == t.month && date.day == t.day
				date = Time.now
			end
			midnight = Time.local(date.year, date.month, date.day, 23, 59, 59)
			epg_data[0][channel_name].each do | channel |
				if channel[1] > date && channel[0] <= midnight
					programs.push(channel)
					return programs if just_currently_running
				end
			end 
		end
		return programs
	end
	
	def add_timer(settings, channel_name, schedule, time, program)
		channellist = fetch_channellist(settings)
		channellist.each_pair do | id, channel |
			if channel == channel_name
				channel_number = id
				time = time.split("-").collect!{|x| x = x.strip}
				t = Time.now
				starts = Time.local(t.year, t.month, t.day, time[0].split(":")[0].to_i, time[0].split(":")[1].to_i)
				#starts -= 60 * settings["timer_interval_before"].to_i if settings["timer_interval_before"]
				ends = Time.local(t.year, t.month, t.day, time[1].split(":")[0].to_i, time[1].split(":")[1].to_i)
				ends += 60 * 10
				response = Common.get_vdr_output(server.settings.netcat, settings[0], settings[1], "NEWT 1:#{channel_number}:#{schedule}:#{starts.strftime("%H%M")}:#{ends.strftime("%H%M")}:99:99:#{program}:").first
				if response && !response.downcase.index("error")
					return true
				end
			end
		end
		false
	end
	
	def fetch_timers(settings, id = nil)
		timers = Array.new
		data = nil		
		channellist = fetch_channellist(settings)
		data = Common.get_vdr_output(server.settings.netcat, settings[0], settings[1], "LSTT")
		data.each do | line |
			if line.index("250")
				begin
					line = line.gsub("250-", "250 ").split(":")
					line[1] = channellist[line[1]]
					line[7] += line[8] if line[7]
					if settings[3] && settings[3].downcase != "utf-8"
						line[1] = Iconv.conv("utf-8", settings[3], line[1])
						line[7] = Iconv.conv("utf-8", settings[3], line[7])
					end
					timers.push(line)
				rescue Exception => ex
				end
			end
		end
		return timers
	end
	
	def fetch_channellist(settings)
		channellist = Hash.new
		data = nil
		data = Common.get_vdr_output(server.settings.netcat, settings[0], settings[1], "LSTC")
		data.each do | line |
			if line.index("250")
				line = line.gsub("250-", "250 ").split(";")[0].split(" ")
				line.delete_at(0)
				num = line[0]
				line.delete_at(0)
				channel = line.join(" ").strip
				["^", ","].each do | separator |
					if channel.index(separator)
						channel = channel[0,channel.index(separator)]
					end
				end
				begin
					if settings[3] && settings[3].downcase != "utf-8"
						channel = Iconv.conv("utf-8", settings[3], channel)
					end
				rescue Exception => ex
					channel = "Unknown"
				end
				channellist[num] = channel
			end
		end
		return channellist
	end
	
	def svdrp_epg(settings)
		response = Common.get_vdr_output(server.settings.netcat, settings[0], settings[1], "LSTE")
		return response
	end
	
	def fetch_epg(vdr, settings)
		if !restore("epg_data")[vdr] || restore("epg_data")[vdr][1] != Time.now.strftime("%Y-%m-%d") 
			epg_data = OrderHash.new
			channels = Array.new
			channel_list = Array.new
			program = nil
			now = Time.now
			midnight = Time.local(now.year, now.month, now.day, 23, 59, 59)
			svdrp_epg_data = svdrp_epg(settings)
			svdrp_epg_data.each do | channel |
				break if channel == "Access denied!"
				begin
					if channel.index("215-C")
						tokens = channel.split(" ")
						channels.clear
						channels.push(tokens[2..tokens.length].join(" "))
					elsif channel.index("215-E")
						if program
							program.push("") if program.size == 3
							epg_data[channels.last] = Array.new if !epg_data[channels.last]
							epg_data[channels.last].push(program)
							program = nil
						end
						tokens = channel.split(" ")
						starts = Time.at(tokens[2].to_i)
						ends = Time.at(tokens[2].to_i) + tokens[3].to_i
						if ends >= now
							program = [starts, ends]
						end
					elsif (channel.index("215-T") || channel.index("215-D")) && program
						program.push(channel[6..channel.length])
					end
				rescue Exception => e
					#puts("Error fetching epg-data: #{e.backtrace.join("\n")}")
				end
			end
			errors = 1
			if settings[3] && (settings[3].downcase != "utf-8")
				epg_data.each_pair do | name, channellist |
					begin
						name = Iconv.conv("utf-8", settings[3], name)
					rescue Exception => e
						#puts("Cant convert channel info for #{name}: #{e.message}. Using name 'Unknown #{errors}'")
						name = "Unknown #{errors}"
						errors += 1
					end
					channellist.each do | channel |
						begin
							channel[2] = Iconv.conv("utf-8", settings[3], channel[2])
							channel[3] = Iconv.conv("utf-8", settings[3], channel[3])
						rescue Exception => e
							channel[2] = "Unknown"
							channel[3] = "Unknown"
						end
					end
				end
			end
			restore("epg_data")[vdr] = [epg_data, Time.now.strftime("%Y-%m-%d")]
		else
			#puts("Using cache fetched at #{restore("epg_data")[vdr][1]} for #{vdr}")
		end
		return restore("epg_data")[vdr][0]
	end
end
