require 'rubygems'
require 'open3'
require 'date'
require 'net/http'
require 'cgi'
require 'timeout'
require 'rexml/document'

include REXML

class String
	def strftime(format)
		begin
			return Time.parse(self).strftime(format)
		rescue Exception => ex
			return self
		end
	end
	
	def beautify
		self.split("_").collect!{|x|x = x.capitalize}.join(" ").strip
	end
end

class Common
	
	def Common.array_part_of_string?(arr, str)
		arr.each do | val |
			return true if str.index(val)
		end
		false
	end
	
	def Common.string_part_of_array?(arr, str)
		arr.each do | val |
			return true if val.index(str)
		end
		false
	end
	
	def Common.close_io(io)
		begin
			io.close_write
			io.close if io && !io.closed?
		rescue Exception => ex
		end
	end
	
	def Common.downcase_array(arr)
		return arr.collect{|item|item = item.to_s.downcase}
	end
	
	def Common.get_vdr_output(netcat, server, port, command, vdr_timeout = 10)
		response = Array.new
		begin
			Timeout.timeout(vdr_timeout + 1) do
				cmd = "\"#{netcat}\" -w #{vdr_timeout} #{server} #{port}"
				vdr_cmd = "#{command}\nquit\n"
				Open3.popen3(cmd) do | stdin, stdout, stderr |
					stdin.write(vdr_cmd)
					response = stdout.readlines
				end
			end
		rescue Exception => ex	
		end
		return response
	end
	
	def Common.is_vdr_dir?(dirlist)
		begin
			dirlist.each do | dir |
				if File.readable?(dir) && File.directory?(dir) && dir[dir.length - 4, 4] == ".rec" && Common.downcase_array(Dir.entries(dir)).index("info.vdr")
					return true
				end
			end
			return false
		rescue Exception => ex
			return false
		end
	end
	
	def Common.remote_file(path)
		if path
			return path.index("dvdsimple://") == nil && path.index("://") != nil
		end
		false
	end
	
	def Common.is_dvd_dir?(dirlist)
		begin
			return File.readable?(dirlist) && File.directory?(dirlist) && Dir.entries(dirlist).collect!{|x|x = x.downcase}.include?("video_ts")
		rescue Exception => ex
			return false
		end
	end
	
	def Common.cleanup_filename(filename)
		#return File.basename(filename, ".*").gsub(".", " ").strip.scan(/[A-Za-z0-9 \-\&\!]/i).flatten.join
		return File.basename(filename, ".*")
	end
	
	def Common.position_for_ffmpeg(position)
		begin
			position = 0 if !position
			return (Time.local(Time.now.year,1,1,0,0,0) + position).strftime("%H:%M:%S")
		rescue Exception => ex
			return "00:00:00"
		end
	end
	
	def Common.ffmpeg_position_to_position(position)
		position = "00:00:00" if !position
		position = position.split(":").collect!{|x| x = x.to_i}
		begin
			return (Time.local(Time.now.year,1,1,position[0],position[1],position[2]) - Time.local(Time.now.year,1,1,0,0,0)).to_i
		rescue Exception => e
			return 0
		end
	end
	
	def Common.parse_info(info)
		duration = 0
		info = info.strip.split("\n")
		video_format, audio_format, audio_bitrate, aspect, width, height = nil
		if info.size > 1
			tokens = info.shift.split(":").collect{|t| t = t.to_f}
			info = info.join("\n").strip
			if tokens.size == 3
				tokens.each_with_index do | token, i |
					duration += 60 * (i == 0 ? 60 : i == 1 ? 1 : 0) * token + (i != 2 ? 0 : token)
				end
			end
			str = info.split(",")
			video_format = str[0]
			audio_format = str[3].split(" ").pop if str[3]
			audio_bitrate = (str[7] || "").strip 
			if str[2]
				aspect = str[2].scan(/DAR (.*)\]/i).flatten.first.to_s
				aspect = nil if aspect && aspect.strip == ""
				width,height = str[2].scan(/(\d{0,})x(\d{0,})/i).flatten.collect{|d|d=d.to_i}
			end
			return {:duration => duration, :video_format => video_format, :audio_format => audio_format, :audio_bitrate => audio_bitrate, :aspect => aspect, :width => width, :height => height}
		end
		return nil	
	end
	
	def Common.humanize_hash(h, truncate = true, indent = "")
		str = ""
		if h && (h.instance_of?(Hash) || h.instance_of?(OrderHash)) 
			h.keys.each do | key |
				val = h[key]
				str += "#{str != "" ? ",\n" : ""}#{indent}'#{key}' => '#{val != nil ? (truncate ? val.to_s[0..40] : val) : ""}'" 
			end
		end
		str
	end
	
	def Common.humanize_array(h)
		str = ""
		if h && (h.instance_of?(Array) || h.instance_of?(KnotsArray)) 
			h.each do | token |
				if token.instance_of?(String)
					str += "#{str != "" ? ",\n" : ""}'#{token}'"
				elsif token.instance_of?(Array) || token.instance_of?(KnotsArray)
					str += "#{str != "" ? ",\n" : ""}'#{self.humanize_array(token)}'"
				elsif token.instance_of?(Hash) || token.instance_of?(OrderHash)
					str += "#{str != "" ? ",\n" : ""}'#{self.humanize_hash(token)}'"
				end
			end
		end
		str
	end
	
	def Common.new_size_keeping_aspect(original_width, original_height, new_width = nil, new_height = nil, fallback_width = nil, fallback_height = nil)
		# TODO FIX THIS
		if original_width && original_width > 0 && original_height && original_height > 0 && ((new_width && new_width > 0) || (new_height && new_height > 0)) 
			return new_width ? [new_width || fallback_width, (original_height.to_f / (original_width.to_f / new_width.to_f)).to_i || fallback_height] : [(original_width.to_f / (original_height.to_f / new_height.to_f)).to_i  || fallback_width, new_height || fallback_height].collect{|x| x = x / 2 * 2}
		else
			return [new_width || fallback_width, new_height || fallback_height].collect{|x| x = x / 2 * 2}
		end
	end
	
	def Common.grab_screenshot(ffmpeg, filename, position = nil, duration = nil, size = nil, curl = nil, tmpdir = "/var/tmp", curl_timeout = 1)
		if !File.exists?(filename) || File.readable?(filename)
			if File.directory?(filename) && File.exists?(File.join(filename, "VIDEO_TS", "VTS_01_1.VOB"))
				filename = File.join(filename, "VIDEO_TS", "VTS_01_1.VOB")
			end
			temp_file = false
			if filename.index("http://") && curl
				filename = grab_video_stream(filename, curl, tmpdir, curl_timeout)
				position = 0
				temp_file = true
			end
			if File.exists?(filename) && (filesize = File.size(filename)) > 0
				images = Dir["#{File.join(File.dirname(filename), File.basename(filename, ".*"))}.{jpg,jpeg,png,gif}"]
				if [".jpg", ".jpeg", ".png", ".gif"].include?(File.extname(filename).downcase)
					position = 0
					images = nil
				end
				if !images || images.size == 0
					position = rand(duration) if !position && duration
					position = 100 if !position
					image = File.join(tmpdir, "knots#{Time.now.to_f}.jpg")
					cmd = "\"#{ffmpeg}\" -ss #{position} -t 1 -i \"#{filename}\" -f image2#{size ? " -s #{size}" : ""} \"#{image}\""
					if !windows_os?
						cmd += "> /dev/null 2>/dev/null"
					end
					image_data = nil
					Common.get_output(cmd)
					image_data = load_file(image)
					FileUtils.rm_rf(image)
					if temp_file == true && filename != nil && filename.index(tmpdir) != nil
						FileUtils.rm_rf(filename) if File.exists?(filename)
					end
					return image_data
				else
					return load_file(images[0])
				end
			end
		end
	end
	
	def Common.windows_os?
		RUBY_PLATFORM.downcase.index("win32") != nil || RUBY_PLATFORM.downcase.index("w32") != nil
	end
	
	def Common.osx?
		RUBY_PLATFORM.downcase.index("darwin") != nil
	end
	
	def Common.is_music_file?(filename, extensions = nil)
		(extensions || [".mp3"]).include?(File.extname(filename).downcase)
	end
	
	def Common.load_file(filename)
		if normal_readable_file?(filename)
			begin
				File.open(filename,'rb') do |f|
					return f.read
				end
			rescue Exception => ex
				nil
			end
		end
	end
	
	def Common.parse_playlist(data)
		playlist_items = Array.new
		if data
			if data.downcase.index("numberofentries") # pls
				items = data.scan(/File\d{0,}=(.*)\s{0,}Title\d{0,}=(.*)/)
				items = data.scan(/Title\d{0,}=(.*)\s{0,}File\d{0,}=(.*)/).collect!{|x| x = x.reverse} if items.size == 0
				items.each do | item |
					playlist_items.push([item[0], item[1]])
				end
			elsif data.downcase.index("<tracklist>") # xspf
				begin
					doc = Document.new(data)
					doc.root.elements["trackList"].each_element do | e |
						playlist_items.push([e.elements["location"] ? e.elements["location"].text : nil, e.elements["title"] ? e.elements["title"].text : nil])
					end
				rescue Exception => ex
				end
			else # m3u
				items = data.scan(/(#EXTINF:.*?,(.*)\n|.+)(.*?)$/)
				items.each do | item |
					item = item.delete_if{|x|x == nil || x.strip == ""}.collect!{|x| x = x.strip if x}
					if item.size == 3
						name = item[1] && item[1].strip !="" ? item[1] : File.basename(item[2])
						name = name.split(" - ")[0] if name && name.index(" - ")
						playlist_items.push([item[2].gsub("\\", "/"), name])
					elsif item.size == 1 && !item[0].index("#EXTM3U")
						name = File.basename(item[0])
						playlist_items.push([item[0].gsub("\\", "/"), name])
					end
				end
			end
		end
		return playlist_items
	end
	
	def Common.fix_filename(filename)
		filename.gsub("`", "\\\\`")
	end
	
	def Common.grab_video_stream(url, curl, tmpdir = "/var/tmp", curl_timeout = 1)
		filename = File.join(tmpdir, "knots#{Time.now.to_f}.mpg")
		cmd = "\"#{curl}\" -o \"#{filename}\" -m #{curl_timeout} \"#{url}\""
		cmd += " > /dev/null 2> /dev/null" if !windows_os?
		Common.get_output(cmd)
		filename
	end
	
	def Common.get_output(cmd, io = "stdout", timeout_seconds = 10)
                output = nil
                Open3.popen3(cmd) do | stdin, stdout, stderr, wait_thr |
                        begin   
                                Timeout.timeout(timeout_seconds) do
                                        output = ((io == "stdout") ? stdout : stderr).readlines.join("")
                                        stdout.close
                                        stderr.close
                                end  
                        rescue Exception => ex
                                begin
                                  stdin << "q"
                                  Process.kill(9,  wait_thr[:pid])                                  
                                end
                        end
                end
                return output
        end
	
	def Common.old_config_dir
		ENV["HOME"] = File.dirname(File.dirname(__FILE__)) if Common.windows_os?
		return File.join(ENV["HOME"], ".config", "kserver")
	end
	
	def Common.config_dir
		ENV["HOME"] = File.dirname(File.dirname(__FILE__)) if Common.windows_os?
		return File.join(ENV["HOME"], ".config", "knots2")
	end
	
	def Common.load_database(detect = true)
		database_file = File.join(config_dir, (ENV["KNOTSDB"] ||"knots.db"))
		if !File.exists?(database_file)
			if !File.exists?(old_config_dir)
				FileUtils.mkdir_p(config_dir) if !File.exists?(config_dir)
				FileUtils.cp(File.join("db", "knots.db"), File.join(config_dir, (ENV["KNOTSDB"] || "knots.db")))
			else
				FileUtils.mv(old_config_dir, config_dir)
				FileUtils.mv(File.join(config_dir, "kserver.db"), File.join(config_dir, "knots.db")) if File.exists?(File.join(config_dir, "kserver.db"))
				FileUtils.mv(File.join(config_dir, "kserver.log"), File.join(config_dir, "knots.log")) if File.exists?(File.join(config_dir, "kserver.log"))
				FileUtils.mv(File.join(config_dir, "kserver_access.log"), File.join(config_dir, "knots_access.log")) if File.exists?(File.join(config_dir, "kserver_access.log"))
			end
		end
		database = KnotsDB.new(database_file)
		detect_apps(database) if detect
		return database
	end
	
	def Common.detect_apps(db)
		paths = {
			"vlc" => ["/usr/local/bin/vlc", "/usr/bin/vlc", "/Applications/VLC.app/Contents/MacOS/VLC", "C:/Program Files/VideoLAN/VLC/vlc.exe", "C:/Program Files (x86)/VideoLAN/VLC/vlc.exe", File.join(ENV["HOME"], "win32", "VideoLAN/VLC/vlc.exe")],
			"ffmpeg" => ["/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg", "/Applications/ffmpegX.app/Contents/Resources/ffmpeg", File.join(ENV["HOME"], "win32", "ffmpeg.exe")],
			"curl" => ["/usr/local/bin/curl", "/usr/bin/curl", File.join(ENV["HOME"], "win32", "curl.exe")],
			"netcat" => ["/usr/local/bin/netcat", "/usr/local/bin/nc", "/usr/bin/netcat", "/usr/bin/nc", "/bin/netcat", "/bin/nc", File.join(ENV["HOME"], "win32", "nc.exe")],
			"lsdvd"=> ["/usr/local/bin/lsdvd", "/usr/bin/lsdvd", File.join(ENV["HOME"], "win32", "lsdvd.exe"), File.join(File.expand_path(File.dirname(File.dirname(__FILE__))), "osx", "lsdvd")]
		}
		paths.each_key do | app |
			setting = db.settings.by_key(app).first
			if setting && setting.value && File.readable?(setting.value) && File.exists?(setting.value)
				paths[app].unshift(setting.value).uniq!
			end
		end
		paths.each_pair do | app, searched |
			searched.each do | path |
				if File.readable?(path) && File.exists?(path)
					store = true
					if false && app == "vlc" && !Common.windows_os?
						output = Common.get_output("#{path} --version")
						version = output.scan(/.*{0,}(\d\.\d)/m).flatten.first if output
						version = output.scan(/(\d\.\d\.{0,}\d{0,})/m).flatten.first if output && RUBY_VERSION >= "1.9.2"
						# Don't allow VLC 0.8
						if !version || version < "0.9"
							store = false
						elsif version < "1.1"
							setting = db.settings.by_key("new_vlc").first
							if setting && setting.value.to_i == 1
								setting.value = 0
								setting.save
							end
						elsif version >= "1.1"
							# Start VLC with oldtelnet if it's 1.1 or newer
							setting = db.settings.by_key("new_vlc").first
							if !setting || setting.value.to_i == 0
								setting.value = 1
								setting.save
							end
						end
					end
					if store
						setting = db.settings.by_key(app).first || db.settings.new
						if !setting.value || setting.value.strip == ""
							setting.key = app
							setting.value = File.expand_path(path)
							setting.name = "Full path to #{app}"
							setting.save
						end
						break
					end
				end
			end
		end
		setting = db.settings.by_key("dvd_drive").first
		if !setting || !setting.value || setting.value.strip == ""
			setting = db.settings.new if !setting
			setting.key = "dvd_drive"
			setting.name = "DVD path"
			if Common.windows_os?
				setting.value = "D:\\"
			elsif Common.osx?
				setting.value = "/Volumes"
			else
				setting.value = File.exists?("/media") ? "/media" : "/mnt"
			end
			setting.save
		end
		begin
			setting = db.settings.by_key("server_name").first || db.settings.new
			if !setting.value || setting.value == "Knots server" || setting.value.strip == ""
				setting.value = "#{Knots} at #{Facter["hostname"].value.scan(/[A-Za-z0-9_ \-]/).join("")}"
				setting.save
			end
		rescue Exception => ex
		end
		if Common.windows_os?
			setting = db.settings.by_key("tmpdir").first
			if !setting || !setting.value || setting.value.strip == "" || !File.exists?(setting.value)
				setting.value = File.expand_path(File.join(ENV["HOME"], "win32"))
				setting.save
			end
		end
	end
	
	def Common.is_dvd?(filename)
		return [".iso", ".img"].include?(File.extname(filename || "").downcase) || Common.is_dvd_dir?(filename) 
	end
	
	def Common.fetch_cover(artist, album, filename = nil)
		begin
			if artist && album
				Timeout.timeout(10) do
					cover = fetch("http://albumart.org/index.php?srchkey=#{CGI::escape(artist + " " + album)}&itempage=1&newsearch=1&searchindex=Music").body.scan(/<img src="([^\"]*)"/i).flatten.delete_if{|img| !img.index("amazon")}.first
					if cover
						return fetch(cover).body, 1
					end
					return nil, 0
				end
			elsif filename
				images = Dir["#{File.join(File.dirname(filename), File.basename(filename, ".*"))}.{jpg,jpeg,png,gif}"]
				if images && images.size > 0
					return load_file(images[0]), 2
				end
			end
		rescue Exception => ex
			return nil, -1
		end
	end
	
	def Common.normal_readable_file?(filename)
		return filename != nil && File.exists?(filename) && File.readable?(filename) && !File.directory?(filename) 
	end
	
	def Common.vdr_info(path, charset = nil)
		info = Hash.new
		data = load_file(File.join(path, "info.vdr"))
		data.split("\n").each do | line |
			line = line.split(" ")
			id = line.first
			line.delete_at(0)
			data = line.join(" ")
			if charset && charset != "utf-8"
				begin
					data = Iconv.conv("utf-8", "iso-8859-1", data)
				rescue Exception => e
				end
			end
			info[id] = data
		end
		info["Date"] = File.basename(path).split(".")[0]
		return info
	end
	
	def Common.generate_password
		id = ""
		chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
		12.times do | i |
			id << chars[rand(chars.size - 1)]
		end
		id
	end
	
	def Common.to_int(str) 
		return str != nil ? str.to_s.strip.to_i : -1
	end
	
	def Common.time_to_datetime(time)
		DateTime.parse(time.to_s)
	end
	
	def Common.fetch(uri_str, limit = 10)
		url = URI.parse(uri_str)
		request = Net::HTTP::Get.new("#{url.path}#{url.query ? "?#{url.query}": ""}")
		response = Net::HTTP.start(url.host, url.port) {|http|
			if url.userinfo
				request.basic_auth(url.userinfo.split(":")[0], url.userinfo.split(":")[1]) 
			end
			http.request(request)
		}
		case response
			when Net::HTTPSuccess     then response
			when Net::HTTPRedirection then fetch(response['location'], limit - 1)
		else
			response.error!
		end
	end
end
